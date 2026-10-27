// Setup.qml - what CLAUDE shows before it can chat: install Claude Code (Anthropic's own installer, for
// this user, no password), then add an account.
import QtQuick
import "../.."
import "../accessory"

Column {
    id: root
    signal accounts()
    spacing: 14

    property bool installing: false
    property string log: ""
    property string err: ""

    function install() {
        installing = true; log = ""; err = "";
        Claude.stream(["install"], o => {
            if (o.ev === "line") root.log = o.text;
            else if (o.ev === "done") {
                root.installing = false;
                if (!o.ok) root.err = o.err;
                Claude.checkCli();
            }
        });
    }

    readonly property string step: !Claude.cliChecked ? "checking" : Claude.cliPath === "" ? "install" : "account"

    SectionLabel { text: root.step === "install" ? "Claude Code" : root.step === "account" ? "Accounts" : "Starting" }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        visible: root.step !== "checking"
        text: root.step === "install"
            ? "CLAUDE runs on Claude Code, Anthropic's own command-line Claude. It isn't installed for you yet. Installing it puts it in ~/.local/bin (no password needed) and it keeps itself up to date."
            : "Add the account Claude should use. Each account keeps its own sign-in, settings and history, so a work and a personal account never mix. You pick the account per project."
        color: Theme.fg; font.family: Theme.ui; font.pixelSize: Theme.type.body
    }
    Row {
        spacing: 10
        visible: root.step === "install"
        ChamferButton { text: root.installing ? "Installing…" : "Install Claude Code"; primary: !root.installing; onClicked: if (!root.installing) root.install() }
        ChamferButton { text: "Check again"; visible: !root.installing; onClicked: Claude.checkCli() }
    }
    Row {
        spacing: 10
        visible: root.step === "account"
        ChamferButton {
            text: "Use my Claude Code sign-in"
            visible: !Claude.defaultUsed
            primary: true
            onClicked: Claude.run(["account-default"], () => Claude.reload())
        }
        ChamferButton { text: "Add an account"; primary: Claude.defaultUsed; onClicked: root.accounts() }
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        visible: root.step === "account" && !Claude.defaultUsed
        text: "\"Use my Claude Code sign-in\" uses the login Claude Code already has in ~/.claude. A new account starts signed out, in its own folder."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
    }
    Text {
        width: parent.width; elide: Text.ElideRight
        visible: root.installing || root.err !== ""
        text: root.err !== "" ? root.err : root.log
        color: root.err !== "" ? Theme.bad : Theme.dim
        wrapMode: root.err !== "" ? Text.Wrap : Text.NoWrap
        font.family: Theme.mono; font.pixelSize: Theme.type.label
    }
}
