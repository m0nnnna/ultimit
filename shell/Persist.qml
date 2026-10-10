// Persist.qml - loads/saves user settings (skin, motion, shard density, boot-on-start)
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
        if (!root.envBoot) Config.bootOnStart = a.bootOnStart;
        Config.shardDensity = clampDensity(a.shardDensity);
        if (!root.envDim) Config.dimAfter = a.dimAfter;
        if (!root.envLock) Config.lockAfter = a.lockAfter;
        if (!root.envSuspend) Config.suspendAfter = a.suspendAfter;
        if (!root.envSuspendAC) Config.suspendOnAC = a.suspendOnAC;
    }
    // singletons -> file
    function push() {
        if (!root.ready) return;
        const a = store.adapter;
        let changed = false;
        if (!root.envSkin && a.skin !== Theme.skin) { a.skin = Theme.skin; changed = true; }
        if (!root.envMotion && a.motion !== Config.motion) { a.motion = Config.motion; changed = true; }
        if (a.shardDensity !== Config.shardDensity) { a.shardDensity = Config.shardDensity; changed = true; }
        if (!root.envBoot && a.bootOnStart !== Config.bootOnStart) { a.bootOnStart = Config.bootOnStart; changed = true; }
        if (!root.envDim && a.dimAfter !== Config.dimAfter) { a.dimAfter = Config.dimAfter; changed = true; }
        if (!root.envLock && a.lockAfter !== Config.lockAfter) { a.lockAfter = Config.lockAfter; changed = true; }
        if (!root.envSuspend && a.suspendAfter !== Config.suspendAfter) { a.suspendAfter = Config.suspendAfter; changed = true; }
        if (!root.envSuspendAC && a.suspendOnAC !== Config.suspendOnAC) { a.suspendOnAC = Config.suspendOnAC; changed = true; }
        if (changed) save.restart();
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.dir]);
        store.path = root.dir + "/shell.json";
    }

    Connections { target: Theme;  function onSkinChanged() { root.push(); } }
    Connections {
        target: Config
        function onMotionChanged() { root.push(); }
        function onShardDensityChanged() { root.push(); }
        function onBootOnStartChanged() { root.push(); }
        function onDimAfterChanged() { root.push(); }
        function onLockAfterChanged() { root.push(); }
        function onSuspendAfterChanged() { root.push(); }
        function onSuspendOnACChanged() { root.push(); }
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
            if (error === FileViewError.FileNotFound) store.writeAdapter();   // first run: write defaults
            else console.warn("ultimit: settings load failed:", error);
        }

        adapter: JsonAdapter {
            property string skin: "mine"
            property bool motion: true
            property int shardDensity: 34
            property bool bootOnStart: true
            property real dimAfter: 300
            property real lockAfter: 360
            property real suspendAfter: 900
            property bool suspendOnAC: false
        }
    }
}
