// GSlider.qml - a plain themed slider: value between from and to, moved(value) while dragging.
import QtQuick
import "../.."

Item {
    id: root
    property real from: 0
    property real to: 1
    property real value: 0
    signal moved(real value)

    implicitHeight: 24
    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    Rectangle { id: track; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter } height: 6; color: Theme.panel2; border.color: Theme.line }
    Rectangle { anchors { left: track.left; verticalCenter: track.verticalCenter } width: track.width * root.frac; height: 6; color: Theme.accent }
    Rectangle {
        x: (root.width - width) * root.frac; width: 12; height: 20; anchors.verticalCenter: parent.verticalCenter
        color: Theme.bg1; border.color: Theme.accent; border.width: 2
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.to > root.from
        cursorShape: Qt.PointingHandCursor
        function set(x) { root.moved(root.from + (root.to - root.from) * Math.max(0, Math.min(1, (x - 6) / Math.max(1, root.width - 12)))); }
        onPressed: mouse => set(mouse.x)
        onPositionChanged: mouse => { if (pressed) set(mouse.x); }
    }
}
