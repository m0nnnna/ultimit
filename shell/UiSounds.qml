pragma Singleton

// UiSounds.qml - short quiet HUD blips (assets/sounds/*.wav, made by assets/sounds/make-sounds.py).
// Config.uiSounds (default off) and Config.uiSoundVolume (0..100) from Settings > Appearance > Effects.
// Played with pw-play (paplay as fallback) in a detached process, so the shell never waits on audio.
// Never while a fullscreen window is up, and at most one blip per name every 120 ms.
//   flyout   a tray flyout opens          launcher  the launcher opens        notify  a popup appears
//   lock / unlock   (LockScreen.qml calls play)
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool allowed: Config.uiSounds && Config.uiSoundVolume > 0 && !Config.fullscreenActive
    property var last: ({})
    property int seen: 0

    function play(name, force) {
        if (!force && !root.allowed) return;
        const now = Date.now();
        if (now - (root.last[name] || 0) < 120) return;
        root.last[name] = now;
        const v = Math.max(0, Math.min(100, Config.uiSoundVolume)) / 100;
        Quickshell.execDetached(["sh", "-c",
            'pw-play --volume "$1" "$2" 2>/dev/null || paplay --volume "$3" "$2" 2>/dev/null',
            "sh", v.toFixed(2), Quickshell.shellPath("../assets/sounds/" + name + ".wav"), String(Math.round(v * 65536))]);
    }
    // The Settings "Play a sample" button: plays even while the master switch is off.
    function test() { root.play("notify", true); }

    Connections {
        target: FlyoutState
        function onOpenChanged() { if (FlyoutState.open) root.play("flyout"); }
    }
    Connections {
        target: Config
        function onLauncherOpenChanged() { if (Config.launcherOpen) root.play("launcher"); }
    }
    Connections {
        target: Notifs

        function onPopupCountChanged() {
            if (Notifs.popupCount > root.seen) root.play("notify");
            root.seen = Notifs.popupCount;
        }
    }
}
