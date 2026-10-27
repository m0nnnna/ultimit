// ClockItem.qml - top bar: the time (hours:minutes). The date is the hover tooltip. Click opens the
// clock + quick settings panel (QuickSettings.qml); it is the last item of the bar.
import QtQuick
import Quickshell
import "../.."
import ".."

BarButton {
    id: clk
    readonly property var days: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    function p2(n) { return String(n).padStart(2, "0"); }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date now: clock.date
    readonly property string timeText: ((now.getHours() % 12) || 12) + ":" + p2(now.getMinutes()) + " " + (now.getHours() < 12 ? "AM" : "PM")
    readonly property string dateText: now.getFullYear() + "." + p2(now.getMonth() + 1) + "." + p2(now.getDate()) + " " + days[now.getDay()]
    name: "Clock: " + timeText + ", " + dateText + ". Opens quick settings"
    tip: dateText
    lit: SysState.qsOpen
    width: clockText.implicitWidth + 24
    onClicked: SysState.toggleQs()
    Text {
        id: clockText
        anchors.centerIn: parent
        text: clk.timeText
        color: clk.lit ? Theme.accent : Theme.fg
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.8
        font.features: Theme.tnum
    }
}
