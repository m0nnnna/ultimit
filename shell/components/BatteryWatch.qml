// BatteryWatch.qml - low-battery warnings. While discharging: a toast at 20% and at 10%, and a
// sticky red one at 5% that names what UPower does at its action level (CriticalPowerAction in
// /etc/UPower/UPower.conf: hibernate, hybrid sleep or power off). Each level warns once per
// discharge; plugging in clears the sticky warning and re-arms all levels.
// IPC (testing): qs ipc call battery test <pct> <charging> | real
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Scope {
    id: root

    property int testPct: -1                 // >= 0: pretend (ipc test)
    property bool testCharging: false
    readonly property bool active: testPct >= 0 || SysState.hasBattery
    readonly property int pct: testPct >= 0 ? testPct : SysState.battPct
    readonly property bool charging: testPct >= 0 ? testCharging : (SysState.charging || SysState.full)

    property int warned: 0                   // lowest level warned about this discharge (0 = none)
    property int criticalId: 0               // sticky toast to take down when power comes back
    property string action: ""               // UPower's critical action, e.g. "PowerOff"
    property int actionPct: 2

    function level(p) { return p <= 5 ? 5 : p <= 10 ? 10 : p <= 20 ? 20 : 0; }

    function actionText() {
        switch (action) {
        case "Hibernate": return "hibernate";
        case "HybridSleep": return "go to sleep and save to disk";
        case "Suspend": return "go to sleep";
        case "PowerOff": return "shut down";
        default: return "shut down";
        }
    }

    function check() {
        if (!active) return;
        if (charging) {
            if (criticalId !== 0) { Notifs.release(criticalId, false); criticalId = 0; }
            warned = 0;
            return;
        }
        if (pct > 22) warned = 0;            // a little hysteresis: re-arm once clearly above 20%
        const l = level(pct);
        if (l === 0 || (warned !== 0 && l >= warned)) return;
        warned = l;
        const left = SysState.battTime && testPct < 0 ? " (about " + SysState.battTime + ")" : "";
        if (l === 5) {
            if (criticalId !== 0) Notifs.release(criticalId, false);
            criticalId = Toasts.show("Battery critical", pct + "% left" + left + ". Plug in now: at "
                + actionPct + "% this PC will " + actionText() + ".", "", 0, 2);
        } else if (l === 10) {
            Toasts.show("Battery low", pct + "% left" + left + ". Plug in soon.", "", 15000);
        } else {
            Toasts.show("Battery low", pct + "% left" + left + ".", "", 8000);
        }
    }

    onPctChanged: check()
    onChargingChanged: check()
    onActiveChanged: check()
    Component.onCompleted: { policy.running = true; check(); }

    // What UPower does at the action level, and at which percentage.
    Process {
        id: policy
        // UPower reports its configured action even when logind can't do it (no swap/resume for
        // hibernate); then it powers off, so ask logind whether the action is really available.
        command: ["sh", "-c", `
            a=$(busctl --system call org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower GetCriticalAction 2>/dev/null | sed 's/^s "\\(.*\\)"$/\\1/')
            case "$a" in Hibernate|HybridSleep|Suspend)
                busctl --system call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager Can$a 2>/dev/null | grep -q '"yes"' || a=PowerOff;;
            esac
            echo "$a"
            sed -n 's/^PercentageAction=\\([0-9]*\\).*/\\1/p' /etc/UPower/UPower.conf 2>/dev/null | head -1`]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                if (l[0]) root.action = l[0].trim();
                const p = parseInt(l[1]);
                if (p > 0) root.actionPct = p;
            }
        }
    }

    IpcHandler {
        target: "battery"
        function test(pct: int, charging: bool): string { root.testCharging = charging; root.testPct = Math.max(0, Math.min(100, pct)); root.check(); return "ok"; }
        function real(): string { root.testPct = -1; root.warned = 0; root.check(); return "ok"; }
        function state(): string { return JSON.stringify({ pct: root.pct, charging: root.charging, warned: root.warned, action: root.action, actionPct: root.actionPct }); }
    }
}
