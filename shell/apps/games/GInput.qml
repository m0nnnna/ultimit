// GInput.qml - boxed single-line text field. `committed(value)` fires on Enter / focus loss.
import QtQuick
import "../.."

Rectangle {
    id: root
    property alias text: field.text
    // External value (e.g. a setting): pushed into the field whenever it changes; typing never breaks the binding.
    property string value: ""
    onValueChanged: field.text = value
    Component.onCompleted: if (value !== "") field.text = value
    property string placeholder: ""
    property alias input: field
    signal committed(string value)
    signal escaped()
    signal edited(string value)
    signal accepted()
    signal downPressed()

    implicitHeight: 32
    color: Theme.field
    border.color: Theme.accent
    border.width: field.activeFocus ? 1 : 0

    TextInput {
        id: field
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 9 }
        clip: true
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        selectByMouse: true
        font.family: Theme.ui
        font.pixelSize: Theme.type.body
        onEditingFinished: root.committed(text)
        onTextEdited: root.edited(text)
        onAccepted: root.accepted()
        Keys.onDownPressed: root.downPressed()
        Keys.onEscapePressed: root.escaped()
    }
    Text {
        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
        visible: field.text === "" && !field.preeditText
        text: root.placeholder.toUpperCase()
        color: Theme.dim
        opacity: 0.7
        font.family: Theme.mono
        font.pixelSize: Theme.type.label
        font.letterSpacing: 1.4
    }
}
