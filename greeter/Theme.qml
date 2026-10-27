pragma Singleton

// Theme.qml - design tokens for every Ultimit skin.
// Mirrors the :root / [data-skin] blocks in docs/design/mockup.html.
// Components never hardcode colors or fonts; they read them from here.
// Switch skins at runtime with `Theme.skin = "amber"`, or start the greeter with
// ULTIMIT_GREETER_SKIN=silver in the environment.

import QtQuick
import Quickshell

Singleton {
    id: root

    // One of: "mine", "amber", "silver", "verdant", "sakura", "paper", "void"
    property string skin: {
        const e = Quickshell.env("ULTIMIT_GREETER_SKIN");
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
        },
        sakura: {
            bg1: "#14040d", bg2: "#8c2a5c",
            panel: [30, 9, 21, 0.6], panel2: [255, 190, 220, .06], rail: [21, 6, 14, 0.72],
            fg: "#fff0f6", dim: "#d29bb6",
            line: [255, 205, 228, .18], lineStrong: [255, 205, 228, .5],
            accent: "#ff5fa2", onAccent: "#2a0715",
            ok: "#9be8c0", warn: "#ffd9a0", bad: "#ff9a6b",
            shard: "255,232,242", edge: "255,205,228", shade: "92,10,52", hexc: "255,214,232",
            light: false
        },
        paper: {
            bg1: "#fbf8f1", bg2: "#d6cdb6",
            panel: [251, 248, 241, 0.7], panel2: [60, 45, 20, .05], rail: [238, 233, 220, 0.78],
            fg: "#1e1b15", dim: "#675f4e",
            line: [40, 32, 16, .16], lineStrong: [40, 32, 16, .5],
            accent: "#0e7c70", onAccent: "#ffffff",
            ok: "#2f7d32", warn: "#9a6200", bad: "#b3261e",
            shard: "255,253,247", edge: "96,80,52", shade: "110,92,58", hexc: "70,58,36",
            light: true
        },
        void: {
            bg1: "#000000", bg2: "#06080e",
            panel: [0, 0, 0, 0.72], panel2: [255, 255, 255, .04], rail: [0, 0, 0, 0.82],
            fg: "#e8ecf2", dim: "#7c8596",
            line: [160, 185, 225, .14], lineStrong: [160, 185, 225, .42],
            accent: "#4f9dff", onAccent: "#00101f",
            ok: "#5fe0b0", warn: "#ffcf70", bad: "#ff6b7a",
            shard: "150,185,255", edge: "120,160,255", shade: "0,0,0", hexc: "110,150,230",
            light: false
        }
    })

    readonly property var cur: skins[skin]

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
    readonly property color accent: cur.accent
    readonly property color onAccent: cur.onAccent
    readonly property color ok: cur.ok
    readonly property color warn: cur.warn
    readonly property color bad: cur.bad

    // ---- wallpaper palette (see components/Wallpaper.qml) ----
    readonly property string shard: cur.shard
    readonly property string edge: cur.edge
    readonly property string shade: cur.shade
    readonly property string hexc: cur.hexc
    readonly property bool light: cur.light

    // ---- fonts (installed system-wide via fontconfig) ----
    // The default font set of the shell ("neo"); the greeter has no settings of its own.
    readonly property string display: "Oxanium"
    readonly property string ui: "Saira"
    readonly property string mono: "JetBrains Mono"


    // ---- polish tokens (docs/design/polish.md) ----
    // Surface fills: field = L2 inset (inputs, tiles), hover/press = fg tints, selection = accent
    // tint, divider = the one hairline between list rows, scrim = what dims the screen behind
    // a modal. hl = the 1px top highlight of every L1 surface (skin edge colour; dark skins .14,
    // light skins .55).
    function _csv(s) { const p = s.split(","); return [parseInt(p[0]), parseInt(p[1]), parseInt(p[2])]; }
    function _fgA(a) { const c = Qt.color(cur.fg); return Qt.rgba(c.r, c.g, c.b, a); }
    readonly property color field: cur.light ? Qt.rgba(0.08, 0.1, 0.14, 0.05) : Qt.rgba(0, 0, 0, 0.20)
    readonly property color hover: _fgA(0.06)
    readonly property color press: _fgA(0.10)
    readonly property color selection: Qt.rgba(accent.r, accent.g, accent.b, 0.18)
    readonly property color divider: _fgA(0.08)
    readonly property color scrim: { const c = _csv(cur.shade); return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, 0.55); }
    readonly property real hlAlpha: cur.light ? 0.55 : 0.14
    readonly property color hl: { const c = _csv(cur.edge); return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, hlAlpha); }

    // Type scale: label = uppercase tracked mono, body = everything readable, title = card
    // titles, head = page headings, hero = clocks and wordmarks (display font, so it scales).
    readonly property var type: ({ label: 12, body: 14, title: 17, head: 24, hero: 64 })
    // Icon sizes: tray and rail use md, launcher rows lg.
    readonly property var icon: ({ sm: 16, md: 20, lg: 24, xl: 32 })
    // Motion: durations in ms (wrap in Config.dur() so reduced motion is honoured) and easings.
    readonly property var motion: ({ fast: 100, base: 180, slow: 280, skin: 400, ambient: 900 })
    readonly property int easeFast: Easing.OutCubic
    readonly property int easeBase: Easing.OutCubic
    readonly property int easeSlow: Easing.OutQuint
    readonly property int easeIn: Easing.InCubic
    readonly property real showScale: 0.96
    readonly property real pressScale: 0.94
    readonly property real pressScaleLarge: 0.98
    // Elevation: drop shadows (blur radius px, y offset px, colour).
    readonly property var elev1: ({ blur: 16, y: 2, color: Qt.rgba(0, 0, 0, 0.30) })
    readonly property var elev2: ({ blur: 32, y: 8, color: Qt.rgba(0, 0, 0, 0.45) })
    function space(n) { return n * 4; }

    // Display name used in captions, e.g. "MINE"
    readonly property string skinLabel: skin.toUpperCase()
}
