// GradArt.qml - generated fallback art: the mockup's radial-gradient tile.
import QtQuick

Canvas {
    id: root
    property var stops: ["#888", "#444", "#111"]
    onStopsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    function css(c) {
        if (typeof c === "string") return c;
        if (!c) return "#000";
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")";
    }
    onPaint: {
        const c = getContext("2d");
        c.clearRect(0, 0, width, height);
        const x = width * 0.3, y = height * 0.2;
        const r = Math.max(width * 1.2, height * 0.9);
        const g = c.createRadialGradient(x, y, 0, x, y, r);
        g.addColorStop(0, css(stops[0]));
        g.addColorStop(0.45, css(stops[1]));
        g.addColorStop(1, css(stops[2]));
        c.fillStyle = g;
        c.fillRect(0, 0, width, height);
    }
}
