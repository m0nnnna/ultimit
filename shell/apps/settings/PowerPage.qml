// Power: battery details, power profile, idle timings (persisted in shell.json via Persist), lid info.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"
import "../../components"

Page {
    id: pg
    title: "Power"

    // seconds -> option list; keeps an out-of-list current value (e.g. an env override) selectable
    function opts(cur) {
        const mins = [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120];
        const out = mins.map(m => ({ id: String(m * 60), label: m === 0 ? "Never" : (m < 60 ? m + " min" : (m / 60) + " h") }));
        if (!out.some(o => o.id === String(Math.round(cur)))) out.push({ id: String(Math.round(cur)), label: Math.round(cur) + " s" });
        return out;
    }
    Component.onCompleted: { SysState.refreshProfiles(); lid.go(); }

    SectionLabel { text: "Battery"; visible: SysState.hasBattery }
    ColumnLayout {
        visible: SysState.hasBattery
        Layout.fillWidth: true
        spacing: 0
        InfoRow { Layout.fillWidth: true; label: "Charge"; value: SysState.battPct + "%  " + SysState.battState.toLowerCase() }
        InfoRow {
            Layout.fillWidth: true; label: SysState.charging ? "Time to full" : "Time remaining"
            visible: SysState.battTime !== ""; value: SysState.battTime
        }
        InfoRow {
            Layout.fillWidth: true; label: "Energy"
            value: SysState.batt ? SysState.batt.energy.toFixed(1) + " / " + SysState.batt.energyCapacity.toFixed(1) + " Wh" : ""
        }
        InfoRow {
            Layout.fillWidth: true; label: "Power draw"
            value: SysState.batt ? Math.abs(SysState.batt.changeRate).toFixed(1) + " W" : ""
        }
        InfoRow {
            Layout.fillWidth: true; label: "Health"
            visible: SysState.batt && SysState.batt.healthSupported
            value: SysState.batt ? Math.round(SysState.batt.healthPercentage) + "%" : ""
        }
        InfoRow {
            Layout.fillWidth: true; label: "Battery"
            visible: SysState.batt && SysState.batt.model !== ""
            value: SysState.batt ? SysState.batt.model : ""
        }
    }
    Text {
        visible: !SysState.hasBattery
        text: "No battery detected."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
    }

    SectionLabel { text: "Power profile"; visible: SysState.profilesAvailable }
    Chips {
        visible: SysState.profilesAvailable
        Layout.fillWidth: true
        options: SysState.profileList.map(p => ({ id: p, label: p === "power-saver" ? "Power saver" : p }))
        current: SysState.profile
        onPicked: id => SysState.setProfile(id)
    }

    GameModeSection { Layout.fillWidth: true }

    SectionLabel { text: "Idle" }
    Text {
        Layout.fillWidth: true
        text: "Applies to the lock screen's idle handling. Fullscreen windows and video players hold idle off."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12; wrapMode: Text.WordWrap
    }
    Dropdown {
        label: "Dim screen after"
        options: pg.opts(Config.dimAfter)
        current: String(Math.round(Config.dimAfter))
        onPicked: id => Config.dimAfter = parseInt(id)
    }
    Dropdown {
        label: "Lock screen after"
        options: pg.opts(Config.lockAfter)
        current: String(Math.round(Config.lockAfter))
        onPicked: id => Config.lockAfter = parseInt(id)
    }
    Dropdown {
        label: "Suspend after"
        options: pg.opts(Config.suspendAfter)
        current: String(Math.round(Config.suspendAfter))
        onPicked: id => Config.suspendAfter = parseInt(id)
    }
    ToggleRow {
        Layout.fillWidth: true
        text: "Suspend on idle when plugged in"
        checked: Config.suspendOnAC
        onToggled: v => Config.suspendOnAC = v
    }
    ToggleRow {
        Layout.fillWidth: true
        text: "Lock when the lid closes / on suspend"
        checked: Config.lockOnSleep
        onToggled: v => Config.lockOnSleep = v
    }

    SectionLabel { text: "Lid" }
    Cmd {
        id: lid
        property string action: "suspend"
        argv: ["sh", "-c", "systemd-analyze cat-config systemd/logind.conf 2>/dev/null | sed -n 's/^HandleLidSwitch=//p' | tail -n1"]
        onDone: out => { if (out.trim() !== "") action = out.trim(); }
    }
    InfoRow { Layout.fillWidth: true; label: "Lid close action (battery)"; value: lid.action }
    Text {
        Layout.fillWidth: true
        text: "Handled by systemd-logind (HandleLidSwitch in /etc/systemd/logind.conf), not by Ultimit. Read-only here."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12; wrapMode: Text.WordWrap
    }
}
