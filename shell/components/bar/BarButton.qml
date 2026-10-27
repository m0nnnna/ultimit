// BarButton.qml - one clickable cell of the top bar: hover / press plate (animated), focus ring,
// a 500 ms hover tooltip below the bar (WindowPopups.qml via WindowUi.showBarTip), click and wheel
// signals, Accessible name. Bar items (<Name>Item.qml) put their content inside it.
import QtQuick
import "../.."
import ".."

Item {
    id: sb
    property string screenName: ""
    property string name: ""
    property string tip: ""
    property string fly: ""           // flyout this button opens ("" = none)
    property bool lit: false          // accent plate (a popup this button opened is up)
    readonly property bool flyLit: FlyoutState.open && FlyoutState.kind === sb.fly && sb.fly !== ""
    default property alias content: slot.data
    signal clicked(int button)
    signal wheeled(int delta)
    signal hovered()

    height: Config.barHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: sb.name
    Accessible.description: sb.tip
    Accessible.onPressAction: sb.clicked(Qt.LeftButton)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { sb.clicked(Qt.LeftButton); event.accepted = true; }
    }
    // Screen-global x of the button's centre (the bar spans the output from x = 0).
    function centerX() { return sb.mapToItem(null, sb.width / 2, 0).x; }
    function openFly(kind) {
        FlyoutState.setAnchor(kind, sb.centerX());
        FlyoutState.toggle(kind, sb.screenName);
    }

    Rectangle {
        anchors.fill: parent
        color: m.pressed ? Theme.press : ((m.containsMouse || sb.lit || sb.flyLit) ? Theme.hover : Theme.clear(Theme.hover))
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 1
        color: "transparent"; border.width: 1; border.color: Theme.accent
        visible: sb.activeFocus
    }
    Item { id: slot; anchors.fill: parent }
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onEntered: { tipTimer.restart(); sb.hovered(); }
        onExited: { tipTimer.stop(); WindowUi.hideTip(); }
        onClicked: mouse => { tipTimer.stop(); WindowUi.hideTip(); sb.clicked(mouse.button); }
        onWheel: wheel => { WindowUi.hideTip(); sb.wheeled(wheel.angleDelta.y); }
    }
    Timer {
        id: tipTimer; interval: 500
        onTriggered: if (sb.tip !== "") WindowUi.showBarTip(sb.tip, sb.centerX(), sb.screenName)
    }
    // keep a visible tip current while hovered (e.g. volume after a scroll)
    onTipChanged: if (m.containsMouse && WindowUi.tipText !== "") WindowUi.showBarTip(sb.tip, sb.centerX(), sb.screenName)
}
