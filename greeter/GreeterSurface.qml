// GreeterSurface.qml - one full-screen greeter window (per output). One continuous piece with the
// boot splash (Plymouth) before it and the session boot overlay (shell/Boot.qml) after it:
//
//   hand-off frame  black, the emblem centred (84 px, stroke 1.2), "[ ULTIMIT ]" 18 px below it and a
//                   240 px accent line below that - exactly what Plymouth leaves on screen.
//   intro (tI, ms)   250-700 the line expands across the screen; 500-1400 the shard wallpaper fades
//                   and settles in behind; 800-1600 emblem + wordmark glide into the login card's
//                   header (other outputs: the emblem goes above the clock); 1200-1700 clock and
//                   status come in; 1350-1740 the card opens (accent line from the centre, then the
//                   content wipes down: the house motion).
//   outro (O, ms)   on login success: 0-260 the card content collapses into its accent line, 260-520
//                   the line contracts to the centre, 250-950 the shards fade to black, 450-1150 the
//                   emblem + wordmark glide back to the centre, 900-1150 the 240 px line draws out:
//                   the same frame Boot.qml starts on. If the launch falls through, it plays back.
//   failed password the card tears sideways and its accent goes to the error colour (HouseCard.glitch).
//
// Each sequence is one linear clock; everything derives from it (Anim.seg + easings). Nothing keeps
// running once a sequence ends: the wallpaper only paints while it is visible. Reduced motion
// (ULTIMIT_MOTION=0) shows the end states with a short crossfade.
import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win
    required property var ctl
    color: "#000000"

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-greeter"
    WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string mainScreen: ""
    readonly property bool primary: screen !== null && Quickshell.screens.length > 0
        && screen.name === (Quickshell.screens.some(s => s.name === mainScreen) ? mainScreen : Quickshell.screens[0].name)
    readonly property real u: Math.max(.7, Math.min(width, height) / 800)

    SystemClock { id: clock; precision: SystemClock.Seconds; enabled: win.uiOp > .01 }
    readonly property var days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    readonly property bool busy: ctl.phase === "auth" || ctl.phase === "launching" || ctl.phase === "starting" || ctl.phase === "loading"

    // ---- sequences ----
    readonly property int introEnd: 1800
    readonly property int outroEnd: 1250
    property real tI: 0
    property real tO: 0
    NumberAnimation {
        id: introAnim; target: win; property: "tI"; from: 0; to: win.introEnd
        duration: Config.motion ? win.introEnd : 1
    }
    NumberAnimation { id: outroAnim; target: win; property: "tO"; duration: Config.motion ? 1250 : 250 }
    // The clock starts once the hand-off frame has been shown (the second swap: frame callbacks only
    // come when the surface is on screen), not while shaders and fonts load.
    property bool started: false
    property int swaps: 0
    Connections {
        target: scope.Window.window
        enabled: !win.started
        function onFrameSwapped() { if (++win.swaps >= 2) { win.started = true; introAnim.start(); } }
    }
    readonly property bool leaving: ctl.phase === "launching"
    onLeavingChanged: {
        outroAnim.stop();
        outroAnim.from = tO;
        outroAnim.to = leaving ? outroEnd : 0;
        outroAnim.duration = (Config.motion ? 1 : .2) * Math.abs(outroAnim.to - tO) * (leaving ? 1 : .6);
        outroAnim.start();
    }

    // ---- derived progress ----
    readonly property real glide: Anim.out3(Anim.seg(tI, 800, 1600)) * (1 - Anim.out3(Anim.seg(tO, 450, 1150)))
    readonly property real wallOp: Anim.out3(Anim.seg(tI, 500, 1400)) * (1 - Anim.seg(tO, 250, 950))
    readonly property real uiOp: Anim.out3(Anim.seg(tI, 1200, 1700)) * (1 - Anim.seg(tO, 0, 300))
    readonly property real cardLine: tO > 0 ? 1 - Anim.out3(Anim.seg(tO, 260, 520)) : Anim.out3(Anim.seg(tI, 1350, 1350 + 140))
    readonly property real cardWipe: tO > 0 ? 1 - Anim.out3(Anim.seg(tO, 0, 260)) : Anim.out3(Anim.seg(tI, 1420, 1420 + 320))
    // the hero accent line: 240 px under the wordmark -> across the screen -> gone; back at the end
    readonly property real heroLineW: tO > 0 ? 240 * Anim.out3(Anim.seg(tO, 900, 1150))
                                            : Anim.mix(240, width, Anim.out3(Anim.seg(tI, 250, 700)))
    readonly property real heroLineOp: tO > 0 ? Anim.seg(tO, 900, 1000) : 1 - Anim.seg(tI, 750, 1150)

    // hand-off geometry: emblem centred on the screen, wordmark 18 px below, line 20 px below that
    readonly property real ecx: width / 2
    readonly property real ecy: height / 2
    readonly property real slotSize: primary ? 36 : 54 * u
    readonly property real slotCx: primary ? card.x + 18 + 18 : center.x + center.width / 2
    readonly property real slotCy: primary ? card.y + 18 + 20 : center.y + 27 * u
    readonly property real embSize: Anim.mix(84, slotSize, glide)

    FocusScope {
        id: scope
        anchors.fill: parent
        focus: true
        opacity: Config.motion ? 1 : introFade.v
        Rectangle { visible: !win.started; width: 1; height: 1; x: win.swaps % 2; opacity: .01 }   // keeps frames coming
        QtObject { id: introFade; property real v: 0
                   Behavior on v { NumberAnimation { duration: Config.dur(Theme.motion.slow); easing.type: Theme.easeBase } } Component.onCompleted: v = 1 }

        // the shard wallpaper, assembling in behind everything
        Item {
            anchors.fill: parent
            visible: win.wallOp > .005
            opacity: win.wallOp
            scale: Anim.mix(1.05, 1, Anim.out3(Anim.seg(win.tI, 500, 1500)))
            WallpaperArt {
                anchors.fill: parent
                active: win.visible && win.wallOp > .005
                animate: Config.motion
            }
            Rectangle { anchors.fill: parent; color: Theme.light ? "#40ffffff" : "#8c000000" }
            Rectangle {
                anchors.fill: parent
                visible: !Theme.light
                gradient: Gradient {
                    GradientStop { position: 0; color: "#66000000" }
                    GradientStop { position: .35; color: "transparent" }
                    GradientStop { position: .65; color: "transparent" }
                    GradientStop { position: 1; color: "#80000000" }
                }
            }
        }

        // status tag, clock, wordmark corner: come in with the card
        Item {
            anchors.fill: parent
            opacity: win.uiOp
            visible: opacity > .005
            Row {
                x: 30; y: 26; spacing: 10
                Rectangle { width: 8; height: 8; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite; running: Config.motion && win.uiOp > .01
                                NumberAnimation { to: .25; duration: Config.dur(Theme.motion.ambient) } NumberAnimation { to: 1; duration: Config.dur(Theme.motion.ambient) } } }
                Text { text: "AWAITING LOGIN" + (win.ctl.demo ? " \u00b7 DEMO" : ""); color: Theme.dim
                       font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 3.3 }
            }
            Wordmark {
                anchors.right: parent.right; anchors.rightMargin: 30
                anchors.bottom: parent.bottom; anchors.bottomMargin: 28
            }
        }

        Column {
            id: center
            anchors.horizontalCenter: parent.horizontalCenter
            y: (win.primary ? Math.max(24, win.height * .5 - (height + 36 * win.u + card.height) * .5)
                            : Math.max(40, win.height * .5 - height * .5)) + (1 - win.uiOp) * 14
            opacity: win.uiOp
            visible: opacity > .005
            spacing: 8 * win.u
            Item { visible: !win.primary; width: 54 * win.u; height: 54 * win.u; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ((win.now.getHours() % 12) || 12) + ":" + win.p2(win.now.getMinutes()) + (win.now.getHours() < 12 ? " AM" : " PM")
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: 104 * win.u; font.letterSpacing: 6 * win.u
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.days[win.now.getDay()] + " \u00b7 " + win.now.getFullYear() + "." + win.p2(win.now.getMonth() + 1) + "." + win.p2(win.now.getDate())
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 15 * win.u; font.letterSpacing: 5
            }
        }

        // ---- login card (first screen only) ----
        HouseCard {
            id: card
            visible: win.primary
            width: 420 * win.u; height: panelCol.height + 36
            x: (win.width - width) / 2
            y: center.y + center.height + 36 * win.u - (1 - win.uiOp) * 14
            lineP: win.cardLine
            wipeP: win.cardWipe
            Connections { target: win.ctl; function onShakeTickChanged() { card.glitch(); } }

            Column {
                id: panelCol
                x: 18; y: 18; width: parent.width - 36
                spacing: 12

                // header slot: the emblem + wordmark glide here (they live in the hero layer above)
                Item { id: hdr; width: parent.width; height: 40 }

                // user: avatar + selector
                Row {
                    spacing: 10
                    width: parent.width
                    Item {
                        id: avatar
                        width: 40; height: 40
                        readonly property real c: 8
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: 1; strokeColor: Theme.accent; fillColor: Theme.panel2
                                startX: avatar.c + .5; startY: .5
                                PathLine { x: avatar.width - .5; y: .5 }
                                PathLine { x: avatar.width - .5; y: avatar.height - avatar.c - .5 }
                                PathLine { x: avatar.width - avatar.c - .5; y: avatar.height - .5 }
                                PathLine { x: .5; y: avatar.height - .5 }
                                PathLine { x: .5; y: avatar.c + .5 }
                                PathLine { x: avatar.c + .5; y: .5 }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: win.ctl.curUser ? win.ctl.curUser.display.charAt(0).toUpperCase() : "?"
                            color: Theme.accent
                            font.family: Theme.display; font.pixelSize: 18
                        }
                    }
                    Selector {
                        id: userSel
                        width: parent.width - 50
                        caption: "USER"
                        model: win.ctl.users.map(u => ({ label: u.display.toUpperCase(), sub: u.name }))
                        currentIndex: win.ctl.userIndex
                        onActivated: i => win.ctl.selectUser(i)
                    }
                }

                // chamfered password / prompt field
                FocusScope {
                    id: field
                    width: parent.width; height: 40
                    activeFocusOnTab: true
                    focus: true
                    readonly property real c: 8
                    readonly property bool bad: win.ctl.denied
                    readonly property bool canType: win.ctl.phase === "prompt"
                    Component.onCompleted: forceActiveFocus()

                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            win.ctl.submit(); e.accepted = true;
                        } else if (!canType) {
                            return;
                        } else if (e.key === Qt.Key_Backspace) {
                            win.ctl.typed(); win.ctl.input = win.ctl.input.slice(0, -1); e.accepted = true;
                        } else if (e.key === Qt.Key_Escape || (e.key === Qt.Key_U && (e.modifiers & Qt.ControlModifier))) {
                            win.ctl.typed(); win.ctl.input = ""; e.accepted = true;
                        } else if (e.text.length > 0 && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                                   && e.text.charCodeAt(0) >= 32 && e.text.charCodeAt(0) !== 127) {
                            win.ctl.typed(); win.ctl.input += e.text; e.accepted = true;
                        }
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: field.bad ? 2 : 1
                            strokeColor: field.bad ? Theme.bad : (field.activeFocus ? Theme.accent : Theme.lineStrong)
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
                    Text {
                        anchors.verticalCenter: parent.verticalCenter; x: 22
                        visible: win.ctl.input.length === 0 && field.canType
                        text: "ENTER " + win.ctl.promptText; color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 3
                    }
                    Text {
                        id: dots
                        anchors.verticalCenter: parent.verticalCenter; x: 14
                        width: parent.width - 28
                        elide: Text.ElideLeft
                        text: win.ctl.promptEcho ? win.ctl.input : "•".repeat(win.ctl.input.length)
                        color: Theme.fg
                        font.family: Theme.ui; font.pixelSize: 18; font.letterSpacing: win.ctl.promptEcho ? 1 : 4
                    }
                    Rectangle {
                        id: caret
                        property bool caretOn: true
                        visible: field.canType && caretOn
                        x: 14 + Math.min(dots.contentWidth, dots.width) + 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 18; color: Theme.accent
                        Timer { interval: 530; repeat: true; running: Config.motion; onTriggered: caret.caretOn = !caret.caretOn }
                    }
                }

                // status line
                Item {
                    width: parent.width; height: 16
                    QtObject { id: dotsAnim; property int n: 0; readonly property string suffix: ".".repeat(n) }
                    Timer { interval: 250; repeat: true; running: win.busy; onTriggered: dotsAnim.n = (dotsAnim.n + 1) % 4 }
                    Text {
                        anchors.left: parent.left
                        width: parent.width
                        elide: Text.ElideRight
                        text: win.ctl.denied ? "ACCESS DENIED"
                              : win.ctl.phase === "auth" ? "AUTHENTICATING" + dotsAnim.suffix
                              : win.ctl.phase === "launching" ? "STARTING SESSION" + dotsAnim.suffix
                              : win.ctl.message !== "" ? win.ctl.message
                              : win.ctl.phase === "prompt" ? "PRESS ENTER TO LOG IN"
                              : "CONNECTING" + dotsAnim.suffix
                        color: (win.ctl.denied || win.ctl.messageErr || win.ctl.phase === "error") ? Theme.bad
                               : (win.busy ? Theme.accent : Theme.dim)
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.6
                    }
                }

                Selector {
                    id: sessSel
                    width: parent.width
                    caption: "SESSION"
                    model: win.ctl.sessions.map(s => ({ label: s.name.toUpperCase(), sub: s.exec }))
                    currentIndex: win.ctl.sessionIndex
                    onActivated: i => win.ctl.sessionIndex = i
                }

                PowerRow {
                    id: power
                    onAction: name => win.ctl.power(name)
                }
            }
        }

        // ---- hero: the hand-off frame's emblem, wordmark and line ----
        Rectangle {
            width: win.heroLineW; height: 2
            x: (win.width - width) / 2
            y: wm.y0 + wm.implicitHeight + 20
            color: Theme.accent
            opacity: win.heroLineOp
            visible: win.heroLineW > .5 && opacity > .005
        }
        Emblem {
            x: Anim.mix(win.ecx, win.slotCx, win.glide) - size / 2
            y: Anim.mix(win.ecy, win.slotCy, win.glide) - size / 2
            size: win.embSize
            strokeWidth: Anim.mix(1.2, 1.8, win.glide)
            color: Theme.fg
        }
        Item {
            id: wm
            readonly property real y0: win.ecy + 42 + 18
            readonly property real s: Anim.mix(1, .55, win.glide)
            implicitWidth: wmText.implicitWidth; implicitHeight: wmText.implicitHeight
            width: implicitWidth; height: implicitHeight
            scale: win.primary ? s : 1
            transformOrigin: Item.TopLeft
            x: win.primary ? Anim.mix(win.ecx - width / 2, card.x + 18 + 36 + 12, win.glide) : win.ecx - width / 2
            y: win.primary ? Anim.mix(y0, card.y + 18 + (40 - implicitHeight * .55) / 2, win.glide) : y0
            opacity: win.primary ? 1 : 1 - Anim.seg(win.glide, 0, .5)
            visible: opacity > .005
            Text {
                id: wmText
                text: "[ ULTIMIT ]"
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: 30; font.letterSpacing: 6
            }
        }
    }
}
