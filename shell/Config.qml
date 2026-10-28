pragma Singleton

// Config.qml - user-tweakable settings and defaults for the Ultimit shell.
// Everything configurable lives here so the components stay generic.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root
    // The real version, the way About and ultimit-update know it: /opt/ultimit/VERSION when installed
    // (a release tag or tag-N-gHASH), else `git describe` in a checkout. "" until read (or if neither exists).
    property string version: ""
    // v1.0.0-26-gcf8dd64 -> v1.0.0-26 (the commit hash is for About)
    readonly property string versionShort: version.replace(/-g[0-9a-f]+/, "").replace(/-dirty$/, "")
    Process {
        running: true
        command: ["sh", "-c", "cat \"$1/../VERSION\" 2>/dev/null || git -C \"$1\" describe --tags --always --dirty 2>/dev/null", "sh", Quickshell.shellDir]
        stdout: StdioCollector { onStreamFinished: root.version = text.trim() }
    }

    // Wallpaper animation. When false the wallpaper is drawn once (zero idle cost).
    // Set ULTIMIT_MOTION=0 in the environment to start with motion off.
    property bool motion: Quickshell.env("ULTIMIT_MOTION") !== "0"
    // The shard wallpaper moves (when motion is on too). Off: drawn once, still, while windows and
    // panels keep their animations. Settings > Appearance > Wallpaper.
    property bool wallpaperMotion: true
    // Wallpaper redraw rate cap while motion is on.
    property int wallpaperFps: 20
    // The wallpaper's turning arc: smooth at 60 steps a second without making three monitors
    // repaint at their full 144-180 Hz.
    property int wallpaperSpinFps: 60
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
    // Icons of other apps (launcher, windows, Alt-Tab, pins): "letters" draws a letter tile in the
    // skin's colours, "original" shows the app's own icon (Settings > Appearance). Ultimit's apps,
    // and apps the Ultimit theme draws, always keep their skin icons.
    property string appIcons: "letters"
    // Mouse cursor style (theme/cursors), Settings > Appearance: "izy" white darts, "shard" crystal shards.
    property string cursorStyle: "izy"
    // ---- effects (Settings > Appearance > Effects; Fx.qml, UiSounds.qml, SysStats.qml, WallpaperArt.qml) ----
    // Soft accent glow along panel edges (rail, flyouts, launcher, notification cards): "off" | "still" | "travel"
    // (a slow light runs along the frame; it stops with motion off or while a fullscreen window is up).
    property string edgeGlow: "travel"
    // Titles scramble for ~150 ms and settle when a panel opens (DecodeText.qml).
    property bool decodeText: true
    // The shard wallpaper reacts to the pointer, to the sound the PC plays, and shifts when the focused
    // window changes (Ultimit has no workspaces). Shards only; all stop with motion off or a fullscreen window.
    property bool reactPointer: true
    property bool reactAudio: true
    property bool reactWorkspace: true
    // Short synthesized blips (assets/sounds); never while a fullscreen window is up.
    property bool uiSounds: false
    property int uiSoundVolume: 40
    // Game Mode (GameMode.qml; Settings > Power > Game Mode): the desktop goes quiet while a game is in front.
    property bool gameModeEnabled: true
    property bool gameModePower: true      // switch power-profiles-daemon to "performance" meanwhile
    property bool gameModeHold: true       // hold notification toasts (critical ones still show)
    property bool gameModeActive: false    // set by GameMode.qml
    // A fullscreen window covers some screen: effects that cost frames stand down.
    readonly property bool fullscreenActive: coveredScreens.length > 0

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
    // Output names a fullscreen (not minimized) window currently covers. Nothing behind it is seen,
    // so the wallpaper, news ticker and rail on those screens pause their animations.
    readonly property var coveredScreens: {
        const out = [];
        for (const t of ToplevelManager.toplevels.values) {
            if (!t.fullscreen || t.minimized) continue;
            for (const s of t.screens)
                if (s && out.indexOf(s.name) < 0) out.push(s.name);
        }
        return out;
    }
    function isCovered(name) { return name !== "" && coveredScreens.indexOf(name) >= 0; }
    // A fullscreen window on any screen (a game, mostly): every screen's desktop animations stop
    // (wallpaper shards and hex flicker, news ticker, rail spin, the clock's seconds), so they
    // take nothing from the GPU while it plays. Window animations are not affected.
    // Locked or dimmed (LockScreen.qml sets desktopIdle): nobody is watching, so the same pause.
    readonly property bool desktopPaused: coveredScreens.length > 0 || desktopIdle || gameModeActive
    property bool desktopIdle: false
    // Rail icon turntables share one 30 Hz clock (Rail icons step together: one repaint per
    // step instead of one per icon). RailButton counts itself in railSpinners while it turns.
    property int railSpinners: 0
    property int railTick: 0
    Timer { interval: 33; repeat: true; running: root.railSpinners > 0; onTriggered: root.railTick++ }
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
    property bool lockAnimated: true
    // Bumped to ask LockScreen.qml to lock (IPC `lock lock`, quick settings, launcher, Super+L).
    property int lockRequest: 0
    function lock() { lockRequest++; }

    // Layout metrics (px)
    readonly property int railWidth: 84
    readonly property int barHeight: 32   // the top bar (TopBar.qml): app menu, news ticker, status, tray, time
    // Right side of the top bar, left to right. Each name is a component file
    // components/bar/<Name>Item.qml (the "plugin" slot sits before the first one: TopBar.qml pluginSlot).
    // Add an item: drop a file in components/bar/ and list its name here.
    property var barItems: ["Privacy", "Network", "Bluetooth", "Sound", "Battery", "Bell", "Claude", "Tray", "Clock"]
    // News ticker inside the top bar (Settings > News).
    property bool tickerOn: true
    // Desktop notifications also crawl in the ticker, newest first, until read or this old.
    property bool tickerNotifs: true
    property int tickerNotifMinutes: 10
    // How long the pointer must rest on the top edge before the bar slides over a fullscreen window
    // while Game Mode is on (a plain flick is enough otherwise).
    readonly property int revealDwellGame: 400

    // ---- launcher / context menu state (see components/Launcher.qml, ContextMenu.qml) ----
    property bool launcherOpen: false
    property bool shortcutsOpen: false   // the keyboard shortcut sheet (Super+/)
    property bool menuOpen: false
    // Screen name the open launcher/menu belongs to ("" = first screen).
    property string uiScreen: ""
    property real menuX: 0
    property real menuY: 0
    property string menuFrame: ""   // the photo frame (Frames.qml) the menu was opened on, "" = the desktop
    function openLauncher(screenName) { menuOpen = false; uiScreen = screenName || ""; launcherOpen = true; }
    function closeLauncher() { launcherOpen = false; }
    function toggleLauncher(screenName) { if (launcherOpen) closeLauncher(); else openLauncher(screenName); }
    function openMenu(screenName, x, y, frame) { launcherOpen = false; uiScreen = screenName || ""; menuX = x; menuY = y; menuFrame = frame || ""; menuOpen = true; }
    function closeMenu() { menuOpen = false; }
    // Once nothing is open the screen is forgotten, so the OSD and password prompt go back to the main display.
    onLauncherOpenChanged: if (!launcherOpen && !menuOpen) uiScreen = ""
    onMenuOpenChanged: if (!launcherOpen && !menuOpen) uiScreen = ""
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
    // Rail on every display ("all", like Windows' taskbar) or on the main one only. The top bar
    // (menu, ticker, status, tray, time) is always on the main display only.
    property string barsOn: "all"
    function showsBars(name) { return barsOn === "all" || isMainScreen(name); }

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
//  ownTitles - titles of that window (app_id org.quickshell): what the rail matches it by
    readonly property var apps: [
        { id: "www",       label: "WWW",
          tryCmds: [
              // The default browser first (Settings > Default apps), then common ones.
              { bin: "gtk-launch", cmd: "gtk-launch \"$(xdg-settings get default-web-browser)\"",
                check: "command -v gtk-launch >/dev/null && [ -n \"$(xdg-settings get default-web-browser 2>/dev/null)\" ]" },
              { bin: "firefox",  cmd: "firefox" },
              { bin: "flatpak", cmd: "flatpak run org.mozilla.firefox", check: "flatpak info org.mozilla.firefox >/dev/null 2>&1" },
              { bin: "chromium", cmd: "chromium" },
              { bin: "google-chrome", cmd: "google-chrome" },
              { bin: "brave-browser", cmd: "brave-browser" }
          ],
          hint: { what: "No web browser installed", store: "web browser" },
          appIds: ["firefox", "org.mozilla.firefox", "firefox-esr", "librewolf", "io.gitlab.librewolf-community", "zen", "zen-browser", "floorp",
                   "google-chrome", "google-chrome-stable", "com.google.chrome", "chromium", "chromium-browser", "org.chromium.chromium",
                   "io.github.ungoogled_software.ungoogled_chromium", "brave-browser", "com.brave.browser", "vivaldi-stable", "microsoft-edge",
                   "org.gnome.epiphany", "epiphany", "org.kde.falkon", "falkon"] },   // + the default browser's desktop id (RailWindows.qml)
        // GAMES owns only Ultimit's own library window. Steam / Lutris / Heroic are separate apps (Steam
        // idles minimized in the tray for hours, which used to light GAMES up forever): their windows
        // are listed under WINDOWS like any other.
        { id: "games",     label: "GAMES",     own: true, ownTitles: ["GAMES"], appIds: [] },
        { id: "mailer",    label: "MAILER",
          tryCmds: [
              // NekoMail (Ultimit's own mail app, /opt/ultimit/nekomail, scripts/build-nekomail.sh): the `nekomail`
              // window command (single instance; starts its background service if needed).
              // ~/.local/bin is where a per-user install from the NekoMail repo puts it, which a session PATH may lack.
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
          // Opens a site in the browser: the windows belong to WWW (a window has one owner on the rail).
          appIds: [] },
        { id: "audio",     label: "AUDIO",
          tryCmds: [
              // NekoPlayer (Ultimit's own music player, /opt/ultimit/nekoplayer,
              // scripts/build-nekoplayer.sh); one window per user. ~/.local/bin: a per-user
              // install from the NekoPlayer repo.
              { bin: "nekoplayer", cmd: "$(command -v nekoplayer || echo \"$HOME/.local/bin/nekoplayer\")",
                check: "command -v nekoplayer >/dev/null 2>&1 || [ -x \"$HOME/.local/bin/nekoplayer\" ]" },
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
          appIds: ["nekoplayer", "rhythmbox", "org.gnome.rhythmbox3", "spotify", "lollypop", "io.bassi.amberol", "org.gnome.music"] },
        { id: "data",      label: "DATA", own: true, ownTitles: ["DATA"], appIds: [] },   // apps/data
        { id: "term",      label: "CONSOLE",
          tryCmds: [
              { bin: "foot", cmd: "foot" }, { bin: "kitty", cmd: "kitty" }, { bin: "ptyxis", cmd: "ptyxis" },
              { bin: "gnome-terminal", cmd: "gnome-terminal" }, { bin: "xterm", cmd: "xterm" }
          ],
          hint: { what: "No terminal installed", store: "terminal" },
          appIds: ["foot", "kitty", "org.gnome.ptyxis", "ptyxis", "org.gnome.terminal", "gnome-terminal-server", "xterm"] },
        { id: "accessory", label: "ACCESSORY", own: true, ownTitles: ["SETTINGS"],
          appIds: ["gnome-control-center", "org.gnome.settings"] }
    ]

    // Desktop entries the launcher never lists (by id): helpers and duplicates
    // that installed packages ship. Foot stays; its client/server variants go.
    readonly property var launcherHidden: [
        "footclient", "foot-server", "debian-xterm", "debian-uxterm", "xterm", "uxterm",
        "com.anthropic.Claude"   // the Claude desktop app: Ultimit's own CLAUDE (ultimit-claude) is the one listed
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

    // One shell run probes every candidate; output lines are "<id> <index>" / "_term <index>" (the
    // desktop menu's terminal; not "term", which is the CONSOLE app's id).
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
                    if (p[0] === "_term") { if (term < 0) term = i; continue; }
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
        terminals.forEach((c, i) => { s += "if command -v " + c.bin + " >/dev/null 2>&1; then echo '_term " + i + "'; fi\n"; });
        return s;
    }

    // Built-in ticker items, shown only when no feed is set or none has loaded yet: true and
    // stable (no fake news). { t: label, h: headline }
    readonly property var headlines: [
        { t: "TIP", h: "Right-click the desktop for the menu, skins and wallpaper" },
        { t: "TIP", h: "The tray icons open flyouts for network, sound, Bluetooth, battery and the clock" },
        { t: "TIP", h: "Settings > News sets the feeds shown here" },
        { t: "TIP", h: "Seven skins, switchable at any time or by time of day" }
    ]
}
