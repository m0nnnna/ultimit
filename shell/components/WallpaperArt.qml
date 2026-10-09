// WallpaperArt.qml - the generative shard/hex/ring picture as a plain Item (Canvas port of
// the mockup's drawWall). Used by Wallpaper.qml (animated) and the lock screen (static).
import QtQuick
import ".."

Item {
    id: art
    // Animate (<= Config.wallpaperFps) while true and Config.motion is on; otherwise paint once.
    property bool active: true
    property bool animate: Config.motion
    // Horizontal inset for the left rail (the desktop wallpaper leaves room for it).
    property real railInset: Config.railWidth
    onAnimateChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative

        // ---- generated geometry ----
        property var shards: []
        property var hexes: []
        property real hexSize: 24
        property real t0: Date.now()
        property real nowMs: 0            // animation clock in ms (mockup's `t`)

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

        function geo(w, h) {
            const rw = w < 720 ? 0 : art.railInset;
            return { px: rw + (w - rw) * .30, py: h * .70, R: Math.min(w * .42, h * .62),
                     sc: Math.max(.6, Math.min(w, h) / 800) };
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

        function draw(c, w, h, t) {
            const light = Theme.light, motion = art.animate;
            const shardC = Theme.shard, edgeC = Theme.edge, shadeC = Theme.shade, hexC = Theme.hexc;

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

            const G = geo(w, h), px = G.px, py = G.py, R = G.R, sc = G.sc;

            // hex grid
            c.lineWidth = 1;
            for (let i = 0; i < hexes.length; i++) {
                const x = hexes[i];
                hexPath(c, x.x, x.y, hexSize - 2);
                c.strokeStyle = "rgba(" + hexC + "," + x.al + ")";
                c.stroke();
                if (x.f >= 0 && Math.sin(t * .0012 + x.f * 3) > .85) {
                    c.fillStyle = "rgba(" + hexC + "," + (x.al * .7) + ")";
                    c.fill();
                }
            }

            // concentric rings, rotating arc, tick marks
            const rx = w * .8, ry = h * .22, rot = t * .00025;
            c.strokeStyle = "rgba(" + hexC + ",.14)";
            [70, 98, 150].forEach(function (rr) {
                c.beginPath(); c.arc(rx, ry, rr * sc, 0, 6.283); c.stroke();
            });
            c.strokeStyle = "rgba(" + hexC + ",.4)";
            c.lineWidth = 2;
            c.beginPath(); c.arc(rx, ry, 120 * sc, rot, rot + 1.3); c.stroke();
            c.beginPath(); c.arc(rx, ry, 120 * sc, rot + 3.2, rot + 3.6); c.stroke();
            c.lineWidth = 1;
            c.strokeStyle = "rgba(" + hexC + ",.22)";
            c.beginPath();   // all ticks in one path: far fewer draw calls
            for (let i = 0; i < 72; i++) {
                const a = i / 72 * 6.283 - rot * .5, l = i % 6 ? 4 : 9;
                c.moveTo(rx + Math.cos(a) * 150 * sc, ry + Math.sin(a) * 150 * sc);
                c.lineTo(rx + Math.cos(a) * (150 * sc + l), ry + Math.sin(a) * (150 * sc + l));
            }
            c.stroke();

            // crystal wing
            const sweep = -3.1 + ((t * .00012) % 1) * 3.6, sway = Math.sin(t * .00018) * .02;
            c.globalCompositeOperation = light ? "source-over" : "lighter";
            for (let i = 0; i < shards.length; i++) {
                const s = shards[i];
                const ang = s.a + sway + Math.sin(t * .00025 + s.ph) * .012;
                const ux = Math.cos(ang), uy = Math.sin(ang), vx = -uy, vy = ux;
                const r0 = s.r0 * R, L = s.L * R, tw = s.t * sc;
                const A = [px + ux * r0 + vx * -tw, py + uy * r0 + vy * -tw];
                const B = [px + ux * (r0 + L * .92) + vx * (-tw * .25), py + uy * (r0 + L * .92) + vy * (-tw * .25)];
                const C = [px + ux * (r0 + L), py + uy * (r0 + L)];
                const D = [px + ux * (r0 + L * .3) + vx * tw, py + uy * (r0 + L * .3) + vy * tw];
                const da = ang - sweep, boost = motion ? Math.exp(-(da * da) / .012) * .4 : 0;
                const gr = c.createLinearGradient(px + ux * r0, py + uy * r0, C[0], C[1]);
                gr.addColorStop(0, "rgba(" + shardC + ",0)");
                gr.addColorStop(.55, "rgba(" + shardC + "," + ((.55 * s.al + boost) * (light ? 1 : .8)) + ")");
                gr.addColorStop(1, "rgba(" + shardC + "," + (.9 * s.al + boost) + ")");
                c.beginPath(); c.moveTo(A[0], A[1]); c.lineTo(B[0], B[1]); c.lineTo(C[0], C[1]); c.lineTo(D[0], D[1]); c.closePath();
                c.fillStyle = gr; c.fill();
                c.globalCompositeOperation = "source-over";
                c.beginPath(); c.moveTo(A[0], A[1]); c.lineTo(C[0], C[1]); c.lineTo(D[0], D[1]); c.closePath();
                c.fillStyle = "rgba(" + shadeC + "," + (light ? .12 : .22) + ")"; c.fill();
                c.strokeStyle = "rgba(" + edgeC + "," + (light ? .45 : .35 * s.al) + ")";
                c.lineWidth = .8;
                c.beginPath(); c.moveTo(A[0], A[1]); c.lineTo(B[0], B[1]); c.lineTo(C[0], C[1]); c.stroke();
                c.globalCompositeOperation = light ? "source-over" : "lighter";
            }
            c.globalCompositeOperation = "source-over";
        }

        onPaint: {
            const c = getContext("2d");
            c.reset();
            draw(c, width, height, nowMs);
        }

        // Regenerate size-dependent geometry, then repaint.
        function relayout() {
            if (width < 2 || height < 2) return;
            genHex(width, height);
            requestPaint();
        }
        onWidthChanged: relayout()
        onHeightChanged: relayout()
        Component.onCompleted: { genShards(); relayout(); }

        Connections {
            target: Theme
            function onSkinChanged() { cv.requestPaint(); }
        }
        Connections {
            target: Config
            function onShardDensityChanged() { cv.genShards(); cv.requestPaint(); }
            function onMotionChanged() { cv.requestPaint(); }
        }

        // Animation clock: only runs while motion is on; capped by wallpaperFps.
        Timer {
            interval: Math.round(1000 / Math.max(1, Config.wallpaperFps))
            repeat: true
            running: art.animate && art.active
            onTriggered: { cv.nowMs = Date.now() - cv.t0; cv.requestPaint(); }
        }
    }
}
