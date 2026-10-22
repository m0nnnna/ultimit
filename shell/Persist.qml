// Persist.qml - loads/saves user settings (skin, accent, motion, shard density, wallpaper, photo frames, boot-on-start, rail pins, news feeds)
// to ~/.config/ultimit/shell.json using FileView + JsonAdapter, and syncs them
// with the Theme / Config singletons in both directions.
// Env overrides (ULTIMIT_SKIN, ULTIMIT_MOTION, ULTIMIT_BOOT) win over the file for that run.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/ultimit"
    property bool ready: false   // true once the file was read (or found missing)

    readonly property bool envSkin: !!Quickshell.env("ULTIMIT_SKIN")
    readonly property bool envMotion: !!Quickshell.env("ULTIMIT_MOTION")
    readonly property bool envBoot: !!Quickshell.env("ULTIMIT_BOOT")
    // ULTIMIT_PINS="games,foot,accessory" and ULTIMIT_FEEDS="url url" ("-" = none) override the file for that run (not saved).
    readonly property bool envPins: !!Quickshell.env("ULTIMIT_PINS")
    readonly property bool envFeeds: !!Quickshell.env("ULTIMIT_FEEDS")

    // Idle timings: an ULTIMIT_*_AFTER / ULTIMIT_SUSPEND_ON_AC env var wins for that run (and is not saved).
    readonly property bool envDim: !!Quickshell.env("ULTIMIT_DIM_AFTER")
    readonly property bool envLock: !!Quickshell.env("ULTIMIT_LOCK_AFTER")
    readonly property bool envSuspend: !!Quickshell.env("ULTIMIT_SUSPEND_AFTER")
    readonly property bool envSuspendAC: !!Quickshell.env("ULTIMIT_SUSPEND_ON_AC")

    function clampDensity(v) { return Math.max(16, Math.min(60, Math.round(v))); }

    // file -> singletons
    function apply() {
        const a = store.adapter;
        if (!root.envSkin && a.skin in Theme.skins) Theme.skin = a.skin;
        Theme.accentOverride = Theme.validAccent(a.accent) ? a.accent.toLowerCase() : "";
        if (!root.envMotion) Config.motion = a.motion;
        Config.railSpin = a.railSpin;
        Config.appIcons = a.appIcons === "original" ? "original" : "letters";
        Config.cursorStyle = a.cursorStyle === "shard" ? "shard" : "izy";
        Config.wallpaperMotion = a.wallpaperMotion;
        if (!root.envBoot) Config.bootOnStart = a.bootOnStart;
        Config.shardDensity = clampDensity(a.shardDensity);
        Config.wallpaper = typeof a.wallpaper === "string" ? a.wallpaper : "";
        Config.barsOn = a.barsOn === "main" ? "main" : "all";
        Config.wallpaperFit = Config.wallpaperFits.indexOf(a.wallpaperFit) >= 0 ? a.wallpaperFit : "fill";
        if (!root.envDim) Config.dimAfter = a.dimAfter;
        if (!root.envLock) Config.lockAfter = a.lockAfter;
        if (!root.envSuspend) Config.suspendAfter = a.suspendAfter;
        if (!root.envSuspendAC) Config.suspendOnAC = a.suspendOnAC;
        Frames.set(Frames.clean(a.frames));
        root.applyRailNews();
    }
    function applyRailNews() {
        const a = store.adapter;
        if (root.envPins) Pins.setSpecs(Pins.fromTokens(Quickshell.env("ULTIMIT_PINS")));
        else {
            const offered = a.pinsOffered || [];
            Pins.setSpecs(Pins.withNew(a.pins, offered));
            if (Pins.laterIds.some(id => offered.indexOf(id) < 0)) {   // new built-ins offered: remember that
                a.pinsOffered = Pins.laterIds; a.pins = Pins.specs; save.restart();
            }
        }
        Feeds.urls = root.envFeeds ? root.envFeedList() : root.cleanFeeds(a.feeds);
        Feeds.start();
    }
    function envFeedList() { const e = Quickshell.env("ULTIMIT_FEEDS").trim(); return e === "-" ? [] : cleanFeeds(e.split(/[\s,]+/)); }
    // Keep only http(s) URLs, no duplicates.
    function cleanFeeds(arr) {
        const out = [];
        for (const u of (arr || [])) if (Feeds.isHttp(u) && out.indexOf(u) < 0) out.push(u);
        return out;
    }
    // singletons -> file
    function push() {
        if (!root.ready) return;
        const a = store.adapter;
        let changed = false;
        if (!root.envSkin && a.skin !== Theme.skin) { a.skin = Theme.skin; changed = true; }
        if (a.accent !== Theme.accentOverride) { a.accent = Theme.accentOverride; changed = true; }
        if (!root.envMotion && a.motion !== Config.motion) { a.motion = Config.motion; changed = true; }
        if (a.railSpin !== Config.railSpin) { a.railSpin = Config.railSpin; changed = true; }
        if (a.appIcons !== Config.appIcons) { a.appIcons = Config.appIcons; changed = true; }
        if (a.cursorStyle !== Config.cursorStyle) { a.cursorStyle = Config.cursorStyle; changed = true; }
        if (a.wallpaperMotion !== Config.wallpaperMotion) { a.wallpaperMotion = Config.wallpaperMotion; changed = true; }
        if (a.shardDensity !== Config.shardDensity) { a.shardDensity = Config.shardDensity; changed = true; }
        if (a.wallpaper !== Config.wallpaper) { a.wallpaper = Config.wallpaper; changed = true; }
        if (a.barsOn !== Config.barsOn) { a.barsOn = Config.barsOn; changed = true; }
        if (a.wallpaperFit !== Config.wallpaperFit) { a.wallpaperFit = Config.wallpaperFit; changed = true; }
        if (!root.envBoot && a.bootOnStart !== Config.bootOnStart) { a.bootOnStart = Config.bootOnStart; changed = true; }
        if (!root.envDim && a.dimAfter !== Config.dimAfter) { a.dimAfter = Config.dimAfter; changed = true; }
        if (!root.envLock && a.lockAfter !== Config.lockAfter) { a.lockAfter = Config.lockAfter; changed = true; }
        if (!root.envSuspend && a.suspendAfter !== Config.suspendAfter) { a.suspendAfter = Config.suspendAfter; changed = true; }
        if (!root.envSuspendAC && a.suspendOnAC !== Config.suspendOnAC) { a.suspendOnAC = Config.suspendOnAC; changed = true; }
        if (!root.envPins && JSON.stringify(a.pins) !== JSON.stringify(Pins.specs)) { a.pins = Pins.specs; changed = true; }
        if (!root.envFeeds && JSON.stringify(a.feeds) !== JSON.stringify(Feeds.urls)) { a.feeds = Feeds.urls; changed = true; }
        if (JSON.stringify(a.frames) !== JSON.stringify(Frames.list)) { a.frames = Frames.list; changed = true; }
        if (changed) save.restart();
    }

    // Window chrome and its animations are the compositor's: give it the skin's colors and the
    // motion setting.
    function pushChrome() {
        Quickshell.execDetached(["ultimitctl", "skin"].concat(Theme.chromeArgs));
        Quickshell.execDetached(["ultimitctl", "motion", Config.motion ? "on" : "off"]);
    }

    Component.onCompleted: {
        root.pushChrome();
        Quickshell.execDetached(["mkdir", "-p", root.dir]);
        store.path = root.dir + "/shell.json";
    }

    Timer {
        id: fastfetchTimer
        interval: 1500
        onTriggered: {
            Quickshell.execDetached([Quickshell.shellPath("../session/ultimit-fastfetch-config")]);
            Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-discord"), "theme"]);
        }
    }
    // A new accent: the GTK themes and cursors are rebuilt with it (both read shell.json, so after
    // it is written), the cursor is reloaded, then fastfetch and Discord follow.
    Timer {
        id: accentTimer
        interval: 1500
        onTriggered: {
            const name = "UltimitCursor-" + Theme.skin.charAt(0).toUpperCase() + Theme.skin.slice(1);
            Quickshell.execDetached(["sh", "-c", "\"$1\" >/dev/null 2>&1; \"$2\" && ultimitctl cursor-theme " + name + " >/dev/null", "sh",
                Quickshell.shellPath("theme/install-gtk-theme.sh"), Quickshell.shellPath("theme/cursors/install-cursors.sh")]);
            fastfetchTimer.restart();
        }
    }
    // A new cursor style: the cursors are rebuilt in it (install-cursors.sh reads shell.json, so
    // after it is written) and reloaded.
    Timer {
        id: cursorTimer
        interval: 1500
        onTriggered: {
            const name = "UltimitCursor-" + Theme.skin.charAt(0).toUpperCase() + Theme.skin.slice(1);
            Quickshell.execDetached(["sh", "-c", "\"$1\" && ultimitctl cursor-theme " + name + " >/dev/null", "sh",
                Quickshell.shellPath("theme/cursors/install-cursors.sh")]);
        }
    }
    Connections {
        target: Theme
        function onAccentOverrideChanged() {
            root.push();
            root.pushChrome();
            if (root.ready) accentTimer.restart();   // at login the session already built them
        }
        function onSkinChanged() {
            root.push();
            root.pushChrome();
            // Re-colour the mouse cursor with the skin (theme/cursors).
            const name = "UltimitCursor-" + Theme.skin.charAt(0).toUpperCase() + Theme.skin.slice(1);
            Quickshell.execDetached(["sh", "-c", "[ -e \"$HOME/.local/share/icons/" + name + "/cursors/default\" ] && ultimitctl cursor-theme " + name + " && gsettings set org.gnome.desktop.interface cursor-theme " + name
                + " && { ! command -v flatpak >/dev/null || flatpak override --user --env=XCURSOR_THEME=" + name + "; }"]);
            // GTK apps started from now on, and Flatpak apps (the browser), take the skin's GTK
            // theme and colour scheme; already open ones keep theirs until restarted.
            const gtk = "Ultimit-" + Theme.skin.charAt(0).toUpperCase() + Theme.skin.slice(1);
            const scheme = Theme.skin === "silver" ? "prefer-light" : "prefer-dark";
            Quickshell.execDetached(["sh", "-c", "gsettings set org.gnome.desktop.interface gtk-theme " + gtk
                + "; gsettings set org.gnome.desktop.interface color-scheme " + scheme
                + "; ! command -v flatpak >/dev/null || flatpak override --user --env=GTK_THEME=" + gtk + " --env=ADW_DEBUG_COLOR_SCHEME=" + scheme]);
            // fastfetch and Discord colours follow the skin too (after shell.json is written).
            fastfetchTimer.restart();
        }
    }
    Connections {
        target: Config
        function onMotionChanged() { root.push(); Quickshell.execDetached(["ultimitctl", "motion", Config.motion ? "on" : "off"]); }
        function onRailSpinChanged() { root.push(); }
        function onAppIconsChanged() { root.push(); }
        function onCursorStyleChanged() {
            root.push();
            if (root.ready) cursorTimer.restart();
        }
        function onWallpaperMotionChanged() { root.push(); }
        function onShardDensityChanged() { root.push(); }
        function onWallpaperChanged() { root.push(); }
        function onWallpaperFitChanged() { root.push(); }
        function onBarsOnChanged() { root.push(); }
        function onBootOnStartChanged() { root.push(); }
        function onDimAfterChanged() { root.push(); }
        function onLockAfterChanged() { root.push(); }
        function onSuspendAfterChanged() { root.push(); }
        function onSuspendOnACChanged() { root.push(); }
    }

    Connections {
        target: Pins
        function onSpecsChanged() { root.push(); }
    }
    Connections {
        target: Feeds
        function onUrlsChanged() { root.push(); }
    }
    Connections {
        target: Frames
        function onListChanged() { root.push(); }
    }

    // Debounce: the density slider fires continuously.
    Timer { id: save; interval: 400; onTriggered: store.writeAdapter() }

    FileView {
        id: store
        printErrors: false
        atomicWrites: true
        watchChanges: false

        onLoaded: { root.apply(); root.ready = true; }
        onLoadFailed: error => {   // typically FileNotFound on first run
            root.ready = true;
            root.applyRailNews();   // no file yet: defaults (or env overrides) still start the ticker feeds
            if (error === FileViewError.FileNotFound) store.writeAdapter();   // first run: write defaults
            else console.warn("ultimit: settings load failed:", error);
        }

        adapter: JsonAdapter {
            property string skin: "mine"
            property string accent: ""   // "#rrggbb" = your own accent on every skin, "" = the skin's
            property bool motion: true
            property string railSpin: "always"
            property string appIcons: "letters"
            property string cursorStyle: "izy"
            property bool wallpaperMotion: true
            property int shardDensity: 34
            property string wallpaper: ""
            property string wallpaperFit: "fill"
            property string barsOn: "all"
            property bool bootOnStart: true
            property real dimAfter: 300
            property real lockAfter: 360
            property real suspendAfter: 900
            property bool suspendOnAC: false
            property var pins: [   // rail pinned items, in order (see Pins.qml); ACCESSORY is always kept
                { id: "www", label: "WWW", icon: "www" }, { id: "games", label: "GAMES", icon: "games" },
                { id: "mailer", label: "MAILER", icon: "mailer" }, { id: "news", label: "NEWS", icon: "news" },
                { id: "audio", label: "AUDIO", icon: "audio" }, { id: "data", label: "DATA", icon: "data" },
                { id: "term", label: "CONSOLE", icon: "term" }, { id: "accessory", label: "ACCESSORY", icon: "accessory" }
            ]
            property var pinsOffered: []   // Pins.laterIds already put into this rail once
            property var feeds: ["https://meowops.net/feed.xml"]   // news ticker feeds; [] = built-in headlines
            property var frames: []   // photo frames on the desktop (see Frames.qml)
        }
    }
}
