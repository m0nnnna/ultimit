pragma Singleton

// Theme.qml - design tokens for every Ultimit skin.
// Mirrors the :root / [data-skin] blocks in docs/design/mockup.html.
// Components never hardcode colors or fonts; they read them from here.
// Switch skins at runtime with `Theme.skin = "amber"`, or start the shell with
// ULTIMIT_SKIN=silver in the environment.

import QtQuick
import Quickshell

Singleton {
    id: root

    // One of: "mine", "amber", "silver", "verdant"
    property string skin: {
        const e = Quickshell.env("ULTIMIT_SKIN");
        return (e && e in root.skins) ? e : "mine";
    }

    // Raw per-skin token table. Colors are CSS-like strings; alpha colors are
    // [r, g, b, a] with r/g/b in 0..255. "shard", "edge", "shade", "hexc" are
    // "r,g,b" strings for the wallpaper canvas, which composes its own alphas.
    readonly property var skins: ({
        mine: {
            bg1: "#050607", bg2: "#1c2026",
            panel: [13, 15, 18, .62], panel2: [255, 255, 255, .05], rail: [7, 8, 10, .72],
            fg: "#eef1f4", dim: "#8d949e",
            line: [235, 240, 245, .16], lineStrong: [235, 240, 245, .48],
            accent: "#d4ebff", onAccent: "#07090b",
            ok: "#8fe3b0", warn: "#ffd98f", bad: "#ff8a8a",
            shard: "246,248,251", edge: "255,255,255", shade: "0,0,0", hexc: "255,255,255",
            light: false
        },
        amber: {
            bg1: "#b84d05", bg2: "#f8cf96",
            panel: [34, 17, 5, .60], panel2: [255, 220, 180, .07], rail: [28, 13, 3, .72],
            fg: "#fff4e6", dim: "#dcb48c",
            line: [255, 226, 196, .2], lineStrong: [255, 226, 196, .55],
            accent: "#ffb04a", onAccent: "#2a1404",
            ok: "#8fe3b0", warn: "#ffd98f", bad: "#ff8a8a",
            shard: "255,250,242", edge: "255,255,255", shade: "120,50,0", hexc: "255,240,220",
            light: false
        },
        silver: {
            bg1: "#f6f7f9", bg2: "#aeb5bf",
            panel: [248, 249, 251, .66], panel2: [20, 30, 45, .05], rail: [232, 235, 239, .76],
            fg: "#14171b", dim: "#5a626d",
            line: [20, 24, 30, .16], lineStrong: [20, 24, 30, .5],
            accent: "#2c5b88", onAccent: "#ffffff",
            ok: "#1f8a52", warn: "#a66b00", bad: "#c0392b",
            shard: "255,255,255", edge: "70,82,98", shade: "60,72,90", hexc: "40,50,65",
            light: true
        },
        verdant: {
            bg1: "#062a0c", bg2: "#79d24f",
            panel: [5, 20, 8, .60], panel2: [200, 255, 180, .06], rail: [3, 14, 5, .72],
            fg: "#effbe9", dim: "#a3cc95",
            line: [220, 255, 205, .18], lineStrong: [220, 255, 205, .5],
            accent: "#b9ff8c", onAccent: "#082008",
            ok: "#8fe3b0", warn: "#ffd98f", bad: "#ff8a8a",
            shard: "242,255,236", edge: "255,255,255", shade: "0,40,0", hexc: "230,255,220",
            light: false
        }
    })

    // "panel" is the frosted glass every app window, menu, flyout and the window chrome are
    // filled with; "rail" is the rail and ticker. The compositor blurs what is behind them
    // (Aero-strength), so these alphas are the tint over that blur, not a plain see-through.
    readonly property var cur: skins[skin]

    // Your own accent (Settings > Appearance, "accent" in shell.json), "" = the skin's own.
    // It replaces the accent on every skin: focus frames, selections, toggles, the cursor.
    // The text on it turns dark or light by its brightness, and "bad" moves to orange when
    // the accent is red-ish so close/error never reads as the accent. Same rules as
    // accented() in theme/gtk/build-gtk.py, which colours GTK, Discord and the cursor.
    property string accentOverride: ""
    readonly property var accentPresets: [
        { n: "Pink", c: "#ff3d7f" }, { n: "Vermilion", c: "#ff5a36" }, { n: "Gold", c: "#ffc23d" },
        { n: "Acid", c: "#c6ff3d" }, { n: "Mint", c: "#3dffb0" }, { n: "Cyan", c: "#3dd8ff" },
        { n: "Blue", c: "#4d7cff" }, { n: "Violet", c: "#a66bff" }
    ]
    function validAccent(a) { return typeof a === "string" && /^#[0-9a-fA-F]{6}$/.test(a); }
    readonly property var eff: _accented(cur, accentOverride)
    function _accented(s, a) {
        if (!validAccent(a)) return { accent: s.accent, onAccent: s.onAccent, bad: s.bad };
        const ch = i => parseInt(a.substr(i, 2), 16) / 255;
        const lin = c => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        const lum = 0.2126 * lin(ch(1)) + 0.7152 * lin(ch(3)) + 0.0722 * lin(ch(5));
        const q = Qt.color(a), h = q.hsvHue;
        const reddish = h >= 0 && (h <= 20 / 360 || h >= 330 / 360) && q.hsvSaturation >= 0.4;
        return {
            accent: a.toLowerCase(),
            onAccent: lum > 0.18 ? "#08090b" : "#ffffff",
            bad: reddish ? (s.light ? "#b35400" : "#ff9a52") : s.bad
        };
    }

    // Settings from shell.json for the apps that run as their own process (MEMO, CLAUDE...).
    function load(o) {
        if (!Quickshell.env("ULTIMIT_SKIN") && o.skin in skins) skin = o.skin;
        accentOverride = validAccent(o.accent) ? o.accent.toLowerCase() : "";
    }

    function _rgba(a) { return Qt.rgba(a[0] / 255, a[1] / 255, a[2] / 255, a[3]); }

    // ---- colors ----
    readonly property color bg1: cur.bg1
    readonly property color bg2: cur.bg2
    readonly property color panel: _rgba(cur.panel)
    readonly property color panel2: _rgba(cur.panel2)
    readonly property color rail: _rgba(cur.rail)
    readonly property color fg: cur.fg
    readonly property color dim: cur.dim
    readonly property color line: _rgba(cur.line)
    readonly property color lineStrong: _rgba(cur.lineStrong)
    readonly property color accent: eff.accent
    readonly property color onAccent: eff.onAccent
    readonly property color ok: cur.ok
    readonly property color warn: cur.warn
    readonly property color bad: eff.bad

    // ---- wallpaper palette (see components/Wallpaper.qml) ----
    readonly property string shard: cur.shard
    readonly property string edge: cur.edge
    readonly property string shade: cur.shade
    readonly property string hexc: cur.hexc
    readonly property bool light: cur.light

    // ---- fonts (installed system-wide via fontconfig) ----
    readonly property string display: "Michroma"
    readonly property string ui: "Chakra Petch"
    readonly property string mono: "Share Tech Mono"

    // Window-chrome colors for the compositor ("ultimitctl skin ..."), as
    // #rrggbbaa: panel fg dim line lineStrong accent bad.
    readonly property var chromeArgs: [cur.panel, cur.fg, cur.dim, cur.line, cur.lineStrong, eff.accent, eff.bad].map(_hex)
    function _hex(v) {
        if (typeof v === "string") return v;
        return "#" + [v[0], v[1], v[2], Math.round(v[3] * 255)].map(n => n.toString(16).padStart(2, "0")).join("");
    }

    // Display name used in captions, e.g. "MINE"
    readonly property string skinLabel: skin.toUpperCase()
}
