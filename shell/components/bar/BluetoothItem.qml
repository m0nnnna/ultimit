// BluetoothItem.qml - top bar: Bluetooth icon (only with an adapter), opens the Bluetooth flyout.
import QtQuick
import "../.."
import ".."

BarButton {
    visible: SysState.btAvailable
    name: "Bluetooth: " + (!SysState.btOn ? "off" : (SysState.btConnectedCount > 0 ? SysState.btConnectedCount + " connected" : "on"))
    tip: !SysState.btOn ? "BLUETOOTH OFF"
        : (SysState.btConnectedCount > 0 ? "BLUETOOTH\n" + SysState.btConnectedNames.join("\n") : "BLUETOOTH ON\nNO DEVICES CONNECTED")
    fly: "bluetooth"
    width: visible ? 32 : 0
    onClicked: openFly("bluetooth")
    StatusIcon {
        anchors.centerIn: parent
        kind: "bt"
        size: Theme.icon.md
        state: !SysState.btOn ? "off" : (SysState.btConnectedCount > 0 ? "connected" : "on")
    }
}
