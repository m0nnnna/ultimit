// StatusBlock.qml - big desktop clock and date, top-right (layer: bottom, no exclusive zone). The live
// NET / BT / BAT / VOL readout moved to the bottom-bar tray (StatusTray.qml).
// The text block is clickable (toggles the quick settings panel, anchored top right as before); the rest of the window is
// click-through via the input mask.
// Config.statusStyle "graph" adds a row of live CPU / GPU / RAM / NET sparklines and bars under the
// date (SysStats, sampled once a second only while shown); Config.clockRing adds a segmented seconds
// ring beside the time. Neither runs while a fullscreen window pauses the desktop.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { top: true; right: true }
    margins { top: 16; right: 24 }
    implicitWidth: 460
    implicitHeight: Math.max(56, block.height)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "ultimit-status"
    mask: Region { item: block }   // only the text extent takes clicks

    SystemClock {
        id: clock
        // Minutes (and no seconds shown) while a fullscreen game runs: no per-second redraw.
        precision: Config.desktopPaused ? SystemClock.Minutes : SystemClock.Seconds
    }

    readonly property var days: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    readonly property bool graph: Config.statusStyle === "graph"
    readonly property bool graphOn: graph && visible && !Config.desktopPaused
    onGraphOnChanged: SysStats.users += graphOn ? 1 : -1
    Component.onCompleted: if (graphOn) SysStats.users++
    Component.onDestruction: if (graphOn) SysStats.users--

    Column {
        id: block
        anchors.right: parent.right
        spacing: 0

        Row {
            anchors.right: parent.right
            spacing: 10
            Item {   // seconds ring: 60 segments, the elapsed ones lit
                id: ring
                visible: Config.clockRing && !Config.desktopPaused
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 30 : 0; height: 30
                readonly property real sec: win.now.getSeconds()
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 4; strokeColor: Theme.line; fillColor: "transparent"
                        strokeStyle: ShapePath.DashLine; dashPattern: [0.38, 0.1436]
                        PathAngleArc { centerX: 15; centerY: 15; radiusX: 12; radiusY: 12; startAngle: -90; sweepAngle: 359.9 }
                    }
                    ShapePath {
                        strokeWidth: 4; strokeColor: Theme.accent; fillColor: "transparent"
                        strokeStyle: ShapePath.DashLine; dashPattern: [0.38, 0.1436]
                        PathAngleArc { centerX: 15; centerY: 15; radiusX: 12; radiusY: 12; startAngle: -90; sweepAngle: Math.max(0.1, (ring.sec + 1) * 6 - 0.1) }
                    }
                }
            }
            Text {
                text: ((win.now.getHours() % 12) || 12) + ":" + win.p2(win.now.getMinutes()) + (Config.desktopPaused ? "" : ":" + win.p2(win.now.getSeconds())) + (win.now.getHours() < 12 ? " AM" : " PM")
                color: hit.containsMouse || SysState.qsOpen ? Theme.accent : Theme.fg
                font.family: Theme.mono; font.pixelSize: Theme.size.xl
                font.letterSpacing: 1.56
                font.features: Theme.tnum
            }
        }
        Text {
            anchors.right: parent.right
            text: win.now.getFullYear() + "." + win.p2(win.now.getMonth() + 1) + "." + win.p2(win.now.getDate()) + " " + win.days[win.now.getDay()]
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 11
            font.letterSpacing: 2.42
            font.features: Theme.tnum
        }

        Row {   // graph style: CPU / GPU sparklines, RAM bar, NET sparkline
            id: stats
            anchors.right: parent.right
            topPadding: 8
            spacing: 14
            visible: win.graph
            Repeater {
                model: [
                    { k: "cpu", name: "CPU" },
                    { k: "gpu", name: "GPU" },
                    { k: "mem", name: "RAM" },
                    { k: "net", name: "NET" }
                ]
                delegate: Column {
                    id: cell
                    required property var modelData
                    readonly property string k: modelData.k
                    visible: k !== "gpu" || SysStats.gpu >= 0
                    spacing: 3
                    Row {
                        spacing: 6
                        Text { text: cell.modelData.name; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.size.xs; font.letterSpacing: 1.6 }
                        Text {
                            color: Theme.fg; font.family: Theme.mono; font.pixelSize: Theme.size.xs; font.features: Theme.tnum
                            text: cell.k === "net" ? "\u2193" + SysStats.rate(SysStats.rx) + " \u2191" + SysStats.rate(SysStats.tx)
                                                  : Math.round(cell.k === "cpu" ? SysStats.cpu : cell.k === "gpu" ? SysStats.gpu : SysStats.mem) + "%"
                        }
                    }
                    Spark {
                        visible: cell.k !== "mem"
                        width: 84; height: 16
                        values: cell.k === "cpu" ? SysStats.cpuHist : cell.k === "gpu" ? SysStats.gpuHist : SysStats.netHist
                        max: cell.k === "net" ? 0 : 100
                        floor: 10240
                    }
                    SegBar { visible: cell.k === "mem"; width: 84; height: 16; value: SysStats.mem; segments: 14 }
                }
            }
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
