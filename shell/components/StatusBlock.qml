// StatusBlock.qml - big desktop clock and date, top-right (layer: bottom, no exclusive zone). The live
// NET / BT / BAT / VOL readout moved to the bottom-bar tray (StatusTray.qml).
// The text block is clickable (toggles the quick settings panel, anchored top right as before); the rest of the window is
// click-through via the input mask.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { top: true; right: true }
    margins { top: 16; right: 24 }
    implicitWidth: 460
    implicitHeight: 56
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "ultimit-status"
    mask: Region { item: block }   // only the text extent takes clicks

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property var days: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    Column {
        id: block
        anchors.right: parent.right
        spacing: 0

        Text {
            anchors.right: parent.right
            text: ((win.now.getHours() % 12) || 12) + ":" + win.p2(win.now.getMinutes()) + ":" + win.p2(win.now.getSeconds()) + (win.now.getHours() < 12 ? " AM" : " PM")
            color: hit.containsMouse || SysState.qsOpen ? Theme.accent : Theme.fg
            font.family: Theme.mono; font.pixelSize: 26
            font.letterSpacing: 1.56
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.right: parent.right
            text: win.now.getFullYear() + "." + win.p2(win.now.getMonth() + 1) + "." + win.p2(win.now.getDate()) + " " + win.days[win.now.getDay()]
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 11
            font.letterSpacing: 2.42
        }
    }

    MouseArea {
        id: hit
        x: block.x; y: block.y; width: block.width; height: block.height
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: SysState.toggleQs(win.screen ? win.screen.name : "", "top")
    }
}
