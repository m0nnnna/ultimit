// Ticker.qml - bottom news ticker (layer: top, exclusive zone = ticker height).
// Accent "NEWS" tab on the left, headlines scrolling right-to-left, and the system tray cluster
// (StatusTray.qml) at the right end on the primary screen. The ticker clips before the tray.
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand   // Tab / Enter on the tray cluster

    // Headlines: real feed items (Feeds.qml) once any feed has loaded, else the built-in ones from Config.
    // { t: time label, h: headline, link: http(s) URL or "" }
    // Paused while a fullscreen window covers this screen.
    readonly property bool covered: Config.isCovered(win.screen ? win.screen.name : "")

    readonly property var entries: Feeds.hasItems ? Feeds.shown
        : Config.headlines.map(n => ({ t: n.t, h: n.h, link: "" }))

    Rectangle {
        anchors.fill: parent
        color: Theme.rail

        Item {
            id: viewport
            anchors { left: tab.right; right: tray.visible ? tray.left : parent.right; top: parent.top; bottom: parent.bottom }
            clip: true

            // "<time> headline  ◆  ..." scrolling right-to-left. Feed text is untrusted: PlainText only.
            Row {
                id: msg
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                x: Config.motion ? viewport.width : 16

                // Constant speed (~48 px/s); restarts when the text or viewport changes. Paused while hovered
                // or while a fullscreen window is up on any screen.
                NumberAnimation on x {
                    running: Config.motion && viewport.width > 0
                    paused: running && (hover.containsMouse || win.covered || Config.desktopPaused)
                    from: viewport.width
                    to: -msg.implicitWidth
                    duration: Math.max(1000, (viewport.width + msg.implicitWidth) / 48 * 1000)
                    loops: Animation.Infinite
                }

                Repeater {
                    id: rep
                    model: win.entries
                    delegate: Row {
                        id: item
                        required property var modelData
                        required property int index
                        readonly property bool hot: hover.hoverIdx === index && modelData.link !== ""
                        spacing: 0
                        Text {
                            text: item.modelData.t
                            textFormat: Text.PlainText
                            color: Theme.fg
                            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
                        }
                        Text {
                            text: "\u00a0\u00a0" + item.modelData.h
                            textFormat: Text.PlainText
                            color: item.hot ? Theme.accent : Theme.dim
                            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
                            font.underline: item.hot
                        }
                        Text {
                            text: "\u00a0\u00a0\u00a0\u25c6\u00a0\u00a0\u00a0"
                            visible: item.index < win.entries.length - 1
                            color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
                        }
                    }
                }
            }

            // Hover pauses the scroll; clicking a headline opens its link (http/https only) via xdg-open.
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                property int hoverIdx: -1
                function hit(mx) {
                    const px = mx - msg.x;
                    for (let i = 0; i < rep.count; i++) {
                        const it = rep.itemAt(i);
                        if (it && px >= it.x && px < it.x + it.width) return i;
                    }
                    return -1;
                }
                function linkAt(mx) { const i = hit(mx); return i >= 0 ? win.entries[i].link : ""; }
                onPositionChanged: mouse => hoverIdx = hit(mouse.x)
                onExited: hoverIdx = -1
                cursorShape: hoverIdx >= 0 && win.entries[hoverIdx] && win.entries[hoverIdx].link !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: mouse => { const l = linkAt(mouse.x); if (l !== "") Feeds.open(l); }
            }
        }

        StatusTray {
            id: tray
            visible: Config.isTrayScreen(win.screen ? win.screen.name : "")
            screenName: win.screen ? win.screen.name : ""
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            height: undefined
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
                font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2.2
            }
        }
    }
}
