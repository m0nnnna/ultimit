// Display: every monitor's place (drag them on the canvas), resolution, refresh rate, scale,
// rotation and adaptive sync, which one is the main display, Extend or Duplicate, and Identify.
// Changes go through wlr-randr (wlr-output-management) and are confirmed with a 15 s "Keep these
// settings?" countdown; without confirmation (or when the window closes) the previous
// configuration is restored. Confirmed configs are saved to ~/.config/ultimit/displays.conf, one
// section per monitor, recognised by its make|model|serial wherever it is plugged in (writeConf).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.."
import "../accessory"
import "../../components"

Item {
    id: pg

    property var outs: []        // draft, edited by the UI
    property var applied: []     // what the compositor is running (last read / last confirmed)
    property bool pending: false // an applied change awaits Keep / Revert
    property int countdown: 15
    property string status: ""
    property int sel: 0          // index of the selected monitor
    property bool identifying: false

    // ---------- helpers ----------
    function clone(v) { return JSON.parse(JSON.stringify(v)); }
    function swapped(o) { return /90|270/.test(o.transform); }
    function lw(o) { return Math.round((swapped(o) ? o.mode.h : o.mode.w) / o.scale); }
    function lh(o) { return Math.round((swapped(o) ? o.mode.w : o.mode.h) / o.scale); }
    function comparable(list) {
        return JSON.stringify(list.map(o => [o.name, o.enabled, o.mode.w, o.mode.h, o.mode.r.toFixed(3), o.scale,
                                             o.vrr, o.x, o.y, o.transform, o.primary]));
    }
    function layoutKey(list) {   // what needs wlr-randr (everything but the main-display flag)
        return JSON.stringify(list.map(o => [o.name, o.enabled, o.mode.w, o.mode.h, o.mode.r.toFixed(3), o.scale, o.vrr, o.x, o.y, o.transform]));
    }
    readonly property bool dirty: comparable(outs) !== comparable(applied)
    readonly property var enabledOuts: outs.filter(o => o.enabled)
    readonly property int mainIndex: Math.max(0, outs.findIndex(o => o.primary))
    // Duplicate: every enabled monitor shows the same place.
    readonly property bool duplicate: enabledOuts.length > 1 && enabledOuts.every(o => o.x === enabledOuts[0].x && o.y === enabledOuts[0].y)

    function parse(text, primaryName) {
        let j;
        try { j = JSON.parse(text); } catch (e) { return []; }
        const list = j.map(o => {
            const modes = (o.modes || []).map(m => ({ w: m.width, h: m.height, r: m.refresh, cur: !!m.current, pref: !!m.preferred }));
            const cur = modes.find(m => m.cur) || modes[0] || { w: 0, h: 0, r: 0 };
            return {
                name: o.name, desc: [o.make, o.model].filter(x => x).join(" ") || o.description || o.name,
                id: [o.make || "", o.model || "", o.serial || ""].join("|"),
                enabled: !!o.enabled, modes: modes, mode: { w: cur.w, h: cur.h, r: cur.r },
                scale: o.scale || 1, vrr: !!o.adaptive_sync,
                x: o.position ? o.position.x : 0, y: o.position ? o.position.y : 0,
                transform: o.transform || "normal", primary: o.name === primaryName, num: 0
            };
        });
        if (list.length && !list.some(o => o.primary)) (list.find(o => o.enabled) || list[0]).primary = true;
        // Display numbers: left to right, then top to bottom, as they are now (stable while editing).
        list.slice().sort((a, b) => (a.x - b.x) || (a.y - b.y)).forEach((o, i) => o.num = i + 1);
        return list;
    }

    // ---------- arrangement ----------
    function overlaps(a, b) {
        return a.x < b.x + lw(b) && b.x < a.x + lw(a) && a.y < b.y + lh(b) && b.y < a.y + lh(a);
    }
    // The spot next to one of `placed` (edge to edge, never overlapping them) nearest to (x, y).
    // Along that edge it goes wherever it was put; edges that come within `snap` (logical px, 0 = off)
    // of lining up do line up.
    function nearestSpot(o, x, y, placed, snap) {
        const w = lw(o), h = lh(o);
        let best = null, bd = 1e18;
        for (const p of placed) {
            const pw = lw(p), ph = lh(p);
            const cands = [];
            for (const side of ["left", "right", "above", "below"]) {
                let cx, cy;
                if (side === "left" || side === "right") {
                    cx = side === "left" ? p.x - w : p.x + pw;
                    cy = Math.max(p.y - h + 1, Math.min(p.y + ph - 1, y));
                    for (const a of [p.y + (ph - h) / 2, p.y + ph - h, p.y]) if (Math.abs(cy - a) < snap) cy = a;   // tops win
                } else {
                    cy = side === "above" ? p.y - h : p.y + ph;
                    cx = Math.max(p.x - w + 1, Math.min(p.x + pw - 1, x));
                    for (const a of [p.x + (pw - w) / 2, p.x + pw - w, p.x]) if (Math.abs(cx - a) < snap) cx = a;   // left edges win
                }
                cands.push({ x: Math.round(cx), y: Math.round(cy) });
            }
            for (const c of cands) {
                const t = Object.assign({}, o, c);
                if (placed.some(q => overlaps(t, q))) continue;
                const d = (c.x - x) ** 2 + (c.y - y) ** 2;
                if (d < bd) { bd = d; best = c; }
            }
        }
        return best || { x: x, y: y };
    }
    // Put every enabled monitor edge to edge: the main display stays, the others (nearest first,
    // `moved` with its wished-for spot) go to the closest free side of one already placed. Only the
    // one being moved lines up with edges (within `snap`); the others keep their offsets.
    // Then shift everything so the layout starts at 0,0.
    function pack(list, moved, wantX, wantY, snap) {
        const en = list.filter(o => o.enabled);
        if (en.length === 0) return list;
        const main = en.find(o => o.primary) || en[0];
        if (moved !== undefined && list[moved] === main && en.length > 1) {
            // dragging the main display: move everything else by the same amount instead
            const dx = wantX - main.x, dy = wantY - main.y;
            for (const o of en) if (o !== main) { o.x -= dx; o.y -= dy; }
        } else if (moved !== undefined) {
            list[moved].x = wantX; list[moved].y = wantY;
        }
        const placed = [main];
        const rest = en.filter(o => o !== main).sort((a, b) => {
            if (moved !== undefined && a === list[moved]) return 1;   // the dragged one goes last: it adapts
            if (moved !== undefined && b === list[moved]) return -1;
            return (Math.abs(a.x - main.x) + Math.abs(a.y - main.y)) - (Math.abs(b.x - main.x) + Math.abs(b.y - main.y));
        });
        // dragging the main display: the one nearest to it is the one that lines up
        const snapper = moved === undefined ? null : list[moved] === main ? rest[0] : list[moved];
        for (const o of rest) {
            const s = nearestSpot(o, o.x, o.y, placed, o === snapper ? (snap || 0) : 0);
            o.x = s.x; o.y = s.y;
            placed.push(o);
        }
        const minX = Math.min(...en.map(o => o.x)), minY = Math.min(...en.map(o => o.y));
        for (const o of en) { o.x -= minX; o.y -= minY; }
        return list;
    }
    // Duplicate: everyone at the main display's spot, at its size when the monitor can do it
    // (else scaled so the picture fits the same logical size).
    function duplicateAll(list) {
        const en = list.filter(o => o.enabled);
        const main = en.find(o => o.primary) || en[0];
        for (const o of en) {
            if (o === main) continue;
            o.transform = main.transform === o.transform ? o.transform : "normal";
            const same = o.modes.filter(m => m.w === main.mode.w && m.h === main.mode.h).sort((a, b) => b.r - a.r)[0];
            if (same) { o.mode = { w: same.w, h: same.h, r: same.r }; o.scale = main.scale; }
            else o.scale = Math.max(0.5, Math.min(4, Math.round((swapped(o) ? o.mode.h : o.mode.w) / lw(main) * 100) / 100));
            o.x = main.x; o.y = main.y;
        }
        return list;
    }
    function extendAll(list) {
        for (const o of list) if (o.enabled && !o.primary) { o.x = 1e6; o.y = 0; }   // all to the right, then packed
        return pack(list);
    }

    function argsFor(list) {
        const a = ["wlr-randr"];
        for (const o of list) {
            a.push("--output", o.name);
            if (!o.enabled) { a.push("--off"); continue; }
            a.push("--on", "--mode", o.mode.w + "x" + o.mode.h + (o.mode.r > 0 ? "@" + o.mode.r.toFixed(3) + "Hz" : ""),
                   "--scale", String(o.scale), "--pos", o.x + "," + o.y,
                   "--transform", o.transform, "--adaptive-sync", o.vrr ? "enabled" : "disabled");
        }
        return a;
    }
    // Typed position (logical px): exactly there, next to the others, no lining up.
    function place(i, x, y) {
        if (isNaN(x) || isNaN(y)) { outs = clone(outs); return; }
        outs = pack(clone(outs), i, x, y, 0);
    }
    function edit(i, patch) {
        const l = clone(outs);
        Object.assign(l[i], patch);
        if (patch.primary) l.forEach((o, k) => o.primary = k === i);
        outs = duplicate && !("enabled" in patch) ? duplicateAll(l) : pack(l);
    }
    function resolutions(o) {
        const seen = {}; const out = [];
        for (const m of o.modes) {
            const k = m.w + "x" + m.h;
            if (!seen[k]) { seen[k] = true; out.push({ id: k, label: m.w + " × " + m.h + (m.pref ? "  (native)" : ""), area: m.w * m.h }); }
        }
        out.sort((a, b) => b.area - a.area);
        return out;
    }
    function rates(o) {
        return o.modes.filter(m => m.w === o.mode.w && m.h === o.mode.h)
            .sort((a, b) => b.r - a.r)
            .map(m => ({ id: m.r.toFixed(3), label: m.r > 0 ? Math.round(m.r * 100) / 100 + " Hz" : "Default" }));
    }
    function pickResolution(i, id) {
        const o = outs[i];
        const [w, h] = id.split("x").map(Number);
        const cand = o.modes.filter(m => m.w === w && m.h === h).sort((a, b) => b.r - a.r);
        if (cand.length) edit(i, { mode: { w: w, h: h, r: cand[0].r } });   // a new size starts at its fastest rate
    }
    function pickRate(i, id) {
        const o = outs[i];
        const m = o.modes.find(m => m.w === o.mode.w && m.h === o.mode.h && m.r.toFixed(3) === id);
        if (m) edit(i, { mode: { w: m.w, h: m.h, r: m.r } });
    }

    // ---------- persistence: ~/.config/ultimit/displays.conf ----------
    // INI-like, one section per monitor (named after its connector), recognised by id:
    //   id = make|model|serial   enabled = true|false   mode = <w>x<h>@<Hz, 3 decimals>   scale = <float>
    //   x / y = <logical px>   transform = normal|90|180|270|flipped|...   adaptive_sync = true|false
    //   primary = true|false
    function writeConf(list) {
        let t = "# Written by Ultimit Settings > Display. One [section] per monitor; `id` (make|model|serial)\n" +
                "# finds it on any connector. mode = WxH@Hz, x/y = logical position, transform = wl_output name.\n";
        for (const o of list) {
            t += "\n[" + o.name + "]\n" +
                 (o.id.replace(/\|/g, "") !== "" ? "id = " + o.id + "\n" : "") +
                 "enabled = " + o.enabled + "\n" +
                 "mode = " + o.mode.w + "x" + o.mode.h + (o.mode.r > 0 ? "@" + o.mode.r.toFixed(3) : "") + "\n" +
                 "scale = " + o.scale.toFixed(2) + "\n" +
                 "x = " + o.x + "\n" + "y = " + o.y + "\n" +
                 "transform = " + o.transform + "\n" +
                 "adaptive_sync = " + o.vrr + "\n" +
                 "primary = " + !!o.primary + "\n";
        }
        SetSys.writeFile(SetSys.cfgPath("displays.conf"), t);
        // the login screen's copy (it can't read home folders); after the write above lands
        Quickshell.execDetached(["sh", "-c", "sleep 1; exec \"$0\"", Quickshell.shellPath("../session/ultimit-greeter-displays")]);
    }

    // ---------- read / apply / keep / revert ----------
    property string randrJson: ""
    Cmd {
        id: read
        argv: ["wlr-randr", "--json"]
        onDone: (out, code) => {
            if (code !== 0) { pg.status = "Could not query displays (wlr-randr failed)."; return; }
            pg.randrJson = out;
            primaryQuery.go();
        }
    }
    Cmd {
        id: primaryQuery
        argv: [SetSys.ctl, "state"]
        onDone: (out, code) => {
            let p = "";
            try { const o = JSON.parse(out).outputs.find(x => x.primary); p = o ? o.name : ""; } catch (e) {}
            const l = pg.parse(pg.randrJson, p);
            pg.applied = l;
            if (!pg.pending) {
                const first = pg.outs.length === 0;
                pg.outs = pg.clone(l);
                pg.sel = first ? Math.max(0, l.findIndex(o => o.primary)) : Math.min(pg.sel, Math.max(0, l.length - 1));
            }
            pg.status = l.length === 0 ? "No displays reported." : "";
        }
    }
    Connections { target: Quickshell; function onScreensChanged() { if (!pg.pending) rescan.restart(); } }
    Timer { id: rescan; interval: 700; onTriggered: read.go() }   // plugged in / unplugged: look again
    Cmd {
        id: apply
        mutating: true
        onDone: (out, code) => {
            if (code !== 0) {
                Toasts.show("Display", (out.trim().split("\n")[0]) || "wlr-randr failed");
                pg.outs = pg.clone(pg.applied);
                read.go();
                return;
            }
            pg.pending = true; pg.countdown = 15; tick.restart();
        }
    }
    Cmd {
        id: restore
        mutating: true
        onDone: read.go()
    }
    function saveMain() {
        const m = outs.find(o => o.primary);
        if (m) SetSys.run([SetSys.ctl, "primary", m.name]);
        Config.primaryScreen = m ? m.name : "";
    }
    function applyNow() {
        if (layoutKey(outs) === layoutKey(applied)) {   // only the main display changed: nothing to confirm
            saveMain(); writeConf(outs); applied = clone(outs);
            return;
        }
        apply.argv = argsFor(outs);
        apply.go();
    }
    function keep() {
        tick.stop(); pending = false;
        applied = clone(outs);
        saveMain();
        writeConf(outs);
        if (!SetSys.dryRun) read.go();
    }
    function revert() {
        tick.stop();
        if (!pending) return;
        pending = false;
        restore.argv = argsFor(applied);
        restore.go();
        outs = clone(applied);
    }
    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: { pg.countdown--; if (pg.countdown <= 0) pg.revert(); }
    }
    Component.onCompleted: read.go()
    // closing Settings (or leaving the page) while unconfirmed counts as "no": restore the old config
    Component.onDestruction: if (pending) SetSys.run(argsFor(applied));

    // ---------- Identify: each screen shows its number for a few seconds ----------
    Timer { id: identifyTimer; interval: 2500; onTriggered: pg.identifying = false }
    function identify() { identifying = true; identifyTimer.restart(); }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: idw
            required property var modelData
            screen: modelData
            visible: pg.identifying
            anchors { left: true; top: true }
            margins { left: 40; top: 40 }
            implicitWidth: 240; implicitHeight: 200
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "ultimit-identify"
            readonly property var o: pg.outs.find(x => x.name === modelData.name) || null
            Rectangle {
                anchors.fill: parent
                color: Theme.panel; border.color: Theme.accent; border.width: 2
                Text {
                    anchors.centerIn: parent; anchors.verticalCenterOffset: -14
                    text: idw.o ? idw.o.num : "?"
                    color: Theme.accent; font.family: Theme.display; font.pixelSize: 110
                }
                Text {
                    anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
                    text: (idw.o && idw.o.primary ? "MAIN  ·  " : "") + idw.modelData.name
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.6
                }
            }
        }
    }

    // ---------- UI ----------
    Page {
        anchors.fill: parent
        title: "Display"

        Text {
            visible: pg.status !== ""
            Layout.fillWidth: true
            text: pg.status; color: Theme.warn; font.family: Theme.ui; font.pixelSize: 13; wrapMode: Text.WordWrap
        }

        // ---- arrangement canvas: drag a display to move it; click to pick it ----
        Item {
            id: canvas
            visible: pg.outs.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Config.mobile ? 220 : 300
            readonly property var en: pg.enabledOuts
            readonly property real x0: en.length ? Math.min(...en.map(o => o.x)) : 0
            readonly property real y0: en.length ? Math.min(...en.map(o => o.y)) : 0
            readonly property real x1: en.length ? Math.max(...en.map(o => o.x + pg.lw(o))) : 1
            readonly property real y1: en.length ? Math.max(...en.map(o => o.y + pg.lh(o))) : 1
            readonly property real k: Math.min((width - 40) / Math.max(1, x1 - x0), (height - 40) / Math.max(1, y1 - y0))
            readonly property real ox: (width - (x1 - x0) * k) / 2
            readonly property real oy: (height - (y1 - y0) * k) / 2
            Rectangle { anchors.fill: parent; color: Theme.panel2; border.width: 1; border.color: Theme.line }
            Text {
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                text: pg.duplicate ? "DUPLICATED" : (pg.enabledOuts.length > 1 ? (Config.mobile ? "DRAG TO ARRANGE" : "DRAG TO ARRANGE  ·  HOLD SHIFT: NO SNAPPING") : "")
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.6
            }
            Repeater {
                model: pg.outs.length
                delegate: Rectangle {
                    id: mon
                    required property int index
                    readonly property var o: pg.outs[index]
                    readonly property bool cur: pg.sel === index
                    visible: o.enabled
                    property bool dragging: false
                    x: dragging ? x : canvas.ox + (o.x - canvas.x0) * canvas.k + (pg.duplicate ? index * 6 : 0)
                    y: dragging ? y : canvas.oy + (o.y - canvas.y0) * canvas.k + (pg.duplicate ? index * 6 : 0)
                    width: pg.lw(o) * canvas.k; height: pg.lh(o) * canvas.k
                    z: cur ? 2 : 1
                    color: cur ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Theme.panel
                    border.width: cur ? 2 : 1; border.color: cur ? Theme.accent : Theme.lineStrong
                    Text {
                        anchors.centerIn: parent; anchors.verticalCenterOffset: -6
                        text: mon.o.num; color: mon.cur ? Theme.accent : Theme.fg
                        font.family: Theme.display; font.pixelSize: Math.max(14, Math.min(42, mon.height * 0.4))
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
                        width: parent.width - 8; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: (mon.o.primary ? "MAIN · " : "") + mon.o.name
                        color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: pg.enabledOuts.length > 1 && !pg.duplicate ? Qt.SizeAllCursor : Qt.PointingHandCursor
                        drag.target: pg.enabledOuts.length > 1 && !pg.duplicate ? mon : null
                        drag.threshold: 4
                        preventStealing: true   // else the page's Flickable takes vertical drags and the drop never lands
                        onPressed: pg.sel = mon.index
                        onPositionChanged: if (drag.active) mon.dragging = true
                        onCanceled: mon.dragging = false
                        onReleased: mouse => {
                            if (!mon.dragging) return;
                            // read the drop spot first: clearing `dragging` snaps x/y back to the old place
                            const wx = Math.round((mon.x - canvas.ox) / canvas.k + canvas.x0);
                            const wy = Math.round((mon.y - canvas.oy) / canvas.k + canvas.y0);
                            mon.dragging = false;
                            // lines up with edges within ~8 px on the canvas; Shift places it freely
                            const snap = (mouse.modifiers & Qt.ShiftModifier) ? 0 : 8 / canvas.k;
                            pg.outs = pg.pack(pg.clone(pg.outs), mon.index, wx, wy, snap);
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: pg.outs.length > 0
            Layout.fillWidth: true
            spacing: 10
            Chips {   // pick a display (also the disabled ones)
                Layout.fillWidth: true
                options: pg.outs.map((o, i) => ({ id: String(i), label: o.num + "  " + o.name + (o.enabled ? "" : " (off)") }))
                current: String(pg.sel)
                onPicked: id => pg.sel = parseInt(id)
            }
            ChamferButton { text: "Identify"; onClicked: pg.identify() }
        }

        // Apply right under the arrangement, where the changes are made
        RowLayout {
            Layout.fillWidth: true
            visible: pg.dirty && !pg.pending
            Text {
                Layout.fillWidth: true
                text: "Changes aren't applied yet."; color: Theme.warn
                font.family: Theme.ui; font.pixelSize: 12
            }
            ChamferButton {
                text: "Reset"
                visible: pg.dirty && !pg.pending
                onClicked: pg.outs = pg.clone(pg.applied)
            }
            ChamferButton {
                text: "Apply"; primary: true
                visible: pg.dirty && !pg.pending
                onClicked: pg.applyNow()
            }
        }
        // ---- several displays ----
        ColumnLayout {
            visible: pg.enabledOuts.length > 1
            Layout.fillWidth: true
            spacing: 8
            SectionLabel { text: "Multiple displays" }
            Chips {
                Layout.fillWidth: true
                options: [{ id: "extend", label: "Extend" }, { id: "duplicate", label: "Duplicate" }]
                current: pg.duplicate ? "duplicate" : "extend"
                onPicked: id => pg.outs = id === "duplicate" ? pg.duplicateAll(pg.clone(pg.outs)) : pg.extendAll(pg.clone(pg.outs))
            }
            Text {
                text: "RAIL ON"; color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
            }
            Chips {   // takes effect at once (no countdown: nothing about the screens changes)
                Layout.fillWidth: true
                options: [{ id: "all", label: "Every display" }, { id: "main", label: "Main display only" }]
                current: Config.barsOn
                onPicked: id => Config.barsOn = id
            }
        }

        // ---- the selected display ----
        ColumnLayout {
            id: od
            visible: pg.outs.length > 0
            Layout.fillWidth: true
            spacing: 8
            readonly property var o: pg.outs[pg.sel] || null
            SectionLabel { text: od.o ? "Display " + od.o.num + "  ·  " + od.o.name : "" }
            Text {
                Layout.fillWidth: true
                text: od.o ? od.o.desc : ""; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ChamferButton {
                    visible: !!od.o && od.o.enabled && !od.o.primary
                    text: "Make this my main display"
                    onClicked: pg.edit(pg.sel, { primary: true })
                }
                Text {
                    visible: !!od.o && od.o.primary
                    Layout.fillWidth: Config.mobile
                    wrapMode: Config.mobile ? Text.WordWrap : Text.NoWrap   // else its one-line width forces the whole page wider
                    text: "■ MAIN DISPLAY  ·  launcher, notifications and new windows open here"
                    color: Theme.accent; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                }
            }
            ToggleRow {
                Layout.fillWidth: true
                text: "Use this display"
                visible: pg.outs.length > 1
                checked: !!od.o && od.o.enabled
                onToggled: v => {
                    if (!v && pg.enabledOuts.length <= 1) { Toasts.show("Display", "At least one display has to stay on."); return; }
                    const patch = { enabled: v };
                    if (!v && od.o.primary) {   // the main display moves to another one that stays on
                        const other = pg.outs.findIndex((x, i) => i !== pg.sel && x.enabled);
                        const l = pg.clone(pg.outs);
                        l.forEach((x, i) => x.primary = i === other);
                        l[pg.sel].enabled = false;
                        pg.outs = pg.pack(l);
                        return;
                    }
                    if (v) { patch.x = 1e6; patch.y = 0; }   // back on: to the right of the others
                    pg.edit(pg.sel, patch);
                }
            }
            ColumnLayout {
                visible: !!od.o && od.o.enabled
                Layout.fillWidth: true
                spacing: 8
                Text {
                    visible: pg.enabledOuts.length > 1 && !pg.duplicate
                    Layout.fillWidth: Config.mobile; wrapMode: Config.mobile ? Text.WordWrap : Text.NoWrap
                    text: "POSITION  (TOP-LEFT CORNER, LOGICAL PIXELS)"; color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                }
                RowLayout {   // exact placement; Enter moves it (it stays touching a neighbour)
                    visible: pg.enabledOuts.length > 1 && !pg.duplicate
                    spacing: 8
                    Text { text: "X"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 12 }
                    TextEntry {
                        id: posX; implicitWidth: 90
                        text: od.o ? String(od.o.x) : ""
                        onAccepted: pg.place(pg.sel, parseInt(text), parseInt(posY.text))
                    }
                    Text { text: "Y"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 12 }
                    TextEntry {
                        id: posY; implicitWidth: 90
                        text: od.o ? String(od.o.y) : ""
                        onAccepted: pg.place(pg.sel, parseInt(posX.text), parseInt(text))
                    }
                }
                Dropdown {
                    label: "Resolution"
                    options: od.o ? pg.resolutions(od.o) : []
                    current: od.o ? od.o.mode.w + "x" + od.o.mode.h : ""
                    onPicked: id => pg.pickResolution(pg.sel, id)
                }
                Dropdown {
                    label: "Refresh rate"
                    options: od.o ? pg.rates(od.o) : []
                    current: od.o ? od.o.mode.r.toFixed(3) : ""
                    onPicked: id => pg.pickRate(pg.sel, id)
                }
                Text {
                    text: "SCALE"; color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                }
                Chips {
                    Layout.fillWidth: true
                    options: [1, 1.25, 1.5, 1.75, 2, 2.5, 3].map(s => ({ id: String(s), label: Math.round(s * 100) + "%" }))
                    current: od.o ? String(od.o.scale) : ""
                    onPicked: id => pg.edit(pg.sel, { scale: parseFloat(id) })
                }
                Text {
                    text: "ROTATION"; color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                }
                Chips {
                    Layout.fillWidth: true
                    options: [{ id: "normal", label: "Landscape" }, { id: "90", label: "Portrait" },
                              { id: "180", label: "Landscape (flipped)" }, { id: "270", label: "Portrait (flipped)" }]
                    current: od.o ? od.o.transform : ""
                    onPicked: id => pg.edit(pg.sel, { transform: id })
                }
                ToggleRow {
                    Layout.fillWidth: true
                    text: "Adaptive sync (VRR) all the time  (fullscreen games get it anyway)"
                    checked: !!od.o && od.o.vrr
                    onToggled: v => pg.edit(pg.sel, { vrr: v })
                }
            }
        }

        Text {
            visible: SetSys.dryRun
            text: "Dry run: changes are logged, not applied."
            color: Theme.warn; font.family: Theme.mono; font.pixelSize: 10
        }
    }

    // ---------- "Keep these settings?" ----------
    Rectangle {
        visible: pg.pending
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: {} }   // swallow input
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 380); height: dlg.implicitHeight + 40
            color: Theme.panel; border.width: 1; border.color: Theme.lineStrong
            Brackets {}
            ColumnLayout {
                id: dlg
                anchors.fill: parent; anchors.margins: 20
                spacing: 14
                Text {
                    text: "KEEP THESE SETTINGS?"
                    color: Theme.fg; font.family: Theme.display; font.pixelSize: 14; font.letterSpacing: 2
                }
                Text {
                    Layout.fillWidth: true
                    text: "The display configuration will revert in " + pg.countdown + " s if you do nothing."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13; wrapMode: Text.WordWrap
                }
                Rectangle {
                    Layout.fillWidth: true; height: 4; color: Theme.panel2
                    border.width: 1; border.color: Theme.line
                    Rectangle { height: parent.height; width: parent.width * pg.countdown / 15; color: pg.countdown <= 5 ? Theme.warn : Theme.accent }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    ChamferButton { text: "Revert"; onClicked: pg.revert() }
                    ChamferButton { text: "Keep"; primary: true; onClicked: pg.keep() }
                }
            }
        }
    }
}
