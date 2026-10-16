// ChatItem.qml - one entry in a CLAUDE chat: your message, Claude's reply (Markdown, selectable),
// a tool Claude ran (click for its output), or a note (permission answers, errors). Images you sent
// show as thumbnails in your message; click one to open it in IMAGE. Right-click asks
// for a menu: menu(x, y, link) in the item, with the link under the pointer if there is one.
import QtQuick
import Quickshell
import "../.."

Item {
    id: root
    property string k: ""               // user | claude | tool | note
    property string text: ""
    property string name: ""            // tool name
    property string summary: ""         // tool: what it ran on
    property string status: ""          // tool: run | ok | error
    property string out: ""             // tool output
    property string kind: ""            // note: perm | error
    property bool sysinfo: false        // user: the system summary went with it
    property string images: ""          // user: the images that went with it, one path per line
    readonly property var imageList: images === "" ? [] : images.split("\n")
    property bool streaming: false
    property bool open: false
    signal menu(real x, real y, string link)

    // the text the menu acts on: the reply, your message, or a tool's output
    readonly property var textEdit: k === "user" ? userT : k === "claude" ? reply : k === "tool" && open ? outT : null
    function selection() { return textEdit ? textEdit.selectedText : ""; }
    function selectAll() { if (textEdit) textEdit.selectAll(); }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: pt => root.menu(pt.position.x, pt.position.y, root.k === "claude" ? reply.hoveredLink : "")
    }

    implicitHeight: k === "user" ? userBox.height : k === "claude" ? reply.implicitHeight
                  : k === "tool" ? toolCol.implicitHeight : noteT.implicitHeight + 4
    height: implicitHeight

    // ---- you
    Rectangle {
        id: userBox
        visible: root.k === "user"
        anchors.right: parent.right
        width: Math.max(userT.visible ? userT.width : 0, thumbs.visible ? thumbs.width : 0) + 28
        height: (thumbs.visible ? thumbs.height + (userT.visible ? 8 : 0) : 0) + (userT.visible ? userT.implicitHeight : 0)
                + 20 + (root.sysinfo ? 16 : 0)
        color: Theme.panel2
        border.width: 1; border.color: Theme.line
        Rectangle { anchors.right: parent.right; width: 2; height: parent.height; color: Theme.accent }
        Flow {
            id: thumbs
            visible: root.imageList.length > 0
            x: 12; y: 10
            width: Math.min(root.width * 0.82 - 28, root.imageList.length * 166 - 6)
            spacing: 6
            Repeater {
                model: root.imageList
                Rectangle {
                    required property string modelData
                    width: 160; height: 110
                    color: Theme.bg1; border.width: 1; border.color: Theme.line
                    Image {
                        anchors.fill: parent; anchors.margins: 1
                        source: "file://" + parent.modelData
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 320; asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-image"), parent.modelData])
                    }
                }
            }
        }
        TextEdit {
            id: userT
            visible: root.text !== ""
            x: 12; y: thumbs.visible ? thumbs.y + thumbs.height + 8 : 10
            width: Math.min(root.width * 0.82 - 28, measure.implicitWidth + 2)
            readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
            text: root.k === "user" ? root.text : ""
            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
            font.family: Theme.ui; font.pixelSize: 14
        }
        Text { id: measure; visible: false; text: userT.text; font: userT.font }
        Text {
            visible: root.sysinfo
            x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
            text: "+ SYSTEM SUMMARY"
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.4
        }
    }

    // ---- Claude
    TextEdit {
        id: reply
        visible: root.k === "claude"
        width: parent.width
        readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
        textFormat: root.streaming ? TextEdit.PlainText : TextEdit.MarkdownText
        text: root.k === "claude" ? root.text : ""
        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
        font.family: Theme.ui; font.pixelSize: 14
        onLinkActivated: link => Qt.openUrlExternally(link)
        HoverHandler { cursorShape: reply.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor }
    }

    // ---- a tool Claude used
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
                text: root.name.toUpperCase()
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
