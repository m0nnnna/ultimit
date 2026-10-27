// Flyout.qml - Windows-11-style tray flyouts: one glass panel per tray icon, anchored just above
// that icon at the bottom right (state: FlyoutState.qml; content: flyout/<Kind>Flyout.qml).
// Overlay-layer, full-screen transparent window like Launcher.qml, so a click outside closes it,
// but the tray cluster is punched out of its input region: the same icon toggles the flyout
// closed and another icon switches to its flyout. It holds the keyboard (Escape closes) only
// while shown and stays mapped until the fade-out ends. Unfolds from the icon (scale) plus fade, Config.dur().
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../apps/accessory"

PanelWindow {
    id: win

    // Set by shell.qml (avoids a visible <-> screen binding loop).
    property string screenName: ""

    readonly property bool shown: FlyoutState.open && FlyoutState.screen === screenName
    property real reveal: shown ? 1 : 0
    ShowBehavior on reveal {}
    property real swap: 1          // quick re-fade when switching icons while open
    NumberAnimation { id: swapAnim; target: win; property: "swap"; from: 0; to: 1; duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase }
    Connections {
        target: FlyoutState
        function onKindChanged() { if (win.shown && win.reveal > 0.5 && Config.motion) swapAnim.restart(); }
    }

    visible: shown || reveal > 0.001
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-flyout"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    mask: shown ? hitRegion : noInput
    Region { id: noInput }
    Region {
        id: hitRegion
        x: 0; y: 0; width: win.width; height: win.height
        Region {
            intersection: Intersection.Subtract
            x: FlyoutState.trayX; y: win.height - Config.tickerHeight
            width: FlyoutState.trayW; height: Config.tickerHeight
        }
    }

    onShownChanged: if (shown) keys.forceActiveFocus()

    MouseArea {   // click outside closes
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: FlyoutState.close()
    }

    readonly property real panelW: FlyoutState.kind === "clock" ? 380 : 372
    readonly property real iconX: FlyoutState.anchors[FlyoutState.kind] !== undefined ? FlyoutState.anchors[FlyoutState.kind] : win.width - 40

    Surface {
        id: panel
        glow: true; brackets: true
        elevation: 2; shadowNs: "ultimit-flyout"; shadowWanted: win.shown
        width: win.panelW
        readonly property real maxH: win.height - Config.tickerHeight - 6 - 12
        height: Math.min((ld.item ? ld.item.implicitHeight : 60) + Theme.space(8), maxH)
        // centred over the icon, clamped inside the output
        x: Math.max(8, Math.min(win.iconX - width / 2, win.width - width - 8))
        y: win.height - Config.tickerHeight - 6 - height
        opacity: win.reveal * win.swap
        // scales out of the tray icon (the shared panel recipe): grows from the tick at its bottom edge (reveal is 0/1 without motion)
        transform: Scale {
            origin.x: Math.max(0, Math.min(win.iconX - panel.x, panel.width))
            origin.y: panel.height
            xScale: Theme.showScale + (1 - Theme.showScale) * win.reveal
            yScale: Theme.showScale + (1 - Theme.showScale) * win.reveal
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton }   // swallow clicks

        Rectangle {   // tick pointing at the icon
            x: Math.max(10, Math.min(win.iconX - panel.x - width / 2, panel.width - width - 10))
            y: parent.height - 1
            width: 14; height: 3
            color: Theme.accent
        }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: {
                if (ld.item && ld.item.handleEscape && ld.item.handleEscape()) return;
                FlyoutState.close();
            }

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: Theme.space(4)
                contentWidth: width
                contentHeight: ld.item ? ld.item.implicitHeight : 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Loader {
                    id: ld
                    width: flick.width
                    active: win.visible
                    source: {
                        switch (FlyoutState.kind) {
                        case "network": return "flyout/NetworkFlyout.qml";
                        case "sound": return "flyout/SoundFlyout.qml";
                        case "bluetooth": return "flyout/BluetoothFlyout.qml";
                        case "battery": return "flyout/BatteryFlyout.qml";
                        case "clock": return "flyout/ClockFlyout.qml";
                        }
                        return "";
                    }
                }
            }
        }
    }
}
