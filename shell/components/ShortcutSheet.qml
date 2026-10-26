// ShortcutSheet.qml - every keyboard shortcut on one screen (Super+/, or Settings > Input). Reads
// the compositor's own key table (`ultimitctl keys`), so it can't drift from what the keys do.
// Overlay-layer, full-screen; typing filters, Esc / Super+/ / a click outside closes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win
    property string screenName: ""
    readonly property bool shown: Config.shortcutsOpen && Config.isUiScreen(screenName)
    visible: shown || panel.opacity > 0.01
    mask: shown ? null : noInput
    Region { id: noInput }
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-shortcuts"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var rows: []
    property string filter: ""
    readonly property var shownRows: {
        const f = filter.trim().toLowerCase();
        return f === "" ? rows : rows.filter(r => (r.keys + " " + r.description + " " + r.category).toLowerCase().indexOf(f) >= 0);
    }
    readonly property var categories: {
        const out = [];
        for (const r of shownRows) if (out.indexOf(r.category) < 0) out.push(r.category);
        return out;
    }

    onShownChanged: if (shown) { filter = ""; load.running = true; keys.forceActiveFocus(); }
    Process {
        id: load
        command: [Quickshell.shellPath("bin/ultimitctl"), "keys"]
        stdout: StdioCollector {
            onStreamFinished: { try { win.rows = JSON.parse(text).bindings; } catch (e) { win.rows = []; } }
        }
    }

    Rectangle {   // dim the desktop behind
        anchors.fill: parent
        color: "black"
        opacity: win.shown ? 0.35 : 0
        ShowBehavior on opacity { ms: 140 }
        MouseArea { anchors.fill: parent; onClicked: Config.shortcutsOpen = false }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1080)
        height: Math.min(parent.height - 100, flow.implicitHeight + 110)
        color: Theme.panel
        border.color: Theme.lineStrong
        opacity: win.shown ? 1 : 0
        ShowBehavior on opacity { ms: 140 }
        MouseArea { anchors.fill: parent }

        Rectangle { x: -1; y: -1; width: 14; height: 2; color: Theme.accent }
        Rectangle { x: -1; y: -1; width: 2; height: 14; color: Theme.accent }
        Rectangle { x: parent.width - 13; y: parent.height - 1; width: 14; height: 2; color: Theme.accent }
        Rectangle { x: parent.width - 1; y: parent.height - 13; width: 2; height: 14; color: Theme.accent }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Config.shortcutsOpen = false
            Keys.onPressed: e => {
                if ((e.modifiers & Qt.MetaModifier) && e.key === Qt.Key_Slash) { Config.shortcutsOpen = false; e.accepted = true; return; }
                if (e.key === Qt.Key_Backspace) { win.filter = win.filter.slice(0, -1); e.accepted = true; return; }
                if (e.text && e.text.length === 1 && e.text >= " " && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                    win.filter += e.text; e.accepted = true;
                }
            }
        }

        Item {
            id: head
            x: 24; y: 18; width: parent.width - 48; height: 30
            Rectangle { id: sq; width: 8; height: 8; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
            Text {
                id: ttl
                anchors { left: sq.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "KEYBOARD SHORTCUTS"; color: Theme.fg
                font.family: Theme.display; font.pixelSize: Theme.ds(16); font.letterSpacing: Theme.dt(2)
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: win.filter !== "" ? "FILTER: " + win.filter.toUpperCase() + "▏" : "TYPE TO FILTER  ·  ESC CLOSES"
                color: win.filter !== "" ? Theme.accent : Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
            }
        }

        Flickable {
            anchors { top: head.bottom; topMargin: 18; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 24; bottomMargin: 18 }
            contentHeight: flow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: flow
                width: parent.width
                spacing: 28
                readonly property int cols: Math.max(1, Math.floor((width + spacing) / (300 + spacing)))
                readonly property real colW: (width - (cols - 1) * spacing) / cols
                Repeater {
                    model: win.categories
                    delegate: Column {
                        id: cat
                        required property string modelData
                        width: flow.colW
                        spacing: 6
                        Text {
                            text: cat.modelData.toUpperCase(); color: Theme.accent
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.line }
                        Repeater {
                            model: win.shownRows.filter(r => r.category === cat.modelData)
                            delegate: Item {
                                required property var modelData
                                width: cat.width
                                height: Math.max(keyRow.height, desc.implicitHeight) + 6
                                Flow {
                                    id: keyRow
                                    width: 128
                                    spacing: 3
                                    // gestures ("Drag titlebar to a screen edge") are words, not keys
                                    Text {
                                        visible: parent.parent.modelData.gesture
                                        width: parent.width; wrapMode: Text.WordWrap
                                        text: parent.parent.modelData.keys; color: Theme.dim
                                        font.family: Theme.mono; font.pixelSize: 10
                                    }
                                    Repeater {
                                        // "Super+Shift+S" -> one chip per key
                                        model: parent.parent.modelData.gesture ? [] : parent.parent.modelData.keys.split("+")
                                        delegate: Rectangle {
                                            required property string modelData
                                            width: Math.min(kt.implicitWidth + 10, 128); height: 20
                                            color: Theme.panel2; border.color: Theme.lineStrong
                                            Text {
                                                id: kt; anchors.centerIn: parent; width: parent.width - 8
                                                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                                text: parent.modelData; color: Theme.fg
                                                font.family: Theme.mono; font.pixelSize: 10
                                            }
                                        }
                                    }
                                }
                                Text {
                                    id: desc
                                    anchors { left: keyRow.right; leftMargin: 12; right: parent.right; top: parent.top; topMargin: 2 }
                                    text: parent.modelData.description; color: Theme.fg
                                    font.family: Theme.ui; font.pixelSize: 12; wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            visible: win.shownRows.length === 0 && win.rows.length > 0
            anchors.centerIn: parent
            text: "No shortcut matches “" + win.filter + "”."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }
    }
}
