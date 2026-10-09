// CopyText.qml - selectable monospace command in a boxed field.
import QtQuick
import "../.."

Rectangle {
    id: root
    property string text: ""
    implicitHeight: edit.implicitHeight + 16
    color: Theme.panel2
    border.color: Theme.line
    border.width: 1
    TextEdit {
        id: edit
        anchors.fill: parent
        anchors.margins: 8
        readOnly: true
        selectByMouse: true
        text: root.text
        wrapMode: TextEdit.Wrap
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.mono
        font.pixelSize: 12
    }
}
