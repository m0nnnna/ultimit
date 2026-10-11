// GToggle.qml - .tog row: label left, 34x16 switch right, bottom hairline.
import QtQuick
import "../.."

Item {
    id: root
    property string label: ""
    property bool checked: false
    property bool available: true       // false -> disabled + "not installed" chip
    property string unavailableText: "not installed"
    signal toggled(bool value)

    implicitHeight: 34
    opacity: available ? 1 : 0.55

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.fg
            font.family: Theme.ui
            font.pixelSize: 13
        }
        GChip {
            visible: !root.available
            anchors.verticalCenter: parent.verticalCenter
            text: root.unavailableText
            tone: Theme.warn
        }
    }
    Rectangle {
        id: box
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 34; height: 16
        color: "transparent"
        border.color: Theme.lineStrong
        border.width: 1
        Rectangle {
            y: 2; width: 10; height: 10
            x: root.checked && root.available ? 20 : 2
            color: root.checked && root.available ? Theme.accent : Theme.dim
            Behavior on x { NumberAnimation { duration: Config.dur(150) } }
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
