// ClockFlyout.qml - tray clock / bell flyout: month calendar (today highlighted, prev / next month)
// and the notification centre (Notifs history rendered with NotifCard, "Clear all", do-not-disturb).
import QtQuick
import Quickshell
import "../.."
import ".."
import "../../apps/accessory"

Column {
    id: root
    spacing: 10

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date today: clock.date
    property int viewY: today.getFullYear()
    property int viewM: today.getMonth()
    readonly property var months: ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    readonly property var dows: ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    readonly property var days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    function p2(n) { return String(n).padStart(2, "0"); }
    function shift(d) {
        let m = viewM + d, y = viewY;
        while (m < 0) { m += 12; y--; }
        while (m > 11) { m -= 12; y++; }
        viewM = m; viewY = y;
    }
    function goToday() { viewY = today.getFullYear(); viewM = today.getMonth(); }
    readonly property int lead: new Date(viewY, viewM, 1).getDay()
    readonly property int dim: new Date(viewY, viewM + 1, 0).getDate()
    readonly property bool isThisMonth: viewY === today.getFullYear() && viewM === today.getMonth()
    function handleEscape() { return false; }

    // ---- header: time / date + DND ----
    Item {
        width: parent.width; height: 52
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                text: ((root.today.getHours() % 12) || 12) + ":" + root.p2(root.today.getMinutes()) + " " + (root.today.getHours() < 12 ? "AM" : "PM")
                color: Theme.fg; font.family: Theme.display; font.pixelSize: Theme.ds(22)
            }
            Text {
                text: root.days[root.today.getDay()] + "  " + root.today.getFullYear() + "." + root.p2(root.today.getMonth() + 1) + "." + root.p2(root.today.getDate())
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.6
            }
        }
    }

    // ---- calendar ----
    Item {
        width: parent.width; height: 26
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.months[root.viewM] + " " + root.viewY
            color: Theme.fg; font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 2
        }
        Row {
            anchors.right: parent.right; spacing: 6
            FlyBtn { text: "Today"; visible: !root.isThisMonth; onClicked: root.goToday() }
            FlyBtn { text: "‹"; width: 30; onClicked: root.shift(-1) }
            FlyBtn { text: "›"; width: 30; onClicked: root.shift(1) }
        }
    }
    Grid {
        id: cal
        columns: 7
        width: parent.width
        readonly property real cw: width / 7
        Repeater {
            model: root.dows
            delegate: Item {
                required property string modelData
                width: cal.cw; height: 20
                Text { anchors.centerIn: parent; text: modelData; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4 }
            }
        }
        Repeater {
            model: 42
            delegate: Item {
                id: cell
                required property int index
                readonly property int dayNum: index - root.lead + 1
                readonly property bool inMonth: dayNum >= 1 && dayNum <= root.dim
                readonly property bool isToday: inMonth && root.isThisMonth && dayNum === root.today.getDate()
                width: cal.cw; height: 28
                visible: index < 35 || root.lead + root.dim > 35
                Rectangle {
                    anchors.centerIn: parent; width: 26; height: 24
                    color: cell.isToday ? Theme.accent : "transparent"
                    border.width: cell.isToday ? 0 : (cm.containsMouse && cell.inMonth ? 1 : 0)
                    border.color: Theme.lineStrong
                }
                Text {
                    anchors.centerIn: parent
                    visible: cell.inMonth
                    text: cell.dayNum
                    color: cell.isToday ? Theme.onAccent : (cell.index % 7 === 0 || cell.index % 7 === 6 ? Theme.dim : Theme.fg)
                    font.family: Theme.mono; font.pixelSize: 12; font.weight: cell.isToday ? Font.Bold : Font.Normal
                }
                MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true }
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.line }

    // ---- notification centre ----
    Item {
        width: parent.width; height: 28
        SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: "Notifications" }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Notifs.count; color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
            }
            FlyBtn { text: "Clear all"; visible: Notifs.count > 0; onClicked: Notifs.clear() }
        }
    }
    ToggleRow {
        width: parent.width
        text: "Do not disturb"
        checked: Notifs.dnd
        onToggled: v => Notifs.dnd = v
    }
    ListView {
        id: nl
        width: parent.width
        height: Notifs.count === 0 ? 40 : Math.min(contentHeight, 260)
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: Notifs.list
        delegate: NotifCard { width: nl.width; inHistory: true }
        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Config.dur(140) } }
        displaced: Transition { NumberAnimation { properties: "y"; duration: Config.dur(160); easing.type: Easing.OutCubic } }
        Text {
            visible: Notifs.count === 0
            anchors.centerIn: parent
            text: "NO NOTIFICATIONS"; color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2
        }
    }
}
