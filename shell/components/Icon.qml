// Icon.qml - stroked line icon on a 24x24 grid, ported from the `I = {...}` table
// in docs/design/mockup.html. `name` selects the glyph; `color` is the stroke.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string name: "games"
    property color color: "white"
    property real strokeWidth: 1.5
    property real size: 26

    // Subpath data per glyph (SVG path syntax, 24x24 viewBox).
    readonly property var glyphs: ({
        games:     ["M3 9l3-3h12l3 3v6l-3 3h-3l-2-2h-2l-2 2H6l-3-3z", "M8 10v4M6 12h4M15.5 11h.01M17.5 13h.01"],
        mailer:    ["M3 6h18v12H3z", "M3 6l9 7 9-7"],
        news:      ["M4 4h16v16H4z", "M8 16V8l8 8V8"],
        audio:     ["M3 12h2M7 8v8M11 4v16M15 9v6M19 11v2"],
        data:      ["M12 3l8 4.5v9L12 21l-8-4.5v-9z", "M4 7.5l8 4.5 8-4.5M12 12v9"],
        accessory: ["M12 3l9 16H3z", "M12 9.5l3.5 6.5h-7z"]
    })

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24; height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        // Up to two subpaths per glyph (see `glyphs`).
        ShapePath {
            fillColor: "transparent"; strokeColor: root.color; strokeWidth: root.strokeWidth
            joinStyle: ShapePath.MiterJoin
            capStyle: ShapePath.RoundCap   // makes the zero-length "dot" subpaths visible
            PathSvg { path: (root.glyphs[root.name] || [])[0] || "" }
        }
        ShapePath {
            fillColor: "transparent"; strokeColor: root.color; strokeWidth: root.strokeWidth
            joinStyle: ShapePath.MiterJoin
            capStyle: ShapePath.RoundCap
            PathSvg { path: (root.glyphs[root.name] || [])[1] || "" }
        }
    }
}
