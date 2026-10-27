// PartBar.qml - the drive laid out as a bar: every partition in its own colour (used part shaded), unallocated gaps
// hatched and dim. Widths follow sizes but never get thinner than a clickable sliver. Click a partition to select it.
import QtQuick
import "../.."

Item {
    id: root
    required property var drive
    property string current: ""
    property real currentFree: -1
    signal picked(string dev)
    signal pickedFree(real offset)

    implicitHeight: 54

    readonly property var segs: {
        const parts = drive.partitions;
        const total = Math.max(1, drive.size);
        const minW = 14, gap = 2;
        const avail = Math.max(1, width - gap * (parts.length - 1));
        // First pass: proportional; then bump slivers up to minW and take the difference from the biggest.
        const w = parts.map(p => Math.max(minW, avail * p.size / total));
        let sum = w.reduce((a, b) => a + b, 0);
        if (sum > avail) {
            let over = sum - avail, guard = 0;
            while (over > 0.5 && guard++ < 20) {
                let big = 0;
                for (let i = 1; i < w.length; i++) if (w[i] > w[big]) big = i;
                const take = Math.min(over, Math.max(0, w[big] - minW));
                if (take <= 0) break;
                w[big] -= take; over -= take;
            }
        }
        let x = 0;
        return parts.map((p, i) => { const s = { p: p, x: x, w: w[i], i: i }; x += w[i] + gap; return s; });
    }

    function colorFor(i, p) {
        if (p.kind === "free") return Theme.dim;
        const hue = (Theme.accent.hslHue >= 0 ? Theme.accent.hslHue : 0.55);
        return Qt.hsla((hue + i * 0.13) % 1, 0.5, 0.52, 1);
    }

    Repeater {
        model: root.segs
        delegate: Item {
            id: seg
            required property var modelData
            readonly property var p: modelData.p
            readonly property bool free: p.kind === "free"
            readonly property bool on: free ? root.currentFree === p.offset : root.current === p.device
            readonly property color base: root.colorFor(modelData.i, p)
            x: modelData.x; width: Math.max(1, modelData.w); height: root.height

            Rectangle {
                anchors.fill: parent
                color: seg.free ? "transparent" : Qt.rgba(seg.base.r, seg.base.g, seg.base.b, 0.22)
                border.color: seg.on ? Theme.fg : seg.free ? Theme.dim : Qt.rgba(seg.base.r, seg.base.g, seg.base.b, 0.9)
                Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                border.width: seg.on ? 2 : 1
            }
            // used part
            Rectangle {
                visible: !seg.free && seg.p.used !== null && seg.p.fs_size > 0
                x: 1; y: 1
                height: parent.height - 2
                width: Math.max(0, (parent.width - 2) * Math.min(1, (seg.p.used || 0) / Math.max(1, seg.p.fs_size || seg.p.size)))
                color: Qt.rgba(seg.base.r, seg.base.g, seg.base.b, 0.55)
            }
            // hatching for unallocated space
            Canvas {
                anchors.fill: parent
                visible: seg.free
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d");
                    c.clearRect(0, 0, width, height);
                    c.strokeStyle = Qt.rgba(Theme.dim.r, Theme.dim.g, Theme.dim.b, 0.35);
                    c.lineWidth = 1;
                    c.beginPath();
                    for (let x = -height; x < width; x += 7) { c.moveTo(x, height); c.lineTo(x + height, 0); }
                    c.stroke();
                }
            }
            Text {
                visible: seg.width > 60
                anchors { left: parent.left; leftMargin: 7; top: parent.top; topMargin: 6; right: parent.right; rightMargin: 4 }
                elide: Text.ElideRight
                text: seg.free ? "Unallocated" : (seg.p.label !== "" ? seg.p.label : seg.p.fs_name || seg.p.type || ("Partition " + seg.p.number))
                color: Theme.fg
                font.family: Theme.ui; font.pixelSize: Theme.type.label; font.weight: Font.DemiBold
            }
            Text {
                visible: seg.width > 60
                anchors { left: parent.left; leftMargin: 7; bottom: parent.bottom; bottomMargin: 6; right: parent.right; rightMargin: 4 }
                elide: Text.ElideRight
                text: Disks.fmt(seg.p.size)
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: Theme.type.label
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: seg.free ? root.pickedFree(seg.p.offset) : root.picked(seg.p.device)
            }
        }
    }
}
