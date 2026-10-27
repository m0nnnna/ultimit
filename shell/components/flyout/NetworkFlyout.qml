// NetworkFlyout.qml - tray network flyout: Wi-Fi switch, the current connection (signal, IP),
// scrollable list of visible networks with an inline password field, VPNs, Ethernet, airplane mode.
// Logic is SysState's (the same netList / connectWifi / disconnectWifi / forgetWifi as Settings >
// Network); the password goes to nmcli on stdin, never argv. ULTIMIT_DRY_RUN=1 logs instead of acting.
import QtQuick
import Quickshell.Networking
import "../.."
import ".."
import "../../apps/accessory"
import "../../apps/settings"

Column {
    id: root
    spacing: Theme.space(3)

    property string pwFor: ""
    function handleEscape() {
        if (pwFor !== "") { pwFor = ""; return true; }
        return false;
    }

    readonly property bool wifiOn: SysState.wifiEnabled
    readonly property var others: SysState.netList.filter(n => !n.connected)

    // keep the list stable while a password is being typed; scan only while on screen
    Binding { target: SysState; property: "netFreeze"; value: root.pwFor !== "" }
    Binding {
        target: SysState.wifiDev; property: "scannerEnabled"
        value: Networking.wifiEnabled
        when: SysState.wifiDev !== null && !SysState.dryRun
    }
    Component.onCompleted: { SysState._netKey = ""; SysState.refreshNets(); SysState.refreshIp(); SysState.refreshVpn(); }

    FlyHead { text: "Network"; detail: SysState.airplaneOn ? "Airplane mode" : "" ; detailColor: Theme.warn }

    ToggleRow {
        width: parent.width
        visible: SysState.wifiDev !== null || SysState.wifiEnabled
        text: "Wi-Fi"
        checked: SysState.wifiEnabled
        onToggled: v => SysState.setWifiEnabled(v)
    }

    // ---- current connection ----
    Rectangle {
        id: cur
        width: parent.width
        height: curCol.implicitHeight + Theme.space(6)
        color: Theme.field
        Rectangle { width: 2; height: parent.height; color: SysState.netKind === "off" ? Theme.dim : Theme.ok }
        Column {
            id: curCol
            x: Theme.space(4); y: Theme.space(3); width: parent.width - Theme.space(8)
            spacing: 8
            Row {
                spacing: 8
                SignalBars {
                    visible: SysState.netKind === "wifi"
                    anchors.verticalCenter: parent.verticalCenter
                    level: SysState.netStrength; color: Theme.ok
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysState.netKind === "wifi" ? SysState.netName
                        : (SysState.netKind === "eth" ? "Ethernet" : (SysState.airplaneOn ? "Airplane mode" : "Not connected"))
                    color: SysState.netKind === "off" ? Theme.dim : Theme.fg
                    font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.body
                    width: Math.min(implicitWidth, curCol.width - 40); elide: Text.ElideRight
                }
            }
            Text {
                visible: SysState.netKind !== "off"
                text: (SysState.netKind === "wifi" ? "SIGNAL " + Math.round(SysState.netStrength * 100) + "%   " : "")
                      + "IP " + (SysState.netIp !== "" ? SysState.netIp : "—")
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.2
            }
            Row {
                visible: SysState.netKind === "wifi"
                spacing: 8
                FlyBtn { text: "Disconnect"; onClicked: { root.pwFor = ""; SysState.disconnectWifi(); } }
                FlyBtn {
                    visible: SysState.activeWifi !== null && SysState.activeWifi.known
                    text: "Forget"
                    onClicked: SysState.forgetWifi(SysState.activeWifi)
                }
            }
        }
    }

    // ---- visible networks ----
    FlyHead {
        visible: root.wifiOn && SysState.wifiDev !== null
        text: "Networks"
        detail: root.others.length > 0 ? root.others.length + " in range" : ""
    }
    Flickable {
        id: netFlick
        visible: root.wifiOn && SysState.wifiDev !== null
        width: parent.width
        height: Math.min(netCol.implicitHeight, 176)
        contentWidth: width; contentHeight: netCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: netCol
            width: netFlick.width
            Repeater {
                model: root.others
                delegate: Column {
                    id: nrow
                    required property var modelData
                    readonly property bool secured: SysState.isSecured(modelData)
                    readonly property bool busy: modelData.stateChanging || SysState.netBusy === modelData.name
                    width: netCol.width
                    FlyRow {
                        title: nrow.modelData.name
                        subtitle: Math.round(nrow.modelData.signalStrength * 100) + "%" + (nrow.modelData.known ? "  ·  saved" : "")
                        badge: nrow.busy ? "connecting" : ""
                        badgeColor: Theme.warn
                        hoverable: false
                        leading: [
                            SignalBars { anchors.verticalCenter: parent.verticalCenter; level: nrow.modelData.signalStrength },
                            FlyLock { opacity: nrow.secured ? 1 : 0; anchors.verticalCenter: parent.verticalCenter }
                        ]
                        FlyBtn {
                            visible: nrow.modelData.known
                            text: "Forget"
                            onClicked: SysState.forgetWifi(nrow.modelData)
                        }
                        FlyBtn {
                            primary: true
                            text: "Connect"
                            onClicked: {
                                if (nrow.secured && !nrow.modelData.known) root.pwFor = nrow.modelData.name;
                                else { root.pwFor = ""; SysState.connectWifi(nrow.modelData.name, ""); }
                            }
                        }
                    }
                    Row {   // inline password
                        visible: root.pwFor === nrow.modelData.name
                        width: parent.width; height: visible ? 44 : 0
                        spacing: 8
                        onVisibleChanged: { if (visible) pw.focusEntry(); else pw.text = ""; }
                        TextEntry {
                            id: pw
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - joinBtn.width - cancelBtn.width - 12
                            implicitHeight: 30
                            secret: true; placeholder: "Password for " + nrow.modelData.name
                            onAccepted: root.join(nrow.modelData.name, pw.text)
                        }
                        FlyBtn { id: cancelBtn; anchors.verticalCenter: parent.verticalCenter; text: "Cancel"; onClicked: root.pwFor = "" }
                        FlyBtn { id: joinBtn; anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Join"; onClicked: root.join(nrow.modelData.name, pw.text) }
                    }
                }
            }
            Text {
                visible: root.others.length === 0
                height: visible ? 36 : 0
                verticalAlignment: Text.AlignVCenter
                text: SysState.netList.length === 0 ? "Scanning for networks…" : "No other networks in range."
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
            }
        }
    }
    function join(ssid, password) {
        if (password === "") return;
        SysState.connectWifi(ssid, password);
        pwFor = "";
    }

    // ---- Ethernet ----
    FlyRow {
        visible: SysState.ethPresent
        title: "Ethernet"
        subtitle: SysState.ethConnected ? "CONNECTED" + (SysState.ethName !== "" ? "  ·  " + SysState.ethName : "") : "CABLE UNPLUGGED"
        hoverable: false
        titleColor: SysState.ethConnected ? Theme.ok : Theme.dim
        leading: [ StatusIcon { anchors.verticalCenter: parent.verticalCenter; kind: "eth"; size: Theme.icon.md; tone: SysState.ethConnected ? Theme.ok : Theme.dim } ]
    }

    // ---- VPN ----
    FlyHead { visible: SysState.vpnList.length > 0; text: "VPN" }
    Column {
        visible: SysState.vpnList.length > 0
        width: parent.width
        Repeater {
            model: SysState.vpnList
            delegate: FlyRow {
                required property var modelData
                title: modelData.name
                badge: modelData.active ? "connected" : modelData.type
                badgeColor: modelData.active ? Theme.ok : Theme.dim
                selected: modelData.active
                hoverable: false
                FlyBtn {
                    primary: !modelData.active
                    text: modelData.active ? "Disconnect" : "Connect"
                    onClicked: SysState.setVpn(modelData, !modelData.active)
                }
            }
        }
    }

    ToggleRow {
        width: parent.width
        text: "Airplane mode"
        checked: SysState.airplaneOn
        onToggled: v => SysState.setAirplane(v)
    }
    ChamferButton {
        width: parent.width
        text: "Network settings…"
        onClicked: { FlyoutState.close(); Config.openSettings("network"); }
    }
}
