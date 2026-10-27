// GChip.qml - .chip from the mockup: mono 10px, outlined, tone-colored.
import QtQuick
import "../.."

Rectangle {
    id: root
    property string text: ""
    property color tone: Theme.dim
    implicitWidth: label.implicitWidth + 14
    implicitHeight: label.implicitHeight + 4
    color: "transparent"
    border.color: tone
    border.width: 1
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text.toUpperCase()
        color: root.tone
        font.family: Theme.mono
        font.pixelSize: Theme.type.label
        font.letterSpacing: 1.2
    }
}
