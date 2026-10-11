// FlySlider.qml - flyout volume / brightness row: glyph button (click = mute) + chunky accent track + value.
import QtQuick
import "../.."
import ".."
import "../../apps/accessory"

Item {
    id: root
    property int value: 50
    property int from: 0
    property int to: 100
    property bool muted: false
    property string icon: "volume"      // StatusIcon kind: volume | mic | sun
    property bool big: false
    property bool muteable: true
    property string label: ""
    signal moved(int value)
    signal muteClicked()

    implicitHeight: big ? 44 : 34
    activeFocusOnTab: true

    readonly property real frac: (Math.max(from, Math.min(to, value)) - from) / (to - from)
    readonly property int level: muted || value <= 0 ? 0 : (value < 34 ? 1 : (value < 67 ? 2 : 3))
    function setFromX(x) {
        const f = Math.max(0, Math.min(1, (x - 6) / (track.width - 12)));
        const v = Math.round(from + f * (to - from));
        if (v !== root.value) root.moved(v);
    }
    Keys.onPressed: event => {
        const step = (event.modifiers & Qt.ShiftModifier) ? 5 : 1;
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) { root.moved(Math.max(from, value - step)); event.accepted = true; }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) { root.moved(Math.min(to, value + step)); event.accepted = true; }
        else if (event.key === Qt.Key_M && muteable) { root.muteClicked(); event.accepted = true; }
    }

    Item {   // glyph button
        id: btn
        width: root.big ? 40 : 30; height: width
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            anchors.fill: parent
            color: bm.containsMouse && root.muteable ? Theme.panel2 : "transparent"
            border.width: 1; border.color: root.activeFocus ? Theme.accent : (bm.containsMouse && root.muteable ? Theme.lineStrong : Theme.line)
        }
        StatusIcon {
            anchors.centerIn: parent
            kind: root.icon
            size: root.big ? 22 : 18
            level: root.level
            muted: root.muted
        }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; enabled: root.muteable
            cursorShape: Qt.PointingHandCursor; onClicked: root.muteClicked() }
    }
    Item {
        id: track
        anchors { left: btn.right; leftMargin: 10; right: valueText.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        height: 24
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: root.big ? 6 : 4
            color: Theme.panel2
            border.width: 1; border.color: Theme.line
            Rectangle { height: parent.height; width: root.frac * parent.width; color: root.muted ? Theme.dim : Theme.accent }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: 6 + root.frac * (track.width - 12) - width / 2
            width: drag.pressed ? 12 : 10; height: root.big ? 20 : 16
            color: root.muted ? Theme.dim : Theme.accent
            border.width: root.activeFocus ? 1 : 0; border.color: Theme.fg
            Behavior on width { NumberAnimation { duration: Config.dur(100); easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => { root.forceActiveFocus(Qt.MouseFocusReason); root.setFromX(mouse.x); }
            onPositionChanged: mouse => { if (pressed) root.setFromX(mouse.x); }
            onWheel: wheel => { root.moved(Math.max(root.from, Math.min(root.to, root.value + (wheel.angleDelta.y > 0 ? 5 : -5)))); }
        }
    }
    Text {
        id: valueText
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 34; horizontalAlignment: Text.AlignRight
        text: root.value + "%"
        color: root.muted ? Theme.dim : Theme.fg
        font.family: Theme.mono; font.pixelSize: root.big ? 13 : 11
    }
}
