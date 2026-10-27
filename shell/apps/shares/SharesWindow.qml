// SharesWindow.qml - the SHARES window: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Header with status chips and your network address, a setup panel while something is missing, then the
// list of shares. Dialogs (New share, Network password, Remove) are overlays inside this window.
import QtQuick
import QtQuick.Controls
import Quickshell
import "../.."
import "../games"

FloatingWindow {
    id: win
    title: "SHARES"
    visible: Shares.open
    implicitWidth: 880
    implicitHeight: 640
    minimumSize: Qt.size(660, 460)
    color: "transparent"   // the Theme.panel glass below fills it

    property bool showSetup: false
    readonly property bool setupShown: Shares.loaded && (Shares.setupNeeded || showSetup)

    onVisibleChanged: if (visible !== Shares.open) Shares.open = visible
    Connections {
        target: Shares
        function onNewSeqChanged() {
            if (!Shares.canShare) { Shares.say("Finish the setup first, then create the share.", "error"); win.showSetup = true; return; }
            Shares.overlay = "new";
        }
        function onOverlayChanged() {
            if (Shares.overlay === "new") newDlg.open(Shares.newPath);
            else if (Shares.overlay === "password") pwDlg.open();
            else if (Shares.overlay === "remove") rmDlg.visible = true;
            else if (Shares.overlay === "creds") credsDlg.open();
            else { credsDlg.clear(); credsDlg.visible = false; newDlg.visible = false; pwDlg.clear(); pwDlg.visible = false; rmDlg.visible = false; }
        }
    }
    Component.onCompleted: Shares.refresh()

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        // ---------------- header ----------------
        Item {
            id: header
            // The window title itself is in the compositor's titlebar.
            x: 20; y: 10
            width: parent.width - 40
            height: 36
            GLabel {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "File share maker"
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                GButton {
                    text: win.setupShown ? "Hide setup" : "Setup"
                    visible: Shares.tab === "mine" && Shares.loaded && !Shares.setupNeeded
                    onClicked: win.showSetup = !win.showSetup
                }
                GButton {
                    visible: Shares.tab === "mine"
                    primary: true
                    text: "New share…"
                    enabled: Shares.canShare && Shares.busy === ""
                    onClicked: { Shares.newPath = ""; Shares.newSeq++; }
                }
            }
        }


        // ---------------- tabs ----------------
        Item {
            id: tabBar
            x: 20; anchors.top: header.bottom; anchors.topMargin: 2
            width: parent.width - 40
            height: 32
            Row {
                spacing: 4
                Repeater {
                    model: [{ id: "mine", label: "My shares" }, { id: "connect", label: "Connect" }]
                    delegate: Item {
                        id: tb
                        required property var modelData
                        readonly property bool on: Shares.tab === modelData.id
                        width: tl.implicitWidth + 36; height: 32
                        Text {
                            id: tl
                            anchors.centerIn: parent
                            text: tb.modelData.label.toUpperCase()
                            color: tb.on ? Theme.accent : (tm.containsMouse ? Theme.fg : Theme.dim)
                            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.8
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent; visible: tb.on }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { Shares.tab = tb.modelData.id; if (tb.modelData.id === "connect") Shares.showConnect(); } }
                    }
                }
            }
        }

        // ---------------- status chips + address ----------------
        Item {
            id: statusRow
            x: 20; anchors.top: tabBar.bottom; anchors.topMargin: 12
            visible: Shares.tab === "mine"
            width: parent.width - 40
            height: chipFlow.height
            Flow {
                id: chipFlow
                width: parent.width
                spacing: 8
                GChip {
                    text: (Shares.installed ? "✓ " : "✕ ") + "Samba"
                    tone: !Shares.loaded ? Theme.dim : Shares.installed ? Theme.ok : Theme.bad
                }
                GChip {
                    text: (Shares.active ? "✓ " : "✕ ") + "Sharing service " + (Shares.active ? "running" : "stopped")
                    tone: !Shares.loaded ? Theme.dim : Shares.active ? Theme.ok : Theme.bad
                }
                GChip {
                    text: Shares.fwState === "allowed" ? "✓ Firewall: allowed on home network"
                        : Shares.fwState === "blocked" ? "✕ Firewall: blocked"
                        : Shares.fwState === "unknown" ? "? Firewall: unknown"
                        : Shares.fwState === "inactive" ? "✓ Firewall: off"
                        : "✓ No firewall"
                    tone: !Shares.loaded ? Theme.dim : Shares.fwState === "blocked" ? Theme.bad
                        : Shares.fwState === "unknown" ? Theme.warn : Theme.ok
                }
                GChip {
                    visible: Shares.loaded && Shares.relogin
                    text: "Log out and back in once"
                    tone: Theme.warn
                }
            }
        }

        Rectangle {
            id: addrBar
            x: 20; anchors.top: statusRow.bottom; anchors.topMargin: 10
            width: parent.width - 40
            height: 40
            color: Theme.field
            visible: Shares.loaded && Shares.tab === "mine"
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 14
                GLabel { anchors.verticalCenter: parent.verticalCenter; text: "Your address" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\\\\" + Shares.host
                    color: Theme.fg; font.family: Theme.mono; font.pixelSize: Theme.type.body
                }
                GLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Copy"
                    color: c1.containsMouse ? Theme.accent : Theme.dim
                    MouseArea { id: c1; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Shares.copy("\\\\" + Shares.host) }
                }
                Rectangle { width: 1; height: 16; color: Theme.line; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Shares.addr !== null
                    text: Shares.addr ? "smb://" + Shares.addr.ip : ""
                    color: Theme.fg; font.family: Theme.mono; font.pixelSize: Theme.type.body
                }
                GLabel {
                    visible: Shares.addr !== null
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Copy"
                    color: c2.containsMouse ? Theme.accent : Theme.dim
                    MouseArea { id: c2; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Shares.copy("smb://" + Shares.addr.ip) }
                }
                GLabel {
                    visible: Shares.addr === null
                    anchors.verticalCenter: parent.verticalCenter
                    text: "No home network found"
                    color: Theme.warn
                }
            }
        }

        // ---------------- message line ----------------
        Text {
            id: noteLine
            x: 20; anchors.top: addrBar.bottom; anchors.topMargin: 8
            width: parent.width - 40
            height: Shares.note !== "" ? 16 : 0
            elide: Text.ElideRight
            text: Shares.note
            color: Shares.noteKind === "error" ? Theme.bad : Theme.dim
            font.family: Theme.ui; font.pixelSize: Theme.type.label
            visible: Shares.note !== "" && Shares.tab === "mine"
        }

        // ---------------- scroll area: setup + list ----------------
        Flickable {
            id: scroller
            visible: Shares.tab === "mine"
            x: 20
            anchors.top: noteLine.bottom; anchors.topMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 40
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: body
                width: scroller.width - 8
                spacing: 12

                SetupPanel {
                    width: parent.width
                    visible: win.setupShown
                    onPasswordRequested: Shares.overlay = "password"
                }

                Item {
                    width: parent.width
                    height: 18
                    visible: Shares.loaded
                    Rectangle { id: sq2; width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                    GLabel { anchors { left: sq2.right; leftMargin: 8; verticalCenter: parent.verticalCenter } text: "Shared folders"; strong: true }
                    GLabel {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: Shares.shares.length + (Shares.shares.length === 1 ? " share" : " shares")
                    }
                }

                Repeater {
                    model: Shares.shares
                    delegate: ShareRow {
                        required property var modelData
                        width: body.width
                        share: modelData
                        onRemoveRequested: name => { Shares.removeName = name; Shares.overlay = "remove"; }
                    }
                }

                // empty state
                Column {
                    visible: Shares.loaded && Shares.shares.length === 0
                    width: parent.width
                    topPadding: 36
                    spacing: 12
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Nothing shared yet"
                        color: Theme.fg
                        font.family: Theme.display; font.pixelSize: Theme.ds(16); font.letterSpacing: Theme.dt(0.5)
                    }
                    Text {
                        width: Math.min(parent.width, 460)
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: Shares.canShare
                            ? "Pick a folder and other computers on your home network can open it. You decide whether they can change files."
                            : "Finish the setup above, then pick a folder to share with other computers on your home network."
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: Theme.type.body
                    }
                    GButton {
                        visible: Shares.canShare
                        anchors.horizontalCenter: parent.horizontalCenter
                        primary: true; text: "New share…"
                        onClicked: { Shares.newPath = ""; Shares.newSeq++; }
                    }
                }

                Text {
                    visible: Shares.listError !== ""
                    width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.warn; font.family: Theme.ui; font.pixelSize: Theme.type.label
                    text: "Could not read the share list: " + Shares.listError
                }
            }
        }

        ConnectPage {
            visible: Shares.tab === "connect"
            x: 20; anchors.top: tabBar.bottom; anchors.topMargin: 14
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 40
        }

        GLabel {
            anchors.centerIn: parent
            visible: !Shares.loaded && Shares.tab === "mine"
            text: "Checking…"
        }
    }

    // ---------------- dialogs ----------------
    NewShareDialog { id: newDlg; onClosed: if (Shares.overlay === "new") Shares.overlay = "" }
    PasswordDialog { id: pwDlg; onClosed: if (Shares.overlay === "password") Shares.overlay = "" }
    CredsDialog { id: credsDlg; onClosed: if (Shares.overlay === "creds") Shares.overlay = "" }
    SharesPrompt {
        id: rmDlg
        visible: false
        title: "Stop sharing “" + Shares.removeName + "”?"
        message: "Other computers will no longer see this folder. Your files stay exactly where they are."
        buttons: [{ id: "cancel", text: "Cancel" }, { id: "remove", text: "Stop sharing", primary: true }]
        onChosen: id => {
            visible = false;
            Shares.overlay = "";
            if (id === "remove") Shares.remove(Shares.removeName);
        }
    }
}
