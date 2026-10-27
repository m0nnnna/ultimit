pragma Singleton

// Anim.qml - the house motion language as helpers (see compositor/src/anim.c): an accent line
// draws out from the centre, then the content wipes down, all on an ease-out cubic.
// Timelines are one linear millisecond clock per sequence; every element derives its progress
// from it with seg() + an easing, so a whole sequence is one cheap animation that stops when done.
import QtQuick

QtObject {
    readonly property int lineMs: 120   // accent line draws out from the centre
    readonly property int wipeMs: 220   // content wipes down

    function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
    // Progress 0..1 of the window [a, b] inside clock t.
    function seg(t, a, b) { return clamp01((t - a) / (b - a)); }
    // Ease-out cubic (the compositor's ease()).
    function out3(x) { const u = 1 - clamp01(x); return 1 - u * u * u; }
    function inOut(x) { x = clamp01(x); return x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }
    // Ease-out with a small overshoot that settles back to 1.
    function back(x, s) { x = clamp01(x) - 1; const k = s === undefined ? 1.2 : s; return 1 + (k + 1) * x * x * x + k * x * x; }
    function mix(a, b, k) { return a + (b - a) * k; }
}
