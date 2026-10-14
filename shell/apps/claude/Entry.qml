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
    implicitWidth: 180; implicitHeight: 32
    color: "transparent"
    border.width: 1; border.color: ti.activeFocus ? Theme.accent : Theme.lineStrong
    TextInput {
        id: ti
        anchors.fill: parent; anchors.margins: 8
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
        font.family: root.mono ? Theme.mono : Theme.ui; font.pixelSize: 13
        selectByMouse: true
        clip: true
        onAccepted: root.accepted()
        Text { visible: ti.text === ""; text: root.placeholder; color: Theme.dim; font: ti.font; anchors.verticalCenter: parent.verticalCenter }
    }
}
