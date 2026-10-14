// Discord: Vesktop (Discord with Vencord) with one instance per account, so several accounts are
// signed in at once. Each account has its own launcher entry and data (sign-in, Vencord plugins).
// Add, rename, open and remove accounts here; ../discord/discord.py does the work (bin/ultimit-discord).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"

Page {
    id: pg
    title: "Discord"
    subtitle: "Discord with Vencord (Vesktop). Every account runs on its own, so they can all be signed in at the same time; each has its own entry in the launcher. Vencord's plugins and themes are under User Settings › Vencord in each account."

    readonly property string script: Quickshell.shellPath("apps/discord/discord.py")
    property var st: ({ accounts: [] })
    property bool loaded: false
    property bool busy: false
    property string sel: ""            // account id being renamed / removed
    property string mode: ""           // "" | "rename" | "remove"
    property string note: ""
    property color noteColor: Theme.dim

    // setup first: the default accounts, launcher entries and theme (also after a fresh install)
    function reload() { setupProc.running = true; }
    Component.onCompleted: reload()
    Timer { interval: 3000; repeat: true; running: pg.visible && pg.loaded && !pg.busy; onTriggered: listProc.running = true }
    Process {
        id: setupProc
        command: ["python3", "-I", pg.script, "setup"]
        onExited: listProc.running = true
    }
    Process {
        id: listProc
        command: ["python3", "-I", pg.script, "list"]
        stdout: StdioCollector { onStreamFinished: { try { pg.st = JSON.parse(text); pg.loaded = true; } catch (e) {} } }
    }

    function run(args, okText) {
        if (busy) return;
        if (SetSys.dryRun) { console.log("[dry-run] ultimit-discord " + args.join(" ")); note = "Dry run: nothing changed."; return; }
        busy = true; note = ""; job.okText = okText;
        job.command = ["python3", "-I", pg.script].concat(args);
        job.running = true;
    }
    Process {
        id: job
        property string okText: ""
        stdout: StdioCollector { id: jobOut }
        onExited: code => {
            pg.busy = false;
            let o = {};
            try { o = JSON.parse(jobOut.text); } catch (e) {}
            if (code === 0 && o.ok !== false) {
                pg.note = job.okText; pg.noteColor = Theme.ok; pg.mode = ""; pg.sel = "";
                newName.text = ""; renameEntry.text = "";
            } else {
                pg.note = o.error || "That didn't work (exit " + code + ")."; pg.noteColor = Theme.bad;
            }
            listProc.running = true;
        }
    }
    function open(id) {
        if (SetSys.dryRun) { console.log("[dry-run] ultimit-discord open " + id); return; }
        Quickshell.execDetached(["python3", "-I", pg.script, "open", id]);
    }

    // ================= not installed =================
    Rectangle {
        visible: pg.loaded && pg.st.installed === false
        Layout.fillWidth: true
        implicitHeight: instRow.implicitHeight + 28
        color: Theme.panel2; border.color: Theme.warn
        RowLayout {
            id: instRow
            x: 16; y: 14; width: parent.width - 32
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Vesktop isn't installed. Install it from STORE, then come back here: the accounts appear in the launcher by themselves."
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12
            }
            ChamferButton {
                primary: true; text: "Open in STORE"
                onClicked: Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-store"), "--app", pg.st.app || "dev.vencord.Vesktop"])
            }
        }
    }

    // ================= the accounts =================
    SectionLabel { text: "Accounts" }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: pg.st.accounts || []
            delegate: ItemRow {
                id: row
                required property var modelData
                title: modelData.name
                subtitle: "Account " + modelData.id + (modelData.id === "1" ? "  ·  opens discord:// links" : "")
                badge: modelData.running ? "running" : ""
                badgeColor: Theme.ok
                selected: pg.sel === modelData.id
                ChamferButton {
                    text: modelData.running ? "Show" : "Open"; implicitHeight: 30
                    enabled: pg.st.installed === true
                    onClicked: pg.open(row.modelData.id)
                }
                ChamferButton {
                    text: "Rename"; implicitHeight: 30
                    onClicked: { pg.sel = row.modelData.id; pg.mode = "rename"; pg.note = ""; renameEntry.text = row.modelData.name; renameEntry.focusEntry(); }
                }
                ChamferButton {
                    visible: row.modelData.id !== "1"
                    text: "Remove"; implicitHeight: 30
                    onClicked: { pg.sel = row.modelData.id; pg.mode = "remove"; pg.note = ""; }
                }
            }
        }
    }

    // ================= rename / remove =================
    RowLayout {
        visible: pg.mode === "rename"
        Layout.fillWidth: true
        spacing: 8
        TextEntry {
            id: renameEntry
            Layout.fillWidth: true
            placeholder: "Name in the launcher"
            onAccepted: pg.run(["rename", pg.sel, text], "Renamed.")
        }
        ChamferButton { text: "Cancel"; onClicked: { pg.mode = ""; pg.sel = ""; } }
        ChamferButton {
            primary: true; text: "Save"
            enabled: !pg.busy && renameEntry.text.trim() !== ""
            onClicked: pg.run(["rename", pg.sel, renameEntry.text], "Renamed.")
        }
    }
    Rectangle {
        visible: pg.mode === "remove"
        Layout.fillWidth: true
        implicitHeight: rmRow.implicitHeight + 28
        color: Theme.panel2; border.color: Theme.bad
        RowLayout {
            id: rmRow
            x: 16; y: 14; width: parent.width - 32
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Remove this account? Its launcher entry goes, and it is signed out: its Vencord plugins and settings are deleted too. Your Discord account itself is not touched."
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12
            }
            ChamferButton { text: "Cancel"; onClicked: { pg.mode = ""; pg.sel = ""; } }
            ChamferButton {
                primary: true; text: pg.busy ? "Removing…" : "Remove"
                enabled: !pg.busy
                onClicked: pg.run(["remove", pg.sel], "Account removed.")
            }
        }
    }

    Text {
        visible: pg.note !== ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: pg.note; color: pg.noteColor; font.family: Theme.ui; font.pixelSize: 12
    }

    // ================= add =================
    SectionLabel { text: "Add an account" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        TextEntry {
            id: newName
            Layout.fillWidth: true
            placeholder: "Name in the launcher (e.g. Alt)"
            onAccepted: pg.run(["add"].concat(text.trim() !== "" ? [text] : []), "Added. Open it and sign in.")
        }
        ChamferButton {
            primary: true; text: pg.busy ? "Adding…" : "Add"
            enabled: !pg.busy
            onClicked: pg.run(["add"].concat(newName.text.trim() !== "" ? [newName.text] : []), "Added. Open it and sign in.")
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "New accounts start with the Ultimit theme and title bar. The theme follows your skin when Discord starts. Rich Presence (the game you're playing as your status) is on for the first account only."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
}
