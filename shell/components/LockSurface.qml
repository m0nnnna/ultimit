// LockSurface.qml - one lock-screen surface (per output): an ext-session-lock surface holding a
// LockView. The password card is shown on the first screen only; every surface accepts keystrokes
// (state lives in LockScreen `ctl`).
import QtQuick
import Quickshell.Wayland
import ".."

WlSessionLockSurface {
    id: surf
    required property var ctl
    color: "#000000"

    LockView {
        anchors.fill: parent
        ctl: surf.ctl
        primary: surf.screen !== null && Config.isMainScreen(surf.screen.name)
    }
}
