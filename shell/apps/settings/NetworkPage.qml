// Network: Wi-Fi on/off, networks (connect with password prompt / forget), connection details, wired,
// VPNs (VpnSection.qml).
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../.."
import "../accessory"
import "../../components"

Page {
    id: pg
    title: "Network"
    property string pwFor: ""
    property var devs: []     // [{ dev, type, state, conn, hw, ip, gw, dns }]

    // keep the list stable while a password is being typed
    Binding { target: SysState; property: "netFreeze"; value: pg.pwFor !== "" }
    Component.onCompleted: {
        SysState._netKey = ""; SysState.refreshNets(); details.go();
        if (SysState.wifiDev && !SetSys.dryRun) SysState.wifiDev.scannerEnabled = true;
    }
    Component.onDestruction: {
        if (SysState.wifiDev && !SetSys.dryRun) SysState.wifiDev.scannerEnabled = false;
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: details.go() }

    Cmd {
        id: details
        argv: ["nmcli", "-t", "-f", "GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show"]
        onDone: out => {
            const list = []; let cur = null;
            for (const line of out.split("\n")) {
                const i = line.indexOf(":"); if (i < 0) continue;
                const k = line.slice(0, i).replace(/\[\d+\]$/, ""), v = line.slice(i + 1).replace(/\\:/g, ":");
                if (k === "GENERAL.DEVICE") { cur = { dev: v, type: "", state: "", conn: "", hw: "", ip: [], gw: "", dns: [] }; list.push(cur); }
                else if (!cur) continue;
                else if (k === "GENERAL.TYPE") cur.type = v;
                else if (k === "GENERAL.STATE") cur.state = v;
                else if (k === "GENERAL.CONNECTION") cur.conn = v === "--" ? "" : v;
                else if (k === "GENERAL.HWADDR") cur.hw = v;
                else if (k === "IP4.ADDRESS") cur.ip.push(v);
                else if (k === "IP4.GATEWAY") cur.gw = v;
                else if (k === "IP4.DNS") cur.dns.push(v);
            }
            pg.devs = list.filter(d => d.type === "wifi" || d.type === "ethernet");
        }
    }

    SectionLabel { text: "Wi-Fi" }
    ToggleRow {
        Layout.fillWidth: true
        visible: SysState.wifiDev !== null || SysState.wifiEnabled
        text: "Wi-Fi"
        checked: SysState.wifiEnabled
        onToggled: v => SysState.setWifiEnabled(v)
    }
    Text {
        visible: SysState.wifiDev === null && !SysState.wifiEnabled
        text: "No Wi-Fi adapter."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
    }

    ColumnLayout {
        visible: SysState.wifiEnabled
        Layout.fillWidth: true; spacing: 0
        Repeater {
            model: SysState.netList
            delegate: ColumnLayout {
                id: nrow
                required property var modelData
                readonly property bool connected: modelData.connected
                readonly property bool busy: SysState.netBusy === modelData.name || modelData.stateChanging
                readonly property bool secured: SysState.isSecured(modelData)
                Layout.fillWidth: true; spacing: 0

                ItemRow {
                    title: nrow.modelData.name
                    titleColor: nrow.connected ? Theme.ok : Theme.fg
                    subtitle: Math.round(nrow.modelData.signalStrength * 100) + "% signal" + (nrow.secured ? "  ·  secured" : "  ·  open")
                    badge: nrow.busy ? "connecting" : (nrow.connected ? "connected" : (nrow.modelData.known ? "saved" : ""))
                    badgeColor: nrow.busy ? Theme.warn : (nrow.connected ? Theme.ok : Theme.dim)
                    selected: nrow.connected
                    ChamferButton {
                        visible: nrow.modelData.known && !nrow.connected
                        text: "Forget"
                        onClicked: SysState.forgetWifi(nrow.modelData)
                    }
                    ChamferButton {
                        primary: !nrow.connected
                        text: nrow.connected ? "Disconnect" : "Connect"
                        onClicked: {
                            if (nrow.connected) { pg.pwFor = ""; SysState.disconnectWifi(); }
                            else if (nrow.secured && !nrow.modelData.known) { pg.pwFor = nrow.modelData.name; pw.text = ""; pw.focusEntry(); }
                            else { pg.pwFor = ""; SysState.connectWifi(nrow.modelData.name, ""); }
                        }
                    }
                }
                RowLayout {
                    visible: pg.pwFor === nrow.modelData.name
                    Layout.fillWidth: true; Layout.margins: 8; spacing: 8
                    TextEntry {
                        id: pw
                        Layout.fillWidth: true
                        secret: true; placeholder: "Password for " + nrow.modelData.name
                        onAccepted: if (text !== "") { SysState.connectWifi(nrow.modelData.name, text); pg.pwFor = ""; text = ""; }
                    }
                    ChamferButton { text: "Cancel"; onClicked: { pg.pwFor = ""; pw.text = ""; } }
                    ChamferButton {
                        primary: true; text: "Join"
                        onClicked: if (pw.text !== "") { SysState.connectWifi(nrow.modelData.name, pw.text); pg.pwFor = ""; pw.text = ""; }
                    }
                }
            }
        }
        Text {
            visible: SysState.netList.length === 0
            text: "Scanning for networks…"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }
    }

    SectionLabel { text: "Connections" }
    Repeater {
        model: pg.devs
        delegate: ColumnLayout {
            id: dv
            required property var modelData
            Layout.fillWidth: true; spacing: 0
            readonly property bool up: modelData.state.indexOf("(connected)") >= 0
            readonly property string kind: modelData.type === "wifi" ? "Wi-Fi" : "Wired"
            InfoRow {
                Layout.fillWidth: true
                label: dv.kind + " (" + dv.modelData.dev + ")"
                value: dv.up ? (dv.modelData.conn || "connected") : dv.modelData.state.replace(/^\d+ /, "").replace(/[()]/g, "")
                valueColor: dv.up ? Theme.ok : Theme.dim
            }
            InfoRow { visible: dv.up; Layout.fillWidth: true; label: "IP address"; value: dv.modelData.ip.join(", ") }
            InfoRow { visible: dv.up && dv.modelData.gw !== ""; Layout.fillWidth: true; label: "Gateway"; value: dv.modelData.gw }
            InfoRow { visible: dv.up && dv.modelData.dns.length > 0; Layout.fillWidth: true; label: "DNS"; value: dv.modelData.dns.join(", ") }
            InfoRow { visible: dv.modelData.hw !== ""; Layout.fillWidth: true; label: "MAC address"; value: dv.modelData.hw }
        }
    }

    VpnSection {}
}
