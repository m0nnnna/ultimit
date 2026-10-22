// AddRuleDialog.qml - modal "Add rule" card: port(s), protocol, who may connect, a name.
// The port is checked by `firewall.py check-allow` (debounced) and the message shown inline.
import QtQuick
import "../.."
import "../games"

Item {
    id: root
    signal closed()

    property string proto: "tcp"            // tcp | udp | any
    property string from: "lan"             // lan | any | custom
    property string portErr: ""
    property string failure: ""
    property bool checking: false

    readonly property string port: portField.text.trim()
    readonly property string source: from === "custom" ? srcField.text.trim() : from
    readonly property bool valid: port !== "" && portErr === "" && !checking && source !== "" && Firewall.busy === ""
                                  && (from !== "lan" || Firewall.subnet !== "")

    function open(prefill) {
        portField.text = prefill ? prefill.port : ""; nameField.text = ""; srcField.text = "";
        proto = prefill ? prefill.proto : "tcp"; from = "lan"; portErr = ""; failure = ""; checking = false;
        visible = true;
        if (port !== "") recheck();
        portField.input.forceActiveFocus();
    }
    function close() { visible = false; closed(); }

    function recheck() {
        failure = "";
        if (port === "") { portErr = ""; checking = false; return; }
        checking = true;
        const seq = ++checkSeq;
        Firewall.checkAllow(port, proto, o => {
            if (seq !== root.checkSeq) return;
            root.checking = false;
            root.portErr = o.error || "";
        });
    }
    property int checkSeq: 0
    Timer { id: debounce; interval: 220; onTriggered: root.recheck() }

    function submit() {
        if (!visible || !valid) return;
        Firewall.allow(port, proto, source, nameField.text.trim(), o => {
            if (o.ok) root.close();
            else if (!o.cancelled) root.failure = o.error || "Could not add the rule.";
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
        anchors.centerIn: parent
        width: Math.min(500, parent.width - 32)
        height: Math.min(col.implicitHeight + 40, parent.height - 24)
        color: Theme.bg1
        border.color: Theme.lineStrong
        border.width: 1
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
                    GLabel { text: "Allow a port"; strong: true }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Port" }
                    GInput {
                        id: portField
                        width: parent.width
                        placeholder: "25565, 27031-27036 or 80,443"
                        onEdited: { root.checking = true; debounce.restart(); }
                        onAccepted: root.submit()
                        onEscaped: root.close()
                    }
                    Text {
                        visible: root.portErr !== ""
                        width: parent.width; wrapMode: Text.WordWrap
                        color: Theme.bad; font.family: Theme.ui; font.pixelSize: 11
                        text: root.portErr
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Protocol" }
                    GSeg {
                        options: [{ id: "tcp", label: "TCP" }, { id: "udp", label: "UDP" }, { id: "any", label: "Both" }]
                        current: root.proto
                        onPicked: id => { root.proto = id; root.recheck(); }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
                        text: "Not sure? The app's help page usually says. Tracking data from phones is mostly UDP."
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Who can connect" }
                    GSeg {
                        options: [{ id: "lan", label: Config.mobile ? "Home" : "Home network", disabled: Firewall.subnet === "" },
                                  { id: "custom", label: Config.mobile ? "One device" : "One device or network" }, { id: "any", label: "Anyone" }]
                        current: root.from
                        onPicked: id => { root.from = id; if (id === "custom") srcField.input.forceActiveFocus(); }
                    }
                    GInput {
                        id: srcField
                        visible: root.from === "custom"
                        width: parent.width
                        placeholder: "192.168.1.50 or 192.168.1.0/24"
                        onAccepted: root.submit()
                        onEscaped: root.close()
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        color: root.from === "any" ? Theme.warn : Theme.dim
                        font.family: Theme.ui; font.pixelSize: 11
                        text: root.from === "lan" ? "Devices on " + (Firewall.subnet || "your home network") + " only. Right for phones, consoles and other PCs at home."
                            : root.from === "any" ? "Anyone who can reach this PC, including from the internet if your router forwards the port. Only use this when you need it."
                            : "Only that address (a phone, say) or that network can connect."
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Name (optional)" }
                    GInput {
                        id: nameField
                        width: parent.width
                        placeholder: "what this is for, e.g. Warudo tracking"
                        onAccepted: root.submit()
                        onEscaped: root.close()
                    }
                }

                Text {
                    visible: root.failure !== ""
                    width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.bad; font.family: Theme.ui; font.pixelSize: 12
                    text: root.failure
                }

                Row {
                    spacing: 10
                    anchors.right: parent.right
                    GButton { text: "Cancel"; onClicked: root.close() }
                    GButton { primary: true; text: Firewall.busy === "allow" ? "Working…" : "Allow"; enabled: root.valid; onClicked: root.submit() }
                }
            }
        }
    }
}
