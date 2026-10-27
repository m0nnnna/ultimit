// ShowBehavior.qml - the Behavior for a value that shows and hides something (`shown ? 1 : 0`).
// The one panel recipe: opacity, scale (Theme.showScale -> 1) and, where a panel is anchored to an
// edge, a Theme.showOffset slide all use this. Arriving takes Theme.motion.base (override with
// `ms` only with a token) and eases out; leaving takes ~70 % of that and eases in. `hidden` is the
// value when hidden (0 for opacity, Theme.showScale for scale, the offset for a slide). Durations
// follow Config.dur (0 with motion off).
//   opacity: shown ? 1 : 0
//   ShowBehavior on opacity {}
//   scale: shown ? 1 : Theme.showScale
//   ShowBehavior on scale { hidden: Theme.showScale }
import QtQuick

Behavior {
    id: b
    property int ms: Theme.motion.base
    property real hidden: 0
    // targetValue is set before the animation starts, so this already knows the direction.
    readonly property bool leaving: b.targetValue === b.hidden
    NumberAnimation {
        duration: Config.dur(b.leaving ? Math.round(b.ms * 0.7) : b.ms)
        easing.type: b.leaving ? Theme.easeIn : Theme.easeBase
    }
}
