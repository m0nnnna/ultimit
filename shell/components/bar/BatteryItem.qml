// BatteryItem.qml - top bar: battery icon and percentage (only with a battery), opens the battery flyout.
import QtQuick
import "../.."
import ".."

BarButton {
    id: bb
    readonly property color battTone: SysState.full ? Theme.ok
        : (SysState.battPct < 10 ? Theme.bad : (SysState.battPct < 20 && !SysState.charging ? Theme.warn : Theme.fg))
    visible: SysState.hasBattery
    name: "Battery: " + SysState.battPct + " percent" + (SysState.charging ? ", charging" : "")
    tip: {
        let t = "BATTERY " + SysState.battPct + "%  " + SysState.battState;
        if (SysState.battTime !== "") t += "\n" + SysState.battTime + (SysState.charging ? " UNTIL FULL" : " REMAINING");
        if (SysState.profile !== "") t += "\nPOWER PROFILE  " + SysState.profile.toUpperCase();
        return t;
    }
    width: visible ? batt.width + 16 : 0
    fly: "battery"
    onHovered: SysState.refreshProfiles()
    onClicked: openFly("battery")
    Row {
        id: batt
        anchors.centerIn: parent
        spacing: 4
        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            kind: "battery"
            size: Theme.icon.md
            pct: SysState.battPct
            tone: bb.battTone
        }
        StatusIcon {
            visible: SysState.charging
            anchors.verticalCenter: parent.verticalCenter
            kind: "bolt"
            size: Theme.icon.sm
            tone: Theme.ok
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: SysState.battPct + "%"
            color: bb.battTone
            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
        }
    }
}
