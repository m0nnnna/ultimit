// InfoRow.qml - dim mono caps key on the left, value on the right, bottom rule.
import QtQuick
import "../.."

Item {
    id: root
    property string label: ""
    property string value: ""
    property color valueColor: Theme.fg
    implicitHeight: Math.max(30, val.implicitHeight + 12)

    Text {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        text: root.label.toUpperCase()
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.8
    }
    Text {
        id: val
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 160
        horizontalAlignment: Text.AlignRight
        text: root.value
        color: root.valueColor
        font.family: Theme.ui; font.pixelSize: Theme.type.body
        wrapMode: Text.WordWrap
    }
}
