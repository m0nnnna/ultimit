// UsageMeters.qml - an account's plan limits in the CLAUDE sidebar: the 5-hour session and the weekly
// limits as Claude Code last reported them (it does with every turn), each with when it resets.
import QtQuick
import "../.."

Column {
    id: root
    property var usage: null            // Claude.usage[account]: { windows: { five_hour: { used, resets } }, overage, t }
    property real now: Date.now() / 1000

    spacing: 6
    Timer { interval: 30000; repeat: true; running: root.visible; onTriggered: root.now = Date.now() / 1000 }

    readonly property var rows: {
        const w = usage && usage.windows ? usage.windows : {};
        const order = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"];
        return Object.keys(w).sort((a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99))
            .map(k => ({ key: k, used: w[k].used, resets: w[k].resets }));
    }
    function label(k) {
        if (k === "five_hour") return "SESSION";
        if (k === "seven_day") return "WEEK";
        if (k.startsWith("seven_day_")) return "WEEK · " + k.substring(10).toUpperCase();
        return k.replace(/_/g, " ").toUpperCase();
    }
    function resetText(t) {
        if (!t) return "";
        if (t <= now) return "RESET";
        const d = new Date(t * 1000), n = new Date(now * 1000);
        return "RESETS " + (d.toDateString() === n.toDateString() ? Qt.formatTime(d, "hh:mm")
                                                                   : Qt.formatDateTime(d, "ddd hh:mm").toUpperCase());
    }

    Text {
        visible: root.rows.length === 0
        width: parent.width; wrapMode: Text.Wrap
        text: "PLAN USAGE SHOWS AFTER A MESSAGE"
        color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
    }
    Repeater {
        model: root.rows
        delegate: Column {
            required property var modelData
            readonly property bool past: !!modelData.resets && modelData.resets <= root.now
            readonly property real used: past ? 0 : Math.max(0, Math.min(1, modelData.used))
            width: root.width
            spacing: 3
            Item {
                width: parent.width; height: 12
                Text {
                    text: root.label(modelData.key) + "  " + (past ? "—" : Math.round(used * 100) + "%")
                    color: used >= 0.9 ? Theme.bad : used >= 0.75 ? Theme.warn : Theme.fg
                    font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
                }
                Text {
                    anchors.right: parent.right
                    text: root.resetText(modelData.resets)
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
                }
            }
            Rectangle {
                width: parent.width; height: 3
                color: Theme.line
                Rectangle {
                    width: parent.width * used; height: parent.height
                    color: used >= 0.9 ? Theme.bad : used >= 0.75 ? Theme.warn : Theme.accent
                }
            }
        }
    }
    Text {
        visible: !!root.usage && root.usage.overage
        text: "USING EXTRA USAGE"
        color: Theme.warn; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
    }
}
