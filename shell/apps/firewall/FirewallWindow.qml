// FirewallWindow.qml - the FIREWALL window: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Header with on/off and status chips, a setup banner while something is missing, then three tabs:
// APPS (ready-made rules), BLOCKED (what the firewall recently turned away) and RULES (every ufw rule).
import QtQuick
import QtQuick.Controls
import Quickshell
import "../.."
import "../games"
import "../shares"

FloatingWindow {
    id: win
    title: "FIREWALL"
    visible: Firewall.open
    implicitWidth: 900
    implicitHeight: 680
    minimumSize: Config.mobile ? Qt.size(0, 0) : Qt.size(680, 480)
    color: "transparent"   // the Theme.panel glass below fills it

    onVisibleChanged: if (visible !== Firewall.open) Firewall.open = visible
    Connections {
        target: Firewall
        function onOverlayChanged() {
            if (Firewall.overlay === "add") addDlg.open(Firewall.addPrefill);
            else if (Firewall.overlay === "remove") rmDlg.visible = true;
            else if (Firewall.overlay === "disable") offDlg.visible = true;
            else { addDlg.visible = false; rmDlg.visible = false; offDlg.visible = false; }
        }
    }
    Component.onCompleted: Firewall.refresh()

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        // ---------------- header ----------------
        Item {
            id: header
            // The window title itself is in the compositor's titlebar.
            x: 20; y: 10
            width: parent.width - 40
            height: Config.mobile && Firewall.ready ? 78 : 36
            GLabel {
                anchors { left: parent.left; verticalCenter: Config.mobile && Firewall.ready ? undefined : parent.verticalCenter; top: Config.mobile && Firewall.ready ? parent.top : undefined; topMargin: 10 }
                text: "Who can reach this PC"
            }
            Row {
                anchors { right: parent.right; verticalCenter: Config.mobile && Firewall.ready ? undefined : parent.verticalCenter; bottom: Config.mobile && Firewall.ready ? parent.bottom : undefined }
                spacing: 10
                GButton {
                    visible: Firewall.ready && Firewall.tab === "rules"
                    text: "Add rule…"
                    enabled: Firewall.busy === ""
                    onClicked: { Firewall.addPrefill = null; Firewall.overlay = "add"; }
                }
                GButton {
                    visible: Firewall.ready
                    primary: !Firewall.active
                    enabled: Firewall.busy === ""
                    text: Firewall.busy === "enable" || Firewall.busy === "disable" ? "Working…" : Firewall.active ? "Turn off" : "Turn on"
                    onClicked: Firewall.active ? (Firewall.overlay = "disable") : Firewall.setEnabled(true)
                }
            }
        }

        // ---------------- status chips ----------------
        Flow {
            id: chips
            x: 20; anchors.top: header.bottom; anchors.topMargin: 6
            width: parent.width - 40
            spacing: 8
            visible: Firewall.ready
            GChip {
                text: Firewall.active ? "✓ Firewall on" : "✕ Firewall off"
                tone: Firewall.active ? Theme.ok : Theme.bad
            }
            GChip {
                visible: Firewall.active
                text: Firewall.st.ufw && Firewall.st.ufw.incoming === "allow" ? "Incoming: everything allowed" : "Incoming: blocked unless allowed"
                tone: Firewall.st.ufw && Firewall.st.ufw.incoming === "allow" ? Theme.warn : Theme.dim
            }
            GChip {
                text: Firewall.subnet !== "" ? "Home network " + Firewall.subnet : "No home network found"
                tone: Firewall.subnet !== "" ? Theme.dim : Theme.warn
            }
            GChip { visible: Firewall.logNote !== ""; text: "Not logging blocks"; tone: Theme.warn }
        }

        // ---------------- setup / off banners ----------------
        Column {
            id: banners
            x: 20; anchors.top: chips.visible ? chips.bottom : header.bottom; anchors.topMargin: 12
            width: parent.width - 40
            spacing: 10
            SetupBanner { width: parent.width }
            Rectangle {
                visible: Firewall.ready && !Firewall.active
                width: parent.width
                implicitHeight: offTxt.implicitHeight + 24
                color: Theme.panel2
                border.color: Theme.warn
                border.width: 1
                Text {
                    id: offTxt
                    x: 16; y: 12
                    width: parent.width - 32
                    wrapMode: Text.WordWrap
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                    text: "The firewall is off: any device that can reach this PC can connect to every program listening here. Turn it on, then allow what you use below. Your rules are kept while it is off."
                }
            }
        }

        // ---------------- tabs ----------------
        Item {
            id: tabBar
            x: 20; anchors.top: banners.bottom; anchors.topMargin: 8
            width: parent.width - 40
            height: 32
            visible: Firewall.ready
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            Row {
                spacing: 4
                Repeater {
                    model: [{ id: "apps", label: "Apps" },
                            { id: "blocked", label: "Blocked" + (Firewall.blockedOpen > 0 ? " · " + Firewall.blockedOpen : "") },
                            { id: "rules", label: "Rules · " + Firewall.rules.length }]
                    delegate: Item {
                        id: tb
                        required property var modelData
                        readonly property bool on: Firewall.tab === modelData.id
                        width: tl.implicitWidth + 36; height: 32
                        Text {
                            id: tl
                            anchors.centerIn: parent
                            text: tb.modelData.label.toUpperCase()
                            color: tb.on ? Theme.accent : (tm.containsMouse ? Theme.fg
                                   : tb.modelData.id === "blocked" && Firewall.blockedOpen > 0 ? Theme.warn : Theme.dim)
                            font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.8
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent; visible: tb.on }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Firewall.tab = tb.modelData.id }
                    }
                }
            }
        }

        // ---------------- message line ----------------
        Text {
            id: noteLine
            x: 20; anchors.top: tabBar.bottom; anchors.topMargin: 8
            width: parent.width - 40
            height: Firewall.note !== "" ? 16 : 0
            elide: Text.ElideRight
            text: Firewall.note
            color: Firewall.noteKind === "error" ? Theme.bad : Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
            visible: Firewall.note !== ""
        }

        // ---------------- tab content ----------------
        Flickable {
            id: scroller
            visible: Firewall.ready
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
                spacing: 10

                // ---- APPS ----
                Text {
                    visible: Firewall.tab === "apps"
                    width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                    text: "Switch on what you use. Each one opens only its own ports, and only to devices on your home network."
                }
                Repeater {
                    model: Firewall.tab === "apps" ? Firewall.groups : []
                    delegate: Column {
                        id: grp
                        required property string modelData
                        width: body.width
                        spacing: 8
                        topPadding: 6
                        Item {
                            width: parent.width; height: 18
                            Rectangle { id: gsq; width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                            GLabel { anchors { left: gsq.right; leftMargin: 8; verticalCenter: parent.verticalCenter } text: grp.modelData; strong: true }
                        }
                        Repeater {
                            model: Firewall.presets.filter(p => p.group === grp.modelData)
                            delegate: PresetRow {
                                required property var modelData
                                width: grp.width
                                preset: modelData
                            }
                        }
                    }
                }

                // ---- BLOCKED ----
                Text {
                    visible: Firewall.tab === "blocked"
                    width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                    text: "Connections the firewall turned away in the last 30 minutes. If a phone app or game can't connect to this PC, it is probably listed here."
                }
                Repeater {
                    model: Firewall.tab === "blocked" ? Firewall.blocked : []
                    delegate: BlockedRow {
                        required property var modelData
                        width: body.width
                        item: modelData
                    }
                }
                Column {
                    visible: Firewall.tab === "blocked" && Firewall.blocked.length === 0
                    width: parent.width
                    topPadding: 36
                    spacing: 10
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Nothing blocked recently"
                        color: Theme.fg
                        font.family: Theme.display; font.pixelSize: 16; font.letterSpacing: 0.5
                    }
                    Text {
                        width: Math.min(parent.width, 480)
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: Firewall.logNote !== "" ? Theme.warn : Theme.dim
                        font.family: Theme.ui; font.pixelSize: 13
                        text: Firewall.logNote !== "" ? Firewall.logNote
                            : !Firewall.active ? "The firewall is off, so nothing is blocked."
                            : "Try connecting from your phone or other device again; anything turned away shows up here within a few seconds."
                    }
                }

                // ---- RULES ----
                Repeater {
                    model: Firewall.tab === "rules" ? Firewall.rules : []
                    delegate: RuleRow {
                        required property var modelData
                        width: body.width
                        rule: modelData
                        onRemoveRequested: r => { Firewall.removeRule = r; Firewall.overlay = "remove"; }
                    }
                }
                Column {
                    visible: Firewall.tab === "rules" && Firewall.rules.length === 0
                    width: parent.width
                    topPadding: 36
                    spacing: 12
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No rules yet"
                        color: Theme.fg
                        font.family: Theme.display; font.pixelSize: 16; font.letterSpacing: 0.5
                    }
                    Text {
                        width: Math.min(parent.width, 460)
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Nothing from other devices can reach this PC. Switch on an app under APPS, or add a port yourself."
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: 13
                    }
                    GButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        primary: true; text: "Add rule…"
                        onClicked: { Firewall.addPrefill = null; Firewall.overlay = "add"; }
                    }
                }
            }
        }

        GLabel {
            anchors.centerIn: parent
            visible: !Firewall.loaded
            text: "Checking…"
        }
    }

    // ---------------- dialogs ----------------
    AddRuleDialog { id: addDlg; onClosed: if (Firewall.overlay === "add") Firewall.overlay = "" }
    SharesPrompt {
        id: rmDlg
        visible: false
        title: "Remove this rule?"
        message: Firewall.removeRule ? Firewall.removeRule.text + (Firewall.removeRule.comment !== "" ? " (" + Firewall.removeRule.comment + ")" : "")
                 + ".\n\nWhatever used it will not be able to connect any more." : ""
        buttons: [{ id: "cancel", text: "Cancel" }, { id: "remove", text: "Remove", primary: true }]
        onChosen: id => {
            visible = false;
            Firewall.overlay = "";
            if (id === "remove" && Firewall.removeRule) Firewall.remove(Firewall.removeRule.line);
        }
    }
    SharesPrompt {
        id: offDlg
        visible: false
        title: "Turn the firewall off?"
        message: "Every device that can reach this PC will be able to connect to any program listening on it. Your rules are kept for when you turn it back on."
        buttons: [{ id: "cancel", text: "Keep it on" }, { id: "off", text: "Turn off", primary: true }]
        onChosen: id => {
            visible = false;
            Firewall.overlay = "";
            if (id === "off") Firewall.setEnabled(false);
        }
    }
}
