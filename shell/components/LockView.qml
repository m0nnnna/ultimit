// LockView.qml - the lock screen's picture (one per output), shared by the real lock surface
// (LockSurface.qml) and the preview window (LockScreen.qml, ULTIMIT_LOCK_PREVIEW=1).
//
//   lock-in (tI, ms)  the surface starts on the frame LockFx hands over: black with an accent line
//                     across the middle. 0-700 the shards fade/settle in; 100-450 the line fades;
//                     330-650 emblem + clock + date assemble (a short accent line draws out from the
//                     centre, then the content wipes down, the emblem re-tracing as it goes);
//                     600-1000 the password card opens (accent line, then wipe).
//   idle              slow ambient shard motion (Config.lockAnimated, <= 8 fps) and a seconds tick
//                     that flashes the accent. Nothing else runs.
//   unlock (tU, ms)   0-380 everything collapses vertically into the screen-centre line, 150-600 the
//                     shards fade to black, 350-560 the accent line draws out across the screen: the
//                     frame LockFx continues from (the black halves then wipe away from the centre).
//   wrong password    the card tears sideways, its accent goes to the error colour (HouseCard.glitch).
// Reduced motion: the end states, with a 250 ms crossfade in; unlocking is immediate.
import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Services.UPower
import ".."

FocusScope {
    id: view
    required property var ctl
    required property bool primary
    focus: true
    readonly property real u: Math.max(.7, Math.min(width, height) / 800)

    SystemClock { id: clock; precision: SystemClock.Seconds; enabled: view.visible }
    readonly property var days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    Component.onCompleted: { forceActiveFocus(); if (!Config.motion) tI = lockInEnd; }
    // Start the clock once the first frame has been shown, not at creation: the compositor sends
    // frame callbacks only when the surface is on screen, so the second swap marks "visible" and the
    // time spent loading shaders and fonts or waiting to be mapped does not eat the animation.
    property bool started: false
    property int swaps: 0
    Connections {
        target: view.Window.window
        enabled: !view.started && Config.motion
        function onFrameSwapped() { if (++view.swaps >= 2) { view.started = true; intro.start(); } }
    }
    Rectangle { visible: !view.started && Config.motion; width: 1; height: 1; opacity: .01; color: "white"   // keeps frames coming until then
                x: view.swaps % 2 }
    Keys.onPressed: e => view.ctl.onKey(e)

    // ---- sequences ----
    readonly property int lockInEnd: 1000
    readonly property int unlockEnd: 650
    property real tI: 0
    property real tU: 0
    // ULTIMIT_ANIM_DELAY=<ms>: hold the first frame this long before the lock-in plays (for screenshots).
    SequentialAnimation {
        id: intro
        PauseAnimation { duration: parseInt(Quickshell.env("ULTIMIT_ANIM_DELAY") || "0") }
        NumberAnimation { target: view; property: "tI"; from: 0; to: view.lockInEnd; duration: view.lockInEnd }
    }
    NumberAnimation { id: outro; target: view; property: "tU"; from: 0; to: view.unlockEnd; duration: view.unlockEnd }
    readonly property bool unlocking: ctl.unlocking
    onUnlockingChanged: if (unlocking && Config.motion) { intro.stop(); tI = lockInEnd; outro.start(); }

    readonly property real wallOp: Anim.out3(Anim.seg(tI, 0, 700)) * (1 - Anim.out3(Anim.seg(tU, 150, 600)))
    readonly property real lineIn: 1 - Anim.seg(tI, 100, 450)              // the handed-over line, fading out
    readonly property real groupWipe: Anim.out3(Anim.seg(tI, 330 + 90, 330 + 90 + 220))
    readonly property real groupLine: Anim.out3(Anim.seg(tI, 330, 330 + 120))
    readonly property real cardLine: Anim.out3(Anim.seg(tI, 600, 600 + 140))
    readonly property real cardWipe: Anim.out3(Anim.seg(tI, 680, 680 + 320))
    readonly property real trace: Anim.out3(Anim.seg(tI, 400, 1000))
    readonly property real collapse: Anim.out3(Anim.seg(tU, 0, 380))
    readonly property real lineOut: Anim.out3(Anim.seg(tU, 350, 560))
    readonly property real lineW: tU > 0 ? width * lineOut : (lineIn > 0 ? width * lineIn : 0)
    readonly property real lineOp: tU > 0 ? 1 : lineIn

    opacity: Config.motion ? 1 : fade.v
    QtObject { id: fade; property real v: 0
               Behavior on v { NumberAnimation { duration: Config.dur(Theme.motion.slow); easing.type: Theme.easeBase } } Component.onCompleted: v = 1 }

    // ---- shards, dimmed ----
    Item {
        anchors.fill: parent
        visible: view.wallOp > .005
        opacity: view.wallOp
        scale: Anim.mix(1.04, 1, Anim.out3(Anim.seg(view.tI, 0, 900)))
        WallpaperArt {
            anchors.fill: parent
            railInset: 0
            active: view.visible && view.wallOp > .005
            animate: Config.motion && Config.lockAnimated
            fps: Math.min(Config.wallpaperFps, 8)
            spinFps: 8
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
    }

    // everything on top collapses into the centre line when unlocking
    Item {
        id: stack
        anchors.fill: parent
        opacity: 1 - Anim.seg(view.tU, 200, 400)
        visible: opacity > .005
        transform: Scale { origin.x: view.width / 2; origin.y: view.height / 2; yScale: Math.max(.004, 1 - view.collapse) }

        // top-left status tag
        Row {
            x: 30; y: 26; spacing: 10
            opacity: view.cardWipe
            Rectangle { width: 8; height: 8; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite; running: Config.motion && view.visible && view.tU === 0
                            NumberAnimation { to: .25; duration: Config.dur(Theme.motion.ambient) } NumberAnimation { to: 1; duration: Config.dur(Theme.motion.ambient) } } }
            Text { text: "SESSION LOCKED"; color: Theme.dim
                   font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 3.3 }
        }

        // centre group: emblem, clock, date. An accent line draws out from the centre of its top edge,
        // then the content wipes down (the house motion).
        Item {
            id: group
            width: center.width; height: center.height
            x: (view.width - width) / 2
            y: Math.max(40, view.height * .5 - height * .5 - (view.primary ? 90 * view.u : 0))
            Rectangle {
                y: -1; height: 2
                width: group.width * view.groupLine * (view.groupWipe > .99 ? 0 : 1)
                x: (group.width - width) / 2
                color: Theme.accent
                visible: width > 1
            }
            Item {
                width: parent.width; height: parent.height * view.groupWipe
                clip: view.groupWipe < .999
                Column {
                    id: center
                    spacing: 8 * view.u
                    Emblem {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: 54 * view.u; color: Theme.fg
                        draw: view.trace < 1 && Config.motion ? view.trace : -1
                    }
                    Row {
                        id: timeRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10 * view.u
                        Text {
                            id: timeText
                            text: ((view.now.getHours() % 12) || 12) + ":" + view.p2(view.now.getMinutes()) + (view.now.getHours() < 12 ? " AM" : " PM")
                            color: Theme.fg
                            font.family: Theme.display; font.pixelSize: Theme.ds(104 * view.u); font.letterSpacing: Theme.dt(6 * view.u)
                            font.features: { "tnum": 1 }
                        }
                        Text {   // seconds: flash the accent on each tick, settle to dim
                            id: secText
                            anchors.baseline: timeText.baseline
                            text: ":" + view.p2(view.now.getSeconds())
                            color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 24 * view.u; font.letterSpacing: 2
                            font.features: { "tnum": 1 }
                            SequentialAnimation {
                                id: tick
                                ColorAnimation { target: secText; property: "color"; to: Theme.accent; duration: Config.dur(Theme.motion.fast) }
                                ColorAnimation { target: secText; property: "color"; to: Theme.dim; duration: Config.dur(Theme.motion.ambient); easing.type: Theme.easeBase }
                            }
                            Connections { target: view; function onNowChanged() { if (Config.motion && view.visible && view.tU === 0) tick.restart(); } }
                        }
                    }
                    Item {   // seconds hairline: the minute filling up
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: timeRow.width; height: 2
                        Rectangle { anchors.fill: parent; color: Theme.line }
                        Rectangle {
                            width: parent.width * (view.now.getSeconds() + 1) / 60; height: parent.height
                            color: Theme.accent; opacity: .75
                            Behavior on width { enabled: view.now.getSeconds() > 0; NumberAnimation { duration: Config.dur(Theme.motion.skin); easing.type: Theme.easeBase } }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: view.days[view.now.getDay()] + " \u00b7 " + view.now.getFullYear() + "." + view.p2(view.now.getMonth() + 1) + "." + view.p2(view.now.getDate())
                        color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 15 * view.u; font.letterSpacing: 5
                    }
                }
            }
        }

        // user panel (first screen only)
        HouseCard {
            id: panel
            visible: view.primary
            width: 380 * view.u; height: panelCol.height + 36
            x: (view.width - width) / 2
            y: group.y + group.height + 36 * view.u
            lineP: view.cardLine
            wipeP: view.cardWipe
            Connections { target: view.ctl; function onShakeTickChanged() { panel.glitch(); } }

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

                // chamfered password field
                Item {
                    id: field
                    width: parent.width; height: 40
                    readonly property real c: 8
                    readonly property bool bad: view.ctl.authState === "fail"
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: field.bad ? 2 : 1
                            strokeColor: field.bad ? Theme.bad : Theme.accent
                            fillColor: Theme.panel2
                            startX: field.c + .5; startY: .5
                            PathLine { x: field.width - .5; y: .5 }
                            PathLine { x: field.width - .5; y: field.height - field.c - .5 }
                            PathLine { x: field.width - field.c - .5; y: field.height - .5 }
                            PathLine { x: .5; y: field.height - .5 }
                            PathLine { x: .5; y: field.c + .5 }
                            PathLine { x: field.c + .5; y: .5 }
                        }
                    }
                    Text {   // placeholder
                        anchors.verticalCenter: parent.verticalCenter; x: 22
                        visible: view.ctl.password.length === 0 && view.ctl.authState !== "auth"
                        text: "ENTER PASSWORD"; color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 3
                    }
                    Text {   // masked input (tail is kept visible when long)
                        id: dots
                        anchors.verticalCenter: parent.verticalCenter; x: 14
                        width: parent.width - 28
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideLeft
                        text: "•".repeat(view.ctl.password.length)
                        color: Theme.fg
                        font.family: Theme.ui; font.pixelSize: 18; font.letterSpacing: 4
                    }
                    Rectangle {   // caret
                        visible: view.ctl.authState !== "auth" && caretOn
                        property bool caretOn: true
                        id: caret
                        x: 14 + Math.min(dots.contentWidth, dots.width) + 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 18; color: Theme.accent
                        Timer { interval: 530; repeat: true; running: Config.motion; onTriggered: caret.caretOn = !caret.caretOn }
                    }
                }

                // status line: authenticating / denied / caps lock
                Item {
                    width: parent.width; height: 16
                    Text {
                        id: statusText
                        anchors.left: parent.left
                        text: view.ctl.authState === "auth" ? "AUTHENTICATING" + dotsAnim.suffix
                              : (view.ctl.message !== "" ? view.ctl.message : "PRESS ENTER TO UNLOCK")
                        color: view.ctl.authState === "auth" ? Theme.accent
                               : (view.ctl.authState === "fail" ? Theme.bad : Theme.dim)
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.6
                        QtObject {
                            id: dotsAnim
                            property int n: 0
                            readonly property string suffix: ".".repeat(n)
                        }
                        Timer { interval: 250; repeat: true; running: view.ctl.authState === "auth"
                                onTriggered: dotsAnim.n = (dotsAnim.n + 1) % 4 }
                    }
                    Text {
                        anchors.right: parent.right
                        visible: view.ctl.capsLock
                        text: "▲ CAPS LOCK"; color: Theme.warn
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.2
                    }
                }
            }
        }

        // bottom-left: battery + media
        Column {
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
            anchors.right: parent.right; anchors.rightMargin: 30
            anchors.bottom: parent.bottom; anchors.bottomMargin: 28
            opacity: view.cardWipe
        }
    }

    // the accent line: handed over from LockFx (fading out), and again when unlocking
    Rectangle {
        height: 2
        width: view.lineW
        x: (view.width - width) / 2; y: view.height / 2 - 1
        color: Theme.accent
        opacity: view.lineOp
        visible: width > 1 && opacity > .005
    }
}
