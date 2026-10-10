pragma Singleton

// Config.qml - user-tweakable settings and defaults for the Ultimit shell.
// Everything configurable lives here so the components stay generic.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string version: "0.1"

    // Wallpaper animation. When false the wallpaper is drawn once (zero idle cost).
    // Set ULTIMIT_MOTION=0 in the environment to start with motion off.
    property bool motion: Quickshell.env("ULTIMIT_MOTION") !== "0"
    // Wallpaper redraw rate cap while motion is on.
    property int wallpaperFps: 20
    // Number of main shards in the wing (mockup slider: 16..60).
    property int shardDensity: 34

    // Play the boot sequence overlay once at shell startup.
    property bool bootOnStart: Quickshell.env("ULTIMIT_BOOT") !== "0"

    // UI animation duration scale: 0 when motion is off (reduced motion), else 1.
    readonly property real motionScale: motion ? 1 : 0
    function dur(ms) { return Math.round(ms * motionScale); }

    // ---- shared UI state / requests (see apps/accessory, Boot.qml, Rail.qml) ----
    // Accessory window visibility; the window writes back here when closed via its frame.
    property bool accessoryOpen: false
    readonly property string accessoryTitle: "Settings"   // the Settings window (apps/settings) replaces Accessory
    // Bumped to ask Boot.qml to (re)play the boot overlay.
    property int bootRequest: 0
    function playBoot() { bootRequest++; }

    // ---- idle / lock (see LockScreen.qml) ----
    // Seconds of inactivity before each step; 0 disables the step. Inhibitors (fullscreen
    // windows, video players) hold idle off through ext-idle-notify. Env overrides
    // (ULTIMIT_DIM_AFTER, ULTIMIT_LOCK_AFTER, ULTIMIT_SUSPEND_AFTER, ULTIMIT_SUSPEND_ON_AC=1)
    // apply to that run only; used by the headless tests.
    function envNum(name, def) { const v = parseFloat(Quickshell.env(name)); return isNaN(v) ? def : v; }
    property real dimAfter: envNum("ULTIMIT_DIM_AFTER", 300)
    property real lockAfter: envNum("ULTIMIT_LOCK_AFTER", 360)
    property real suspendAfter: envNum("ULTIMIT_SUSPEND_AFTER", 900)
    // Suspend on idle even when plugged in (default: only on battery).
    property bool suspendOnAC: Quickshell.env("ULTIMIT_SUSPEND_ON_AC") === "1"
    // Lock when the machine suspends / the lid closes (logind PrepareForSleep) and on `loginctl lock-session`.
    property bool lockOnSleep: true
    // PAM service used by the lock screen. "ultimit-lock" is used when /etc/pam.d/ultimit-lock exists
    // (see docs/design or the install notes), else the stock "login" service.
    property string pamService: "ultimit-lock"
    property string pamFallback: "login"
    // Lock-screen wallpaper animation (off: painted once; saves power while locked).
    property bool lockAnimated: false
    // Bumped to ask LockScreen.qml to lock (IPC `lock lock`, quick settings, launcher, Super+L).
    property int lockRequest: 0
    function lock() { lockRequest++; }

    // Layout metrics (px)
    readonly property int railWidth: 84
    readonly property int tickerHeight: 26

    // ---- launcher / context menu state (see components/Launcher.qml, ContextMenu.qml) ----
    property bool launcherOpen: false
    property bool menuOpen: false
    // Screen name the open launcher/menu belongs to ("" = first screen).
    property string uiScreen: ""
    property real menuX: 0
    property real menuY: 0
    function openLauncher(screenName) { menuOpen = false; uiScreen = screenName || ""; launcherOpen = true; }
    function closeLauncher() { launcherOpen = false; }
    function toggleLauncher(screenName) { if (launcherOpen) closeLauncher(); else openLauncher(screenName); }
    function openMenu(screenName, x, y) { launcherOpen = false; uiScreen = screenName || ""; menuX = x; menuY = y; menuOpen = true; }
    function closeMenu() { menuOpen = false; }
    function isUiScreen(name) {
        if (uiScreen !== "") return uiScreen === name;
        const s = Quickshell.screens;
        return s.length > 0 && s[0].name === name;
    }

    // Rail buttons, in display order.
    //  id       - key used for icons
    //  label    - text under the icon
    //  tryCmds  - ordered candidates { bin, cmd, check? }; the first whose check passes
    //             (default: `command -v bin`) is used. Detected once at startup.
    //  hint     - shown in the "not installed" toast: { what, install }
    //  appIds   - Wayland app_ids that count as "this app is open"
    //             (compared case-insensitively)
    //  own      - opens one of Ultimit's own windows (no external command needed)
    readonly property var apps: [
        { id: "games",     label: "GAMES",     own: true,
          appIds: ["steam", "lutris", "heroic", "com.heroicgameslauncher.hgl", "net.lutris.lutris"] },
        { id: "mailer",    label: "MAILER",
          tryCmds: [
              { bin: "thunderbird", cmd: "thunderbird" },
              { bin: "evolution",   cmd: "evolution" },
              { bin: "geary",       cmd: "geary" },
              { bin: "xdg-open", cmd: "xdg-open mailto:",
                check: "command -v xdg-open >/dev/null && [ -n \"$(xdg-mime query default x-scheme-handler/mailto 2>/dev/null)\" ]" }
          ],
          hint: { what: "No mail app installed", install: "sudo apt install thunderbird" },
          appIds: ["thunderbird", "org.mozilla.thunderbird", "org.gnome.evolution", "evolution", "geary", "org.gnome.geary"] },
        { id: "news",      label: "NEWS",
          tryCmds: [ { bin: "xdg-open", cmd: "xdg-open https://news.ycombinator.com" } ],
          hint: { what: "No default browser launcher", install: "sudo apt install xdg-utils firefox" },
          appIds: ["firefox", "org.mozilla.firefox", "google-chrome", "chromium", "brave-browser"] },
        { id: "audio",     label: "AUDIO",
          tryCmds: [
              { bin: "rhythmbox",  cmd: "rhythmbox" },
              { bin: "lollypop",   cmd: "lollypop" },
              { bin: "amberol",    cmd: "amberol" },
              { bin: "gnome-music", cmd: "gnome-music" },
              { bin: "gtk-launch", cmd: "gtk-launch \"$(xdg-mime query default audio/mpeg)\"",
                check: "command -v gtk-launch >/dev/null && [ -n \"$(xdg-mime query default audio/mpeg 2>/dev/null)\" ]" }
          ],
          hint: { what: "No music app installed", install: "sudo apt install rhythmbox" },
          appIds: ["rhythmbox", "org.gnome.rhythmbox3", "spotify", "lollypop", "io.bassi.amberol", "org.gnome.music"] },
        { id: "data",      label: "DATA",
          tryCmds: [
              { bin: "nautilus", cmd: "nautilus" },
              { bin: "nemo",     cmd: "nemo" },
              { bin: "thunar",   cmd: "thunar" },
              { bin: "dolphin",  cmd: "dolphin" }
          ],
          hint: { what: "No file manager installed", install: "sudo apt install nautilus" },
          appIds: ["nautilus", "org.gnome.nautilus", "org.gnome.files", "nemo", "thunar", "org.kde.dolphin"] },
        { id: "accessory", label: "ACCESSORY", own: true,
          appIds: ["gnome-control-center", "org.gnome.settings"] }
    ]

    // Terminal candidates for the desktop menu.
    readonly property var terminals: [
        { bin: "foot", cmd: "foot" }, { bin: "kitty", cmd: "kitty" },
        { bin: "ptyxis", cmd: "ptyxis" }, { bin: "xterm", cmd: "xterm" }
    ]

    // Detected launch commands: { appId: cmd } (missing key = nothing installed).
    property var resolved: ({})
    property string terminalCmd: ""
    property bool detected: false

    // Command for an app id, or "" when unavailable. Own-window apps are always available.
    function commandFor(id) { return resolved[id] || ""; }
    function available(app) { return !detected || !!app.own || !!resolved[app.id]; }
    function appById(id) { for (const a of apps) if (a.id === id) return a; return null; }

    // Run an app's resolved command, or toast the install hint.
    function launchApp(app) {
        const cmd = commandFor(app.id);
        if (cmd) { Quickshell.execDetached(["sh", "-c", cmd]); return true; }
        if (app.hint) Toasts.show(app.label, app.hint.what + " — try:", app.hint.install);
        return false;
    }
    function openTerminal() {
        if (terminalCmd) Quickshell.execDetached(["sh", "-c", terminalCmd]);
        else Toasts.show("Terminal", "No terminal installed — try:", "sudo apt install foot");
    }

    // One shell run probes every candidate; output lines are "<id> <index>" / "term <index>".
    Process {
        running: true
        command: ["sh", "-c", root.probeScript()]
        stdout: StdioCollector {
            onStreamFinished: {
                const res = {}; let term = -1;
                for (const line of text.split("\n")) {
                    const p = line.trim().split(" ");
                    if (p.length !== 2) continue;
                    const i = parseInt(p[1]);
                    if (p[0] === "term") { if (term < 0) term = i; continue; }
                    if (!(p[0] in res)) res[p[0]] = i;
                }
                const out = {};
                for (const a of root.apps) {
                    if (a.tryCmds && a.id in res) out[a.id] = a.tryCmds[res[a.id]].cmd;
                }
                root.resolved = out;
                root.terminalCmd = term >= 0 ? root.terminals[term].cmd : "";
                root.detected = true;
            }
        }
    }
    function probeScript() {
        let s = "";
        for (const a of apps) {
            if (!a.tryCmds) continue;
            a.tryCmds.forEach((c, i) => {
                const chk = c.check || ("command -v " + c.bin + " >/dev/null 2>&1");
                s += "if " + chk + "; then echo '" + a.id + " " + i + "'; fi\n";
            });
        }
        terminals.forEach((c, i) => { s += "if command -v " + c.bin + " >/dev/null 2>&1; then echo 'term " + i + "'; fi\n"; });
        return s;
    }

    // Static sample headlines for the ticker: { t: time label, h: headline }
    readonly property var headlines: [
        { t: "10:04", h: "Ultimit 0.1 “Mine” enters development" },
        { t: "09:20", h: "Fullscreen games skip the compositor" },
        { t: "YDAY",  h: "Desktop cat learns to sit on windows" },
        { t: "OCT 07", h: "Four skins ship in the first build" }
    ]
}
