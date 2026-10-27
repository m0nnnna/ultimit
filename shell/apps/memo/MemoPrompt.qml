// MemoPrompt.qml - modal message box: title, text, a row of buttons. Emits chosen(id).
import QtQuick
import "../.."
import "../accessory"

Item {
    id: root
    property string title: ""
    property string message: ""
    property var buttons: []          // [{ id, text, primary }]
    signal chosen(string id)
    anchors.fill: parent
    focus: true
    Component.onCompleted: Qt.callLater(() => root.forceActiveFocus())
    Keys.onEscapePressed: root.chosen("cancel")
    Keys.onEnterPressed: event => root.chosenDefault()
    Keys.onReturnPressed: event => root.chosenDefault()
    function chosenDefault() { for (const b of root.buttons) if (b.primary) { root.chosen(b.id); return; } }

    Rectangle { anchors.fill: parent; color: Theme.bg1; opacity: 0.6 }
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: wheel => wheel.accepted = true }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width - 40, 440)
        height: col.implicitHeight + 40
        color: Theme.panel
        Rectangle { anchors.fill: parent; color: Theme.bg1; z: -1 }
        Column {
            id: col
            x: 20; y: 20; width: parent.width - 40
            spacing: 14
            SectionLabel { text: root.title }
            Text {
                width: parent.width
                text: root.message
                color: Theme.fg; wrapMode: Text.Wrap
                font.family: Theme.ui; font.pixelSize: Theme.type.body
            }
            Row {
                spacing: 10
                anchors.right: parent.right
                Repeater {
                    model: root.buttons
                    delegate: ChamferButton {
                        required property var modelData
                        text: modelData.text; primary: !!modelData.primary
                        onClicked: root.chosen(modelData.id)
                    }
                }
            }
        }
    }
}
