// RailButton.qml - one launcher button in the left rail.
// Hover wash (panel-2), animated accent "on" bar, press feedback, keyboard focus outline.
// Animation durations go through Config.dur() so they collapse to 0 with motion off.
import QtQuick
import ".."

Item {
    id: root
    property string appId: "games"
    property string label: "GAMES"
    property bool on: false
    property bool missing: false   // no candidate app installed
    signal clicked()

    width: 72
    height: 62

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked();
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
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.appId
            color: Theme.fg
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
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: { root.focusReason = Qt.MouseFocusReason; root.forceActiveFocus(Qt.MouseFocusReason); }
        onClicked: root.clicked()
    }
    onActiveFocusChanged: focusReason = activeFocus ? (focusReason === Qt.MouseFocusReason ? focusReason : Qt.TabFocusReason) : Qt.OtherFocusReason
}
