// GreeterSurface.qml - one full-screen greeter window (per output): wallpaper art dimmed, emblem,
// big clock, [ ULTIMIT ] wordmark; the login panel is shown on the first screen only.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win
    required property var ctl
    color: Theme.bg1

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-greeter"
    WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool primary: screen !== null && Quickshell.screens.length > 0
                                    && screen.name === Quickshell.screens[0].name
    readonly property real u: Math.max(.7, Math.min(width, height) / 800)

    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property var days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    readonly property bool busy: ctl.phase === "auth" || ctl.phase === "launching" || ctl.phase === "starting" || ctl.phase === "loading"

    FocusScope {
        id: scope
        anchors.fill: parent
        focus: true

        WallpaperArt {
            anchors.fill: parent
            active: win.visible
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

        // top-left status tag
        Row {
            x: 30; y: 26; spacing: 10
            Rectangle { width: 8; height: 8; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite; running: Config.motion
                            NumberAnimation { to: .25; duration: 900 } NumberAnimation { to: 1; duration: 900 } } }
            Text { text: "AWAITING LOGIN" + (win.ctl.demo ? " · DEMO" : ""); color: Theme.dim
                   font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 3.3 }
        }

        Column {
            id: center
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.primary ? Math.max(24, win.height * .5 - (height + 36 * win.u + 290) * .5)
                           : Math.max(40, win.height * .5 - height * .5)
            spacing: 8 * win.u
            Emblem { anchors.horizontalCenter: parent.horizontalCenter; size: 54 * win.u; color: Theme.fg }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ((win.now.getHours() % 12) || 12) + ":" + win.p2(win.now.getMinutes()) + (win.now.getHours() < 12 ? " AM" : " PM")
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: 104 * win.u; font.letterSpacing: 6 * win.u
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.days[win.now.getDay()] + " · " + win.now.getFullYear() + "." + win.p2(win.now.getMonth() + 1) + "." + win.p2(win.now.getDate())
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 15 * win.u; font.letterSpacing: 5
            }
        }

        // ---- login panel (first screen only) ----
        Item {
            id: panel
            visible: win.primary
            width: 420 * win.u; height: panelCol.height + 36
            anchors.horizontalCenter: parent.horizontalCenter
            y: center.y + center.height + 36 * win.u
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
            Connections { target: win.ctl; function onShakeTickChanged() { shake.restart(); } }

            Rectangle {
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

        Wordmark {
            anchors.right: parent.right; anchors.rightMargin: 30
            anchors.bottom: parent.bottom; anchors.bottomMargin: 28
        }
    }
}
