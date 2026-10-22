// LockSurface.qml - one lock-screen surface (per output), Altimit look: wallpaper art dimmed,
// big clock + date, [ ULTIMIT ] wordmark, user panel with a masked chamfered password field.
// The password field is shown on the first screen only; every surface accepts keystrokes
// (state lives in LockScreen `ctl`).
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import ".."

WlSessionLockSurface {
    id: surf
    required property var ctl
    color: Theme.bg1

    readonly property bool primary: screen !== null && Config.isMainScreen(screen.name)
    readonly property real u: Math.max(.7, Math.min(width, height) / 800)
    // the on-screen keyboard covers the bottom while locked (LockScreen.osk): centre above it
    readonly property real oskH: surf.primary && Quickshell.env("ULTIMIT_OSK") === "1" ? 480 : 0

    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property var days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    FocusScope {
        id: scope
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()
        Keys.onPressed: e => surf.ctl.onKey(e)

        WallpaperArt {
            anchors.fill: parent
            railInset: 0
            active: surf.visible
            animate: Config.motion && Config.lockAnimated && !Config.mobile
        }
        Rectangle { anchors.fill: parent; color: Theme.light ? "#40ffffff" : "#8c000000" }   // dimmed look
        Rectangle {   // soft vignette via two gradients
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#66000000" }
                GradientStop { position: .35; color: "transparent" }
                GradientStop { position: .65; color: "transparent" }
                GradientStop { position: 1; color: "#80000000" }
            }
            visible: !Theme.light
        }

        // phones: their own layout (glance view, swipe up for the password)
        MobileLock {
            anchors.fill: parent
            visible: Config.mobile
            ctl: surf.ctl
            now: surf.now
        }

        // top-left status tag
        Row {
            visible: !Config.mobile
            x: 30; y: 26; spacing: 10
            Rectangle { width: 8; height: 8; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite; running: Config.motion
                            NumberAnimation { to: .25; duration: 900 } NumberAnimation { to: 1; duration: 900 } } }
            Text { text: "SESSION LOCKED"; color: Theme.dim
                   font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 3.3 }
        }

        // centre column: emblem, clock, date
        Column {
            id: center
            visible: !Config.mobile
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(40, (parent.height - surf.oskH) * .5 - height * .5 - (surf.primary ? 90 * surf.u : 0))
            spacing: 8 * surf.u
            Emblem { anchors.horizontalCenter: parent.horizontalCenter; size: 54 * surf.u; color: Theme.fg }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ((surf.now.getHours() % 12) || 12) + ":" + surf.p2(surf.now.getMinutes()) + (surf.now.getHours() < 12 ? " AM" : " PM")
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: 104 * surf.u; font.letterSpacing: 6 * surf.u
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: surf.days[surf.now.getDay()] + " · " + surf.now.getFullYear() + "." + surf.p2(surf.now.getMonth() + 1) + "." + surf.p2(surf.now.getDate())
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 15 * surf.u; font.letterSpacing: 5
            }
        }

        // user panel (first screen only)
        Item {
            id: panel
            visible: surf.primary && !Config.mobile
            width: 380 * surf.u; height: panelCol.height + 36
            anchors.horizontalCenter: parent.horizontalCenter
            y: center.y + center.height + 36 * surf.u
            property real shakeX: 0
            transform: Translate { x: panel.shakeX }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: panel; property: "shakeX"; to: -14; duration: Config.dur(55) }
                NumberAnimation { target: panel; property: "shakeX"; to: 14; duration: Config.dur(80) }
                NumberAnimation { target: panel; property: "shakeX"; to: -10; duration: Config.dur(80) }
                NumberAnimation { target: panel; property: "shakeX"; to: 8; duration: Config.dur(70) }
                NumberAnimation { target: panel; property: "shakeX"; to: 0; duration: Config.dur(60) }
            }
            Connections { target: surf.ctl; function onShakeTickChanged() { shake.restart(); } }

            Rectangle {
                id: frame
                anchors.fill: parent
                color: Theme.panel
                border.width: 1
                border.color: Theme.line
                Brackets {}
            }

            Column {
                id: panelCol
                x: 18; y: 18; width: parent.width - 36
                spacing: 12

                Row {
                    spacing: 10
                    Text { text: "USER"; color: Theme.dim; anchors.baseline: uname.baseline
                           font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4 }
                    Text { id: uname; text: (Quickshell.env("USER") || "user").toUpperCase(); color: Theme.fg
                           font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 16; font.letterSpacing: 3 }
                }

                LockField { width: parent.width; ctl: surf.ctl }

                // status line: authenticating / denied / caps lock
                Item {
                    width: parent.width; height: 16
                    Text {
                        id: statusText
                        anchors.left: parent.left
                        text: surf.ctl.authState === "auth" ? "AUTHENTICATING" + dotsAnim.suffix
                              : (surf.ctl.message !== "" ? surf.ctl.message : "PRESS ENTER TO UNLOCK")
                        color: surf.ctl.authState === "auth" ? Theme.accent
                               : (surf.ctl.authState === "fail" ? Theme.bad : Theme.dim)
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.6
                        QtObject {
                            id: dotsAnim
                            property int n: 0
                            readonly property string suffix: ".".repeat(n)
                        }
                        Timer { interval: 250; repeat: true; running: surf.ctl.authState === "auth"
                                onTriggered: dotsAnim.n = (dotsAnim.n + 1) % 4 }
                    }
                    Text {
                        anchors.right: parent.right
                        visible: surf.ctl.capsLock
                        text: "▲ CAPS LOCK"; color: Theme.warn
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.2
                    }
                }
            }
        }

        // bottom-left: battery + media
        Column {
            visible: !Config.mobile
            x: 30; anchors.bottom: parent.bottom; anchors.bottomMargin: 28
            spacing: 6
            Row {
                spacing: 8
                visible: SysState.hasBattery
                Text { text: "BAT"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2 }
                Text {
                    text: SysState.battPct + "%" + (SysState.charging ? " CHARGING" : "")
                    color: SysState.charging ? Theme.ok : (SysState.battPct <= 15 ? Theme.bad : Theme.fg)
                    font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2
                }
            }
            Row {
                spacing: 8
                readonly property var p: SysState.player
                visible: p !== null && p.isPlaying && (p.trackTitle || "") !== ""
                Text { text: "▶"; color: Theme.accent; font.family: Theme.mono; font.pixelSize: 11 }
                Text {
                    width: Math.min(implicitWidth, 420)
                    elide: Text.ElideRight
                    text: parent.p ? (parent.p.trackTitle + (parent.p.trackArtist ? " — " + parent.p.trackArtist : "")).toUpperCase() : ""
                    color: Theme.fg
                    font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2
                }
            }
        }

        Wordmark {
            visible: !Config.mobile
            anchors.right: parent.right; anchors.rightMargin: 30
            anchors.bottom: parent.bottom; anchors.bottomMargin: 28
        }
    }
}
