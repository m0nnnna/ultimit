// WallpaperArt.qml - the generative shard/hex/ring picture (port of the mockup's drawWall).
// Used by Wallpaper.qml (animated) and the lock screen (static).
//
// Drawn on the GPU. The still parts (background, vignette, hex outlines, rings) are one Canvas,
// painted once per size or skin change. The moving parts are scene-graph items that are never
// re-rasterised: an animation frame only changes their transforms, opacities and shader uniforms.
//   - shards: one ShaderEffect each (shaders/shard.frag), turned into place by a Rotation;
//     the shader also does the canvas's additive ("lighter") blend on dark skins
//   - hex flicker: a filled Shape per flickering cell, shown/hidden by opacity
//   - turning arc and ticks: two Shapes rotated by a NumberAnimation
// Every screen has its own copy; nothing ticks while `active` or `animate` is false.
//
// Reactions (Wallpaper.qml turns them on from Config.react*; all off for the lock screen), worked
// out on the same slow step as the shards, so they add no timer and no per-event work:
//   pointer  the shards nearest the pointer's bearing light up while it moves, fading after ~1 s
//   audio    every shard brightens with the output level (AudioLevel, a PipeWire peak monitor that
//            only exists while a wallpaper wants it)
//   shift    kick(): the bright sweep jumps and settles back (the active window changed)
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: art
    // Animate while true and `animate` is on; otherwise hold still (no timers run).
    property bool active: true
    property bool animate: Config.motion
    // Step rates (the lock screen runs the shards slower than the desktop does).
    property int fps: Config.wallpaperFps
    property int spinFps: Config.wallpaperSpinFps
    // Horizontal inset for the left rail (the desktop wallpaper leaves room for it).
    property real railInset: Config.railWidth
    readonly property bool running: animate && active && visible && width > 1

    // ---- animation clock (mockup's `t`, ms) ----
    // Advances only while running, so a paused wallpaper resumes where it stopped.
    property real t: 0
    property real spin: 0   // turning arc, degrees (mockup: rot = t * .00025 rad)
    readonly property real sway: Math.sin(t * .00018) * .02
    readonly property real sweep: -3.1 + ((t * .00012) % 1) * 3.6 + kickV

    // ---- reactions ----
    property bool reactPointer: false
    property bool reactAudio: false
    property real rawX: -1          // last pointer position, written by Wallpaper.qml (not bound to anything)
    property real rawY: -1
    property real lastX: -1
    property real lastY: -1
    property real pa: 0             // bearing of the pointer from the shards' origin
    property real pEnergy: 0        // 0..1, builds while the pointer moves
    property real pulse: 0          // smoothed output level, 0..1
    property real kickV: 0          // sweep offset after kick(), rad, decays to 0
    function kick() { if (running) kickV = 1.1; }
    readonly property bool audioOn: reactAudio && running
    onAudioOnChanged: AudioLevel.users += audioOn ? 1 : -1
    Component.onDestruction: if (audioOn) AudioLevel.users--
    function react(dt) {
        if (reactPointer && rawX >= 0) {
            if (rawX !== lastX || rawY !== lastY) {
                lastX = rawX; lastY = rawY;
                pa = Math.atan2(rawY - py, rawX - px);
                pEnergy = Math.min(1, pEnergy + dt / 250);
            } else if (pEnergy > 0) pEnergy = Math.max(0, pEnergy - dt / 1000);
        } else if (pEnergy > 0) pEnergy = 0;
        const p = audioOn ? Math.round(Math.min(1, Math.max(AudioLevel.peak, pulse - dt / 350)) * 50) / 50 : 0;
        if (p !== pulse) pulse = p;
        if (kickV > 0) kickV = Math.max(0, kickV - dt / 800);
    }

    // Shards and flicker are slow; Config.wallpaperFps steps are plenty for them.
    // The clock follows real elapsed time (timers fire late under load); a gap of more than a
    // second (paused, suspended) is skipped rather than jumped over.
    // One clock for both, so their steps land in the same frame: the arc turns at
    // Config.wallpaperSpinFps (a transform only), the shards step at Config.wallpaperFps.
    Timer {
        property real last: 0
        property real pending: 0
        readonly property int step: Math.round(1000 / Math.max(1, art.fps))
        interval: Math.round(1000 / Math.max(1, art.spinFps, art.fps))
        repeat: true
        running: art.running
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now(), dt0 = now - last;
            const dt = dt0 > 1000 ? interval : dt0;
            last = now;
            art.spin = (art.spin + dt * .00025 * 180 / Math.PI) % 360;
            pending += dt;
            if (pending >= step) { art.t += pending; art.react(pending); pending = 0; }
        }
    }

    // ---- generated geometry ----
    property var shards: []
    property var hexes: []
    readonly property var flickers: hexes.filter(h => h.f >= 0)
    property real hexSize: 24

    readonly property real rw: width < 720 ? 0 : railInset
    readonly property real px: rw + (width - rw) * .30
    readonly property real py: height * .70
    readonly property real bigR: Math.min(width * .42, height * .62)
    readonly property real sc: Math.max(.6, Math.min(width, height) / 800)
    readonly property real rx: width * .8
    readonly property real ry: height * .22

    // "r,g,b" skin strings -> colors
    function rgb(s, a) {
        const p = ("" + s).split(",");
        return Qt.rgba(p[0] / 255, p[1] / 255, p[2] / 255, a === undefined ? 1 : a);
    }

    // Mulberry32 PRNG, identical to the mockup's rng().
    function rng(seed) {
        return function () {
            seed |= 0;
            seed = seed + 0x6D2B79F5 | 0;
            let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
            t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
            return ((t ^ t >>> 14) >>> 0) / 4294967296;
        };
    }

    function genShards() {
        const r = rng(7), density = Config.shardDensity, out = [];
        for (let i = 0; i < density; i++) {
            const k = i / (density - 1);
            out.push({ a: -2.95 + k * 2.7 + (r() - .5) * .08, r0: .06 + r() * .26,
                       L: (.45 + r() * .55) * (.55 + .65 * k), t: 5 + r() * 17,
                       ph: r() * 6.28, al: .55 + r() * .45 });
        }
        const extra = Math.round(density / 5);
        for (let i = 0; i < extra; i++)
            out.push({ a: .15 + r() * .7, r0: .1 + r() * .2, L: .2 + r() * .3,
                       t: 4 + r() * 8, ph: r() * 6.28, al: .25 + r() * .25 });
        shards = out;
    }

    function genHex(w, h) {
        const r = rng(11), s = 24 * Math.max(.7, Math.min(w, h) / 800), hw = Math.sqrt(3) * s;
        const cx = w * .8, cy = h * .2, out = [];
        for (let row = 0; row * s * 1.5 < h * .7; row++)
            for (let col = 0; col * hw < w * .55 + hw; col++) {
                const x = w * .45 + col * hw + (row % 2 ? hw / 2 : 0), y = row * s * 1.5;
                const d = Math.hypot(x - cx, y - cy) / (Math.min(w, h) * .5);
                const al = .24 - d * .2;
                if (al > .02) out.push({ x: x, y: y, al: al, f: r() < .1 ? r() * 6.28 : -1 });
            }
        hexSize = s;
        hexes = out;
    }

    function hexPath(c, x, y, s) {
        c.beginPath();
        for (let i = 0; i < 6; i++) {
            const a = Math.PI / 6 + i * Math.PI / 3;
            if (i) c.lineTo(x + s * Math.cos(a), y + s * Math.sin(a));
            else c.moveTo(x + s * Math.cos(a), y + s * Math.sin(a));
        }
        c.closePath();
    }
    // The same hexagon as an SVG path centred on (s, s).
    function hexSvg(s) {
        let d = "";
        for (let i = 0; i < 6; i++) {
            const a = Math.PI / 6 + i * Math.PI / 3;
            d += (i ? "L" : "M") + (s + s * Math.cos(a)).toFixed(2) + " " + (s + s * Math.sin(a)).toFixed(2);
        }
        return d + "Z";
    }
    // 72 ticks around a circle centred on (c, c): long every sixth.
    function tickSvg(c, rad) {
        let d = "";
        for (let i = 0; i < 72; i++) {
            const a = i / 72 * 6.283, l = i % 6 ? 4 : 9;
            d += "M" + (c + Math.cos(a) * rad).toFixed(2) + " " + (c + Math.sin(a) * rad).toFixed(2)
               + "L" + (c + Math.cos(a) * (rad + l)).toFixed(2) + " " + (c + Math.sin(a) * (rad + l)).toFixed(2);
        }
        return d;
    }

    // ---- skin change: the old still layer fades out over the new one ----
    // A one-shot snapshot of the canvas (taken just before it is repainted) sits above it and
    // fades over motion.skin; the Loader drops it afterwards, so nothing exists while idle.
    property string oldFrame: ""
    function fadeFromOld() {
        if (!Theme.fadeSkin || !Config.motion || !visible || width < 2 || !base.available) return;
        oldFrame = base.toDataURL("image/png");
    }
    // ---- still layer: painted once per size / skin change ----
    Canvas {
        id: base
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height, light = Theme.light, hexC = Theme.hexc;

            // background gradient + vignette
            const g = c.createLinearGradient(0, h, w * .9, 0);
            g.addColorStop(0, "" + Theme.cur.bg1);   // the skin's own value, not the gliding token
            g.addColorStop(1, "" + Theme.cur.bg2);
            c.fillStyle = g;
            c.fillRect(0, 0, w, h);
            const vg = c.createRadialGradient(w * .5, h * .5, Math.min(w, h) * .2, w * .5, h * .5, Math.max(w, h) * .75);
            vg.addColorStop(0, "rgba(0,0,0,0)");
            vg.addColorStop(1, light ? "rgba(40,50,65,.18)" : "rgba(0,0,0,.45)");
            c.fillStyle = vg;
            c.fillRect(0, 0, w, h);

            // hex grid outlines
            c.lineWidth = 1;
            for (let i = 0; i < art.hexes.length; i++) {
                const x = art.hexes[i];
                art.hexPath(c, x.x, x.y, art.hexSize - 2);
                c.strokeStyle = "rgba(" + hexC + "," + x.al + ")";
                c.stroke();
            }

            // concentric rings
            c.strokeStyle = "rgba(" + hexC + ",.14)";
            [70, 98, 150].forEach(function (rr) {
                c.beginPath(); c.arc(art.rx, art.ry, rr * art.sc, 0, 6.283); c.stroke();
            });
        }
    }

    Loader {
        anchors.fill: parent
        active: art.oldFrame !== ""
        sourceComponent: Image {
            source: art.oldFrame
            opacity: 1
            smooth: false
            NumberAnimation on opacity {
                running: true; from: 1; to: 0
                duration: Config.dur(Theme.motion.skin); easing.type: Theme.easeSlow
                onFinished: art.oldFrame = ""
            }
        }
    }

    // ---- moving layer ----

    // hex flicker: a few cells light up now and then
    Repeater {
        model: art.flickers
        delegate: Shape {
            id: cell
            required property var modelData
            readonly property real s: art.hexSize - 2
            x: modelData.x - s; y: modelData.y - s
            width: 2 * s; height: 2 * s
            opacity: Math.sin(art.t * .0012 + modelData.f * 3) > .85 ? 1 : 0
            visible: opacity > 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: art.rgb(Theme.hexc, cell.modelData.al * .7)
                PathSvg { path: art.hexSvg(cell.s) }
            }
        }
    }

    // turning arc
    Shape {
        id: arc
        readonly property real rad: 120 * art.sc
        width: 2 * rad + 4; height: width
        x: art.rx - width / 2; y: art.ry - height / 2
        rotation: art.spin
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: art.rgb(Theme.hexc, .4); strokeWidth: 2
            fillColor: "transparent"; capStyle: ShapePath.FlatCap
            PathAngleArc { moveToStart: true; centerX: arc.width / 2; centerY: arc.height / 2
                           radiusX: arc.rad; radiusY: arc.rad
                           startAngle: 0; sweepAngle: 1.3 * 180 / Math.PI }
        }
        ShapePath {
            strokeColor: art.rgb(Theme.hexc, .4); strokeWidth: 2
            fillColor: "transparent"; capStyle: ShapePath.FlatCap
            PathAngleArc { moveToStart: true; centerX: arc.width / 2; centerY: arc.height / 2
                           radiusX: arc.rad; radiusY: arc.rad
                           startAngle: 3.2 * 180 / Math.PI; sweepAngle: .4 * 180 / Math.PI }
        }
    }

    // tick ring, turning back at half speed
    Shape {
        id: ticks
        readonly property real rad: 150 * art.sc
        width: 2 * (rad + 10); height: width
        x: art.rx - width / 2; y: art.ry - height / 2
        rotation: -art.spin / 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: art.rgb(Theme.hexc, .22); strokeWidth: 1
            fillColor: "transparent"; capStyle: ShapePath.FlatCap
            PathSvg { path: art.tickSvg(ticks.width / 2, ticks.rad) }
        }
    }

    // crystal wing
    Repeater {
        model: art.shards
        delegate: ShaderEffect {
            required property var modelData
            readonly property real ang: modelData.a + art.sway + Math.sin(art.t * .00025 + modelData.ph) * .012
            readonly property real da: ang - art.sweep
            readonly property real dp: ang - art.pa

            // uniforms (see shaders/shard.frag)
            property size box: Qt.size(width, height)
            property real r0: modelData.r0 * art.bigR
            property real len: modelData.L * art.bigR
            property real tw: modelData.t * art.sc
            property real al: modelData.al
            property real boost: art.animate ? Math.exp(-(da * da) / .012) * .4 + art.pulse * .35
                                              + (art.pEnergy > 0 ? art.pEnergy * Math.exp(-(dp * dp) / .03) * .55 : 0) : 0
            property real lightSkin: Theme.light ? 1 : 0
            property color shardC: art.rgb(Theme.shard)
            property color edgeC: art.rgb(Theme.edge)
            property color shadeC: art.rgb(Theme.shade)

            x: art.px; y: art.py - tw - 2
            width: r0 + len + 2; height: 2 * tw + 4
            transform: Rotation { origin.x: 0; origin.y: tw + 2; angle: ang * 180 / Math.PI }
            fragmentShader: Qt.resolvedUrl("shaders/shard.frag.qsb")
        }
    }

    // Regenerate size-dependent geometry, then repaint the still layer.
    function relayout() {
        if (width < 2 || height < 2) return;
        genHex(width, height);
        base.requestPaint();
    }
    onWidthChanged: relayout()
    onHeightChanged: relayout()
    Component.onCompleted: { genShards(); relayout(); }

    Connections {
        target: Theme
        function onSkinChanged() { art.fadeFromOld(); base.requestPaint(); }
    }
    Connections {
        target: Config
        function onShardDensityChanged() { art.genShards(); }
    }
}
