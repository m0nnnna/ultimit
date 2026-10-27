// BluetoothFlyout.qml - tray Bluetooth flyout: adapter switch, paired devices (connect / disconnect,
// battery when exposed), "Add device…" (Settings > Bluetooth, scanning) and "Bluetooth settings…".
import QtQuick
import "../.."
import ".."
import "../../apps/accessory"

Column {
    id: root
    spacing: Theme.space(3)

    FlyHead { text: "Bluetooth"; detail: SysState.btAdapter ? SysState.btAdapter.name : ""; }

    Text {
        visible: !SysState.btAvailable
        text: "No Bluetooth adapter found."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
    }
    ToggleRow {
        width: parent.width
        visible: SysState.btAvailable
        text: "Bluetooth"
        checked: SysState.btOn
        onToggled: v => SysState.setBtEnabled(v)
    }

    FlyHead { visible: SysState.btOn; text: "Paired devices"; detail: SysState.btConnectedCount > 0 ? SysState.btConnectedCount + " connected" : "" }
    Flickable {
        visible: SysState.btOn
        width: parent.width
        height: Math.min(devCol.implicitHeight, 280)
        contentWidth: width; contentHeight: devCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: devCol
            width: parent.width
            Repeater {
                model: SysState.btShown
                delegate: FlyRow {
                    id: dr
                    required property var modelData
                    title: modelData.name || modelData.address
                    subtitle: modelData.address
                    selected: modelData.connected
                    badge: modelData.pairing ? "pairing" : (modelData.connected ? "connected" : "")
                    badgeColor: modelData.connected ? Theme.ok : Theme.warn
                    hoverable: false
                    // battery level when the device exposes it
                    Text {
                        visible: dr.modelData.batteryAvailable
                        anchors.verticalCenter: parent.verticalCenter
                        text: "BAT " + Math.round(dr.modelData.battery * 100) + "%"
                        color: dr.modelData.battery < 0.2 ? Theme.warn : Theme.dim
                        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.2
                    }
                    FlyBtn {
                        primary: !dr.modelData.connected
                        text: dr.modelData.connected ? "Disconnect" : "Connect"
                        onClicked: SysState.btToggleDevice(dr.modelData)
                    }
                }
            }
            Text {
                visible: SysState.btShown.length === 0
                height: visible ? 36 : 0; verticalAlignment: Text.AlignVCenter
                text: "No paired devices."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
            }
        }
    }

    Row {
        width: parent.width
        spacing: 8
        ChamferButton {
            visible: SysState.btAvailable
            width: (parent.width - 8) / 2
            primary: true
            text: "Add device…"
            onClicked: { FlyoutState.close(); Config.openBluetoothAdd(); }
        }
        ChamferButton {
            width: SysState.btAvailable ? (parent.width - 8) / 2 : parent.width
            text: "Bluetooth settings…"
            onClicked: { FlyoutState.close(); Config.openSettings("bluetooth"); }
        }
    }
}
