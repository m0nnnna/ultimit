// DriveRow.qml - one drive in the left list: kind chip (NVMe / SSD / HDD / USB), model, size, a hint when it holds the system.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    required property var drive
    readonly property bool on: Disks.drive && Disks.drive.id === drive.id
    signal picked()

    implicitHeight: 62
    color: on ? Theme.selection : (m.containsMouse ? Theme.hover : Theme.field)
    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }

    GChip {
        id: chip
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 48
        text: Disks.kindText(root.drive)
        tone: root.on ? Theme.accent : Theme.dim
    }
    Column {
        anchors { left: chip.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 3
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.drive.name
            color: Theme.fg
            font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.body
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: Disks.fmt(root.drive.size) + (root.drive.is_system ? " · system" : root.drive.removable ? " · removable" : "")
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: Theme.type.label
        }
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.picked() }
}
