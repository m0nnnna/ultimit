// ProjectPanel.qml - edit a CLAUDE project (or make one): name, the folder Claude works in, the account,
// the model, how much Claude may do without asking, and notes Claude gets with every chat. The built-in
// "This PC" keeps its name and home folder; the rest is editable.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../.."
import "../accessory"

Rectangle {
    id: root
    required property var host          // the ClaudeWindow
    required property var project       // a copy ({} = new)

    readonly property bool isNew: !project || !project.id
    readonly property bool builtin: !!project && !!project.builtin
    property string account: project && project.account ? project.account : Claude.accountFor(null)
    property string model: project && project.model ? project.model : ""
    property string perm: project && project.perm ? project.perm : "default"
    property string effort: project && project.effort ? project.effort : ""
    property string err: ""
    property bool confirmRemove: false

    implicitHeight: picking ? 480 : col.implicitHeight + 40
    color: Theme.bg1
    Keys.onEscapePressed: if (picking) picking = false; else host.overlay = ""

    function save() {
        const o = { id: isNew ? "" : project.id, name: nameE.text, dir: dirE.text.replace(/^~(?=\/|$)/, Quickshell.env("HOME")),
                    account: account, model: modelE.text.trim(), perm: perm, effort: effort, notes: notes.text };
        Claude.saveProject(o, r => {
            if (!r.ok) { root.err = r.err; return; }
            root.host.overlay = "";
            if (root.isNew) root.host.selectProject(r.project.id);
        });
    }

    // Browse… swaps the form for an in-app folder picker (FolderPicker.qml) in this same panel.
    property bool picking: false
    function picked(f) {
        dirE.text = f;
        if (nameE.text === "") nameE.text = f.substring(f.lastIndexOf("/") + 1);
        picking = false;
        dirE.focusEntry();
    }
    Loader {
        x: 20; y: 20; width: parent.width - 40; height: parent.height - 40
        active: root.picking
        sourceComponent: FolderPicker {
            startDir: dirE.text.trim() || "~"
            onAccepted: d => root.picked(d)
            onCancelled: root.picking = false
        }
        onLoaded: item.forceActiveFocus()
    }

    ColumnLayout {
        id: col
        visible: !root.picking
        x: 20; y: 20; width: parent.width - 40
        spacing: 10

        SectionLabel { text: root.isNew ? "New project" : root.builtin ? "This PC" : "Project" }

        Label_ { text: "Name"; visible: !root.builtin }
        Entry { id: nameE; Layout.fillWidth: true; visible: !root.builtin; text: root.project && root.project.name ? root.project.name : ""; placeholder: "e.g. ultimit" }

        Label_ { text: "Folder Claude works in"; visible: !root.builtin }
        RowLayout {
            visible: !root.builtin
            Layout.fillWidth: true
            Entry { id: dirE; Layout.fillWidth: true; mono: true; text: root.project && root.project.dir ? root.project.dir : ""; placeholder: "~/src/my-project" }
            ChamferButton { implicitHeight: 32; text: "Browse…"; onClicked: root.picking = true }
        }

        Label_ { text: "Account" }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Claude.accounts
                delegate: Chip {
                    required property var modelData
                    text: modelData.name; sel: root.account === modelData.id
                    onClicked: root.account = modelData.id
                }
            }
        }

        Label_ { text: "Model" }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "", label: "Default" }, { id: "fable", label: "Fable" }, { id: "opus", label: "Opus" },
                        { id: "sonnet", label: "Sonnet" }, { id: "haiku", label: "Haiku" }]
                delegate: Chip {
                    required property var modelData
                    text: modelData.label; sel: modelE.text.trim() === modelData.id
                    onClicked: modelE.text = modelData.id
                }
            }
            Entry { id: modelE; width: 200; mono: true; text: root.model; placeholder: "or a full model name" }
        }

        Label_ { text: "Effort" }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "", label: "Default" }, { id: "low", label: "Low" }, { id: "medium", label: "Medium" },
                        { id: "high", label: "High" }, { id: "xhigh", label: "Extra high" }, { id: "max", label: "Max" }]
                delegate: Chip {
                    required property var modelData
                    text: modelData.label; sel: root.effort === modelData.id
                    onClicked: root.effort = modelData.id
                }
            }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "How hard the chat itself thinks (Default is medium). Either way Claude hands grunt work to cheaper "
                  + "Haiku and Sonnet helpers and scales up to an Opus helper only for hard problems."
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: Theme.type.label
        }

        Label_ { text: "Without asking, Claude may" }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{ id: "default", label: "Only read" }, { id: "acceptEdits", label: "Edit files" },
                        { id: "auto", label: "Decide (auto)" }, { id: "plan", label: "Plan only" },
                        { id: "bypassPermissions", label: "Do anything" }]
                delegate: Chip {
                    required property var modelData
                    text: modelData.label; sel: root.perm === modelData.id
                    onClicked: root.perm = modelData.id
                }
            }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: ({ default: "Claude asks before it edits a file or runs a command; you answer in the chat.",
                     acceptEdits: "Claude edits files in the project folder freely and asks before running other commands.",
                     auto: "Claude Code's own safety check decides what is fine to run and asks you about the rest.",
                     plan: "Claude only reads and plans; it changes nothing.",
                     bypassPermissions: "Claude runs anything without asking. Only for a folder you can afford to lose." })[root.perm] || ""
            color: root.perm === "bypassPermissions" ? Theme.warn : Theme.dim
            font.family: Theme.ui; font.pixelSize: Theme.type.label
        }

        Label_ { text: root.builtin ? "Notes about this PC (Claude reads them in every chat)" : "Notes (Claude reads them in every chat in this project)" }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 110
            color: Theme.field
            border.width: notes.activeFocus ? 1 : 0; border.color: Theme.accent
            ScrollView {
                anchors.fill: parent; anchors.margins: 1
                TextArea {
                    id: notes
                    text: root.project && root.project.notes ? root.project.notes : ""
                    wrapMode: TextArea.Wrap; background: null; padding: 8
                    color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                    placeholderText: root.builtin ? "e.g. three monitors, RTX 4070 on the NVIDIA driver; I play through Steam with DW-Proton"
                                                  : "e.g. Godot 4 game in C#; run tests with ./test.sh; never push to main"
                    placeholderTextColor: Theme.dim
                    font.family: Theme.ui; font.pixelSize: Theme.type.body
                }
            }
        }

        Text {
            visible: root.err !== ""
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: root.err; color: Theme.bad; font.family: Theme.ui; font.pixelSize: Theme.type.body
        }
        RowLayout {
            Layout.fillWidth: true; Layout.topMargin: 4
            ChamferButton {
                visible: !root.isNew && !root.builtin
                implicitHeight: 32
                text: root.confirmRemove ? "Really remove?" : "Remove project"
                onClicked: {
                    if (!root.confirmRemove) { root.confirmRemove = true; return; }
                    Claude.run(["project-remove", root.project.id], () => { root.host.overlay = ""; Claude.reload(); });
                }
            }
            Item { Layout.fillWidth: true }
            ChamferButton { implicitHeight: 32; text: "Cancel"; onClicked: root.host.overlay = "" }
            ChamferButton { implicitHeight: 32; text: root.isNew ? "Create" : "Save"; primary: true; onClicked: root.save() }
        }
        Text {
            visible: root.confirmRemove
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "Removes the project and its chats from CLAUDE. The folder and its files stay as they are."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
        }
    }

    component Label_: Text {
        Layout.topMargin: 4
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.8
        font.capitalization: Font.AllUppercase
    }
    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool sel: false
        signal clicked()
        width: ct.implicitWidth + 24; height: 32
        color: sel ? Theme.accent : (cm.containsMouse ? Theme.press : Theme.field)
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        Text {
            id: ct
            anchors.centerIn: parent
            text: chip.text
            color: chip.sel ? Theme.onAccent : Theme.fg
            font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.label
        }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }
}
