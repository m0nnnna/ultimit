// PopupMenu.qml - small context-menu panel in the WindowPopups / ContextMenu style: panel fill,
// 1px strong line, corner brackets, mono caps rows with an accent hover bar.
// The host owns the open/close and key handling:  items: [{ id, label }]  cur: highlighted row.
import QtQuick
import ".."

Rectangle {
    id: menu
    property var items: []
    property int cur: -1
    property int rowH: 30
    signal activated(var item)

    width: 190; height: items.length * rowH + 12
    color: Theme.panel
    border.width: 1; border.color: Theme.lineStrong
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
    Brackets { size: 8 }

    Repeater {
        model: menu.items
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool hot: menu.cur === index
            y: 6 + index * menu.rowH
            width: menu.width; height: menu.rowH
            Rectangle {
                anchors.fill: parent; anchors.leftMargin: 1; anchors.rightMargin: 1
                color: row.hot ? Theme.panel2 : "transparent"
                Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: row.hot }
            }
            Text {
                x: 14; anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label.toUpperCase()
                color: row.hot ? Theme.accent : Theme.fg
                font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.6
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
