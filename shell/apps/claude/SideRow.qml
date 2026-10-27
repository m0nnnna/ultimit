// SideRow.qml - a project or chat in the CLAUDE sidebar: name, a dim second line, accent bar when
// selected; chats get rename / remove on hover. Right-click asks for a menu (menu(x, y), in the row).
import QtQuick
import "../.."

Item {
    id: root
    property string text: ""
    property string sub: ""
    property bool selected: false
    property bool actions: false
    signal clicked()
    signal rename()
    signal remove()
    signal menu(real x, real y)

    height: 48
    Rectangle {
        anchors.fill: parent
        color: root.selected ? Theme.selection : (ma.containsMouse ? Theme.hover : Theme.clear(Theme.hover))
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? root.menu(mouse.x, mouse.y) : root.clicked()
    }
    Column {
        x: 12; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 24 - (acts.visible ? acts.width + 6 : 0)
        spacing: 0
        Text {
            width: parent.width; elide: Text.ElideRight
            text: root.text
            color: root.selected ? Theme.accent : Theme.fg
            font.family: Theme.ui; font.pixelSize: Theme.type.body; font.weight: root.selected ? Font.DemiBold : Font.Normal
        }
        Text {
            visible: root.sub !== ""
            width: parent.width; elide: Text.ElideMiddle
            text: root.sub
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
        }
    }
    Row {
        id: acts
        visible: root.actions && (ma.containsMouse || renA.containsMouse || rmA.containsMouse)
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: 24; height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: "✎"; color: renA.containsMouse ? Theme.accent : Theme.dim; font.pixelSize: Theme.type.label
            MouseArea { id: renA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.rename() }
        }
        Text {
            width: 24; height: 24; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: "✕"; color: rmA.containsMouse ? Theme.bad : Theme.dim; font.pixelSize: Theme.type.label
            MouseArea { id: rmA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.remove() }
        }
    }
}
