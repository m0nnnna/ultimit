// StatusIcon.qml - thin-line status glyphs for the tray cluster (network, Bluetooth, volume,
// battery, bell, bolt). Same drawing rules as Icon.qml: 24x24 grid, chamfered mitred corners, a
// constant 1.5 px stroke on screen (the grid stroke is scaled up to compensate for `size`).
// Every colour comes from Theme, so the glyphs follow the skin. Up to four layered paths per
// state: main (fg or `tone`), dim (inactive parts), a highlight/alert, and an optional fill.
//
//   kind: "wifi"     level 0..3 lit arcs; `on` false = disconnected (dim arcs + red slash)
//         "eth"      wired plug
//         "airplane" radio off
//         "bt"       state "off" | "on" | "connected" (accent)
//         "volume"   level 0..3 waves, `muted` = dim speaker + X
//         "battery"  pct 0..100 fill in `tone`
//         "bolt"     charging bolt (colour = `tone`)
//         "bell"     `muted` = slashed (do-not-disturb)
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root
    property string kind: "wifi"
    property real size: 18
    property real strokeWidth: 1.5 * 24 / size     // 1.5 px on screen
    property color tone: Theme.fg
    property int level: 0
    property bool on: true
    property bool muted: false
    property int pct: 100
    property string state: "on"

    implicitWidth: size
    implicitHeight: size

    // Each spec entry: [path, colour, filled]
    readonly property var spec: {
        const fg = root.tone, dim = Theme.dim, faint = Qt.alpha(Theme.dim, 0.4);   // faint = unlit parts
        switch (root.kind) {
        case "wifi": {
            const arcs = ["M9 17.5l3-2 3 2", "M5.5 13.5l6.5-4 6.5 4", "M2 9.5l10-6 10 6"];
            if (!root.on) return [[arcs.join(""), dim, false], ["M4 4l16 16", Theme.bad, false]];
            const lit = [], off = [];
            for (let i = 0; i < 3; i++) (i < root.level ? lit : off).push(arcs[i]);
            return [[lit.join(""), fg, false], [off.join(""), faint, false], ["M12 20.5h.01", fg, false]];
        }
        case "eth":
            return [["M5 5h14v9h-4v3H9v-3H5z", fg, false], ["M9 8.5v2.5M12 8.5v2.5M15 8.5v2.5", dim, false], ["M12 16v5", fg, false]];
        case "airplane":
            return [["M12 3l2 7 7 3v2l-7-1-1 5 2 1.5V22l-3-1-3 1v-1.5L10 18l-1-5-7 1v-2l7-3z", dim, false]];
        case "bt": {
            const rune = "M7 7l10 10-5 4.5V2.5L17 7 7 17";
            if (root.state === "off") return [[rune, dim, false], ["M4 4l16 16", dim, false]];
            if (root.state === "connected") return [[rune, Theme.accent, false], ["M3 12h.01M21 12h.01", Theme.accent, false]];
            return [[rune, fg, false]];
        }
        case "volume": {
            const spk = "M2 9h3.5L10 5v14l-4.5-4H2z";
            if (root.muted) return [[spk, dim, false], ["M14 9.5l6 5M20 9.5l-6 5", Theme.warn, false]];
            const waves = ["M13 9.5l2 2.5-2 2.5", "M16 7l3 5-3 5", "M19 4.5l3 7.5-3 7.5"];
            const lit = [], off = [];
            for (let i = 0; i < 3; i++) (i < root.level ? lit : off).push(waves[i]);
            return [[spk, fg, false], [lit.join(""), fg, false], [off.join(""), faint, false]];
        }
        case "battery": {
            const w = root.pct <= 0 ? 0 : Math.max(1.5, 12 * Math.min(100, root.pct) / 100);
            const out = [["M4 7h15v10H4l-2-2V9z", fg, false], ["M19 10h3v4h-3", fg, false]];
            if (w > 0) out.push(["M5.5 9.5h" + w + "v5h-" + w + "z", fg, true]);
            return out;
        }
        case "bolt":
            return [["M13 2L5 13.5h6L10 22l8-11.5h-6z", fg, false]];
        case "bell": {
            const bell = "M6 17v-6l3-6h6l3 6v6l2 2H4z M10 21.5h4";
            if (root.muted) return [[bell, dim, false], ["M3 3l18 18", Theme.warn, false]];
            return [[bell, fg, false]];
        }
        }
        return [];
    }

    Shape {
        width: 24; height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: sp0
            readonly property var s: root.spec[0] || ["", "transparent", false]
            fillColor: s[2] ? s[1] : "transparent"; strokeColor: s[1]; strokeWidth: s[2] ? 0 : root.strokeWidth
            joinStyle: ShapePath.MiterJoin; capStyle: ShapePath.RoundCap
            PathSvg { path: sp0.s[0] }
        }
        ShapePath {
            id: sp1
            readonly property var s: root.spec[1] || ["", "transparent", false]
            fillColor: s[2] ? s[1] : "transparent"; strokeColor: s[1]; strokeWidth: s[2] ? 0 : root.strokeWidth
            joinStyle: ShapePath.MiterJoin; capStyle: ShapePath.RoundCap
            PathSvg { path: sp1.s[0] }
        }
        ShapePath {
            id: sp2
            readonly property var s: root.spec[2] || ["", "transparent", false]
            fillColor: s[2] ? s[1] : "transparent"; strokeColor: s[1]; strokeWidth: s[2] ? 0 : root.strokeWidth
            joinStyle: ShapePath.MiterJoin; capStyle: ShapePath.RoundCap
            PathSvg { path: sp2.s[0] }
        }
        ShapePath {
            id: sp3
            readonly property var s: root.spec[3] || ["", "transparent", false]
            fillColor: s[2] ? s[1] : "transparent"; strokeColor: s[1]; strokeWidth: s[2] ? 0 : root.strokeWidth
            joinStyle: ShapePath.MiterJoin; capStyle: ShapePath.RoundCap
            PathSvg { path: sp3.s[0] }
        }
    }
}
