// Surface.qml - the L1 floating-surface recipe of docs/design/polish.md, shared by the flyouts,
// launcher, menus and notification cards (windows get the same look from the compositor):
//   - fill: Theme.panel with a soft vertical sheen (4% darker at the bottom)
//   - a 1px top highlight (Theme.hl), fading out over the outer 15% of the width
//   - no other stroke: sides and bottom are defined by the shadow (elev1 / elev2)
//   - optional corner brackets and GlowFrame, passed through
// Children go inside it like any Item. The shadow is a few stacked rings (an even-odd Shape with
// the panel punched out, so a glass panel is not darkened from behind): no offscreen buffer,
// and nothing is redrawn while the surface sits still.
// It is OFF by default (elevation 0): the compositor blurs the backdrop under every non-transparent
// pixel of an ultimit-* layer surface, so a shadow drawn in the same surface as the panel gets a
// hard-edged blurred halo. Turn it on only for a Surface nested inside another one (PopupMenu).
// The real fix is a compositor-side shadow for layer panels (like the window shadow).
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root

    property color fill: Theme.panel
    property int elevation: 0           // 0 none, 1 = Theme.elev1, 2 = Theme.elev2
    property bool brackets: false
    property int bracketSize: 14
    property color bracketColor: Theme.accent
    property bool glow: false
    property color glowColor: Theme.accent
    property bool glowTravel: true
    property real glowStrength: 1

    readonly property var elev: elevation === 1 ? Theme.elev1 : Theme.elev2
    readonly property int shadowStep: 4
    readonly property int shadowRings: elevation > 0 ? Math.round(elev.blur / shadowStep) : 0

    // shadow
    Repeater {
        model: root.shadowRings
        delegate: Shape {
            id: ring
            required property int index
            readonly property real k: (index + 1) * root.shadowStep
            readonly property real yt: Math.min(0, -k + root.elev.y)
            readonly property real yb: root.height + k + root.elev.y
            visible: root.width > 0 && root.height > 0
            ShapePath {
                fillColor: Qt.rgba(root.elev.color.r, root.elev.color.g, root.elev.color.b,
                                   root.elev.color.a * 0.6 / root.shadowRings)
                strokeColor: "transparent"
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                startX: -ring.k; startY: ring.yt
                PathLine { x: root.width + ring.k; y: ring.yt }
                PathLine { x: root.width + ring.k; y: ring.yb }
                PathLine { x: -ring.k; y: ring.yb }
                PathLine { x: -ring.k; y: ring.yt }
                PathMove { x: 0; y: 0 }
                PathLine { x: root.width; y: 0 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // fill + sheen
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: root.fill }
            GradientStop {
                position: 1
                color: Qt.rgba(root.fill.r * 0.96, root.fill.g * 0.96, root.fill.b * 0.96, root.fill.a)
            }
        }
    }

    // top highlight
    Rectangle {
        x: 0; y: 0; width: parent.width; height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(Theme.hl.r, Theme.hl.g, Theme.hl.b, 0) }
            GradientStop { position: 0.15; color: Theme.hl }
            GradientStop { position: 0.85; color: Theme.hl }
            GradientStop { position: 1; color: Qt.rgba(Theme.hl.r, Theme.hl.g, Theme.hl.b, 0) }
        }
    }

    GlowFrame {
        anchors.fill: parent
        visible: root.glow
        color: root.glowColor; travel: root.glowTravel; strength: root.glowStrength
    }
    Brackets { visible: root.brackets; size: root.bracketSize; color: root.bracketColor }
}
