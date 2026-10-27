// GlowFrame.qml - soft accent glow along a panel's edges, optionally with a slow light travelling round.
// Drop it inside a bordered panel (anchors.fill: parent, before the content so the text stays on top).
// The glow is three thin strokes of falling alpha on the border: no offscreen buffer, no shader, and
// nothing is redrawn while it sits still. The travelling light is a dashed stroke whose offset
// follows Fx.glowPhase (one shared 25 Hz clock that runs only while a travelling frame is visible,
// motion is on and no fullscreen window is up); with Config.edgeGlow "still" or reduced motion
// the frame simply glows. Config.edgeGlow "off" draws nothing.
//   cut    chamfer at the top-left and bottom-right corners (0: square, like the glass panels)
//   edges  "frame" all round | "right" the right edge only (the rail) | "bottom" the bottom edge only (the top bar)
//   travel false: never moves (the rail, lists of cards)
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root

    property color color: Theme.accent
    property real cut: 0
    property string edges: "frame"
    property bool travel: true
    property real strength: 1

    readonly property bool lit: Config.edgeGlow !== "off" && visible && width > 16 && height > 16
    readonly property bool moving: root.travel && root.lit && Fx.travelOn
    onMovingChanged: Fx.glowUsers += root.moving ? 1 : -1
    Component.onCompleted: if (root.moving) Fx.glowUsers++
    Component.onDestruction: if (root.moving) Fx.glowUsers--

    function pt(x, y) { return Qt.point(x, y); }
    readonly property var pts: {
        const w = root.width - 0.5, h = root.height - 0.5, i = 0.5, c = root.cut;
        if (root.edges === "right") return [root.pt(w, 0), root.pt(w, root.height)];
        if (root.edges === "bottom") return [root.pt(0, h), root.pt(root.width, h)];
        if (c > 0) return [root.pt(i + c, i), root.pt(w, i), root.pt(w, h - c), root.pt(w - c, h), root.pt(i, h), root.pt(i, i + c), root.pt(i + c, i)];
        return [root.pt(i, i), root.pt(w, i), root.pt(w, h), root.pt(i, h), root.pt(i, i)];
    }
    readonly property real perim: {
        let n = 0;
        for (let k = 1; k < root.pts.length; k++) n += Math.hypot(root.pts[k].x - root.pts[k - 1].x, root.pts[k].y - root.pts[k - 1].y);
        return Math.max(1, n);
    }
    readonly property real lightLen: Math.min(root.perim * 0.14, 110)

    function tone(a) { return Qt.rgba(root.color.r, root.color.g, root.color.b, a * root.strength); }

    Shape {   // the standing glow
        anchors.fill: parent
        visible: root.lit
        preferredRendererType: Shape.CurveRenderer
        ShapePath { strokeWidth: 9; strokeColor: root.tone(0.035); fillColor: "transparent"; joinStyle: ShapePath.MiterJoin; PathPolyline { path: root.pts } }
        ShapePath { strokeWidth: 5; strokeColor: root.tone(0.07); fillColor: "transparent"; joinStyle: ShapePath.MiterJoin; PathPolyline { path: root.pts } }
        ShapePath { strokeWidth: 2; strokeColor: root.tone(0.2); fillColor: "transparent"; joinStyle: ShapePath.MiterJoin; PathPolyline { path: root.pts } }
    }

    Shape {   // the light going round: a dash that slides along the same path
        anchors.fill: parent
        visible: root.moving
        ShapePath {
            readonly property real w: 6
            strokeWidth: w; strokeColor: root.tone(0.16); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [root.lightLen / w, Math.max(1, root.perim - root.lightLen) / w]
            dashOffset: -Fx.glowPhase * root.perim / w
            PathPolyline { path: root.pts }
        }
        ShapePath {
            readonly property real w: 2
            strokeWidth: w; strokeColor: root.tone(0.7); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [root.lightLen * 0.5 / w, Math.max(1, root.perim - root.lightLen * 0.5) / w]
            dashOffset: -Fx.glowPhase * root.perim / w - root.lightLen * 0.25 / w
            PathPolyline { path: root.pts }
        }
    }
}
