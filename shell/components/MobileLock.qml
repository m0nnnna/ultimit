// MobileLock.qml - the phone lock screen (Config.mobile), drawn by LockSurface over its dimmed art.
// Glance view: big clock, date, battery, the latest notifications (app + title only, never the
// body) and a swipe-up hint; the keyboard is down. Swiping up (or a key) moves to the entry view:
// the clock tucks up and the password field sits just above the on-screen keyboard. LockScreen
// drops back to the glance view after 30 s without typing.
import QtQuick
import Quickshell
import ".."

Item {
    id: root
    required property var ctl
    required property date now
    property real oskH: 240

    readonly property bool entry: ctl.entry
    readonly property var days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    readonly property var months: ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
                                   "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    function p2(n) { return String(n).padStart(2, "0"); }
    function ago(t) {
        const m = Math.floor((now.getTime() - t) / 60000);
        if (m < 1) return "NOW";
        if (m < 60) return m + "M";
        const d = new Date(t);
        return p2(d.getHours()) + ":" + p2(d.getMinutes());
    }

    // swipe up anywhere for the password; tap the clock area to go back to the glance view
    MouseArea {
        anchors.fill: parent
        property real y0: 0
        onPressed: m => y0 = m.y
        onReleased: m => {
            if (y0 - m.y > 60) root.ctl.showEntry();
            else if (root.entry && m.y < field.y - 20) root.ctl.hideEntry();
            else if (!root.entry && m.y > hint.y - 40) root.ctl.showEntry();
        }
    }

    // ---- top strip ----
    Row {
        x: 18; y: 16; spacing: 8
        Rectangle { width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
        Text { text: "LOCKED"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 3 }
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 18; y: 14
        visible: SysState.hasBattery
        text: (SysState.charging ? "⚡ " : "") + SysState.battPct + "%"
        color: SysState.charging ? Theme.ok : (SysState.battPct <= 15 ? Theme.bad : Theme.fg)
        font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 1.5
    }

    // ---- clock ----
    Column {
        id: clock
        x: 24
        y: root.entry ? 52 : 92
        spacing: root.entry ? 2 : 6
        Behavior on y { NumberAnimation { duration: Config.dur(200); easing.type: Easing.OutCubic } }
        Row {
            spacing: 6
            Text {
                text: ((root.now.getHours() % 12) || 12) + ":" + root.p2(root.now.getMinutes())
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: root.entry ? 44 : 76
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.baseline: parent.children[0].baseline
                text: root.now.getHours() < 12 ? "AM" : "PM"
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: root.entry ? 12 : 16; font.letterSpacing: 2
            }
        }
        Text {
            text: root.days[root.now.getDay()] + " · " + root.now.getDate() + " " + root.months[root.now.getMonth()]
            color: Theme.accent
            font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 3
        }
    }

    // ---- glance: notifications + media ----
    Column {
        id: glance
        x: 18; width: parent.width - 36
        y: clock.y + clock.height + 34
        spacing: 8
        opacity: root.entry ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(160) } }

        Row {   // now playing
            readonly property var p: SysState.player
            visible: p !== null && p.isPlaying && (p.trackTitle || "") !== ""
            spacing: 8; width: parent.width
            Text { text: "▶"; color: Theme.accent; font.family: Theme.mono; font.pixelSize: 11 }
            Text {
                width: parent.width - 20; elide: Text.ElideRight
                text: parent.p ? (parent.p.trackTitle + (parent.p.trackArtist ? " — " + parent.p.trackArtist : "")) : ""
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
            }
        }

        Repeater {
            model: Notifs.list   // newest first; the first four
            delegate: Rectangle {
                id: card
                required property int index
                required property var model
                readonly property var n: model
                visible: index < 4
                width: glance.width; height: visible ? 52 : 0
                color: Theme.panel2
                border.width: 1; border.color: Theme.line
                Rectangle { width: 2; height: parent.height; color: card.n && card.n.urgency === 2 ? Theme.bad : Theme.accent }
                Text {
                    x: 14; y: 9; width: parent.width - 70; elide: Text.ElideRight
                    text: card.n ? (card.n.app || "NOTIFICATION").toUpperCase() : ""
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 12; y: 9
                    text: card.n ? root.ago(card.n.time) : ""
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Text {
                    x: 14; y: 26; width: parent.width - 28; elide: Text.ElideRight
                    text: card.n ? card.n.title : ""
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                }
            }
        }
        Text {
            visible: Notifs.count > 4
            text: "+" + (Notifs.count - 4) + " MORE"
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2
        }
    }

    // ---- glance: swipe hint ----
    Column {
        id: hint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 34
        spacing: 6
        opacity: root.entry ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(160) } }
        Item {   // chevron
            id: chevron
            anchors.horizontalCenter: parent.horizontalCenter
            width: 22; height: 12
            Rectangle { x: 1; y: 5; width: 12; height: 2; color: Theme.accent; rotation: -30; antialiasing: true }
            Rectangle { x: 9; y: 5; width: 12; height: 2; color: Theme.accent; rotation: 30; antialiasing: true }
            SequentialAnimation on opacity {
                loops: Animation.Infinite; running: Config.motion && hint.visible
                NumberAnimation { to: .3; duration: 900 } NumberAnimation { to: 1; duration: 900 }
            }
        }
        Text {
            text: "SWIPE UP TO UNLOCK"
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 3
        }
    }

    // ---- entry: password above the keyboard ----
    Rectangle {   // solid backing so the field reads over the art
        x: 0; width: parent.width
        y: field.y - 18; height: parent.height - y
        opacity: field.opacity
        visible: field.visible
        color: Theme.bg1
        Rectangle { width: parent.width; height: 1; color: Theme.line }
    }
    Column {
        id: field
        x: 18; width: parent.width - 36
        y: root.entry ? parent.height - root.oskH - height - 18 : parent.height
        spacing: 10
        opacity: root.entry ? 1 : 0
        visible: opacity > 0
        Behavior on y { NumberAnimation { duration: Config.dur(200); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Config.dur(160) } }

        property real shakeX: 0
        transform: Translate { x: field.shakeX }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: field; property: "shakeX"; to: -14; duration: Config.dur(55) }
            NumberAnimation { target: field; property: "shakeX"; to: 14; duration: Config.dur(80) }
            NumberAnimation { target: field; property: "shakeX"; to: -8; duration: Config.dur(80) }
            NumberAnimation { target: field; property: "shakeX"; to: 0; duration: Config.dur(60) }
        }
        Connections { target: root.ctl; function onShakeTickChanged() { shake.restart(); } }

        Row {
            spacing: 10
            Text { text: "USER"; color: Theme.dim; anchors.baseline: uname.baseline
                   font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4 }
            Text { id: uname; text: (Quickshell.env("USER") || "user").toUpperCase(); color: Theme.fg
                   font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 15; font.letterSpacing: 3 }
        }
        LockField { width: parent.width; height: 46; ctl: root.ctl }
        Text {
            text: root.ctl.authState === "auth" ? "AUTHENTICATING…"
                  : (root.ctl.message !== "" ? root.ctl.message : "ENTER TO UNLOCK")
            color: root.ctl.authState === "auth" ? Theme.accent
                   : (root.ctl.authState === "fail" ? Theme.bad : Theme.dim)
            font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.6
        }
    }
}
