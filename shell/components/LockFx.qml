// LockFx.qml - the two moments the lock surface itself cannot draw, because it only exists while
// the session is locked: the desktop going dark just before the lock, and the desktop coming back
// just after the unlock. One Overlay-layer window per output, mapped only while it has something
// to show (no timers, nothing painting otherwise; input passes through).
//
//   playLock(done)  0-120 ms an accent line draws out from the screen centre, 100-420 the screen
//                   darkens to black under it (the lock's own animation starts from this frame:
//                   black + the line), then done() engages the lock. The window stays (hold) until
//                   release(), once the lock surfaces are up, or the failsafe.
//   arm()           map the window under the lock (hidden by the compositor's cover) so it is ready.
//   playUnlock()    called as the session unlocks, from the frame the lock surface ended on (black
//                   with the line across the middle): the two black halves retreat from the centre
//                   (700 ms, ease-out cubic), each edge carrying an accent line, uncovering the desktop.
// Reduced motion: none of this runs (the callers skip it).
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Scope {
    id: fx

    property string mode: ""          // "" | lock | hold | armed | unlock
    property real t: 0
    property var doneCb: null
    readonly property bool busy: mode === "lock" || mode === "unlock"

    function playLock(done) {
        if (!Config.motion) { if (done) done(); return; }
        doneCb = done;
        mode = "lock"; t = 0;
        seq.stop(); seq.from = 0; seq.to = 430; seq.duration = 430; seq.start();
        failsafe.restart();
    }
    function arm() { if (Config.motion && mode === "") { mode = "armed"; t = 0; failsafe.restart(); } }
    function playUnlock() {
        if (!Config.motion) { hide(); return; }
        mode = "unlock"; t = 0;
        seq.stop(); seq.from = 0; seq.to = 700; seq.duration = 700; seq.start();
        failsafe.restart();
    }
    function release() { if (mode === "hold") hide(); }
    function hide() { seq.stop(); failsafe.stop(); mode = ""; t = 0; doneCb = null; }

    NumberAnimation {
        id: seq; target: fx; property: "t"
        onFinished: {
            if (fx.mode === "lock") {
                fx.mode = "hold";
                const cb = fx.doneCb; fx.doneCb = null;
                if (cb) cb();
            } else if (fx.mode === "unlock") fx.hide();
        }
    }
    // never leave a black window behind, whatever happens to the lock
    Timer { id: failsafe; interval: 6000; onTriggered: fx.hide() }

    // hold: black + line; lock: sweep + darken; unlock: halves retreating
    readonly property real sweep: mode === "lock" ? Anim.out3(Anim.seg(t, 0, 120)) : 1
    readonly property real dark: mode === "lock" ? Anim.out3(Anim.seg(t, 100, 420)) : 1
    readonly property real open: mode === "unlock" ? Anim.out3(Anim.seg(t, 0, 520)) : 0
    readonly property real edgeOp: mode === "unlock" ? 1 - Anim.seg(t, 300, 700) : 1

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: fx.mode !== ""
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "ultimit-lockfx"

            readonly property real half: height / 2
            readonly property real gap: half * fx.open   // each black half has retreated by this much

            Rectangle {   // darkening (lock) / the whole black stage (hold, armed)
                anchors.fill: parent
                color: "#000000"
                opacity: fx.dark
                visible: fx.mode !== "unlock"
            }
            Rectangle {   // top half, retreating up
                x: 0; y: 0; width: parent.width; height: win.half - win.gap
                color: "#000000"
                visible: fx.mode === "unlock"
            }
            Rectangle {   // bottom half, retreating down
                x: 0; y: win.half + win.gap; width: parent.width; height: win.half - win.gap
                color: "#000000"
                visible: fx.mode === "unlock"
            }
            Rectangle {   // accent edge on the top half (and, from the centre line, the lock sweep)
                height: 2; width: parent.width * fx.sweep
                x: (parent.width - width) / 2
                y: win.half - win.gap - 1
                color: Theme.accent
                opacity: fx.edgeOp
                visible: fx.mode !== "" && width > 1
            }
            Rectangle {   // accent edge on the bottom half
                height: 2; width: parent.width
                x: 0; y: win.half + win.gap - 1
                color: Theme.accent
                opacity: fx.edgeOp
                visible: fx.mode === "unlock" && win.gap > 1
            }
        }
    }
}
