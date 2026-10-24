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
    property bool missing: false   // no candidate app installed
    property int badge: 0          // unread-style count tag on the icon (MAILER); hidden at 0
    // Pinned desktop apps: themed icon (URL from Icons.path) drawn inside a chamfered frame like the WINDOWS list;
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
    Behavior on spinSpeed { NumberAnimation { duration: Config.dur(400); easing.type: Easing.OutCubic } }
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
    signal rightClicked(real globalY)   // right click / Menu key; y is the button centre in rail coordinates

    width: 72
    height: 62

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

    // hover wash
    Rectangle {
        anchors.fill: parent
        color: Theme.panel2
        opacity: mouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(150); easing.type: Easing.OutCubic } }
    }
    // press: a second wash layer so pressed reads stronger than hover (washes stack)
    Rectangle {
        anchors.fill: parent
        color: Theme.panel2
        opacity: root.pressed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(90); easing.type: Easing.OutCubic } }
    }
    // Accent bar: the mockup draws it 6px outside the button, i.e. flush to the rail edge.
    // Grows from the vertical center when `on`.
    Rectangle {
        x: -6
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: root.on ? parent.height - 24 : 0
        color: Theme.accent
        visible: height > 0
        Behavior on height { NumberAnimation { duration: Config.dur(220); easing.type: Easing.OutCubic } }
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
        spacing: 6
        opacity: root.missing ? 0.45 : 1
        scale: root.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
        Icon {
            id: coreIcon
            visible: !root.framed
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.appId
            color: Theme.fg
            transform: Rotation {
                axis { x: 0; y: 1; z: 0 }
                origin.x: coreIcon.width / 2; origin.y: coreIcon.height / 2
                angle: Config.motion && Config.railSpin !== "off" ? root.spinAngle : 0
            }
        }
        Item {   // pinned desktop app: themed icon in the Altimit chamfer frame (same cut as WindowList)
            id: frame
            visible: root.framed
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30; height: 30
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 1
                    strokeColor: root.on ? Theme.accent : Theme.lineStrong
                    fillColor: root.on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10) : "transparent"
                    joinStyle: ShapePath.MiterJoin
                    startX: 0.5; startY: 0.5
                    PathLine { x: 24.5; y: 0.5 }
                    PathLine { x: 29.5; y: 5.5 }
                    PathLine { x: 29.5; y: 29.5 }
                    PathLine { x: 5.5; y: 29.5 }
                    PathLine { x: 0.5; y: 24.5 }
                    PathLine { x: 0.5; y: 0.5 }
                }
            }
            Image {
                id: img
                anchors.centerIn: parent
                width: 20; height: 20
                visible: root.iconSrc !== "" && status !== Image.Error
                source: root.iconSrc
                sourceSize: Qt.size(40, 40)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Text {
                anchors.centerIn: parent
                visible: root.iconSrc === "" || img.status === Image.Error
                text: root.letter
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: 12
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.fg
            font.family: Theme.ui
            font.weight: Font.DemiBold
            font.pixelSize: 9
            font.letterSpacing: 1.62   // .18em
        }
        Text {   // tiny "not installed" state
            visible: root.missing
            anchors.horizontalCenter: parent.horizontalCenter
            text: "NOT INSTALLED"
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 6; font.letterSpacing: 0.6
        }
    }
    // Count tag: tiny chamfered accent tag at the icon's top-right (hidden at 0).
    Item {
        id: tag
        visible: root.badge > 0 && !root.framed
        x: content.x + coreIcon.x + coreIcon.width - 6
        y: content.y + coreIcon.y - 7
        width: Math.max(15, tagText.implicitWidth + 8)
        height: 14
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
            font.pixelSize: 9
            font.letterSpacing: 0.4
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: { root.focusReason = Qt.MouseFocusReason; root.forceActiveFocus(Qt.MouseFocusReason); }
        onClicked: mouseEvent => {
            if (mouseEvent.button === Qt.RightButton) root.rightClicked(root.mapToGlobal(0, root.height / 2).y);
            else root.clicked();
        }
    }
    onActiveFocusChanged: focusReason = activeFocus ? (focusReason === Qt.MouseFocusReason ? focusReason : Qt.TabFocusReason) : Qt.OtherFocusReason
}
