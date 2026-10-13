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
            panel: [13, 15, 18, .80], panel2: [255, 255, 255, .05], rail: [7, 8, 10, .86],
            fg: "#eef1f4", dim: "#8d949e",
            line: [235, 240, 245, .16], lineStrong: [235, 240, 245, .48],
            accent: "#d4ebff", onAccent: "#07090b",
            ok: "#8fe3b0", warn: "#ffd98f", bad: "#ff8a8a",
            shard: "246,248,251", edge: "255,255,255", shade: "0,0,0", hexc: "255,255,255",
            light: false
        },
        amber: {
            bg1: "#b84d05", bg2: "#f8cf96",
            panel: [34, 17, 5, .78], panel2: [255, 220, 180, .07], rail: [28, 13, 3, .86],
            fg: "#fff4e6", dim: "#dcb48c",
            line: [255, 226, 196, .2], lineStrong: [255, 226, 196, .55],
            accent: "#ffb04a", onAccent: "#2a1404",
            ok: "#8fe3b0", warn: "#ffd98f", bad: "#ff8a8a",
            shard: "255,250,242", edge: "255,255,255", shade: "120,50,0", hexc: "255,240,220",
            light: false
        },
        silver: {
            bg1: "#f6f7f9", bg2: "#aeb5bf",
            panel: [248, 249, 251, .82], panel2: [20, 30, 45, .05], rail: [232, 235, 239, .9],
            fg: "#14171b", dim: "#5a626d",
            line: [20, 24, 30, .16], lineStrong: [20, 24, 30, .5],
            accent: "#2c5b88", onAccent: "#ffffff",
            ok: "#1f8a52", warn: "#a66b00", bad: "#c0392b",
            shard: "255,255,255", edge: "70,82,98", shade: "60,72,90", hexc: "40,50,65",
            light: true
        },
        verdant: {
            bg1: "#062a0c", bg2: "#79d24f",
            panel: [5, 20, 8, .78], panel2: [200, 255, 180, .06], rail: [3, 14, 5, .86],
            fg: "#effbe9", dim: "#a3cc95",
            line: [220, 255, 205, .18], lineStrong: [220, 255, 205, .5],
            accent: "#b9ff8c", onAccent: "#082008",
            ok: "#8fe3b0", warn: "#ffd98f", bad: "#ff8a8a",
            shard: "242,255,236", edge: "255,255,255", shade: "0,40,0", hexc: "230,255,220",
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
    readonly property string display: "Michroma"
    readonly property string ui: "Chakra Petch"
    readonly property string mono: "Share Tech Mono"

    // Window-chrome colors for the compositor ("ultimitctl skin ..."), as
    // #rrggbbaa: panel fg dim line lineStrong accent bad.
    readonly property var chromeArgs: [cur.panel, cur.fg, cur.dim, cur.line, cur.lineStrong, cur.accent, cur.bad].map(_hex)
    function _hex(v) {
        if (typeof v === "string") return v;
        return "#" + [v[0], v[1], v[2], Math.round(v[3] * 255)].map(n => n.toString(16).padStart(2, "0")).join("");
    }

    // Display name used in captions, e.g. "MINE"
    readonly property string skinLabel: skin.toUpperCase()
}
