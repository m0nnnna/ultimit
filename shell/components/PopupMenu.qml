// PopupMenu.qml - small context-menu panel in the WindowPopups / ContextMenu style: an L1
// Surface (panel fill, top highlight, shadow), corner brackets, mono caps rows with an accent hover bar.
// The host owns the open/close and key handling:  items: [{ id, label }]  cur: highlighted row.
import QtQuick
import ".."

Surface {
    id: menu
    brackets: true; bracketSize: 8
    elevation: 2   // sits inside the launcher panel, so no halo
    property var items: []
    property int cur: -1
    property int rowH: Theme.space(8)
    signal activated(var item)

    width: 192; height: items.length * rowH + Theme.space(4)
    PopIn { target: menu; shown: menu.visible }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

    Repeater {
        model: menu.items
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool hot: menu.cur === index
            y: Theme.space(2) + index * menu.rowH
            width: menu.width; height: menu.rowH
            Rectangle {
                anchors.fill: parent; anchors.leftMargin: Theme.space(1); anchors.rightMargin: Theme.space(1)
                color: row.hot ? Theme.hover : Theme.clear(Theme.hover)
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                Rectangle {
                    width: 2; height: parent.height; color: Theme.accent
                    opacity: row.hot ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                }
            }
            Text {
                x: Theme.space(4); anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label.toUpperCase()
                color: row.hot ? Theme.accent : Theme.fg
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: menu.cur = row.index
                onClicked: menu.activated(row.modelData)
            }
        }
    }
}
