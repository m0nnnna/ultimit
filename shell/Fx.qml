pragma Singleton

// Fx.qml - the one clock behind the travelling edge light (components/GlowFrame.qml).
// Every GlowFrame that is lit and visible counts itself in glowUsers; the clock runs only while there
// is one, travelling is on, motion is on and no fullscreen window (or lock/dim) holds the desktop
// paused. 25 steps a second is plenty for a light that takes six seconds to go round, and one
// timer serves every frame on every screen.
import QtQuick
import Quickshell

Singleton {
    id: root

    property int glowUsers: 0
    property real glowPhase: 0          // 0..1, one lap of the frame
    readonly property real lapMs: 6000
    readonly property int stepMs: 40
    readonly property bool travelOn: Config.edgeGlow === "travel" && Config.motion && !Config.desktopPaused

    Timer {
        interval: root.stepMs
        repeat: true
        running: root.travelOn && root.glowUsers > 0
        onTriggered: root.glowPhase = (root.glowPhase + root.stepMs / root.lapMs) % 1
    }
}
