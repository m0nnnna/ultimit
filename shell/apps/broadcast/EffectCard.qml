// EffectCard.qml - one effect: title + on/off switch, a dim description and optional controls (children).
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    property string title: ""
    property string desc: ""
    property bool checked: false
    property bool available: true
    property string unavailableText: ""
    property bool showToggle: true
    default property alias content: slot.data
    signal toggled(bool value)

    implicitHeight: col.implicitHeight + 24
    color: Theme.panel2
    border.color: root.checked && root.available ? Theme.lineStrong : Theme.line
    border.width: 1

    Column {
        id: col
        x: 14; y: 12
        width: parent.width - 28
        spacing: 8
        GToggle {
            width: parent.width
            label: root.title
            checked: root.checked
            available: root.available
            unavailableText: root.unavailableText
            visible: root.showToggle
            onToggled: v => root.toggled(v)
        }
        GLabel { visible: !root.showToggle; text: root.title; strong: true }
        Text {
            width: parent.width
            visible: root.desc !== ""
            text: root.desc
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
        }
        Column { id: slot; width: parent.width; spacing: 8 }
    }
}
