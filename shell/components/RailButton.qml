// RailButton.qml - one launcher button in the left rail.
// Hover wash (panel-2), animated accent "on" bar, press feedback, keyboard focus outline.
// Animation durations go through Config.dur() so they collapse to 0 with motion off.
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root
    property string appId: "games"
    property string label: "GAMES"
    property bool on: false
    property bool focused: false   // its window is the active one: the rail's sliding marker sits here instead of the bar
    property bool minimized: false // every window of it is minimized: the bar is dimmed
    property int count: 0          // windows it owns; a pip shows from 2
    readonly property bool hovered: mouse.containsMouse
    property bool missing: false   // no candidate app installed
    property int badge: 0          // unread-style count tag on the icon (MAILER); hidden at 0
    // Pinned desktop apps: themed icon (URL from Icons.path) drawn inside an IconBadge (hex or chamfer, like the launcher and Alt-Tab);
    // `letter` is the fallback when it does not resolve. Built-ins leave `iconSrc` and `letter` empty.
    property string iconSrc: ""
    property string letter: ""
    readonly property bool framed: letter !== ""
    // Altimit-style turntable: the core icons turn slowly on their vertical
    // axis, faster under the pointer (Config.railSpin: always | hover | off).
    property real phase: 0
    property real spinAngle: phase
    readonly property bool spinning: !framed && Config.motion && Config.railSpin !== "off"
        && (Config.railSpin === "always" || mouse.containsMouse || spinAngle % 360 !== 0)
    property bool covered: false   // a fullscreen window hides the rail: hold the spin
    property real spinSpeed: mouse.containsMouse ? 200 : 36   // degrees per second
    Behavior on spinSpeed { NumberAnimation { duration: Config.dur(Theme.motion.skin); easing.type: Theme.easeBase } }
    // 30 steps a second on the rail's shared clock (Config.railTick): smooth enough, and the rail
    // repaints once per step for all icons instead of once per icon.
    readonly property bool ticking: root.spinning && root.visible && !root.covered && !Config.desktopPaused
    onTickingChanged: Config.railSpinners += ticking ? 1 : -1
    Component.onCompleted: if (ticking) Config.railSpinners++
    Component.onDestruction: if (ticking) Config.railSpinners--
    Connections {
        target: Config
        enabled: root.ticking
        function onRailTickChanged() {
            let a = root.spinAngle + root.spinSpeed * 33 / 1000;
            // In hover-only mode, settle facing front once the pointer leaves.
            if (Config.railSpin === "hover" && !mouse.containsMouse && a >= 360)
                a = 0;
            root.spinAngle = a % 360;
        }
    }
    signal clicked()
    signal middleClicked()             // new window
    signal rightClicked(real globalY)   // right click / Menu key; y is the button centre in rail coordinates

    width: 76
    height: 64

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
            event.accepted = true;
        } else if (event.key === Qt.Key_Menu) {
            root.rightClicked(root.mapToGlobal(0, root.height / 2).y);
            event.accepted = true;
        }
    }

    readonly property bool pressed: mouse.pressed

    // hover / press wash (tokens: hover, press), faded in and out
    Rectangle {
        anchors.fill: parent
        color: root.pressed ? Theme.press : (mouse.containsMouse ? Theme.hover : Theme.clear(Theme.hover))
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    }
    // Accent bar: the mockup draws it 6px outside the button, i.e. flush to the rail edge.
    // Grows from the vertical center when `on`.
    Rectangle {
        x: -6
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: root.on && !root.focused ? parent.height - (root.minimized ? 36 : 24) : 0
        color: root.minimized ? Theme.dim : Theme.accent
        visible: height > 0
        Behavior on height { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    }
    // keyboard focus outline
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: "transparent"
        border.width: 1
        border.color: Theme.accent
        visible: root.activeFocus && root.focusReason !== Qt.MouseFocusReason
    }
    property int focusReason: Qt.OtherFocusReason

    Column {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space(1)
        opacity: root.missing ? 0.45 : (root.minimized ? 0.6 : 1)
        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        scale: root.pressed ? Theme.pressScale : 1
        Behavior on scale { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        Icon {
            id: coreIcon
            visible: !root.framed
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.appId
            size: Theme.icon.md
            color: Theme.fg
            transform: Rotation {
                axis { x: 0; y: 1; z: 0 }
                origin.x: coreIcon.width / 2; origin.y: coreIcon.height / 2
                angle: Config.motion && Config.railSpin !== "off" ? root.spinAngle : 0
            }
        }
        Item {   // pinned desktop app: themed icon in the IconBadge
            id: frame
            visible: root.framed
            anchors.horizontalCenter: parent.horizontalCenter
            width: 28; height: 28
            IconBadge {
                anchors.fill: parent
                size: 28
                letter: root.letter
                iconSrc: root.iconSrc
                active: root.on
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: root.on ? Theme.accent : Theme.fg
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            font.family: Theme.ui
            font.weight: Font.DemiBold
            font.pixelSize: Theme.type.label
            font.letterSpacing: 1.0
        }
        Text {   // tiny "not installed" state
            visible: root.missing
            anchors.horizontalCenter: parent.horizontalCenter
            text: "MISSING"
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.4
        }
    }
    // Count tag: tiny chamfered accent tag at the icon's top-right (hidden at 0).
    Item {
        id: tag
        readonly property bool want: root.badge > 0 && !root.framed
        opacity: want ? 1 : 0
        scale: want ? 1 : Theme.showScale
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        Behavior on scale { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        x: content.x + coreIcon.x + coreIcon.width - 8
        y: content.y + coreIcon.y - 7
        width: Math.max(16, tagText.implicitWidth + 8)
        height: 16
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1
                strokeColor: Theme.accent
                fillColor: Theme.light ? Qt.rgba(1, 1, 1, 0.94) : Qt.rgba(0.02, 0.025, 0.03, 0.94)
                joinStyle: ShapePath.MiterJoin
                startX: 0.5; startY: 0.5
                PathLine { x: tag.width - 3.5; y: 0.5 }
                PathLine { x: tag.width - 0.5; y: 3.5 }
                PathLine { x: tag.width - 0.5; y: tag.height - 0.5 }
                PathLine { x: 3.5; y: tag.height - 0.5 }
                PathLine { x: 0.5; y: tag.height - 3.5 }
                PathLine { x: 0.5; y: 0.5 }
            }
        }
        Text {
            id: tagText
            anchors.centerIn: parent
            text: root.badge > 99 ? "99+" : String(root.badge)
            color: Theme.accent
            font.family: Theme.mono
            font.pixelSize: Theme.type.label
            font.letterSpacing: 0.4
        }
    }
    // Window count pip (2+ windows): top-right corner, mono label in an accent outline.
    Rectangle {
        readonly property bool want: root.count > 1
        opacity: want ? 1 : 0
        scale: want ? 1 : Theme.showScale
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        Behavior on scale { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        x: root.width - width - 4
        y: 4
        width: Math.max(14, pipText.implicitWidth + 6); height: 14
        color: Theme.light ? Qt.rgba(1, 1, 1, 0.94) : Qt.rgba(0.02, 0.025, 0.03, 0.94)
        border.width: 1; border.color: root.minimized ? Theme.dim : Theme.accent
        Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        Text {
            id: pipText
            anchors.centerIn: parent
            text: root.count > 9 ? "9+" : String(root.count)
            color: root.minimized ? Theme.dim : Theme.accent
            font.family: Theme.mono; font.pixelSize: Theme.type.label
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: { root.focusReason = Qt.MouseFocusReason; root.forceActiveFocus(Qt.MouseFocusReason); }
        onClicked: mouseEvent => {
            if (mouseEvent.button === Qt.RightButton) root.rightClicked(root.mapToGlobal(0, root.height / 2).y);
            else if (mouseEvent.button === Qt.MiddleButton) root.middleClicked();
            else root.clicked();
        }
    }
    onActiveFocusChanged: focusReason = activeFocus ? (focusReason === Qt.MouseFocusReason ? focusReason : Qt.TabFocusReason) : Qt.OtherFocusReason
}
