// NetworkItem.qml - top bar: network status icon, opens the network flyout.
import QtQuick
import "../.."
import ".."

BarButton {
    id: net
    readonly property bool airplane: SysState.netKind === "off" && SysState.wifiDev !== null && !SysState.wifiEnabled
    readonly property int wifiLevel: SysState.netStrength <= 0 ? 1 : Math.max(1, Math.min(3, Math.ceil(SysState.netStrength * 3 - 0.1)))
    name: "Network: " + (SysState.netKind === "wifi" ? "Wi-Fi " + SysState.netName : (SysState.netKind === "eth" ? "Ethernet" : (airplane ? "Airplane mode" : "Offline")))
    tip: {
        const ip = SysState.netIp !== "" ? SysState.netIp : "NO ADDRESS";
        if (SysState.netKind === "wifi") return "WI-FI  " + SysState.netName + "\nIP " + ip + "  SIGNAL " + Math.round(SysState.netStrength * 100) + "%";
        if (SysState.netKind === "eth") return "ETHERNET  " + (SysState.ethName || "WIRED") + "\nIP " + ip;
        return airplane ? "AIRPLANE MODE\nWI-FI RADIO OFF" : "OFFLINE\nNO NETWORK";
    }
    fly: "network"
    width: 32
    onClicked: openFly("network")
    StatusIcon {
        anchors.centerIn: parent
        kind: SysState.netKind === "eth" ? "eth" : (net.airplane ? "airplane" : "wifi")
        size: Theme.icon.md
        on: SysState.netKind !== "off"
        level: net.wifiLevel
        tone: SysState.netKind === "off" ? Theme.dim : Theme.fg
    }
}
