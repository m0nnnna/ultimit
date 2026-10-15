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

    height: 40
    Rectangle {
        anchors.fill: parent
        color: root.selected ? Theme.panel2 : (ma.containsMouse ? Qt.rgba(Theme.panel2.r, Theme.panel2.g, Theme.panel2.b, Theme.panel2.a * 0.6) : "transparent")
        Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: root.selected }
    }
    MouseArea {
        id: ma
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? root.menu(mouse.x, mouse.y) : root.clicked()
    }
    Column {
        x: 10; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 20 - (acts.visible ? acts.width + 6 : 0)
        spacing: 2
        Text {
            width: parent.width; elide: Text.ElideRight
            text: root.text
            color: root.selected ? Theme.fg : Theme.fg
            font.family: Theme.ui; font.pixelSize: 13; font.weight: root.selected ? Font.DemiBold : Font.Normal
        }
        Text {
            visible: root.sub !== ""
            width: parent.width; elide: Text.ElideMiddle
            text: root.sub
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1
        }
    }
    Row {
        id: acts
        visible: root.actions && (ma.containsMouse || renA.containsMouse || rmA.containsMouse)
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: 20; height: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: "✎"; color: renA.containsMouse ? Theme.accent : Theme.dim; font.pixelSize: 12
            MouseArea { id: renA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.rename() }
        }
        Text {
            width: 20; height: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: "✕"; color: rmA.containsMouse ? Theme.bad : Theme.dim; font.pixelSize: 11
            MouseArea { id: rmA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.remove() }
        }
    }
}
