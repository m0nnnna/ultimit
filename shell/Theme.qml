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

    // One of: "mine", "amber", "silver", "verdant", "sakura", "paper", "void"
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
        if (!Quickshell.env("ULTIMIT_FONTSET") && o.fontSet in fontSets) fontSet = o.fontSet;
    }

    // Day/night skin switching (Settings > Appearance, "skinAuto" in shell.json). The schedule
    // runs in the main shell (Persist.qml); this is only the data and its validation.
    property var skinAuto: defaultAuto
    readonly property var defaultAuto: ({ enabled: false, day: "paper", night: "mine", dayStart: "07:00", nightStart: "19:00" })
    function validTime(t) { return typeof t === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(t); }
    function cleanAuto(o) {
        const d = defaultAuto, a = (o && typeof o === "object") ? o : {};
        return {
            enabled: a.enabled === true,
            day: a.day in skins ? a.day : d.day,
            night: a.night in skins ? a.night : d.night,
            dayStart: validTime(a.dayStart) ? a.dayStart : d.dayStart,
            nightStart: validTime(a.nightStart) ? a.nightStart : d.nightStart
        };
    }
    // The skin the schedule asks for at `now` ("day" from dayStart up to nightStart, wrapping midnight).
    function autoSkin(a, now) {
        const m = t => parseInt(t.substr(0, 2), 10) * 60 + parseInt(t.substr(3, 2), 10);
        const n = now.getHours() * 60 + now.getMinutes(), d = m(a.dayStart), k = m(a.nightStart);
        const day = d <= k ? (n >= d && n < k) : (n >= d || n < k);
        return day ? a.day : a.night;
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
    // The family triple comes from the chosen font set (Settings > Appearance, "fontSet" in
    // shell.json, ULTIMIT_FONTSET for one run). Keys are quoted so the skin scanners
    // (install-cursors.sh, build-cursors.py) do not mistake them for skins.
    property string fontSet: {
        const e = Quickshell.env("ULTIMIT_FONTSET");
        return (e && e in root.fontSets) ? e : "neo";
    }
    readonly property var fontSets: ({
        "hud":   { n: "HUD",   display: "Michroma",      ui: "Chakra Petch", mono: "Share Tech Mono" },
        "neo":   { n: "Neo",   display: "Oxanium",       ui: "Saira",        mono: "JetBrains Mono" },
        "clean": { n: "Clean", display: "Space Grotesk", ui: "Inter",        mono: "JetBrains Mono" }
    })
    readonly property string display: fontSets[fontSet].display
    readonly property string ui: fontSets[fontSet].ui
    readonly property string mono: fontSets[fontSet].mono

    // Window-chrome colors for the compositor ("ultimitctl skin ..."), as
    // #rrggbbaa: panel fg dim line lineStrong accent bad.
    readonly property var chromeArgs: [cur.panel, cur.fg, cur.dim, cur.line, cur.lineStrong, eff.accent, eff.bad].map(_hex)
    function _hex(v) {
        if (typeof v === "string") return v;
        return "#" + [v[0], v[1], v[2], Math.round(v[3] * 255)].map(n => n.toString(16).padStart(2, "0")).join("");
    }

    // ---- spacing and type scale ----
    // Components read these instead of bare numbers: space(n) is n steps of a 4 px grid
    // (space(2) = 8), size.* the pixel sizes of text. Changing numbers (clocks, rates, counters)
    // use tabular digits, `font.features: Theme.tnum`, so they don't jitter as the digits change.
    function space(n) { return n * 4; }
    readonly property var size: ({ xs: 9, sm: 10, md: 12, lg: 13, xl: 26 })
    readonly property var tnum: ({ "tnum": 1 })

    // Display name used in captions, e.g. "MINE"
    readonly property string skinLabel: skin.toUpperCase()
}
