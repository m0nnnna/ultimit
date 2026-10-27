// FlyRow.qml - flyout list row (36, 44 with a subtitle): hover wash, selection fill + accent text when
// `selected`, title + dim mono subtitle on the left, trailing children (buttons) on the right.
// No hairlines: the fills and the spacing separate rows. `radio` draws a ■ / □ square.
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
    implicitHeight: subtitle !== "" ? Theme.space(11) : Theme.space(9)
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        color: root.selected ? Theme.selection : (m.containsMouse && root.hoverable ? Theme.hover : Theme.clear(Theme.hover))
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: root.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.clicked() }
    Row {
        id: lead
        anchors { left: parent.left; leftMargin: Theme.space(2); verticalCenter: parent.verticalCenter }
        spacing: Theme.space(2)
        Text {
            visible: root.radio
            anchors.verticalCenter: parent.verticalCenter
            text: root.selected ? "■" : "□"
            color: root.selected ? Theme.accent : Theme.dim
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            font.family: Theme.mono; font.pixelSize: Theme.type.label
        }
    }
    Column {
        anchors { left: lead.right; leftMargin: lead.width > 0 ? Theme.space(2) : Theme.space(2); right: tr.left; rightMargin: Theme.space(2); verticalCenter: parent.verticalCenter }
        spacing: 2
        Row {
            spacing: Theme.space(2)
            width: parent.width
            Text {
                width: Math.min(implicitWidth, parent.width - (badgeT.visible ? badgeT.implicitWidth + 8 : 0))
                text: root.title; color: root.titleColor; elide: Text.ElideRight
                font.family: Theme.ui; font.pixelSize: Theme.type.body
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            }
            Text {
                id: badgeT
                visible: root.badge !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.badge.toUpperCase(); color: root.badgeColor
                font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
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
        anchors { right: parent.right; rightMargin: Theme.space(2); verticalCenter: parent.verticalCenter }
        spacing: Theme.space(2)
    }
}
