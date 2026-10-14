pragma Singleton

// Config.qml - user-tweakable settings and defaults for the Ultimit shell.
// Everything configurable lives here so the components stay generic.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root
    readonly property string version: "0.1"

    // Wallpaper animation. When false the wallpaper is drawn once (zero idle cost).
    // Set ULTIMIT_MOTION=0 in the environment to start with motion off.
    property bool motion: Quickshell.env("ULTIMIT_MOTION") !== "0"
    // The shard wallpaper moves (when motion is on too). Off: drawn once, still, while windows and
    // panels keep their animations. Settings > Appearance > Wallpaper.
    property bool wallpaperMotion: true
    // Wallpaper redraw rate cap while motion is on.
    property int wallpaperFps: 20
    // Number of main shards in the wing (mockup slider: 16..60).
    property int shardDensity: 34
    // Desktop picture: "" = the generative shards, else an image file; wallpaperFit is how it
    // fills the screen: fill (crop) | fit | stretch | center.
    property string wallpaper: ""
    property string wallpaperFit: "fill"
    readonly property var wallpaperFits: ["fill", "fit", "stretch", "center"]

    // Play the boot sequence overlay once at shell startup.
    property bool bootOnStart: Quickshell.env("ULTIMIT_BOOT") !== "0"

    // Rail core icons turn like Altimit's: "always" | "hover" | "off" (Settings > Appearance).
    property string railSpin: "always"
    // UI animation duration scale: 0 when motion is off (reduced motion), else 1.
    readonly property real motionScale: motion ? 1 : 0
    function dur(ms) { return Math.round(ms * motionScale); }

    // ---- shared UI state / requests (see apps/accessory, Boot.qml, Rail.qml) ----
    // Accessory window visibility; the window writes back here when closed via its frame.
    property bool accessoryOpen: false
    // Window titles of Ultimit's own windows: what the titlebar shows and how the rail, Alt+Tab and
    // pins recognise them (they all report appId "org.quickshell").
    readonly property string accessoryTitle: "SETTINGS"   // the Settings window (apps/settings) replaces Accessory
    readonly property string gamesTitle: "GAMES"
    // Ask the Settings window to open on a page (id from SettingsWindow.pages), e.g. "rail", "news".
    property string settingsPage: ""
    property int settingsRequest: 0
    // "Add device..." in the Bluetooth flyout: Settings > Bluetooth starts a scan when it shows the page.
    property bool btScanRequest: false
    function openBluetoothAdd() { btScanRequest = true; openSettings("bluetooth"); }
    // Raise the Settings window when it's open; otherwise make a fresh one (SettingsWindow.qml loads it
    // only while accessoryOpen; a FloatingWindow closed from its frame won't show again).
    function openSettings(page) {
        settingsPage = page || "";
        settingsRequest++;
        for (const t of ToplevelManager.toplevels.values) {
            if (t.appId === "org.quickshell" && t.title === accessoryTitle) { t.minimized = false; t.activate(); return; }
        }
        accessoryOpen = false;
        accessoryOpen = true;
    }
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
    readonly property int tickerHeight: 30   // bottom bar (ticker + tray cluster)

    // ---- launcher / context menu state (see components/Launcher.qml, ContextMenu.qml) ----
    property bool launcherOpen: false
    property bool shortcutsOpen: false   // the keyboard shortcut sheet (Super+/)
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
        return isMainScreen(name);
    }

    // ---- the main display (Settings > Display; the compositor keeps it in displays.conf) ----
    // primaryScreen is its output name as the compositor reports it; asked again whenever screens
    // come and go. Until known (or if it's gone), the first screen is the main one.
    property string primaryScreen: ""
    function isMainScreen(name) {
        const s = Quickshell.screens;
        if (primaryScreen !== "" && s.some(x => x.name === primaryScreen)) return name === primaryScreen;
        return s.length > 0 && s[0].name === name;
    }
    function refreshPrimary() { primaryProc.running = false; primaryProc.running = true; }
    Process {
        id: primaryProc
        running: true
        command: [Quickshell.shellPath("bin/ultimitctl"), "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text).outputs.find(o => o.primary);
                    root.primaryScreen = p ? p.name : "";
                } catch (e) {}
            }
        }
    }
    Connections { target: Quickshell; function onScreensChanged() { primaryDelay.restart(); } }
    Timer { id: primaryDelay; interval: 500; onTriggered: root.refreshPrimary() }   // after the compositor settles
    // Rail on every display ("all", like Windows' taskbar) or on the main one only. The news
    // ticker (bottom bar) is always on the main display only.
    property string barsOn: "all"
    function showsBars(name) { return barsOn === "all" || isMainScreen(name); }

    // The screen that carries the bottom-bar tray cluster. Deliberately NOT isUiScreen(): that one
    // follows the launcher/menu (uiScreen), so the tray would hop screens whenever the launcher
    // opens elsewhere. The tray stays on the first (primary) screen, like the OSD default.
    function isTrayScreen(name) {
        return isMainScreen(name);
    }

    // Rail buttons, in display order.
    //  id       - key used for icons
    //  label    - text under the icon
    //  tryCmds  - ordered candidates { bin, cmd, check? }; the first whose check passes
    //             (default: `command -v bin`) is used. Detected once at startup.
    //  hint     - when nothing is installed: { what, store } toasts `what` and opens STORE on a
    //             search for `store`
    //  appIds   - Wayland app_ids that count as "this app is open"
    //             (compared case-insensitively)
    //  own      - opens one of Ultimit's own windows (no external command needed)
    readonly property var apps: [
        { id: "games",     label: "GAMES",     own: true,
          appIds: ["steam", "lutris", "heroic", "com.heroicgameslauncher.hgl", "net.lutris.lutris"] },
        { id: "mailer",    label: "MAILER",
          tryCmds: [
              // NekoMail (Ultimit's own mail app, ~/code/nekomail ultimit branch): the `nekomail`
              // window command (single instance; starts its background service if needed).
              // ~/.local/bin is where its installer puts it, which a session PATH may lack.
              { bin: "nekomail", cmd: "$(command -v nekomail || echo \"$HOME/.local/bin/nekomail\")",
                check: "command -v nekomail >/dev/null 2>&1 || [ -x \"$HOME/.local/bin/nekomail\" ]" },
              { bin: "thunderbird", cmd: "thunderbird" },
              { bin: "flatpak", cmd: "flatpak run org.mozilla.thunderbird",
                check: "flatpak info org.mozilla.thunderbird >/dev/null 2>&1" },
              { bin: "evolution",   cmd: "evolution" },
              { bin: "geary",       cmd: "geary" },
              { bin: "xdg-open", cmd: "xdg-open mailto:",
                check: "command -v xdg-open >/dev/null && [ -n \"$(xdg-mime query default x-scheme-handler/mailto 2>/dev/null)\" ]" }
          ],
          hint: { what: "No mail app installed", store: "mail" },
          appIds: ["nekomail", "thunderbird", "org.mozilla.thunderbird", "org.gnome.evolution", "evolution", "geary", "org.gnome.geary"] },
        { id: "news",      label: "NEWS",
          tryCmds: [ { bin: "xdg-open", cmd: "xdg-open https://news.ycombinator.com" } ],
          hint: { what: "No web browser installed", store: "web browser" },
          appIds: ["firefox", "org.mozilla.firefox", "google-chrome", "chromium", "brave-browser"] },
        { id: "audio",     label: "AUDIO",
          tryCmds: [
              { bin: "rhythmbox",  cmd: "rhythmbox" },
              { bin: "lollypop",   cmd: "lollypop" },
              { bin: "amberol",    cmd: "amberol" },
              { bin: "gnome-music", cmd: "gnome-music" },
              { bin: "flatpak", cmd: "flatpak run io.bassi.Amberol", check: "flatpak info io.bassi.Amberol >/dev/null 2>&1" },
              { bin: "flatpak", cmd: "flatpak run org.gnome.Rhythmbox3", check: "flatpak info org.gnome.Rhythmbox3 >/dev/null 2>&1" },
              { bin: "flatpak", cmd: "flatpak run com.spotify.Client", check: "flatpak info com.spotify.Client >/dev/null 2>&1" },
              { bin: "gtk-launch", cmd: "gtk-launch \"$(xdg-mime query default audio/mpeg)\"",
                check: "command -v gtk-launch >/dev/null && [ -n \"$(xdg-mime query default audio/mpeg 2>/dev/null)\" ]" }
          ],
          hint: { what: "No music app installed", store: "music player" },
          appIds: ["rhythmbox", "org.gnome.rhythmbox3", "spotify", "lollypop", "io.bassi.amberol", "org.gnome.music"] },
        { id: "data",      label: "DATA", own: true, appIds: [] },   // apps/data
        { id: "accessory", label: "ACCESSORY", own: true,
          appIds: ["gnome-control-center", "org.gnome.settings"] }
    ]

    // Desktop entries the launcher never lists (by id): helpers and duplicates
    // that installed packages ship. Foot stays; its client/server variants go.
    readonly property var launcherHidden: [
        "footclient", "foot-server", "debian-xterm", "debian-uxterm", "xterm", "uxterm"
    ]

    // Terminal candidates for the desktop menu.
    readonly property var terminals: [
        { bin: "foot", cmd: "foot" }, { bin: "kitty", cmd: "kitty" },
        { bin: "ptyxis", cmd: "ptyxis" }, { bin: "xterm", cmd: "xterm" }
    ]

    // ---- NekoMail unread badge (MAILER rail button, see RailButton.qml `badge`) ----
    // NekoMail's server rewrites this file (a plain integer: total inbox unread) atomically whenever
    // the count changes; no auth needed. Missing file or 0 = no badge. The watcher reloads on change;
    // the timer also catches the atomic rename replacing the watched inode.
    readonly property string mailUnreadFile: Quickshell.env("NEKOMAIL_UNREAD_FILE")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nekomail/unread")
    property int mailUnread: 0
    FileView {
        id: mailUnreadView
        path: root.mailUnreadFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const n = parseInt(text().trim()); root.mailUnread = isNaN(n) || n < 0 ? 0 : n; }
        onLoadFailed: root.mailUnread = 0
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: mailUnreadView.reload() }

    // Detected launch commands: { appId: cmd } (missing key = nothing installed).
    property var resolved: ({})
    property string terminalCmd: ""
    property bool detected: false

    // Command for an app id, or "" when unavailable. Own-window apps are always available.
    function commandFor(id) { return resolved[id] || ""; }
    function available(app) { return !detected || !!app.own || !!resolved[app.id]; }
    function appById(id) { for (const a of apps) if (a.id === id) return a; return null; }

    // Run an app's resolved command, or say nothing is installed and open STORE on a search for one.
    function launchApp(app) {
        const cmd = commandFor(app.id);
        if (cmd) { Quickshell.execDetached(["sh", "-c", cmd]); return true; }
        if (app.hint) {
            Toasts.show(app.label, app.hint.what + ". Opening STORE…");
            Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-store"), "--search", app.hint.store]);
        }
        redetect();
        return false;
    }
    // Probe again: something may have been installed since (STORE, apt). Also every minute, so the
    // rail's NOT INSTALLED goes away on its own.
    function redetect() { probe.running = false; probe.running = true; }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.redetect() }
    function openTerminal() {
        if (terminalCmd) Quickshell.execDetached(["sh", "-c", terminalCmd]);
        else Toasts.show("Terminal", "No terminal installed — try:", "sudo apt install foot");
    }

    // One shell run probes every candidate; output lines are "<id> <index>" / "term <index>".
    Process {
        id: probe
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
