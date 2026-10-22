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
    // phone: wide button sets drop under the text instead of squeezing it
    readonly property bool stacked: Config.mobile && tr.childrenRect.width > width * 0.45
    implicitHeight: stacked ? info.height + tr.height + 20 : 48

    Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: m.containsMouse ? 1 : 0 }
    Rectangle { x: 0; width: 2; height: parent.height; color: Theme.accent; visible: root.selected }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
    Column {
        id: info
        x: 10; y: root.stacked ? 8 : (root.height - height) / 2
        width: root.stacked ? root.width - 20 : tr.x - 8 - x
        spacing: 2
        Row {
            spacing: 8
            Text {
                text: root.title; color: root.titleColor; elide: Text.ElideRight
                font.family: Theme.ui; font.pixelSize: 13
            }
            Text {
                visible: root.badge !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.badge.toUpperCase(); color: root.badgeColor
                font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.6
            }
        }
        Text {
            visible: root.subtitle !== ""
            width: parent.width; elide: Text.ElideRight
            text: root.subtitle; color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 10
        }
    }
    Row {
        id: tr
        x: root.stacked ? 10 : root.width - width - 6
        y: root.stacked ? info.y + info.height + 6 : (root.height - height) / 2
        spacing: 6
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
}
