// SetupBanner.qml - what FIREWALL needs before it can work: ufw itself, the root helper (+ its polkit policy),
// or an unlock when reading the firewall was not authorized. Shows the exact command a button runs.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root

    readonly property string step: !Firewall.helperInstalled ? "install-helper" : !Firewall.ufwInstalled ? "install-ufw" : Firewall.locked ? "unlock" : ""
    property var commands: ({})
    Component.onCompleted: Firewall.setupCommands(o => { if (o.ok) for (const s of o.steps) root.commands[s.id] = s.display; root.commandsChanged(); })

    visible: Firewall.loaded && step !== ""
    implicitHeight: col.implicitHeight + 28
    color: Theme.panel2
    border.color: Theme.warn
    border.width: 1

    Column {
        id: col
        x: 16; y: 14
        width: parent.width - 32
        spacing: 8

        Row {
            spacing: 8
            Rectangle { width: 6; height: 6; color: Theme.warn; anchors.verticalCenter: parent.verticalCenter }
            GLabel {
                strong: true
                text: root.step === "install-helper" ? "One-time setup" : root.step === "install-ufw" ? "No firewall installed" : "Locked"
            }
        }
        Item {
            width: parent.width
            height: Math.max(txt.implicitHeight, btn.height)
            Text {
                id: txt
                anchors { left: parent.left; right: btn.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                wrapMode: Text.WordWrap
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                text: root.step === "install-helper"
                    ? "FIREWALL needs its small helper installed in the system, so it can read and change the firewall. Looking needs no password afterwards; every change still asks."
                    : root.step === "install-ufw"
                    ? "ufw (the Uncomplicated Firewall) is not installed. Install it to choose which devices can reach this PC."
                    : "You did not authorize reading the firewall, so nothing is shown. Unlock to try again."
            }
            GButton {
                id: btn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                primary: true
                enabled: Firewall.busy === ""
                text: Firewall.busy.startsWith("setup:") ? "Working…" : root.step === "unlock" ? "Unlock" : "Install"
                onClicked: root.step === "unlock" ? Firewall.unlock() : Firewall.setup(root.step)
            }
        }
        Text {
            visible: (root.commands[root.step] || "") !== ""
            width: parent.width
            wrapMode: Text.WrapAnywhere
            text: root.commands[root.step] || ""
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
        }
    }
}
