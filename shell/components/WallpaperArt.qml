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
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: art
    // Animate while true and `animate` is on; otherwise hold still (no timers run).
    property bool active: true
    property bool animate: Config.motion
    // Horizontal inset for the left rail (the desktop wallpaper leaves room for it).
    property real railInset: Config.railWidth
    readonly property bool running: animate && active && visible && width > 1

    // ---- animation clock (mockup's `t`, ms) ----
    // Advances only while running, so a paused wallpaper resumes where it stopped.
    property real t: 0
    property real spin: 0   // turning arc, degrees (mockup: rot = t * .00025 rad)
    readonly property real sway: Math.sin(t * .00018) * .02
    readonly property real sweep: -3.1 + ((t * .00012) % 1) * 3.6

    // Shards and flicker are slow; Config.wallpaperFps steps are plenty for them.
    // The clock follows real elapsed time (timers fire late under load); a gap of more than a
    // second (paused, suspended) is skipped rather than jumped over.
    Timer {
        property real last: 0
        interval: Math.round(1000 / Math.max(1, Config.wallpaperFps))
        repeat: true
        running: art.running
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now(), dt = now - last;
            last = now;
            art.t += dt > 1000 ? interval : dt;
        }
    }
    // The arc turns smoothly at display rate (a transform only: no CPU drawing).
    NumberAnimation on spin {
        from: 0; to: 360
        duration: Math.round(2 * Math.PI / .00025)
        loops: Animation.Infinite
        running: art.animate
        paused: running && !art.running
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
            g.addColorStop(0, "" + Theme.bg1);
            g.addColorStop(1, "" + Theme.bg2);
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

            // uniforms (see shaders/shard.frag)
            property size box: Qt.size(width, height)
            property real r0: modelData.r0 * art.bigR
            property real len: modelData.L * art.bigR
            property real tw: modelData.t * art.sc
            property real al: modelData.al
            property real boost: art.animate ? Math.exp(-(da * da) / .012) * .4 : 0
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
        function onSkinChanged() { base.requestPaint(); }
    }
    Connections {
        target: Config
        function onShardDensityChanged() { art.genShards(); }
    }
}
