// AccountsPanel.qml - CLAUDE's accounts: add, sign in / out, rename, remove, and pick the one the open
// project uses. Signing in runs `claude auth login` in the account's own folder; the browser opens and
// normally hands the login back by itself, otherwise it shows a code to paste here.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../.."
import "../accessory"

Rectangle {
    id: root
    required property var host          // the ClaudeWindow

    implicitHeight: col.implicitHeight + 40
    color: Theme.bg1
    border.width: 1; border.color: Theme.lineStrong
    Keys.onEscapePressed: if (!login) host.overlay = ""

    // ---- signing in ----
    property var login: null            // the running claude.py login process
    property string loginId: ""
    property string loginUrl: ""
    property bool askCode: false
    property string loginMsg: ""
    property string loginErr: ""
    function signIn(id, console_) {
        cancelLogin();
        loginId = id; loginUrl = ""; askCode = false; loginMsg = "Opening the sign-in page in your browser…"; loginErr = "";
        login = Claude.stream(["login", id].concat(console_ ? ["console"] : []), o => {
            if (o.ev === "url") root.loginUrl = o.url;
            else if (o.ev === "code") root.askCode = true;
            else if (o.ev === "line") root.loginMsg = o.text;
            else if (o.ev === "done") {
                root.login = null;
                if (o.ok) { root.loginId = ""; Claude.setStatus(id, o.status); }
                else root.loginErr = o.err;
            }
        });
    }
    function sendCode() {
        if (login && codeEntry.text.trim() !== "") { login.write(codeEntry.text.trim() + "\n"); codeEntry.text = ""; loginMsg = "Checking the code…"; askCode = false; }
    }
    function cancelLogin() { if (login) { login.onEvent = null; login.running = false; login = null; } loginId = ""; loginErr = ""; }
    Component.onDestruction: cancelLogin()

    property string renaming: ""
    property string removing: ""

    ColumnLayout {
        id: col
        x: 20; y: 20; width: parent.width - 40
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            SectionLabel { text: "Accounts"; Layout.fillWidth: true }
            SmallLink { text: "CLOSE"; onClicked: { root.cancelLogin(); root.host.overlay = ""; } }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "Each account is its own Claude Code folder with its own sign-in, settings and history. "
                + (root.host.proj ? "\"" + root.host.proj.name + "\" uses the one marked USED HERE; its older chats keep the account they started with." : "")
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(accCol.implicitHeight, 360)
            clip: true
            ColumnLayout {
                id: accCol
                width: root.width - 40
                spacing: 8
                Repeater {
                    model: Claude.accounts
                    delegate: Rectangle {
                        id: acc
                        required property var modelData
                        readonly property var st: Claude.status[modelData.id] || {}
                        readonly property bool here: root.host.proj && Claude.accountFor(root.host.proj) === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: accInner.implicitHeight + 20
                        color: Theme.panel
                        border.width: 1; border.color: here ? Theme.accent : Theme.line
                        ColumnLayout {
                            id: accInner
                            x: 12; y: 10; width: parent.width - 24
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: acc.st.checking ? Theme.dim : acc.st.loggedIn ? Theme.ok : Theme.warn
                                }
                                Column {
                                    Layout.fillWidth: true
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: acc.modelData.name + (acc.here ? "   ·   USED HERE" : "")
                                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14; font.weight: Font.DemiBold
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideMiddle
                                        text: (acc.st.checking ? "checking…" : acc.st.loggedIn
                                               ? "signed in" + (acc.st.email ? " as " + acc.st.email : "") + (acc.st.method ? " (" + acc.st.method + ")" : "")
                                               : "not signed in") + "   ·   " + root.host.tilde(acc.modelData.dir || "~/.claude")
                                        color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                                    }
                                }
                            }
                            // rename
                            RowLayout {
                                visible: root.renaming === acc.modelData.id
                                Layout.fillWidth: true
                                Entry { id: renameEntry; Layout.fillWidth: true; text: acc.modelData.name; onAccepted: renBtn.clicked() }
                                ChamferButton {
                                    id: renBtn; implicitHeight: 30; text: "Save"; primary: true
                                    onClicked: Claude.run(["account-rename", acc.modelData.id, renameEntry.text], () => { root.renaming = ""; Claude.reload(); })
                                }
                                ChamferButton { implicitHeight: 30; text: "Cancel"; onClicked: root.renaming = "" }
                            }
                            // remove
                            ColumnLayout {
                                visible: root.removing === acc.modelData.id
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.Wrap
                                    text: acc.modelData.dir
                                        ? "Remove this account and delete its folder (its sign-in, settings and Claude Code history)?"
                                        : "Stop using ~/.claude here? Nothing is deleted; Claude Code itself keeps working as before."
                                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                                }
                                Row {
                                    spacing: 8
                                    ChamferButton {
                                        implicitHeight: 30; text: "Remove"; primary: true
                                        onClicked: Claude.run(["account-remove", acc.modelData.id, "purge"], () => { root.removing = ""; Claude.reload(); })
                                    }
                                    ChamferButton { implicitHeight: 30; text: "Cancel"; onClicked: root.removing = "" }
                                }
                            }
                            // signing in
                            ColumnLayout {
                                visible: root.loginId === acc.modelData.id
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.Wrap
                                    text: root.loginErr !== "" ? root.loginErr : root.loginMsg
                                    color: root.loginErr !== "" ? Theme.bad : Theme.fg
                                    font.family: Theme.ui; font.pixelSize: 13
                                }
                                Text {
                                    visible: root.askCode
                                    Layout.fillWidth: true; wrapMode: Text.Wrap
                                    text: "If the page shows a code after you sign in, paste it here:"
                                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                                }
                                RowLayout {
                                    visible: root.askCode
                                    Layout.fillWidth: true
                                    Entry { id: codeEntry; Layout.fillWidth: true; mono: true; placeholder: "code"; onAccepted: root.sendCode() }
                                    ChamferButton { implicitHeight: 30; text: "Send code"; primary: true; onClicked: root.sendCode() }
                                }
                                Row {
                                    spacing: 8
                                    ChamferButton { implicitHeight: 30; text: "Open page again"; visible: root.loginUrl !== ""; onClicked: Qt.openUrlExternally(root.loginUrl) }
                                    ChamferButton {
                                        implicitHeight: 30; text: "Copy link"; visible: root.loginUrl !== ""
                                        onClicked: Quickshell.execDetached(["wl-copy", root.loginUrl])
                                    }
                                    ChamferButton { implicitHeight: 30; text: root.loginErr !== "" ? "Close" : "Cancel"; onClicked: root.cancelLogin() }
                                }
                            }
                            // actions
                            Flow {
                                visible: root.loginId !== acc.modelData.id && root.renaming !== acc.modelData.id && root.removing !== acc.modelData.id
                                Layout.fillWidth: true
                                spacing: 6
                                ChamferButton {
                                    implicitHeight: 28; text: "Use here"; visible: !acc.here && !!root.host.proj; primary: true
                                    onClicked: {
                                        const p = root.host.proj;
                                        Claude.saveProject({ id: p.id, name: p.name, dir: p.dir, account: acc.modelData.id, model: p.model, perm: p.perm, notes: p.notes });
                                    }
                                }
                                ChamferButton { implicitHeight: 28; text: "Sign in"; visible: !acc.st.loggedIn; onClicked: root.signIn(acc.modelData.id, false) }
                                ChamferButton { implicitHeight: 28; text: "Sign in with Console"; visible: !acc.st.loggedIn; onClicked: root.signIn(acc.modelData.id, true) }
                                ChamferButton {
                                    implicitHeight: 28; text: "Sign out"; visible: !!acc.st.loggedIn
                                    onClicked: Claude.run(["logout", acc.modelData.id], () => Claude.checkAccount(acc.modelData.id))
                                }
                                ChamferButton { implicitHeight: 28; text: "Rename"; onClicked: root.renaming = acc.modelData.id }
                                ChamferButton { implicitHeight: 28; text: "Remove"; onClicked: root.removing = acc.modelData.id }
                            }
                        }
                    }
                }
            }
        }

        // add one
        SectionLabel { text: "Add an account"; Layout.topMargin: 6 }
        RowLayout {
            Layout.fillWidth: true
            Entry { id: newName; Layout.fillWidth: true; placeholder: "Name, e.g. Work or Personal"; onAccepted: addBtn.clicked() }
            ChamferButton {
                id: addBtn; implicitHeight: 32; text: "Add"; primary: newName.text.trim() !== ""
                onClicked: {
                    if (newName.text.trim() === "") return;
                    Claude.run(["account-add", newName.text], o => { newName.text = ""; if (o.ok) Claude.reload(() => root.signIn(o.account.id, false)); });
                }
            }
        }
        RowLayout {
            visible: !Claude.defaultUsed
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: "Already signed in to Claude Code? Use that sign-in (~/.claude) as an account."
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
            }
            ChamferButton { implicitHeight: 30; text: "Use it"; onClicked: Claude.run(["account-default"], () => Claude.reload()) }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "\"Sign in\" is for a Claude Pro, Max, Team or Enterprise plan; \"Sign in with Console\" bills an Anthropic Console organization instead."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
        }
    }
}
