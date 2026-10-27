// OsdOverlay.qml - volume / brightness OSD: slim Altimit bar, centered above the ticker.
// Icon, caps label, animated accent fill, value. Click-through; auto-hides (Osd.qml, 1.2s).
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    property string screenName: ""

    anchors { bottom: true }
    margins { bottom: Config.tickerHeight + 36 }
    implicitWidth: 340
    implicitHeight: 44
    visible: (Osd.shown || box.opacity > 0.01) && Config.isUiScreen(screenName)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-osd"

    readonly property var glyphs: ({
        volume: ["M3 9h4l5-4v14l-5-4H3z", "M15.5 9a4 4 0 010 6M18 6.5a8 8 0 010 11"],
        muted:  ["M3 9h4l5-4v14l-5-4H3z", "M16 9.5l5 5M21 9.5l-5 5"],
        brightness: ["M12 8a4 4 0 100 8 4 4 0 000-8z", "M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"],
        mic:    ["M9 4h6v8a3 3 0 01-6 0z", "M5 11a7 7 0 0014 0M12 18v3"],
        micOff: ["M9 4h6v8a3 3 0 01-6 0z", "M4 4l16 16"]
    })
    readonly property string gname: Osd.kind === "volume" ? (Osd.muted ? "muted" : "volume")
        : (Osd.kind === "mic" ? (Osd.muted ? "micOff" : "mic") : "brightness")

    Rectangle {
        id: box
        anchors.fill: parent
        color: Theme.panel
        border.width: 1; border.color: Theme.lineStrong
        opacity: Osd.shown ? 1 : 0
        ShowBehavior on opacity {}
        scale: Osd.shown ? 1 : Theme.showScale
        ShowBehavior on scale { hidden: Theme.showScale }
        transform: Translate { y: Osd.shown ? 0 : Theme.showOffset; ShowBehavior on y { hidden: Theme.showOffset } }
        Brackets { size: 8 }

        Item {
            id: ico
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22
            Shape {
                width: 24; height: 24
                scale: 22 / 24
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeColor: Osd.muted ? Theme.dim : Theme.accent; strokeWidth: 1.5
                    joinStyle: ShapePath.MiterJoin; capStyle: ShapePath.RoundCap
                    PathSvg { path: win.glyphs[win.gname][0] }
                }
                ShapePath {
                    fillColor: "transparent"; strokeColor: Osd.muted ? Theme.dim : Theme.accent; strokeWidth: 1.5
                    joinStyle: ShapePath.MiterJoin; capStyle: ShapePath.RoundCap
                    PathSvg { path: win.glyphs[win.gname][1] }
                }
            }
        }
        Text {
            id: lbl
            anchors.left: ico.right; anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 92
            text: Osd.label
            color: Osd.muted ? Theme.dim : Theme.fg
            font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2
        }
        Rectangle {   // track
            id: track
            anchors.left: lbl.right; anchors.right: num.left
            anchors.leftMargin: 4; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            color: Theme.line
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(100, Osd.muted ? 0 : Osd.value)) / 100
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
            }
        }
        Text {
            id: num
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            horizontalAlignment: Text.AlignRight
            text: Osd.muted ? "--" : Math.round(Osd.value)
            color: Theme.fg
            font.family: Theme.mono; font.pixelSize: 12
        }
    }
}
