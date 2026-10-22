// AddGameDialog.qml - modal "Add game" card: a Windows program to run with Wine, or any command.
// Saved to games.json "manual" via Games.addManual(); Wine games pick a prefix (shared or custom).
import QtQuick
import Quickshell.Io
import "../.."

Item {
    id: root
    signal closed()

    property string kind: "wine"
    property string prefixMode: "default"
    property string runner: "wine"
    property string proton: ""
    readonly property string target: targetField.text.trim()
    readonly property bool valid: target !== ""
        && (kind !== "wine" || prefixMode === "default" || prefixField.text.trim() !== "")

    function open() {
        kind = "wine"; prefixMode = "default"; runner = "wine"; proton = "";
        targetField.text = ""; nameField.text = ""; prefixField.text = "";
        visible = true;
        targetField.input.forceActiveFocus();
    }
    function close() { visible = false; closed(); }
    function baseName(p) {
        const f = p.replace(/\\/g, "/").split("/").pop();
        const i = f.lastIndexOf(".");
        return (kind === "wine" && i > 0) ? f.slice(0, i) : f.split(" ")[0];
    }
    function submit() {
        if (!visible || !valid) return;
        const nm = nameField.text.trim() || baseName(target);
        Games.addManual(nm, kind, target, kind === "wine" && prefixMode === "custom" ? prefixField.text.trim() : "",
                         kind === "wine" ? runner : "", kind === "wine" && runner === "proton" ? proton : "");
        close();
    }

    visible: false
    anchors.fill: parent
    z: 50
    focus: visible
    Keys.onEscapePressed: root.close()

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Config.mobile ? parent.width - 24 : Math.min(480, parent.width - 32)
        height: Config.mobile ? Math.min(parent.height - 24, col.implicitHeight + 40) : col.implicitHeight + 40
        color: Theme.bg1
        border.color: Theme.lineStrong
        border.width: 1
        MouseArea { anchors.fill: parent }          // swallow clicks
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: Theme.accent; size: 12 }

        Flickable {   // phone: the form scrolls when it is taller than the window
            id: sc
            anchors.fill: parent
            contentHeight: col.implicitHeight + 40
            clip: true
            interactive: Config.mobile
            boundsBehavior: Flickable.StopAtBounds
        }
        Column {
            id: col
            parent: sc.contentItem
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                GLabel { text: "Add game"; strong: true }
            }
            GSeg {
                options: [{ id: "wine", label: Config.mobile ? "Wine program" : "Windows program (Wine)" }, { id: "command", label: "Command" }]
                current: root.kind
                onPicked: id => root.kind = id
            }
            Column {
                width: parent.width
                spacing: 6
                GLabel { text: root.kind === "wine" ? "Program (.exe)" : "Command" }
                Row {
                    width: parent.width
                    spacing: 8
                    GInput {
                        id: targetField
                        width: parent.width - (root.kind === "wine" ? browse.width + 8 : 0)
                        placeholder: root.kind === "wine" ? "/path/to/game.exe" : "e.g. retroarch -f"
                        onAccepted: root.submit()
                        onEscaped: root.close()
                    }
                    GButton {
                        id: browse
                        visible: root.kind === "wine"
                        text: "Browse"
                        onClicked: picker.running = true
                    }
                }
            }
            Column {
                width: parent.width
                spacing: 6
                GLabel { text: "Name" }
                GInput {
                    id: nameField
                    width: parent.width
                    placeholder: root.target !== "" ? root.baseName(root.target) : "shown in the library"
                    onAccepted: root.submit()
                    onEscaped: root.close()
                }
            }
            Column {
                visible: root.kind === "wine"
                width: parent.width
                spacing: 6
                GLabel { text: "Runner" }
                GSeg {
                    options: [{ id: "wine", label: "Wine" }, { id: "proton", label: "Proton (umu)" }]
                    current: root.runner
                    onPicked: id => root.runner = id
                }
                ProtonPicker {
                    visible: root.runner === "proton"
                    width: parent.width
                    current: root.proton
                    onPicked: path => root.proton = path
                }
                Text {
                    visible: root.runner === "proton" && !Games.tools.umu
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.warn
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "umu-launcher not installed; Proton games cannot start without umu-run."
                }
            }
            Column {
                visible: root.kind === "wine"
                width: parent.width
                spacing: 6
                GLabel { text: root.runner === "proton" ? "Prefix" : "Wine prefix" }
                GSeg {
                    options: [{ id: "default", label: "Shared default" }, { id: "custom", label: "Custom" }]
                    current: root.prefixMode
                    onPicked: id => root.prefixMode = id
                }
                GInput {
                    id: prefixField
                    visible: root.prefixMode === "custom"
                    width: parent.width
                    placeholder: "~/.local/share/ultimit/wine/my-game"
                    onAccepted: root.submit()
                    onEscaped: root.close()
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 11
                    text: root.prefixMode === "default"
                        ? "All games with the shared prefix live in " + Games.winePrefix + ". A custom prefix is created on first launch."
                        : "A folder for this game's own Wine prefix. It is created on first launch."
                }
            }
            Row {
                spacing: 10
                anchors.right: parent.right
                GButton { text: "Cancel"; onClicked: root.close() }
                GButton { primary: true; text: "Add game"; enabled: root.valid; onClicked: root.submit() }
            }
        }
    }

    Process {
        id: picker
        command: ["zenity", "--file-selection", "--title=Choose a Windows program",
                  "--file-filter=Programs | *.exe *.EXE *.bat *.msi", "--file-filter=All files | *"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p !== "") { targetField.text = p; if (nameField.text === "") nameField.input.forceActiveFocus(); }
            }
        }
    }
}
