// WallpaperAccent.qml - picks a vivid dominant colour from a picture (no helper process: the
// picture is scaled to <= 64 px by an Image and read back through a Canvas).
//   WallpaperAccent { id: wa; onPicked: hex => Theme.accentOverride = hex; onFailed: ... }
//   wa.pick("/path/to/picture")
// Pixels vote by saturation x brightness into 10-degree hue bins (greys and near-black or
// near-white pixels don't vote); the strongest hue (with its neighbours) wins and its mean colour
// is lifted to an accent: saturated, and bright on dark skins, mid-bright on light ones.
import QtQuick
import "../.."

Item {
    id: root
    width: 0; height: 0
    signal picked(string hex)
    signal failed()
    property bool busy: false

    function pick(path) {
        if (!path || root.busy) return;
        root.busy = true;
        if (img.source.toString() === "file://" + path) img.source = "";   // same file: force a reload
        img.source = "file://" + path;
    }

    // The accent for a flat RGBA array (0..255), "" when the picture has no colour to speak of.
    function dominant(d, light) {
        const hist = [], N = 36;
        for (let i = 0; i < N; i++) hist.push({ w: 0, r: 0, g: 0, b: 0 });
        for (let i = 0; i + 3 < d.length; i += 4) {
            if (d[i + 3] < 128) continue;
            const r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255;
            const mx = Math.max(r, g, b), mn = Math.min(r, g, b), c = mx - mn;
            if (mx < 0.22 || c / mx < 0.25 || mn > 0.9) continue;   // too dark, grey or washed out
            const h = mx === r ? ((g - b) / c + 6) % 6 : mx === g ? (b - r) / c + 2 : (r - g) / c + 4;
            const s = c / mx, w = s * s * (0.4 + mx);
            const e = hist[Math.min(N - 1, Math.floor(h * 6))];   // h in 0..6 -> 36 bins
            e.w += w; e.r += r * w; e.g += g * w; e.b += b * w;
        }
        let best = -1, bestScore = 0;
        for (let i = 0; i < N; i++) {
            const score = hist[i].w + 0.5 * (hist[(i + 1) % N].w + hist[(i + N - 1) % N].w);
            if (score > bestScore) { bestScore = score; best = i; }
        }
        if (best < 0 || hist[best].w <= 0) return "";
        const e = hist[best];
        const q = Qt.rgba(e.r / e.w, e.g / e.w, e.b / e.w, 1);
        const col = Qt.hsva(q.hsvHue, Math.max(0.6, Math.min(1, q.hsvSaturation)),
                            light ? Math.max(0.45, Math.min(0.68, q.hsvValue)) : Math.max(0.85, q.hsvValue), 1);
        const x = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return "#" + x(col.r) + x(col.g) + x(col.b);
    }

    // The Image only tells us the file decodes; the Canvas reads the pixels (drawImage of an
    // Image item gives an empty canvas), scaled to 64 x 64 (the shape is irrelevant to a histogram).
    Image {
        id: img
        opacity: 0
        asynchronous: true; cache: false
        sourceSize: Qt.size(16, 16)
        onStatusChanged: {
            if (status === Image.Ready) {
                if (cv.isImageLoaded(source)) cv.requestPaint(); else cv.loadImage(source);
            } else if (status === Image.Error) { root.busy = false; root.failed(); }
        }
    }
    Canvas {
        id: cv
        width: 64; height: 64
        opacity: 0
        renderStrategy: Canvas.Immediate
        onImageLoaded: requestPaint()
        onPaint: {
            if (!root.busy || !isImageLoaded(img.source)) return;
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(img.source, 0, 0, width, height);
            const hex = root.dominant(ctx.getImageData(0, 0, width, height).data, Theme.light);
            unloadImage(img.source);
            root.busy = false;
            if (hex === "") root.failed(); else root.picked(hex);
        }
    }
}
