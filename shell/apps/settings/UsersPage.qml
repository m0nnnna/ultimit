// Users: the people who can sign in. Add an account (standard or administrator), change your own
// password (passwd checks the current one, so standard accounts can too), and for other accounts:
// full name, password, administrator rights, delete (keeping or removing their files). Reading is
// users.py; changes to other accounts go through /usr/libexec/ultimit/users-helper via pkexec
// (polkit org.ultimit.users asks for an administrator's password). Passwords travel on stdin only.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"

Page {
    id: pg
    title: "Users"
    subtitle: "Everyone who can sign in to this computer. Administrators can install updates and change system settings."

    readonly property string script: Quickshell.shellPath("apps/settings/users.py")
    readonly property string helper: "/usr/libexec/ultimit/users-helper"
    property var st: ({ users: [] })
    property var setupCmd: null
    property string sel: ""            // selected user name ("" = none)
    property string mode: ""           // "" | "add" | "mypw" | "pw" | "delete"
    property bool busy: false
    property string note: ""
    property color noteColor: Theme.dim

    readonly property var me: (st.users || []).find(u => u.you) || null
    readonly property var cur: (st.users || []).find(u => u.user === sel) || null

    function reload() { listProc.running = true; }
    Component.onCompleted: { reload(); setupProc.running = true; }
    Process {
        id: listProc
        command: ["python3", "-I", pg.script, "list"]
        stdout: StdioCollector { onStreamFinished: { try { pg.st = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: setupProc
        command: ["python3", "-I", pg.script, "setup"]
        stdout: StdioCollector { onStreamFinished: { try { pg.setupCmd = JSON.parse(text); } catch (e) {} } }
    }

    // ---- one change at a time: argv, optional stdin, then a note and a fresh list ----
    function run(argv, input, okText) {
        if (busy) return;
        if (SetSys.dryRun) { console.log("[dry-run] " + argv.join(" ")); note = "Dry run: nothing changed."; return; }
        busy = true; note = ""; job.okText = okText; job.input = input || "";
        job.command = argv;
        job.running = true;
    }
    Process {
        id: job
        property string okText: ""
        property string input: ""
        stdinEnabled: true
        onStarted: { if (input !== "") write(input); stdinEnabled = false; }
        stdout: StdioCollector { id: jobOut }
        onExited: code => {
            pg.busy = false; job.stdinEnabled = true;
            let o = {};
            try { o = JSON.parse(jobOut.text); } catch (e) {}
            if (code === 0 && o.ok !== false) {
                pg.note = job.okText; pg.noteColor = Theme.ok; pg.mode = "";
                pw1.text = ""; pw2.text = ""; pw0.text = ""; pwA.text = ""; pwB.text = "";
                newName.text = ""; newUser.text = ""; newUser.edited = false;
            } else if (job.command[0] === "pkexec" && (code === 126 || code === 127)) {
                pg.note = "Cancelled."; pg.noteColor = Theme.dim;
            } else {
                pg.note = o.error || "That didn't work (exit " + code + ")."; pg.noteColor = Theme.bad;
            }
            pg.reload();
        }
    }
    function helperRun(args, input, okText) { run(["pkexec", helper].concat(args), input, okText); }

    function passwordProblem(a, b) {
        if (a.length < 8) return "Use at least 8 characters.";
        if (a !== b) return "The two passwords don't match.";
        return "";
    }
    function slug(name) {   // "Alex Doe" -> "alex"
        const s = name.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").split(/\s+/)[0] || "";
        return s.replace(/[^a-z0-9_-]/g, "").replace(/^[^a-z_]+/, "").slice(0, 32);
    }

    // ================= one-time setup =================
    Rectangle {
        visible: pg.st.helper === false
        Layout.fillWidth: true
        implicitHeight: setupCol.implicitHeight + 28
        color: Theme.panel2; border.color: Theme.warn
        ColumnLayout {
            id: setupCol
            x: 16; y: 14; width: parent.width - 32
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: "One-time setup: adding and changing other people's accounts needs a small helper installed in the system. You can change your own password without it."
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12
                }
                ChamferButton {
                    primary: true
                    text: pg.busy ? "Setting up…" : "Set up"
                    enabled: !pg.busy && pg.setupCmd !== null
                    onClicked: pg.run(["pkexec"].concat(pg.setupCmd.argv), "", "Users are set up.")
                }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                text: pg.setupCmd ? pg.setupCmd.display : ""
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9
            }
        }
    }

    // ================= the accounts =================
    RowLayout {
        Layout.fillWidth: true
        SectionLabel { text: "Accounts"; Layout.fillWidth: true }
        ChamferButton {
            visible: pg.st.helper === true
            text: "Add someone"
            enabled: !pg.busy
            onClicked: { pg.mode = "add"; pg.sel = ""; pg.note = ""; newName.focusEntry(); }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: pg.st.users || []
            delegate: ItemRow {
                required property var modelData
                title: modelData.name + (modelData.you ? "  (you)" : "")
                subtitle: modelData.user + "  ·  " + modelData.home
                badge: modelData.admin ? "administrator" : "standard"
                badgeColor: modelData.admin ? Theme.accent : Theme.dim
                selected: pg.sel === modelData.user
                onClicked: { pg.sel = pg.sel === modelData.user ? "" : modelData.user; pg.mode = ""; pg.note = ""; }
            }
        }
    }

    Text {
        visible: pg.note !== ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: pg.note; color: pg.noteColor; font.family: Theme.ui; font.pixelSize: 12
    }

    // ================= add someone =================
    Rectangle {
        visible: pg.mode === "add"
        Layout.fillWidth: true
        implicitHeight: addCol.implicitHeight + 28
        color: Theme.panel2; border.color: Theme.line
        ColumnLayout {
            id: addCol
            x: 16; y: 14; width: parent.width - 32
            spacing: 8
            SectionLabel { text: "New account" }
            GridLayout {
                Layout.fillWidth: true
                columns: 2; columnSpacing: 12; rowSpacing: 8
                Text { text: "Full name"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12 }
                TextEntry {
                    id: newName; Layout.fillWidth: true; placeholder: "Alex Doe"
                    onTextChanged: if (!newUser.edited) newUser.text = pg.slug(text)
                }
                Text { text: "User name"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12 }
                TextEntry {
                    id: newUser; Layout.fillWidth: true; placeholder: "alex"
                    property bool edited: false
                    onTextChanged: if (activeFocus) edited = true
                }
                Text { text: "Password"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12 }
                TextEntry { id: pw1; Layout.fillWidth: true; secret: true; placeholder: "at least 8 characters" }
                Text { text: "Again"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12 }
                TextEntry { id: pw2; Layout.fillWidth: true; secret: true }
            }
            Chips {
                id: kind
                Layout.fillWidth: true
                property string value: "standard"
                options: [{ id: "standard", label: "Standard account" }, { id: "admin", label: "Administrator" }]
                current: value
                onPicked: id => value = id
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ChamferButton { text: "Cancel"; onClicked: pg.mode = "" }
                ChamferButton {
                    primary: true
                    text: pg.busy ? "Creating…" : "Create account"
                    enabled: !pg.busy && newName.text.trim() !== "" && newUser.text !== ""
                    onClicked: {
                        const p = pg.passwordProblem(pw1.text, pw2.text);
                        if (p) { pg.note = p; pg.noteColor = Theme.bad; return; }
                        pg.helperRun(["create", newUser.text, newName.text.trim(), kind.value], pw1.text + "\n",
                                     newName.text.trim() + " can sign in now.");
                    }
                }
            }
        }
    }

    // ================= the selected account =================
    Rectangle {
        visible: pg.cur !== null && pg.mode !== "add"
        Layout.fillWidth: true
        implicitHeight: accCol.implicitHeight + 28
        color: Theme.panel2; border.color: Theme.line
        ColumnLayout {
            id: accCol
            x: 16; y: 14; width: parent.width - 32
            spacing: 10
            SectionLabel { text: pg.cur ? pg.cur.name + (pg.cur.you ? "  ·  your account" : "") : "" }

            // actions
            Flow {
                Layout.fillWidth: true
                spacing: 8
                ChamferButton {
                    text: "Change password"
                    onClicked: { pg.mode = pg.cur.you ? "mypw" : "pw"; pg.note = ""; (pg.cur.you ? pw0 : pwA).focusEntry(); }
                }
                ChamferButton {
                    visible: !!pg.cur && !pg.cur.you && pg.st.helper === true
                    text: pg.cur && pg.cur.admin ? "Make standard" : "Make administrator"
                    enabled: !pg.busy
                    onClicked: pg.helperRun(["admin", pg.cur.user, pg.cur.admin ? "off" : "on"], "",
                                            pg.cur.name + (pg.cur.admin ? " is a standard account now." : " is an administrator now."))
                }
                ChamferButton {
                    visible: !!pg.cur && !pg.cur.you && pg.st.helper === true
                    text: "Delete account…"
                    onClicked: { pg.mode = "delete"; pg.note = ""; }
                }
            }

            // password (yours: current + new; someone else's: new only, an admin's password authorises)
            GridLayout {
                visible: pg.mode === "mypw" || pg.mode === "pw"
                Layout.fillWidth: true
                columns: 2; columnSpacing: 12; rowSpacing: 8
                Text { visible: pg.mode === "mypw"; text: "Current password"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12 }
                TextEntry { id: pw0; visible: pg.mode === "mypw"; Layout.fillWidth: true; secret: true }
                Text { text: "New password"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12 }
                TextEntry { id: pwA; Layout.fillWidth: true; secret: true; placeholder: "at least 8 characters" }
                Text { text: "Again"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12 }
                TextEntry { id: pwB; Layout.fillWidth: true; secret: true }
            }
            Text {
                visible: pg.mode === "mypw"
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Your keyring (saved Wi-Fi and app passwords) still opens with your old password: the next time it asks, give the old one."
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
            }
            RowLayout {
                visible: pg.mode === "mypw" || pg.mode === "pw"
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ChamferButton { text: "Cancel"; onClicked: { pg.mode = ""; pw0.text = ""; pwA.text = ""; pwB.text = ""; } }
                ChamferButton {
                    primary: true
                    text: pg.busy ? "Changing…" : "Change password"
                    enabled: !pg.busy
                    onClicked: {
                        const p = pg.passwordProblem(pwA.text, pwB.text);
                        if (p) { pg.note = p; pg.noteColor = Theme.bad; return; }
                        if (pg.mode === "mypw")
                            pg.run(["python3", "-I", pg.script, "mypassword"], pw0.text + "\n" + pwA.text + "\n", "Your password is changed.");
                        else
                            pg.helperRun(["password", pg.cur.user], pwA.text + "\n", pg.cur.name + "'s password is changed.");
                        pwA.text = ""; pwB.text = "";
                    }
                }
            }

            // delete
            ColumnLayout {
                visible: pg.mode === "delete"
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: pg.cur ? "Delete " + pg.cur.name + "'s account? They can't sign in any more. Their files in " + pg.cur.home + " can stay (you can still open them as an administrator) or go too." : ""
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    ChamferButton { text: "Cancel"; onClicked: pg.mode = "" }
                    ChamferButton {
                        text: "Delete, keep files"; enabled: !pg.busy
                        onClicked: { const n = pg.cur.name; pg.helperRun(["delete", pg.cur.user, "keep"], "", n + "'s account is deleted; the files stay."); pg.sel = ""; }
                    }
                    ChamferButton {
                        primary: true; text: "Delete with files"; enabled: !pg.busy
                        onClicked: { const n = pg.cur.name; pg.helperRun(["delete", pg.cur.user, "remove"], "", n + "'s account and files are deleted."); pg.sel = ""; }
                    }
                }
            }
        }
    }
}
