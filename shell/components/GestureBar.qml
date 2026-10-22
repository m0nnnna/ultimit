// GestureBar.qml - phone navigation strip along the bottom (ULTIMIT_MOBILE=1).
//   swipe up             home (every app minimized, the app grid shows)
//   swipe up and hold    app switcher (MobileSwitcher.qml)
//   swipe left / right   back to the previous app
// The pressed surface keeps the pointer until release (compositor implicit grab), so a drag
// is tracked well past this thin strip. Overlay layer, so it also works over fullscreen apps.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { left: true; right: true; bottom: true }
    implicitHeight: Config.gestureH
    exclusiveZone: Config.gestureH
    color: Theme.rail
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-gestures"

    Rectangle {
        id: pill
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.max(-6, drag.dy / 12)
        width: 120; height: 4; radius: 2
        color: Theme.fg
        opacity: drag.pressed ? 1 : .7
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        property real x0: 0
        property real y0: 0
        property real dy: 0
        property double lastMove: 0
        onPressed: mouse => { x0 = mouse.x; y0 = mouse.y; dy = 0; lastMove = Date.now(); }
        onPositionChanged: mouse => {
            const ndy = mouse.y - y0;
            if (Math.abs(ndy - dy) > 6) lastMove = Date.now();
            dy = ndy;
        }
        onReleased: mouse => {
            const dx = mouse.x - x0, up = y0 - mouse.y;
            dy = 0;
            if (up > 36 && up > Math.abs(dx)) {
                // A pause at the end (finger held still), or a long pull: the switcher.
                if (Date.now() - lastMove > 220 || up > win.screen.height * .45) {
                    if (Config.switcherOpen) MobileState.home(); else Config.switcherOpen = true;
                } else {
                    MobileState.home();
                }
            } else if (Math.abs(dx) > 60) {
                MobileState.previous();
            }
        }
    }
}
