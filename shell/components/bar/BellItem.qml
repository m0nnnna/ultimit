// BellItem.qml - top bar: do-not-disturb / unread bell (shown while either applies). Click opens the
// notification centre flyout, right-click toggles do not disturb.
import QtQuick
import "../.."
import ".."

BarButton {
    id: bell
    readonly property int unread: Notifs.count + (SysState.fake.unread !== undefined && Notifs.count === 0 ? SysState.fake.unread : 0)
    visible: Notifs.dnd || unread > 0
    name: (Notifs.dnd ? "Do not disturb on, " : "Notifications, ") + unread + " in history"
    tip: (Notifs.dnd ? "DO NOT DISTURB ON" : "NOTIFICATIONS") + "\n" + unread + " IN HISTORY  RIGHT-CLICK: " + (Notifs.dnd ? "ALLOW" : "MUTE")
    fly: "clock"
    width: visible ? 32 : 0
    onClicked: button => { if (button === Qt.LeftButton) openFly("clock"); else if (button === Qt.RightButton) Notifs.toggleDnd(); }
    StatusIcon {
        anchors.centerIn: parent
        kind: "bell"
        muted: Notifs.dnd
        size: Theme.icon.md
    }
    Rectangle {   // unread count badge
        visible: bell.unread > 0
        x: parent.width / 2 + 2; y: 2
        width: Math.max(16, cnt.implicitWidth + 6); height: 16
        color: Theme.accent
        Text {
            id: cnt
            anchors.centerIn: parent
            text: bell.unread > 9 ? "9+" : String(bell.unread)
            color: Theme.onAccent
            font.family: Theme.mono; font.pixelSize: Theme.type.label
        }
    }
}
