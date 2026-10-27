// Bluetooth: on/off, discovery, pair / connect / disconnect / forget.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"
import "../../components"

Page {
    id: pg
    title: "Bluetooth"
    readonly property var ad: SysState.btAdapter
    property bool startedScan: false

    // Paired/connected first, then by name; the list only reorders when the set changes.
    readonly property var devices: {
        if (!ad) return [];
        const v = ad.devices.values.filter(d => d.name !== "").slice();
        v.sort((a, b) => ((b.connected - a.connected) || ((b.paired || b.bonded) - (a.paired || a.bonded)) || a.name.localeCompare(b.name)));
        return v;
    }
    function setScan(on) {
        if (!ad) return;
        if (SetSys.dryRun) { SetSys.note("Bluetooth adapter discovering = " + on); return; }
        ad.discovering = on;
        startedScan = on;
    }
    Component.onDestruction: if (startedScan && ad) ad.discovering = false
    // "Add device..." in the Bluetooth flyout asks for a scan (Config.btScanRequest)
    function consumeScanRequest() {
        if (!Config.btScanRequest) return;
        Config.btScanRequest = false;
        if (SysState.btOn) setScan(true);
    }
    Component.onCompleted: consumeScanRequest()
    Connections { target: Config; function onBtScanRequestChanged() { pg.consumeScanRequest(); } }

    SectionLabel { text: "Adapter" }
    Text {
        visible: !SysState.btAvailable
        text: "No Bluetooth adapter found."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
    }
    ToggleRow {
        visible: SysState.btAvailable
        Layout.fillWidth: true
        text: "Bluetooth"
        checked: SysState.btOn
        onToggled: v => SysState.setBtEnabled(v)
    }
    InfoRow { visible: pg.ad !== null; Layout.fillWidth: true; label: "Adapter"; value: pg.ad ? pg.ad.name : "" }

    RowLayout {
        visible: SysState.btOn
        Layout.fillWidth: true
        SectionLabel { text: "Devices" }
        Item { Layout.fillWidth: true }
        Text {
            visible: pg.ad && pg.ad.discovering
            text: "SCANNING…"; color: Theme.warn   // status chip
            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.8
        }
        ChamferButton {
            text: pg.ad && pg.ad.discovering ? "Stop scan" : "Scan"
            primary: !(pg.ad && pg.ad.discovering)
            onClicked: pg.setScan(!(pg.ad && pg.ad.discovering))
        }
    }
    ColumnLayout {
        visible: SysState.btOn
        Layout.fillWidth: true; spacing: 0
        Repeater {
            model: pg.devices
            delegate: ItemRow {
                id: dr
                required property var modelData
                readonly property bool isPaired: modelData.paired || modelData.bonded
                title: modelData.name
                subtitle: modelData.address + (modelData.batteryAvailable ? "  ·  battery " + Math.round(modelData.battery * 100) + "%" : "")
                selected: modelData.connected
                badge: modelData.pairing ? "pairing" : (modelData.connected ? "connected" : (isPaired ? "paired" : ""))
                badgeColor: modelData.connected ? Theme.ok : (modelData.pairing ? Theme.warn : Theme.dim)
                ChamferButton {
                    visible: dr.isPaired
                    text: "Forget"
                    onClicked: { if (SetSys.dryRun) SetSys.note("BluetoothDevice(" + dr.modelData.name + ").forget()"); else dr.modelData.forget(); }
                }
                ChamferButton {
                    primary: !dr.modelData.connected
                    text: !dr.isPaired ? "Pair" : (dr.modelData.connected ? "Disconnect" : "Connect")
                    onClicked: {
                        const d = dr.modelData;
                        if (!dr.isPaired) {
                            if (SetSys.dryRun) SetSys.note("BluetoothDevice(" + d.name + ").pair()"); else d.pair();
                        } else SysState.btToggleDevice(d);
                    }
                }
            }
        }
        Text {
            visible: pg.devices.length === 0
            text: "No devices yet. Press Scan to look for nearby devices."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
        }
    }
}
