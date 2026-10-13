// SharesPrompt.qml - modal message box: title, text, buttons [{id, text, primary}]. Emits chosen(id).
import QtQuick
import "../.."
import "../games"

Item {
    id: root
    property string title: ""
    property string message: ""
    property var buttons: []
    signal chosen(string id)

    anchors.fill: parent
    z: 60
    focus: visible
    Keys.onEscapePressed: root.chosen("cancel")
    Keys.onReturnPressed: { for (const b of root.buttons) if (b.primary) { root.chosen(b.id); return; } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: root.chosen("cancel") }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(440, parent.width - 32)
        height: col.implicitHeight + 40
        color: Theme.bg1
        border.color: Theme.lineStrong
        border.width: 1
        MouseArea { anchors.fill: parent }
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: Theme.accent; size: 12 }
        Column {
            id: col
            x: 20; y: 20; width: parent.width - 40
            spacing: 14
            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                GLabel { text: root.title; strong: true }
            }
            Text {
                width: parent.width
                text: root.message
                color: Theme.fg; wrapMode: Text.Wrap
                font.family: Theme.ui; font.pixelSize: 13
            }
            Row {
                spacing: 10
                anchors.right: parent.right
                Repeater {
                    model: root.buttons
                    delegate: GButton {
                        required property var modelData
                        text: modelData.text; primary: !!modelData.primary
                        onClicked: root.chosen(modelData.id)
                    }
                }
            }
        }
    }
}
