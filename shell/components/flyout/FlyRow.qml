// FlyRow.qml - flyout list row: hover wash, accent left bar when `selected`, title + dim mono subtitle
// on the left, trailing children (buttons) on the right. `mark` draws a ■ / □ radio square.
import QtQuick
import "../.."
import ".."

Item {
    id: root
    property string title: ""
    property string subtitle: ""
    property string badge: ""
    property color badgeColor: Theme.dim
    property bool selected: false
    property bool radio: false
    property bool hoverable: true
    property color titleColor: selected ? Theme.accent : Theme.fg
    property alias leading: lead.data
    default property alias trailing: tr.data
    signal clicked()

    width: parent ? parent.width : 300
    implicitHeight: subtitle !== "" ? 44 : 36
    height: implicitHeight

    Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: m.containsMouse && root.hoverable ? 1 : 0 }
    Rectangle { x: -14; width: 2; height: parent.height; color: Theme.accent; visible: root.selected }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: root.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.clicked() }
    Row {
        id: lead
        anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
        spacing: 8
        Text {
            visible: root.radio
            anchors.verticalCenter: parent.verticalCenter
            text: root.selected ? "■" : "□"
            color: root.selected ? Theme.accent : Theme.dim
            font.family: Theme.mono; font.pixelSize: 10
        }
    }
    Column {
        anchors { left: lead.right; leftMargin: lead.width > 0 ? 8 : 2; right: tr.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 2
        Row {
            spacing: 8
            width: parent.width
            Text {
                width: Math.min(implicitWidth, parent.width - (badgeT.visible ? badgeT.implicitWidth + 8 : 0))
                text: root.title; color: root.titleColor; elide: Text.ElideRight
                font.family: Theme.ui; font.pixelSize: 13
            }
            Text {
                id: badgeT
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
        anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
        spacing: 6
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
}
