// Emblem.qml - hex-aperture emblem, ported from emblem() in the mockup:
// outer hexagon, six blades running to an inner (rotated) hexagon.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property color color: "white"
    property real strokeWidth: 1.6
    property real size: 40

    implicitWidth: size
    implicitHeight: size

    // Point i on a hexagon of radius `rad`, rotated by `off` (radians), 48x48 box.
    function pt(rad, i, off) {
        const a = i * Math.PI / 3 - Math.PI / 2 + off;
        return [24 + rad * Math.cos(a), 24 + rad * Math.sin(a)];
    }
    function hexPath(rad, off) {
        let d = "";
        for (let i = 0; i < 6; i++) {
            const p = pt(rad, i, off);
            d += (i ? "L" : "M") + p[0].toFixed(2) + " " + p[1].toFixed(2);
        }
        return d + "Z";
    }
    function bladePath() {
        let d = "";
        for (let i = 0; i < 6; i++) {
            const o = pt(20, i, 0), n = pt(8.5, (i + 1) % 6, .35);
            d += "M" + o[0].toFixed(2) + " " + o[1].toFixed(2) + "L" + n[0].toFixed(2) + " " + n[1].toFixed(2);
        }
        return d;
    }

    Shape {
        width: 48; height: 48
        scale: root.size / 48
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"; strokeColor: root.color; strokeWidth: root.strokeWidth
            PathSvg { path: root.hexPath(20, 0) }
        }
        ShapePath {
            fillColor: "transparent"; strokeColor: root.color; strokeWidth: root.strokeWidth
            PathSvg { path: root.bladePath() }
        }
        ShapePath {
            fillColor: "transparent"; strokeColor: root.color; strokeWidth: root.strokeWidth
            PathSvg { path: root.hexPath(8.5, .35) }
        }
    }
}
