// Spark.qml - a small sparkline: a line over a faint fill, from `values` (oldest first).
// Scaled to 0..max (max 0: to the largest value, at least `floor`, so an idle network is a flat line
// instead of noise). Redrawn only when `values` changes, i.e. once per sample.
//   Spark { width: 90; height: 16; values: SysStats.cpuHist; max: 100 }
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root

    property var values: []
    property real max: 100
    property real floor: 1
    property int slots: 40
    property color color: Theme.accent

    readonly property real limit: root.max > 0 ? root.max : Math.max(root.floor, Math.max.apply(null, root.values.length ? root.values : [0]))
    readonly property var pts: {
        const v = root.values, n = v.length, out = [];
        const step = root.width / Math.max(1, root.slots - 1);
        const x0 = root.width - (n - 1) * step;           // newest sample at the right edge
        for (let i = 0; i < n; i++)
            out.push(Qt.point(x0 + i * step, root.height - 1 - Math.min(1, Math.max(0, v[i] / root.limit)) * (root.height - 2)));
        return out;
    }
    readonly property var area: root.pts.length > 1
        ? [Qt.point(root.pts[0].x, root.height)].concat(root.pts, [Qt.point(root.pts[root.pts.length - 1].x, root.height)]) : []

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.14)
            PathPolyline { path: root.area }
        }
        ShapePath {
            strokeWidth: 1; strokeColor: root.color; fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.pts }
        }
    }
}
