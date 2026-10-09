// ToggleRow.qml - ".tog" from the mockup: label left, 34x16 switch right, bottom rule.
import QtQuick
import "../.."

Item {
    id: root
    property string text: ""
    property bool checked: false
    signal toggled(bool value)

    implicitHeight: 36
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.toggled(!root.checked); event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.panel2
        opacity: mouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(150); easing.type: Easing.OutCubic } }
    }
    Text {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Theme.fg
        font.family: Theme.ui; font.pixelSize: 13
    }
    Rectangle {
        id: sw
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: 34; height: 16
        color: "transparent"
        border.width: 1
        border.color: root.activeFocus ? Theme.accent : Theme.lineStrong
        Rectangle {
            y: 2
            x: root.checked ? 20 : 2
            width: 10; height: 10
            color: root.checked ? Theme.accent : Theme.dim
            Behavior on x { NumberAnimation { duration: Config.dur(150); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Config.dur(150) } }
        }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.toggled(!root.checked); }
    }
}
