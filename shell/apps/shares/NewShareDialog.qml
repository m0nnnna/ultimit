// NewShareDialog.qml - modal "New share" card: folder (+ Browse), name, access, guests, comment.
// Every edit is validated by `shares.py check` (debounced) and the messages shown inline.
import QtQuick
import Quickshell.Io
import "../.."
import "../games"

Item {
    id: root
    signal closed()

    property string access: "read"          // read | writable
    property bool guest: false
    property bool nameEdited: false
    property string suggested: ""
    property var res: ({ ok: false, errors: {}, warnings: [] })
    property string failure: ""             // error text from Samba on create
    property bool checking: false

    readonly property string folder: folderField.text.trim()
    readonly property string effName: nameEdited && nameField.text.trim() !== "" ? nameField.text.trim() : suggested
    readonly property bool valid: folder !== "" && effName !== "" && res.ok === true && !checking && Shares.busy === "" && Shares.canShare
    readonly property var warns: res.warnings || []
    readonly property string nameErr: folder !== "" && res.errors && res.errors.name ? res.errors.name : ""
    readonly property string pathErr: folder !== "" && res.errors && res.errors.path ? res.errors.path : ""

    function open(path) {
        folderField.text = path || ""; nameField.text = ""; commentField.text = "";
        access = "read"; guest = false; nameEdited = false; suggested = ""; failure = "";
        res = ({ ok: false, errors: {}, warnings: [] });
        visible = true;
        if (folder !== "") onFolderChanged();
        else folderField.input.forceActiveFocus();
    }
    function close() { visible = false; closed(); }

    // folder changed: new suggested name first, then validate
    function onFolderChanged() {
        failure = "";
        if (folder === "") { suggested = ""; res = ({ ok: false, errors: {}, warnings: [] }); return; }
        checking = true;
        Shares.suggest(folder, o => { if (o.ok) root.suggested = o.name; root.recheck(); });
    }
    function recheck() {
        failure = "";
        if (folder === "") return;
        checking = true;
        const seq = ++checkSeq;
        Shares.check(effName, folder, access === "writable", guest, o => {
            if (seq !== root.checkSeq) return;
            root.checking = false;
            root.res = o;
        });
    }
    property int checkSeq: 0
    Timer { id: debounce; interval: 220; onTriggered: root.onFolderChanged() }
    Timer { id: debounceName; interval: 220; onTriggered: root.recheck() }

    function submit() {
        if (!visible || !valid) return;
        Shares.add(effName, folder, access === "writable", guest, commentField.text.trim(), o => {
            if (o.ok) root.close();
            else {
                root.failure = o.error || "Could not create the share.";
                if (o.errors) root.res = o;
            }
        });
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
        width: Math.min(520, parent.width - 32)
        height: Math.min(col.implicitHeight + 40, parent.height - 24)
        color: Theme.bg1
        MouseArea { anchors.fill: parent }
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: Theme.accent; size: 12 }

        Flickable {
            anchors.fill: parent
            anchors.margins: 20
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 12

                Row {
                    spacing: 8
                    Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    GLabel { text: "New share"; strong: true }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Folder" }
                    Row {
                        width: parent.width
                        spacing: 8
                        GInput {
                            id: folderField
                            width: parent.width - browse.width - 8
                            placeholder: "/home/you/Music"
                            onEdited: { root.checking = true; debounce.restart(); }
                            onAccepted: nameField.input.forceActiveFocus()
                            onEscaped: root.close()
                        }
                        GButton { id: browse; text: "Browse…"; onClicked: picker.running = true }
                    }
                    Text {
                        visible: root.pathErr !== ""
                        width: parent.width; wrapMode: Text.WordWrap
                        color: Theme.bad; font.family: Theme.ui; font.pixelSize: Theme.type.label
                        text: root.pathErr
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Share name" }
                    GInput {
                        id: nameField
                        width: parent.width
                        placeholder: root.suggested !== "" ? root.suggested : "how it appears on the network"
                        onEdited: { root.nameEdited = true; root.checking = true; debounceName.restart(); }
                        onAccepted: root.submit()
                        onEscaped: root.close()
                    }
                    Text {
                        visible: root.nameErr !== ""
                        width: parent.width; wrapMode: Text.WordWrap
                        color: Theme.bad; font.family: Theme.ui; font.pixelSize: Theme.type.label
                        text: root.nameErr
                    }
                    Text {
                        visible: root.nameErr === "" && root.effName !== ""
                        width: parent.width; elide: Text.ElideRight
                        color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label
                        text: Shares.uncPath(root.effName)
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Access" }
                    GSeg {
                        options: [{ id: "read", label: "Read-only" }, { id: "writable", label: "Writable" }]
                        current: root.access
                        onPicked: id => { root.access = id; root.recheck(); }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                        text: root.access === "writable"
                            ? "Other computers can add, change and delete files in this folder."
                            : "Other computers can look at and copy files, but not change them."
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GToggle {
                        width: parent.width
                        label: "Allow guests (no password)"
                        checked: root.guest
                        available: Shares.guestsAllowed
                        unavailableText: "off in Samba config"
                        onToggled: v => { root.guest = v; root.recheck(); }
                    }
                    Text {
                        visible: root.guest
                        width: parent.width; wrapMode: Text.WordWrap
                        color: Theme.warn; font.family: Theme.ui; font.pixelSize: Theme.type.label
                        text: "Anyone on your network can open this share without a password."
                    }
                    Repeater {
                        model: root.warns.filter(w => w.code !== "guest")
                        delegate: Column {
                            id: wl
                            required property var modelData
                            width: col.width
                            spacing: 6
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                color: Theme.warn; font.family: Theme.ui; font.pixelSize: Theme.type.label
                                text: wl.modelData.message
                            }
                            GButton {
                                visible: wl.modelData.fix === "chmod-ow"
                                height: 28
                                text: "Make folder writable for everyone"
                                onClicked: Shares.chmodOw(root.folder, o => root.recheck())
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Comment (optional)" }
                    GInput {
                        id: commentField
                        width: parent.width
                        placeholder: "shown next to the share on other computers"
                        onAccepted: root.submit()
                        onEscaped: root.close()
                    }
                }

                Text {
                    visible: root.failure !== ""
                    width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.bad; font.family: Theme.ui; font.pixelSize: Theme.type.label
                    text: root.failure
                }

                Row {
                    spacing: 10
                    anchors.right: parent.right
                    GButton { text: "Cancel"; onClicked: root.close() }
                    GButton { primary: true; text: "Create share"; enabled: root.valid; onClicked: root.submit() }
                }
            }
        }
    }

    Process {
        id: picker
        command: ["zenity", "--file-selection", "--directory", "--title=Choose a folder to share"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p !== "") { folderField.text = p; root.onFolderChanged(); }
            }
        }
    }
}
