// StatusBlock.qml - clock, date and system row, top-right (layer: bottom, no exclusive zone).
// NET / iGPU / NV / VOL are placeholders for now.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { top: true; right: true }
    margins { top: 16; right: 24 }
    implicitWidth: 300
    implicitHeight: 84
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "ultimit-status"
    mask: Region {}   // purely informational: let clicks fall through

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property var days: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    Column {
        anchors.right: parent.right
        spacing: 0

        Text {
            anchors.right: parent.right
            text: win.p2(win.now.getHours()) + ":" + win.p2(win.now.getMinutes()) + ":" + win.p2(win.now.getSeconds())
            color: Theme.fg
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
        Item { width: 1; height: 6 }
        Row {
            anchors.right: parent.right
            spacing: 14
            Repeater {
                model: [
                    { k: "NET", dot: true }, { k: "iGPU", dot: true },
                    { k: "NV 1650", dot: true }, { k: "VOL 72", dot: false }
                ]
                delegate: Row {
                    required property var modelData
                    spacing: 4
                    Text {
                        text: modelData.k
                        color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                    }
                    Text {
                        visible: modelData.dot
                        text: "●"
                        color: Theme.ok
                        font.family: Theme.mono; font.pixelSize: 10
                    }
                }
            }
        }
    }
}
