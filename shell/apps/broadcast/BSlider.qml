// BSlider.qml - range slider (copy of accessory SliderField for BROADCAST): dim mono caps label + value, accent track.
import QtQuick
import "../.."

Item {
    id: root
    property string label: ""
    property int from: 0
    property int to: 100
    property int value: 50
    signal moved(int value)

    implicitHeight: 48
    activeFocusOnTab: true

    readonly property real frac: (Math.max(from, Math.min(to, value)) - from) / (to - from)
    function setFromX(x) {
        const f = Math.max(0, Math.min(1, (x - 6) / (track.width - 12)));
        const v = Math.round(from + f * (to - from));
        if (v !== root.value) root.moved(v);
    }
    Keys.onPressed: event => {
        const step = (event.modifiers & Qt.ShiftModifier) ? 5 : 1;
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) { root.moved(Math.max(from, value - step)); event.accepted = true; }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) { root.moved(Math.min(to, value + step)); event.accepted = true; }
    }

    Row {
        anchors.left: parent.left; anchors.right: parent.right; y: 0
        Text {
            width: parent.width - valueText.implicitWidth
            text: root.label.toUpperCase()
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 10
            font.letterSpacing: 1.8   // .18em
        }
        Text {
            id: valueText
            text: root.value
            color: Theme.fg
            font.family: Theme.mono; font.pixelSize: 10
        }
    }
    Item {
        id: track
        anchors.left: parent.left; anchors.right: parent.right
        y: 22; height: 22
        Rectangle {   // rail
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4
            color: Theme.panel2
            border.width: 1; border.color: Theme.line
            Rectangle { x: 0; y: 0; height: parent.height; width: root.frac * parent.width; color: Theme.accent }
        }
        Rectangle {   // handle
            id: handle
            anchors.verticalCenter: parent.verticalCenter
            x: 6 + root.frac * (track.width - 12) - width / 2
            width: drag.pressed ? 12 : 10; height: 16
            color: Theme.accent
            border.width: root.activeFocus ? 1 : 0
            border.color: Theme.fg
            Behavior on width { NumberAnimation { duration: Config.dur(100); easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => { root.forceActiveFocus(Qt.MouseFocusReason); root.setFromX(mouse.x); }
            onPositionChanged: mouse => { if (pressed) root.setFromX(mouse.x); }
        }
    }
}
