// TextEntry.qml - single-line input in the Ultimit style (optionally masked).
import QtQuick
import "../.."

Rectangle {
    id: root
    property alias text: ti.text
    property string placeholder: ""
    property bool secret: false
    signal accepted()
    function focusEntry() { ti.forceActiveFocus(); }
    implicitWidth: 180; implicitHeight: 32
    color: Theme.field
    border.width: ti.activeFocus ? 1 : 0; border.color: Theme.accent
    TextInput {
        id: ti
        anchors.fill: parent; anchors.margins: 8
        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
        font.family: Theme.ui; font.pixelSize: Theme.type.body
        echoMode: root.secret ? TextInput.Password : TextInput.Normal
        clip: true
        onAccepted: root.accepted()
        Text { visible: ti.text === ""; text: root.placeholder; color: Theme.dim; font: ti.font }
    }
}
