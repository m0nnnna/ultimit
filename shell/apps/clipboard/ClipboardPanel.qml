// ClipboardPanel.qml - the Super+V clipboard history panel, bottom-right above the tray like
// Windows'. Overlay-layer, full-screen transparent window (clicks outside close it) with exclusive
// keyboard focus. Up/Down pick, Enter pastes, Delete removes, P pins, Esc closes.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../.."

PanelWindow {
    id: win
    property string screenName: ""
    readonly property bool shown: Clipboard.open && Config.isUiScreen(screenName)
    visible: shown || panel.opacity > 0.01
    mask: shown ? null : noInput
    Region { id: noInput }
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-clipboard"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onShownChanged: if (shown) { list.currentIndex = 0; list.positionViewAtBeginning(); keys.forceActiveFocus(); }

    MouseArea { anchors.fill: parent; onClicked: Clipboard.open = false }

    Rectangle {
        id: panel
        width: 400
        height: Math.min(520, parent.height - 120)
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 16; bottomMargin: 46 }
        color: Theme.panel
        border.color: Theme.lineStrong
        opacity: win.shown ? 1 : 0
        ShowBehavior on opacity { ms: 160 }
        transform: Translate { y: win.shown ? 0 : 12; ShowBehavior on y { ms: 160; hidden: 12 } }
        MouseArea { anchors.fill: parent }   // clicks inside don't close

        // corner brackets, as on windows
        Rectangle { x: -1; y: -1; width: 14; height: 2; color: Theme.accent }
        Rectangle { x: -1; y: -1; width: 2; height: 14; color: Theme.accent }
        Rectangle { x: parent.width - 13; y: parent.height - 1; width: 14; height: 2; color: Theme.accent }
        Rectangle { x: parent.width - 1; y: parent.height - 13; width: 2; height: 14; color: Theme.accent }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Clipboard.open = false
            Keys.onUpPressed: list.decrementCurrentIndex()
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onReturnPressed: { const it = Clipboard.items[list.currentIndex]; if (it) Clipboard.paste(it.id); }
            Keys.onEnterPressed: { const it = Clipboard.items[list.currentIndex]; if (it) Clipboard.paste(it.id); }
            Keys.onDeletePressed: { const it = Clipboard.items[list.currentIndex]; if (it) Clipboard.remove(it.id); }
            Keys.onPressed: e => {
                if (e.key === Qt.Key_P) { const it = Clipboard.items[list.currentIndex]; if (it) Clipboard.pin(it.id, !it.pinned); e.accepted = true; }
            }
        }

        Item {
            id: head
            x: 16; y: 12; width: parent.width - 32; height: 24
            Rectangle { id: sq; width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors { left: sq.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                text: "CLIPBOARD"; color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.2
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: Clipboard.items.some(i => !i.pinned)
                text: "CLEAR ALL"; color: clr.hovered ? Theme.fg : Theme.accent
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                HoverHandler { id: clr; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Clipboard.clear() }
            }
        }

        Text {
            visible: Clipboard.loaded && Clipboard.items.length === 0
            anchors.centerIn: parent; width: parent.width - 60
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: "Nothing copied yet.\nWhat you copy shows up here."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13; lineHeight: 1.3
        }

        ListView {
            id: list
            anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: hint.top; bottomMargin: 6; leftMargin: 10; rightMargin: 10 }
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: Clipboard.items
            highlightFollowsCurrentItem: true
            highlightMoveDuration: Config.dur(80)
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool cur: ListView.isCurrentItem
                width: ListView.view.width - 6
                height: modelData.kind === "image" ? 96 : Math.min(84, txt.implicitHeight + 24)
                color: cur || rh.hovered ? Theme.panel2 : "transparent"
                border.color: cur ? Theme.accent : Theme.line
                HoverHandler { id: rh; onHoveredChanged: if (hovered) list.currentIndex = row.index }
                TapHandler { onTapped: Clipboard.paste(row.modelData.id) }

                Text {
                    id: txt
                    visible: row.modelData.kind === "text"
                    anchors { left: parent.left; right: tools.left; top: parent.top; margins: 12; rightMargin: 8 }
                    text: row.modelData.text.replace(/\t/g, "    ")
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Image {
                    visible: row.modelData.kind === "image"
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 8 }
                    width: Math.min(260, parent.width - 90)
                    source: row.modelData.kind === "image" ? "file://" + row.modelData.file : ""
                    fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft
                    asynchronous: true; sourceSize.height: 160
                }
                Row {
                    id: tools
                    anchors { right: parent.right; top: parent.top; margins: 8 }
                    spacing: 4
                    opacity: row.cur || rh.hovered || row.modelData.pinned ? 1 : 0
                    Repeater {
                        model: [
                            { id: "pin", label: row.modelData.pinned ? "PINNED" : "PIN" },
                            { id: "del", label: "×" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: tl.implicitWidth + 12; height: 20
                            color: th.hovered ? Theme.panel : "transparent"
                            border.color: modelData.id === "pin" && row.modelData.pinned ? Theme.accent : Theme.line
                            Text {
                                id: tl; anchors.centerIn: parent; text: parent.modelData.label
                                color: parent.modelData.id === "pin" && row.modelData.pinned ? Theme.accent : Theme.dim
                                font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.2
                            }
                            HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: parent.modelData.id === "pin" ? Clipboard.pin(row.modelData.id, !row.modelData.pinned)
                                                                       : Clipboard.remove(row.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: hint
            anchors { left: parent.left; leftMargin: 16; bottom: parent.bottom; bottomMargin: 10 }
            text: "ENTER PASTE  ·  P PIN  ·  DEL REMOVE  ·  ESC CLOSE"
            color: Theme.dim; opacity: 0.7
            font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.4
        }
    }
}
