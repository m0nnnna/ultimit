// ItemRow.qml - list row: title + subtitle on the left, buttons (children) on the right.
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root
    property string title: ""
    property string subtitle: ""
    property bool selected: false
    property color titleColor: selected ? Theme.accent : Theme.fg
    property string badge: ""
    property color badgeColor: Theme.dim
    signal clicked()
    default property alias trailing: tr.data

    Layout.fillWidth: true
    implicitHeight: 48

    Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: m.containsMouse ? 1 : 0 }
    Rectangle { x: 0; width: 2; height: parent.height; color: Theme.accent; visible: root.selected }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
    Column {
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
        anchors.right: tr.left; anchors.rightMargin: 8
        spacing: 2
        Row {
            spacing: 8
            Text {
                text: root.title; color: root.titleColor; elide: Text.ElideRight
                font.family: Theme.ui; font.pixelSize: Theme.type.body
            }
            Text {
                visible: root.badge !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.badge.toUpperCase(); color: root.badgeColor
                font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
            }
        }
        Text {
            visible: root.subtitle !== ""
            width: parent.width; elide: Text.ElideRight
            text: root.subtitle; color: Theme.dim
            font.family: Theme.mono; font.pixelSize: Theme.type.label
        }
    }
    Row {
        id: tr
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
}
