// DDialog.qml - modal dialogs for DATA, driven by Data.dialog:
// confirm (delete / empty trash), conflict (Replace / Keep both / Skip), props, openwith,
// password (archive password prompt), input (path entry, e.g. Extract to…), compress (name / format / password).
import QtQuick
import Quickshell
import "../.."
import "../../components"
import "../games"

FocusScope {
    id: root
    anchors.fill: parent
    z: 100
    readonly property var d: Data.dialog
    visible: d !== null
    property bool applyAll: false
    property int appSel: 0
    property string cFmt: "zip"
    readonly property bool fielded: !!d && (d.kind === "password" || d.kind === "input" || d.kind === "compress")

    onVisibleChanged: if (visible) { applyAll = false; appSel = 0; forceActiveFocus(); }
    onDChanged: {   // fresh dialog: fresh fields (a password must never linger), focus the first one
        pwF.text = ""; cpwF.text = ""; cFmt = "zip";
        if (d && d.kind === "input") inF.text = d.value;
        if (d && d.kind === "compress") { nameF.text = d.name; cFmt = d.fmt || "zip"; }
        const isField = !!d && (d.kind === "password" || d.kind === "input" || d.kind === "compress");
        if (isField) Qt.callLater(() => { if (!d) return; const f = d.kind === "password" ? pwF : (d.kind === "input" ? inF : nameF); f.input.forceActiveFocus(); f.input.selectAll(); });
        else if (visible) forceActiveFocus();
    }
    function submit() {
        if (!d) return;
        if (d.kind === "password") { if (pwF.text !== "") Data.submitDialog({ pw: pwF.text }); }
        else if (d.kind === "input") { if (inF.text.trim() !== "") Data.submitDialog({ text: inF.text }); }
        else if (d.kind === "compress") { if (nameF.text.trim() !== "") Data.submitDialog({ name: nameF.text, fmt: cFmt, pw: cFmt === "tar.gz" ? "" : cpwF.text }); }
    }

    // single-line text field (mono, accent border while focused); echo = TextInput.Password for secrets
    component Field: Rectangle {
        id: fld
        property alias text: ti.text
        property alias input: ti
        property int echo: TextInput.Normal
        property string hint: ""
        property Item next: null          // Tab goes here
        signal accepted()
        height: 30
        color: Theme.bg1
        border.width: 1; border.color: ti.activeFocus ? Theme.accent : Theme.lineStrong
        Text {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            visible: ti.text === "" && fld.hint !== ""
            text: fld.hint; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
        }
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            echoMode: fld.echo; passwordCharacter: "•"
            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
            font.family: Theme.mono; font.pixelSize: 12; clip: true
            onAccepted: fld.accepted()
            KeyNavigation.tab: fld.next
        }
    }

    Keys.onPressed: event => {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
            if (d && d.kind === "conflict") Data.answerConflict("cancel", false); else Data.closeDialog();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (fielded) submit();
            else if (d && d.kind === "openwith") { if (Data.apps.length) Data.openWith(Data.apps[appSel]); }
            else if (d && d.kind === "conflict") Data.answerConflict("both", applyAll);
            else Data.acceptDialog();
        } else if (d && d.kind === "openwith" && event.key === Qt.Key_Down) appSel = Math.min(Data.apps.length - 1, appSel + 1);
        else if (d && d.kind === "openwith" && event.key === Qt.Key_Up) appSel = Math.max(0, appSel - 1);
        else event.accepted = false;
    }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55) }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Math.min(root.width - 40, d && d.kind === "conflict" ? 480 : (d && d.kind === "input" ? 520 : 440))
        height: Math.min(content.implicitHeight + 40, root.height - 24)
        color: Theme.bg1
        border.width: 1; border.color: Theme.lineStrong
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets {}

        Flickable {   // scrolls when the dialog is taller than the window (phone)
            id: contentFlick
            x: 20; y: 20
            width: box.width - 40; height: box.height - 40
            contentHeight: content.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
        Column {
            id: content
            width: contentFlick.width
            spacing: 14

            Item {   // .lbl
                width: parent.width; height: 16
                Rectangle { id: sq; width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                Text {
                    anchors.left: sq.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: !d ? "" : (d.kind === "confirm" || d.kind === "password" || d.kind === "input") ? d.title.toUpperCase()
                        : d.kind === "conflict" ? "NAME CONFLICT" : d.kind === "props" ? "PROPERTIES"
                        : d.kind === "compress" ? "COMPRESS" : "OPEN WITH"
                    color: Theme.fg
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                }
            }

            // ---- confirm
            Text {
                visible: d && d.kind === "confirm"
                width: parent.width; wrapMode: Text.WordWrap
                text: d && d.kind === "confirm" ? d.text : ""
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
            }
            // ---- password / input / compress
            Text {
                visible: d && (d.kind === "password" || d.kind === "input")
                width: parent.width; wrapMode: Text.WordWrap
                text: d && (d.kind === "password" || d.kind === "input") ? d.text : ""
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
            }
            Field {
                id: pwF
                visible: d && d.kind === "password"
                width: parent.width; echo: TextInput.Password; hint: "PASSWORD"
                onAccepted: root.submit()
            }
            Field {
                id: inF
                visible: d && d.kind === "input"
                width: parent.width
                onAccepted: root.submit()
            }
            Column {
                visible: d && d.kind === "compress"
                width: parent.width; spacing: 10
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: d && d.kind === "compress" ? "Compress " + (d.count === 1 ? "1 item" : d.count + " items") + " into an archive next to " + (d.count === 1 ? "it" : "them") + ". A taken name becomes “name (1)”." : ""
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                }
                Row {
                    spacing: 8
                    Repeater {
                        model: ["zip", "7z", "tar.gz"]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool on: root.cFmt === modelData
                            width: fl.implicitWidth + 24; height: 26
                            color: on ? Theme.panel2 : "transparent"
                            border.width: 1; border.color: on ? Theme.accent : Theme.lineStrong
                            Text { id: fl; anchors.centerIn: parent; text: modelData.toUpperCase(); color: parent.on ? Theme.accent : Theme.fg
                                   font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cFmt = parent.modelData }
                        }
                    }
                }
                Field { id: nameF; width: parent.width; hint: "NAME"; next: cpwF.input; onAccepted: root.submit() }
                Field {
                    id: cpwF
                    width: parent.width; echo: TextInput.Password; enabled: root.cFmt !== "tar.gz"; opacity: enabled ? 1 : 0.4
                    hint: root.cFmt === "tar.gz" ? "TAR.GZ CANNOT BE PASSWORD PROTECTED" : "PASSWORD (OPTIONAL)"
                    onAccepted: root.submit()
                }
                Text {
                    visible: root.cFmt !== "tar.gz"
                    width: parent.width; wrapMode: Text.WordWrap
                    text: root.cFmt === "zip" ? "With a password the zip uses AES-256." : "With a password the 7z hides file names too (AES-256)."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: nameF.text.trim() === "" ? "" : "→ " + nameF.text.trim() + (nameF.text.trim().toLowerCase().endsWith("." + root.cFmt) ? "" : "." + root.cFmt)
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                }
            }
            // ---- conflict
            Text {
                visible: d && d.kind === "conflict"
                width: parent.width; wrapMode: Text.WordWrap
                text: d && d.kind === "conflict" ? "“" + d.name + "” already exists in " + (Data.basename(d.dstDir) || "/") + ". What should happen?" : ""
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
            }
            Item {
                visible: d && d.kind === "conflict" && d.remaining > 1
                width: parent.width; height: 22
                Rectangle {
                    id: cb; width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter
                    color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; color: Theme.accent; visible: root.applyAll }
                }
                Text {
                    anchors.left: cb.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: "Apply to all " + (d && d.kind === "conflict" ? d.remaining : 0) + " conflicts"
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.applyAll = !root.applyAll }
            }

            // ---- props
            Column {
                visible: d && d.kind === "props"
                width: parent.width; spacing: 0
                Repeater {
                    model: {
                        const s = Data.propsStat, u = Data.propsDu;
                        if (!d || d.kind !== "props") return [];
                        if (!s) return [["", "Reading…"]];
                        if (s.err) return [["", s.err]];
                        const multi = s.count > 1;
                        const rows = [];
                        rows.push(["Name", multi ? s.count + " items" : s.name]);
                        rows.push(["Type", multi ? "Mixed" : s.mime + (s.link ? " → " + s.link : "")]);
                        rows.push(["Location", s.dir]);
                        rows.push(["Size", !u ? "Counting…" : Data.fmtSize(u.size) + (u.size >= 1000 ? " (" + u.size.toLocaleString(Qt.locale("en_US"), "f", 0) + " bytes)" : "") +
                                   (s.isdir || multi ? " · " + u.files + " files, " + u.dirs + " folders" : "")]);
                        if (!multi) {
                            rows.push(["Permissions", s.mode + "  (" + s.octal + ")"]);
                            rows.push(["Owner", s.owner + " : " + s.group]);
                            rows.push(["Modified", Data.fmtFull(s.mtime)]);
                            rows.push(["Accessed", Data.fmtFull(s.atime)]);
                            rows.push(["Changed", Data.fmtFull(s.ctime)]);
                        }
                        return rows;
                    }
                    delegate: Item {
                        required property var modelData
                        width: parent.width; height: 26
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                        Text {
                            x: 0; width: 96; anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0].toUpperCase(); color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                        }
                        Text {
                            x: 100; width: parent.width - 100; anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]; color: Theme.fg; elide: Text.ElideMiddle
                            font.family: Theme.mono; font.pixelSize: 12
                        }
                    }
                }
            }

            // ---- open with
            Column {
                visible: d && d.kind === "openwith"
                width: parent.width; spacing: 8
                Text {
                    width: parent.width; elide: Text.ElideMiddle
                    text: d && d.kind === "openwith" ? d.entry.n + "  ·  " + d.entry.t : ""
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                }
                Text {
                    visible: Data.apps.length === 0
                    text: "No applications found for this type."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
                }
                Repeater {
                    model: Data.apps
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: parent.width; height: 34
                        readonly property bool hot: root.appSel === index
                        Rectangle {
                            anchors.fill: parent; color: hot ? Theme.panel2 : "transparent"
                            Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: hot }
                        }
                        Image {
                            x: 10; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22
                            sourceSize: Qt.size(44, 44)
                            source: Icons.pathOr(modelData.icon, "application-x-executable")
                        }
                        Text {
                            x: 44; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name; color: hot ? Theme.accent : Theme.fg
                            font.family: Theme.ui; font.pixelSize: 13
                        }
                        GChip { visible: modelData.default; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "default"; tone: Theme.ok }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: root.appSel = index
                            onClicked: root.appSel = index
                            onDoubleClicked: Data.openWith(modelData)
                        }
                    }
                }
            }

            // ---- buttons (right-to-left, so they stay right-aligned and wrap on a narrow window)
            Flow {
                width: parent.width
                layoutDirection: Qt.RightToLeft
                spacing: 10
                GButton { visible: d && d.kind === "openwith"; primary: true; enabled: Data.apps.length > 0; text: "Open"; onClicked: Data.openWith(Data.apps[root.appSel]) }
                GButton { visible: d && d.kind === "openwith"; text: "Cancel"; onClicked: Data.closeDialog() }
                GButton { visible: d && d.kind === "props"; primary: true; text: "Close"; onClicked: Data.closeDialog() }
                GButton { visible: d && d.kind === "compress"; primary: true; text: "Compress"; onClicked: root.submit() }
                GButton { visible: d && (d.kind === "password" || d.kind === "input"); primary: true; text: d && d.ok ? d.ok : "OK"; onClicked: root.submit() }
                GButton { visible: d && (d.kind === "password" || d.kind === "input" || d.kind === "compress"); text: "Cancel"; onClicked: Data.closeDialog() }
                GButton { visible: d && d.kind === "confirm"; primary: true; text: d && d.kind === "confirm" ? d.ok : ""; onClicked: Data.acceptDialog() }
                GButton { visible: d && d.kind === "confirm"; text: "Cancel"; onClicked: Data.closeDialog() }
                GButton { visible: d && d.kind === "conflict"; primary: true; text: "Replace"; onClicked: Data.answerConflict("replace", root.applyAll) }
                GButton { visible: d && d.kind === "conflict"; text: "Keep both"; onClicked: Data.answerConflict("both", root.applyAll) }
                GButton { visible: d && d.kind === "conflict"; text: "Skip"; onClicked: Data.answerConflict("skip", root.applyAll) }
                GButton { visible: d && d.kind === "conflict"; text: "Cancel"; onClicked: Data.answerConflict("cancel", false) }
            }
        }
        }
    }
}
