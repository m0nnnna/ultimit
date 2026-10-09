// Ticker.qml - bottom news ticker (layer: top, exclusive zone = ticker height).
// Accent "NEWS" tab on the left, headlines scrolling right-to-left.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { left: true; right: true; bottom: true }
    margins { left: Config.railWidth }   // sit beside the rail, not under it
    implicitHeight: Config.tickerHeight
    exclusiveZone: Config.tickerHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ultimit-ticker"

    // Pre-built rich text: "<time> headline  ◆  ..." with the time in the fg color.
    readonly property string html: {
        const sep = "&nbsp;&nbsp;&nbsp;◆&nbsp;&nbsp;&nbsp;";
        return Config.headlines.map(function (n) {
            return "<font color='" + Theme.fg + "'>" + n.t + "</font>&nbsp;&nbsp;" + n.h;
        }).join(sep);
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rail
        Rectangle { width: parent.width; height: 1; color: Theme.line }   // top border

        Item {
            id: viewport
            anchors { left: tab.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            clip: true

            Text {
                id: msg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: win.html
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 0.88
                x: Config.motion ? viewport.width : 16

                // Constant speed (~48 px/s); restarts when the text or viewport changes.
                NumberAnimation on x {
                    running: Config.motion && viewport.width > 0
                    from: viewport.width
                    to: -msg.implicitWidth
                    duration: Math.max(1000, (viewport.width + msg.implicitWidth) / 48 * 1000)
                    loops: Animation.Infinite
                }
            }
        }

        Rectangle {
            id: tab
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: tabText.implicitWidth + 28
            color: Theme.accent
            Text {
                id: tabText
                anchors.centerIn: parent
                text: "NEWS"
                color: Theme.onAccent
                font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.2
            }
        }
    }
}
