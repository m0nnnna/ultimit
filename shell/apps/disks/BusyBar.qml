// BusyBar.qml - shows that a drive action is still running: what UDisks is doing (from `disks.py jobs`), the time
// so far, and a bar: real progress when the job reports it, otherwise a block sweeping back and forth.
import QtQuick
import "../.."

Column {
    id: root
    visible: Disks.busy !== ""
    spacing: 6

    readonly property var job: Disks.job
    readonly property bool known: job !== null && job.progress !== null

    Item {
        width: parent.width
        height: Math.max(what.implicitHeight, when.implicitHeight)
        Text {
            id: what
            anchors.left: parent.left
            width: parent.width - when.implicitWidth - 12
            elide: Text.ElideRight
            text: Disks.busyText
            color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
        }
        Text {
            id: when
            anchors.right: parent.right
            text: Disks.busyDetail
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
        }
    }
    Rectangle {
        id: track
        width: parent.width
        height: 6
        color: Theme.line
        clip: true
        Rectangle {
            visible: root.known
            height: parent.height
            width: root.known ? Math.max(2, parent.width * root.job.progress) : 0
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 400 } }
        }
        Rectangle {
            id: sweep
            visible: !root.known && root.visible
            height: parent.height
            width: parent.width * 0.25
            color: Theme.accent
            SequentialAnimation on x {
                running: sweep.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: track.width - sweep.width; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: track.width - sweep.width; to: 0; duration: 900; easing.type: Easing.InOutQuad }
            }
        }
    }
}
