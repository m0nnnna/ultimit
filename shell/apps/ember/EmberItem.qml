// EmberItem.qml - one entry in an EMBER chat: your message, Ember's reply (Markdown, selectable), a tool
// she used (click for its output) or a note. Right-click asks for a menu: menu(x, y, link).
import QtQuick
import "../.."

Item {
    id: root
    property string k: ""               // user | ember | tool | note
    property string text: ""
    property string name: ""            // tool name
    property string summary: ""         // tool: what it ran on
    property string status: ""          // tool: run | ok | error
    property string out: ""             // tool output
    property string kind: ""            // note: error | stopped
    property bool streaming: false
    property bool open: false
    signal menu(real x, real y, string link)

    readonly property var textEdit: k === "user" ? userT : k === "ember" ? reply : k === "tool" && open ? outT : null
    function selection() { return textEdit ? textEdit.selectedText : ""; }
    function selectAll() { if (textEdit) textEdit.selectAll(); }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: pt => root.menu(pt.position.x, pt.position.y, root.k === "ember" ? reply.hoveredLink : "")
    }

    implicitHeight: k === "user" ? userBox.height : k === "ember" ? emberCol.implicitHeight
                  : k === "tool" ? toolCol.implicitHeight : noteT.implicitHeight + 4
    height: implicitHeight

    // ---- you
    Rectangle {
        id: userBox
        visible: root.k === "user"
        anchors.right: parent.right
        width: userT.width + 28
        height: userT.implicitHeight + 20
        color: Theme.panel2
        border.width: 1; border.color: Theme.line
        Rectangle { anchors.right: parent.right; width: 2; height: parent.height; color: Theme.accent }
        TextEdit {
            id: userT
            x: 12; y: 10
            width: Math.min(root.width * 0.8 - 28, measure.implicitWidth + 2)
            readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
            text: root.k === "user" ? root.text : ""
            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
            font.family: Theme.ui; font.pixelSize: 14
        }
        Text { id: measure; visible: false; text: userT.text; font: userT.font }
    }

    // ---- Ember
    Column {
        id: emberCol
        visible: root.k === "ember"
        width: parent.width
        spacing: 4
        Text {
            text: "EMBER"
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 2
        }
        TextEdit {
            id: reply
            width: parent.width
            readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
            textFormat: root.streaming ? TextEdit.PlainText : TextEdit.MarkdownText
            text: root.k === "ember" ? root.text : ""
            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
            font.family: Theme.ui; font.pixelSize: 14
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: reply.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor }
        }
    }

    // ---- a tool she used
    Column {
        id: toolCol
        visible: root.k === "tool"
        width: parent.width
        spacing: 4
        Item {
            width: parent.width; height: 22
            Rectangle {
                width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter
                color: root.status === "error" ? Theme.bad : root.status === "ok" ? Theme.dim : Theme.accent
            }
            Text {
                id: toolName
                x: 14; anchors.verticalCenter: parent.verticalCenter
                text: root.name.replace(/_/g, " ").toUpperCase()
                color: root.status === "error" ? Theme.bad : Theme.accent
                font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.4
            }
            Text {
                x: toolName.x + toolName.implicitWidth + 10; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 10
                elide: Text.ElideMiddle
                text: root.summary.replace(/\n/g, " ⏎ ")
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.out !== ""
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.open = !root.open
            }
        }
        Rectangle {
            visible: root.open && root.out !== ""
            x: 14; width: parent.width - 14
            height: Math.min(outT.implicitHeight + 16, 260)
            color: Theme.panel; border.width: 1; border.color: Theme.line
            Flickable {
                anchors.fill: parent; anchors.margins: 8
                contentHeight: outT.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: outT
                    width: parent.width; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                    text: root.open ? root.out : ""
                    color: root.status === "error" ? Theme.bad : Theme.fg
                    selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                    font.family: Theme.mono; font.pixelSize: 11
                }
            }
        }
    }

    // ---- notes
    Text {
        id: noteT
        visible: root.k === "note"
        width: parent.width; wrapMode: Text.Wrap
        text: root.k === "note" ? (root.kind === "error" ? "⚠ " : "") + root.text : ""
        color: root.kind === "error" ? Theme.bad : Theme.dim
        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 0.6
    }
}
