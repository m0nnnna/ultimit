// SegBar.qml - a segmented level bar (like a HUD gauge): `segments` small cells, the first
// round(value/max * segments) lit in the accent, the rest a faint outline. Warm colours above `warnAt`.
//   SegBar { width: 90; height: 8; value: SysStats.mem }
import QtQuick
import ".."

Item {
    id: root

    property real value: 0
    property real max: 100
    property int segments: 12
    property real warnAt: 0.85
    property color color: Theme.accent

    readonly property real frac: Math.max(0, Math.min(1, root.value / root.max))
    readonly property int lit: Math.round(root.frac * root.segments)

    Row {
        spacing: 2
        Repeater {
            model: root.segments
            delegate: Rectangle {
                required property int index
                width: (root.width - (root.segments - 1) * 2) / root.segments
                height: root.height
                color: index < root.lit ? (root.frac >= root.warnAt ? Theme.warn : root.color) : "transparent"
                border.width: 1
                border.color: index < root.lit ? color : Theme.line
            }
        }
    }
}
