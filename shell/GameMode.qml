pragma Singleton

// GameMode.qml - automatic Game Mode: while a game is in front the desktop gets out of the way.
//   GameMode.active     true while engaged (debounced: 1.5 s either way, so alt-tab or a fullscreen
//                       video does not flap)
//   GameMode.reason     "fullscreen" | "game-id" | "game-run" | "forced"
// Detection is apps/gamemode/detect.js (fullscreen window; steam_app_* / gamescope / wine / proton
// focused; a window of an ultimit-game-run game focused. Browsers, video players, terminals do not count).
// While active:
//   Config.gameModeActive  -> Config.desktopPaused: wallpaper, edge glow travel, rail spin, ticker,
//                             clock seconds, SysStats graphs, decode text and feed refresh all stop
//   Notifs.gameHold        -> toasts held (critical ones still show), summed up on exit
//   UiSounds               -> off
//   gamemode.py power on   -> power profile "performance", restored on exit (see gamemode.py)
// The compositor already turns on VRR and tearing and keeps direct scanout for a fullscreen window.
// Switches: Config.gameModeEnabled / gameModePower / gameModeHold (Settings > Power > Game Mode).
// IPC: qs ipc call gamemode status | force on|off|auto | launched <id>
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "apps/gamemode/detect.js" as Detect

Singleton {
    id: root

    property bool active: false
    property string reason: ""
    property string forced: ""          // "" (automatic) | "on" | "off", from IPC (tests, debugging)
    property bool powerOn: false        // the helper was asked to switch the profile
    readonly property string helper: Quickshell.shellPath("apps/gamemode/gamemode.py")
    readonly property bool devbox: Quickshell.env("ULTIMIT_DEVBOX") === "1"

    // ultimit-game-run games (marker files): alive flag and the app ids learned for them
    property bool runAlive: false
    property var runPre: []
    property var runApps: []

    function windows() {
        const out = [];
        for (const t of ToplevelManager.toplevels.values)
            out.push({ appId: t.appId, fullscreen: t.fullscreen, minimized: t.minimized, focused: t.activated,
                       screens: t.screens.map(s => s ? s.name : "") });
        return out;
    }
    readonly property var verdict: Detect.classify(root.windows(), { alive: root.runAlive, apps: root.runApps })
    readonly property bool wanted: root.forced === "on" ? true : (root.forced === "off" ? false : (Config.gameModeEnabled && root.verdict.active))

    onWantedChanged: {
        if (root.wanted === root.active) { settle.stop(); return; }
        if (root.forced !== "" || !Config.gameModeEnabled) root.apply(root.wanted);
        else settle.restart();
    }
    Timer { id: settle; interval: 1500; onTriggered: root.apply(root.wanted) }

    function init() {}   // referenced from shell.qml so the singleton (and its IPC) exist from the start

    function apply(on) {
        settle.stop();
        if (on === root.active) return;
        const why = root.forced === "on" ? "forced" : root.verdict.reason;
        if (on) {
            root.reason = why;
            // The toast first (before holding), and not over a game that owns the screen that carries toasts.
            const mainCovered = Quickshell.screens.some(s => Config.isMainScreen(s.name) && Config.isCovered(s.name));
            if (!mainCovered) Toasts.show("GAME MODE · ON", Config.gameModePower ? "Desktop quiet, performance profile" : "Desktop quiet", "", 2600);
            root.active = true;
            Config.gameModeActive = true;
            Notifs.gameHeld = 0;
            Notifs.gameHold = Config.gameModeHold;
            if (Config.gameModePower) root.setPower(true);
        } else {
            root.active = false;
            root.reason = "";
            Config.gameModeActive = false;
            Notifs.gameHold = false;
            root.setPower(false);
            const n = Notifs.gameHeld;
            Notifs.gameHeld = 0;
            if (n > 0) Toasts.show("GAME MODE · OFF", n + (n === 1 ? " notification" : " notifications") + " while you played", "", 5000);
        }
    }

    // Settings switches act at once.
    Connections {
        target: Config
        function onGameModeHoldChanged() { if (root.active) { Notifs.gameHold = Config.gameModeHold; } }
        function onGameModePowerChanged() { if (root.active) root.setPower(Config.gameModePower); }
    }

    // ---- power profile (helper; restores the old one on off, at startup and if the shell dies) ----
    function setPower(on) {
        if (on) {
            if (root.powerOn) return;
            root.powerOn = true;
            // sh keeps qs as its parent: the helper's watcher restores the profile if the shell is killed
            powerOnProc.command = ["sh", "-c", "exec python3 \"$1\" power on --owner $PPID", "sh", root.helper];
            powerOnProc.running = true;
        } else if (root.powerOn) {
            root.powerOn = false;
            if (!powerOnProc.running) { powerOffProc.command = ["python3", root.helper, "power", "off"]; powerOffProc.running = true; }
        }
    }
    Process {
        id: powerOnProc
        onExited: if (!root.powerOn) { powerOffProc.command = ["python3", root.helper, "power", "off"]; powerOffProc.running = true; }
    }
    Process { id: powerOffProc }
    Process { id: staleProc; command: ["python3", root.helper, "power", "restore-stale"] }   // a crashed shell left it on

    // ---- ultimit-game-run games ----
    // ultimit-game-run tells us (launched) and leaves a marker (pid); polled only while one is alive.
    function launched(id) { root.pollRun(); }
    function pollRun() { if (!runProc.running) runProc.running = true; }
    Process {
        id: runProc
        command: ["python3", root.helper, "running"]
        stdout: StdioCollector {
            onStreamFinished: {
                const alive = text.trim().startsWith("1");
                if (alive && !root.runAlive) { root.runPre = root.windows().map(w => Detect.norm(w.appId)); root.runApps = []; }
                if (!alive) root.runApps = [];
                root.runAlive = alive;
            }
        }
    }
    Timer {   // learn which window is the game's, notice the game ending (window close covers most cases)
        interval: 1000; repeat: true; running: root.runAlive
        property int n: 0
        onTriggered: {
            root.runApps = Detect.learn(root.windows(), root.runPre, root.runApps);
            if (++n % 3 === 0) root.pollRun();
        }
    }

    Component.onCompleted: { staleProc.running = true; root.pollRun(); }
    Component.onDestruction: if (root.powerOn) { root.powerOn = false; Quickshell.execDetached(["python3", root.helper, "power", "off"]); }

    IpcHandler {
        target: "gamemode"
        function status(): string {
            return JSON.stringify({ active: root.active, reason: root.reason, forced: root.forced || "auto", wanted: root.wanted,
                enabled: Config.gameModeEnabled, power: Config.gameModePower, hold: Config.gameModeHold, held: Notifs.gameHeld,
                detected: root.verdict.reason, runAlive: root.runAlive, desktopPaused: Config.desktopPaused });
        }
        function force(mode: string): string {
            root.forced = mode === "on" ? "on" : (mode === "off" ? "off" : "");
            return root.forced || "auto";
        }
        function launched(id: string): void { root.launched(id); }
    }
}
