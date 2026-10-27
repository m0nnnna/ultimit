// Entry.qml - single-line input in the Ultimit style (as Settings' TextEntry).
import QtQuick
import "../.."

Rectangle {
    id: root
    property alias text: ti.text
    property string placeholder: ""
    property bool mono: false
    signal accepted()
    function focusEntry() { ti.forceActiveFocus(); }
    function selectAll() { ti.selectAll(); }
    implicitWidth: 180; implicitHeight: 36
    color: Theme.field
    border.width: ti.activeFocus ? 1 : 0; border.color: Theme.accent
    TextInput {
        id: ti
        anchors.fill: parent; anchors.margins: 8
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
        font.family: root.mono ? Theme.mono : Theme.ui; font.pixelSize: Theme.type.body
        selectByMouse: true
        clip: true
        onAccepted: root.accepted()
        Text { visible: ti.text === ""; text: root.placeholder; color: Theme.dim; font: ti.font; anchors.verticalCenter: parent.verticalCenter }
    }
}
