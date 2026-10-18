// ShowBehavior.qml - the Behavior for a value that shows and hides something (`shown ? 1 : 0`):
// arriving eases out over `ms`; leaving takes ~70 % of that and eases in, so a panel gets out of
// the way instead of lingering. `hidden` is the value when hidden (0 for opacity, the offset for
// a slide). Durations follow Config.dur (0 with motion off).
//   opacity: shown ? 1 : 0
//   ShowBehavior on opacity { ms: 180 }
//   transform: Translate { x: shown ? 0 : -14; ShowBehavior on x { ms: 180; hidden: -14 } }
import QtQuick

Behavior {
    id: b
    property int ms: 180
    property real hidden: 0
    // targetValue is set before the animation starts, so this already knows the direction.
    readonly property bool leaving: b.targetValue === b.hidden
    NumberAnimation {
        duration: Config.dur(b.leaving ? Math.round(b.ms * 0.7) : b.ms)
        easing.type: b.leaving ? Easing.InQuad : Easing.OutCubic
    }
}
