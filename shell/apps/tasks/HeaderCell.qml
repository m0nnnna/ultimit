// HeaderCell.qml - one column title of the process table: click to sort by it, click again to flip. `alignRight` aligns numbers.
import QtQuick
import "../.."

Item {
    id: root
    property string key: ""
    property string text: ""
    property bool alignRight: false
    property real leftPadding: 0
    property real rightPadding: 0
    readonly property bool on: Tasks.sortKey === key

    implicitHeight: 28
    Text {
        id: label
        anchors { left: root.alignRight ? undefined : parent.left; right: root.alignRight ? parent.right : undefined; verticalCenter: parent.verticalCenter }
        anchors.leftMargin: root.leftPadding; anchors.rightMargin: root.rightPadding
        text: root.text.toUpperCase() + (root.on ? (Tasks.sortDesc ? "  ▼" : "  ▲") : "")
        color: root.on ? Theme.accent : (m.containsMouse ? Theme.fg : Theme.dim)
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Tasks.sortBy(root.key) }
}
