// Graph.qml - a 60 second history line with a soft fill, newest on the right. `values` (and optionally `values2`) are
// the samples, one per second. max > 0 fixes the top of the scale (percent graphs); max = 0 scales to the biggest
// sample, rounded up, but never below `floor` (rates).
import QtQuick
import "../.."

Item {
    id: root
    property var values: []
    property var values2: []
    property real max: 100
    property real floor: 1
    property color color: Theme.accent
    property color color2: Theme.warn
    readonly property int slots: Tasks.histLen
    // the top of the scale actually drawn
    readonly property real scaleTop: {
        if (max > 0) return max;
        let m = floor;
        for (const v of values) if (v > m) m = v;
        for (const v of values2) if (v > m) m = v;
        const e = Math.pow(2, Math.ceil(Math.log(m) / Math.LN2));
        return e;
    }

    onValuesChanged: canvas.requestPaint()
    onValues2Changed: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onScaleTopChanged: canvas.requestPaint()

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28); border.color: Theme.line; border.width: 1 }
    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 1
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height;
            ctx.clearRect(0, 0, w, h);
            ctx.lineWidth = 1;
            ctx.strokeStyle = Qt.rgba(Theme.line.r, Theme.line.g, Theme.line.b, Theme.line.a);
            for (let i = 1; i < 4; i++) {
                const y = Math.round(h * i / 4) + 0.5;
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
            }
            const draw = (vals, col, fill) => {
                const n = vals.length;
                if (n < 2) return;
                const px = i => w - (n - 1 - i) * w / (root.slots - 1);
                const py = v => h - 1 - Math.max(0, Math.min(1, v / root.scaleTop)) * (h - 3);
                ctx.beginPath();
                ctx.moveTo(px(0), py(vals[0]));
                for (let i = 1; i < n; i++) ctx.lineTo(px(i), py(vals[i]));
                ctx.strokeStyle = col;
                ctx.lineWidth = 1.5;
                ctx.stroke();
                if (!fill) return;
                ctx.lineTo(px(n - 1), h);
                ctx.lineTo(px(0), h);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.16);
                ctx.fill();
            };
            draw(root.values, root.color, true);
            draw(root.values2, root.color2, false);
        }
    }
}
