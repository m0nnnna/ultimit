// Persist.qml - loads/saves user settings (skin, motion, shard density, boot-on-start, rail pins, news feeds)
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
        if (!root.envMotion) Config.motion = a.motion;
        Config.railSpin = a.railSpin;
        if (!root.envBoot) Config.bootOnStart = a.bootOnStart;
        Config.shardDensity = clampDensity(a.shardDensity);
        if (!root.envDim) Config.dimAfter = a.dimAfter;
        if (!root.envLock) Config.lockAfter = a.lockAfter;
        if (!root.envSuspend) Config.suspendAfter = a.suspendAfter;
        if (!root.envSuspendAC) Config.suspendOnAC = a.suspendOnAC;
        root.applyRailNews();
    }
    function applyRailNews() {
        const a = store.adapter;
        Pins.setSpecs(root.envPins ? Pins.fromTokens(Quickshell.env("ULTIMIT_PINS")) : a.pins);
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
        if (!root.envMotion && a.motion !== Config.motion) { a.motion = Config.motion; changed = true; }
        if (a.railSpin !== Config.railSpin) { a.railSpin = Config.railSpin; changed = true; }
        if (a.shardDensity !== Config.shardDensity) { a.shardDensity = Config.shardDensity; changed = true; }
        if (!root.envBoot && a.bootOnStart !== Config.bootOnStart) { a.bootOnStart = Config.bootOnStart; changed = true; }
        if (!root.envDim && a.dimAfter !== Config.dimAfter) { a.dimAfter = Config.dimAfter; changed = true; }
        if (!root.envLock && a.lockAfter !== Config.lockAfter) { a.lockAfter = Config.lockAfter; changed = true; }
        if (!root.envSuspend && a.suspendAfter !== Config.suspendAfter) { a.suspendAfter = Config.suspendAfter; changed = true; }
        if (!root.envSuspendAC && a.suspendOnAC !== Config.suspendOnAC) { a.suspendOnAC = Config.suspendOnAC; changed = true; }
        if (!root.envPins && JSON.stringify(a.pins) !== JSON.stringify(Pins.specs)) { a.pins = Pins.specs; changed = true; }
        if (!root.envFeeds && JSON.stringify(a.feeds) !== JSON.stringify(Feeds.urls)) { a.feeds = Feeds.urls; changed = true; }
        if (changed) save.restart();
    }

    // Window chrome is drawn by the compositor; give it the skin's colors.
    function pushChrome() { Quickshell.execDetached(["ultimitctl", "skin"].concat(Theme.chromeArgs)); }

    Component.onCompleted: {
        root.pushChrome();
        Quickshell.execDetached(["mkdir", "-p", root.dir]);
        store.path = root.dir + "/shell.json";
    }

    Timer {
        id: fastfetchTimer
        interval: 1500
        onTriggered: Quickshell.execDetached([Quickshell.shellPath("../session/ultimit-fastfetch-config")])
    }
    Connections {
        target: Theme
        function onSkinChanged() {
            root.push();
            root.pushChrome();
            // Re-colour the mouse cursor with the skin (theme/cursors).
            const name = "UltimitCursor-" + Theme.skin.charAt(0).toUpperCase() + Theme.skin.slice(1);
            Quickshell.execDetached(["sh", "-c", "[ -e \"$HOME/.local/share/icons/" + name + "/cursors/default\" ] && ultimitctl cursor-theme " + name + " && gsettings set org.gnome.desktop.interface cursor-theme " + name]);
            // fastfetch colours follow the skin too (after shell.json is written).
            fastfetchTimer.restart();
        }
    }
    Connections {
        target: Config
        function onMotionChanged() { root.push(); }
        function onRailSpinChanged() { root.push(); }
        function onShardDensityChanged() { root.push(); }
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
            property bool motion: true
            property string railSpin: "always"
            property int shardDensity: 34
            property bool bootOnStart: true
            property real dimAfter: 300
            property real lockAfter: 360
            property real suspendAfter: 900
            property bool suspendOnAC: false
            property var pins: [   // rail pinned items, in order (see Pins.qml); ACCESSORY is always kept
                { id: "games", label: "GAMES", icon: "games" }, { id: "mailer", label: "MAILER", icon: "mailer" },
                { id: "news", label: "NEWS", icon: "news" }, { id: "audio", label: "AUDIO", icon: "audio" },
                { id: "data", label: "DATA", icon: "data" }, { id: "accessory", label: "ACCESSORY", icon: "accessory" }
            ]
            property var feeds: ["https://meowops.net/feed.xml"]   // news ticker feeds; [] = built-in headlines
        }
    }
}
