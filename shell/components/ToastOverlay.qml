// ToastOverlay.qml - renders Notifs.popups (D-Bus notifications + Toasts.show) top-right, under the clock block
// (mockup .toast: panel, strong 1px line, 3px accent left bar, mono caps title).
// Overlay layer; the window is only mapped while toasts exist and is sized to them.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    // Set by shell.qml (avoids a visible <-> screen binding loop).
    property string screenName: ""

    anchors { top: true; right: true }
    // Starts 8px under the desktop clock block (StatusBlock.qml: 16px from the top; every output
    // shows the clock, Config.clockHeight is its current height, so the graph style pushes the toasts down).
    margins { top: 16 + Config.clockHeight + 8; right: 20 }
    implicitWidth: 340
    implicitHeight: Math.max(1, col.implicitHeight)
    visible: Notifs.popupCount > 0 && Config.isUiScreen(screenName)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-toasts"

    Column {
        id: col
        width: parent.width
        spacing: 8

        move: Transition { NumberAnimation { properties: "y"; duration: Config.dur(180); easing.type: Easing.OutCubic } }

        Repeater {
            model: Notifs.popups
            delegate: NotifCard { width: col.width }
        }
    }
}
