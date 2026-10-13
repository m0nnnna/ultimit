// LevelMeter.qml - live input level of a PipeWire node: segmented bar, peak hold. Uses Quickshell's
// PwNodePeakMonitor; with BROADCAST_FAKE=1 (no real audio in the devbox) a synthetic signal is shown.
import QtQuick
import Quickshell.Services.Pipewire
import "../.."

Item {
    id: root
    property string nodeName: ""
    property bool active: true
    property real level: 0               // 0..1 on a -60..0 dB scale, with fast attack and slow decay
    property real hold: 0
    readonly property var node: nodeName === "" ? null : (Pipewire.nodes.values.find(n => n.name === nodeName) ?? null)
    implicitHeight: 28

    function feed(linear) {
        const db = linear > 0.00001 ? 20 * Math.log(linear) / Math.LN10 : -80;
        const v = Math.max(0, Math.min(1, (db + 60) / 60));
        if (v > level) level = v;
        if (v > hold) hold = v;
    }
    PwObjectTracker { objects: root.node ? [root.node] : [] }
    PwNodePeakMonitor {
        node: root.node && root.active && !Broadcast.fake ? root.node : null
        enabled: root.active && !Broadcast.fake
        onPeakChanged: root.feed(peak)
    }
    Timer {
        interval: 50; repeat: true; running: root.active
        property real t: 0
        onTriggered: {
            if (Broadcast.fake) { t += 0.05; root.feed(Math.max(0, 0.18 + 0.14 * Math.sin(t * 5.3) * Math.sin(t * 1.7) + 0.05 * Math.sin(t * 17))); }
            root.level = Math.max(0, root.level - 0.025);
            root.hold = Math.max(root.level, root.hold - 0.006);
        }
    }

    readonly property int segs: 40
    Row {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 14
        spacing: 2
        Repeater {
            model: root.segs
            delegate: Rectangle {
                required property int index
                readonly property real pos: (index + 1) / root.segs
                width: (bar.width - (root.segs - 1) * 2) / root.segs
                height: bar.height
                color: root.level >= pos - 0.0001 ? (pos > 0.9 ? Theme.bad : pos > 0.75 ? Theme.warn : Theme.accent)
                       : (root.hold >= pos - 0.013 && root.hold < pos + 0.013 ? Theme.fg : Theme.panel2)
                border.color: Theme.line; border.width: 1
            }
        }
    }
    Row {
        anchors { left: parent.left; right: parent.right; top: bar.bottom; topMargin: 4 }
        Repeater {
            model: ["-60", "-40", "-20", "-10", "0 dB"]
            delegate: Text {
                required property string modelData
                width: parent.width / 5
                text: modelData
                color: Theme.dim; opacity: 0.8
                font.family: Theme.mono; font.pixelSize: 9
            }
        }
    }
}
