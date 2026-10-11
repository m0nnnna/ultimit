// BatteryFlyout.qml - tray battery flyout: charge, state, time to empty / full, power-profile chips
// (power-profiles-daemon, SysState.setProfile, same as Settings > Power), screen brightness slider
// when a backlight exists (SysState.setBrightness), "Power settings…".
import QtQuick
import "../.."
import ".."
import "../../apps/accessory"
import "../../apps/settings"

Column {
    id: root
    spacing: 10

    Component.onCompleted: { SysState.refreshProfiles(); SysState.refreshBrightness(); }
    Timer { interval: 2000; repeat: true; running: true; onTriggered: { SysState.refreshBrightness(); SysState.profGetTick(); } }

    readonly property color tone: SysState.full ? Theme.ok
        : (SysState.battPct < 10 ? Theme.bad : (SysState.battPct < 20 && !SysState.charging ? Theme.warn : Theme.fg))

    FlyHead { text: "Battery"; detail: SysState.hasBattery ? SysState.battState : "" }

    Row {
        visible: SysState.hasBattery
        spacing: 14
        StatusIcon { anchors.verticalCenter: parent.verticalCenter; kind: "battery"; size: 40; pct: SysState.battPct; tone: root.tone }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Row {
                spacing: 8
                Text {
                    text: SysState.battPct; color: root.tone
                    font.family: Theme.display; font.pixelSize: 26
                }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: "%"; color: root.tone
                    font.family: Theme.mono; font.pixelSize: 16
                }
                StatusIcon { visible: SysState.charging; anchors.verticalCenter: parent.verticalCenter; kind: "bolt"; size: 18; tone: Theme.ok }
            }
            Text {
                text: SysState.battState + (SysState.battTime !== "" ? "  ·  " + SysState.battTime + (SysState.charging ? " TO FULL" : " TO EMPTY") : "")
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.4
            }
        }
    }
    Text {
        visible: !SysState.hasBattery
        text: "No battery detected."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
    }

    FlyHead { visible: SysState.profileChoices.length > 0; text: "Power profile" }
    Chips {
        visible: SysState.profileChoices.length > 0
        width: parent.width
        options: SysState.profileChoices.map(p => ({ id: p, label: p === "power-saver" ? "Power saver" : p }))
        current: SysState.profile
        onPicked: id => SysState.setProfile(id)
    }

    FlyHead { visible: SysState.hasBacklight; text: "Brightness" }
    FlySlider {
        visible: SysState.hasBacklight
        width: parent.width
        icon: "sun"
        muteable: false
        from: 1
        value: SysState.blPct
        onMoved: v => SysState.setBrightness(v)
    }

    ChamferButton {
        width: parent.width
        text: "Power settings…"
        onClicked: { FlyoutState.close(); Config.openSettings("power"); }
    }
}
