// Display: per-output resolution / refresh, scale, adaptive sync, arrangement. Changes go through
// wlr-randr (wlr-output-management) and are confirmed with a 15 s "Keep these settings?" countdown;
// without confirmation (or when the window closes) the previous configuration is restored.
// Confirmed configs are saved to ~/.config/ultimit/displays.conf (see writeConf for the format).
import QtQuick
import QtQuick.Layouts
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

    // ---------- helpers ----------
    function clone(v) { return JSON.parse(JSON.stringify(v)); }
    function mkey(m) { return m.w + "x" + m.h + "@" + m.r.toFixed(3); }
    function swapped(o) { return o.transform === "90" || o.transform === "270" || o.transform === "flipped-90" || o.transform === "flipped-270"; }
    function lw(o) { return (swapped(o) ? o.mode.h : o.mode.w) / o.scale; }
    function lh(o) { return (swapped(o) ? o.mode.w : o.mode.h) / o.scale; }
    function comparable(list) {
        return JSON.stringify(list.map(o => [o.name, o.enabled, o.mode.w, o.mode.h, o.mode.r.toFixed(3), o.scale, o.vrr, o.x, o.y]));
    }
    readonly property bool dirty: comparable(outs) !== comparable(applied)

    function parse(text) {
        let j;
        try { j = JSON.parse(text); } catch (e) { return []; }
        return j.map(o => {
            const modes = (o.modes || []).map(m => ({ w: m.width, h: m.height, r: m.refresh, cur: !!m.current }));
            const cur = modes.find(m => m.cur) || modes[0] || { w: 0, h: 0, r: 0 };
            return {
                name: o.name, desc: o.description || o.name, enabled: !!o.enabled,
                modes: modes, mode: { w: cur.w, h: cur.h, r: cur.r },
                scale: o.scale || 1, vrr: !!o.adaptive_sync,
                x: o.position ? o.position.x : 0, y: o.position ? o.position.y : 0,
                transform: o.transform || "normal", rel: "right"
            };
        });
    }
    // Infer left/right/above/below (relative to the first output) from loaded positions.
    function inferRel(list) {
        for (let i = 1; i < list.length; i++) {
            const o = list[i], r = list[0];
            if (o.x >= r.x + lw(r)) o.rel = "right";
            else if (o.x + lw(o) <= r.x) o.rel = "left";
            else if (o.y >= r.y + lh(r)) o.rel = "below";
            else o.rel = "above";
        }
        return list;
    }
    // Lay outputs out edge to edge around the first one (which keeps its position).
    function layout(list) {
        if (list.length < 2) return list;
        const r = list[0];
        let minX = r.x, maxX = r.x + lw(r), minY = r.y, maxY = r.y + lh(r);
        for (let i = 1; i < list.length; i++) {
            const o = list[i], w = lw(o), h = lh(o);
            if (!o.enabled) continue;
            if (o.rel === "right") { o.x = Math.round(maxX); o.y = r.y; }
            else if (o.rel === "left") { o.x = Math.round(minX - w); o.y = r.y; }
            else if (o.rel === "below") { o.x = r.x; o.y = Math.round(maxY); }
            else { o.x = r.x; o.y = Math.round(minY - h); }
            minX = Math.min(minX, o.x); maxX = Math.max(maxX, o.x + w);
            minY = Math.min(minY, o.y); maxY = Math.max(maxY, o.y + h);
        }
        return list;
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
    function edit(i, patch) {
        const l = clone(outs);
        Object.assign(l[i], patch);
        outs = layout(l);
    }
    function resolutions(o) {
        const seen = {}; const out = [];
        for (const m of o.modes) {
            const k = m.w + "x" + m.h;
            if (!seen[k]) { seen[k] = true; out.push({ id: k, label: m.w + " × " + m.h, area: m.w * m.h }); }
        }
        out.sort((a, b) => b.area - a.area);
        return out;
    }
    function rates(o) {
        return o.modes.filter(m => m.w === o.mode.w && m.h === o.mode.h)
            .sort((a, b) => b.r - a.r)
            .map(m => ({ id: m.r.toFixed(3), label: m.r > 0 ? parseFloat(m.r.toFixed(2)) + " Hz" : "Default" }));
    }
    function pickResolution(i, id) {
        const o = outs[i];
        const [w, h] = id.split("x").map(Number);
        const cand = o.modes.filter(m => m.w === w && m.h === h);
        if (!cand.length) return;
        cand.sort((a, b) => Math.abs(a.r - o.mode.r) - Math.abs(b.r - o.mode.r));
        edit(i, { mode: { w: w, h: h, r: cand[0].r } });
    }
    function pickRate(i, id) {
        const o = outs[i];
        const m = o.modes.find(m => m.w === o.mode.w && m.h === o.mode.h && m.r.toFixed(3) === id);
        if (m) edit(i, { mode: { w: m.w, h: m.h, r: m.r } });
    }

    // ---------- persistence: ~/.config/ultimit/displays.conf ----------
    // INI-like, one section per output, section name = connector name (e.g. [eDP-1]):
    //   enabled = true|false          mode = <w>x<h>@<refresh Hz, 3 decimals>   scale = <float>
    //   x = <logical px>   y = <logical px>   transform = normal|90|180|270|flipped|flipped-90|...
    //   adaptive_sync = true|false
    function writeConf(list) {
        let t = "# Written by Ultimit Settings. One [section] per output (connector name).\n" +
                "# mode = WxH@Hz, x/y = logical position, transform = wl_output transform name.\n";
        for (const o of list) {
            t += "\n[" + o.name + "]\n" +
                 "enabled = " + o.enabled + "\n" +
                 "mode = " + o.mode.w + "x" + o.mode.h + (o.mode.r > 0 ? "@" + o.mode.r.toFixed(3) : "") + "\n" +
                 "scale = " + o.scale.toFixed(2) + "\n" +
                 "x = " + o.x + "\n" + "y = " + o.y + "\n" +
                 "transform = " + o.transform + "\n" +
                 "adaptive_sync = " + o.vrr + "\n";
        }
        SetSys.writeFile(SetSys.cfgPath("displays.conf"), t);
    }

    // ---------- apply / keep / revert ----------
    Cmd {
        id: read
        argv: ["wlr-randr", "--json"]
        onDone: (out, code) => {
            if (code !== 0) { pg.status = "Could not query outputs (wlr-randr failed)."; return; }
            const l = pg.parse(out);
            pg.applied = pg.inferRel(l);
            if (!pg.pending) pg.outs = pg.clone(pg.applied);
            pg.status = l.length === 0 ? "No outputs reported." : "";
        }
    }
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
    function applyNow() {
        const l = layout(clone(outs));
        outs = l;
        apply.argv = argsFor(l);
        apply.go();
    }
    function keep() {
        tick.stop(); pending = false;
        applied = clone(outs);
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

    // ---------- UI ----------
    Page {
        anchors.fill: parent
        title: "Display"

        Text {
            visible: pg.status !== ""
            Layout.fillWidth: true
            text: pg.status; color: Theme.warn; font.family: Theme.ui; font.pixelSize: 13; wrapMode: Text.WordWrap
        }

        // arrangement preview
        Item {
            id: prev
            visible: pg.outs.length > 1
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            readonly property real k: {
                if (pg.outs.length < 2) return 1;
                let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
                for (const o of pg.outs) { x0 = Math.min(x0, o.x); x1 = Math.max(x1, o.x + pg.lw(o)); y0 = Math.min(y0, o.y); y1 = Math.max(y1, o.y + pg.lh(o)); }
                return Math.min((width - 20) / Math.max(1, x1 - x0), 100 / Math.max(1, y1 - y0));
            }
            readonly property real ox: { let m = 1e9; for (const o of pg.outs) m = Math.min(m, o.x); return m; }
            readonly property real oy: { let m = 1e9; for (const o of pg.outs) m = Math.min(m, o.y); return m; }
            Rectangle { anchors.fill: parent; color: Theme.panel2; border.width: 1; border.color: Theme.line }
            Repeater {
                model: pg.outs.length > 1 ? pg.outs.length : 0
                delegate: Rectangle {
                    required property int index
                    readonly property var o: pg.outs[index]
                    x: 10 + (o.x - prev.ox) * prev.k
                    y: 10 + (o.y - prev.oy) * prev.k
                    width: pg.lw(o) * prev.k; height: pg.lh(o) * prev.k
                    color: "transparent"; border.width: 1; border.color: Theme.accent
                    Text {
                        anchors.centerIn: parent; text: o.name; color: Theme.fg
                        font.family: Theme.mono; font.pixelSize: 10
                    }
                }
            }
        }

        Repeater {
            model: pg.outs.length
            delegate: ColumnLayout {
                id: od
                required property int index
                readonly property var o: pg.outs[index]
                Layout.fillWidth: true
                spacing: 8

                SectionLabel { text: od.o.name }
                Text {
                    Layout.fillWidth: true
                    text: od.o.desc; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; elide: Text.ElideRight
                }
                Dropdown {
                    label: "Resolution"
                    options: pg.resolutions(od.o)
                    current: od.o.mode.w + "x" + od.o.mode.h
                    onPicked: id => pg.pickResolution(od.index, id)
                }
                Dropdown {
                    label: "Refresh rate"
                    options: pg.rates(od.o)
                    current: od.o.mode.r.toFixed(3)
                    onPicked: id => pg.pickRate(od.index, id)
                }
                Text {
                    text: "SCALE"; color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                }
                Chips {
                    Layout.fillWidth: true
                    options: [1, 1.25, 1.5, 2].map(s => ({ id: String(s), label: s + "×" }))
                    current: String(od.o.scale)
                    onPicked: id => pg.edit(od.index, { scale: parseFloat(id) })
                }
                ToggleRow {
                    Layout.fillWidth: true
                    text: "Adaptive sync (VRR)"
                    checked: od.o.vrr
                    onToggled: v => pg.edit(od.index, { vrr: v })
                }
                ColumnLayout {
                    visible: od.index > 0
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "POSITION RELATIVE TO " + pg.outs[0].name.toUpperCase(); color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                    }
                    Chips {
                        Layout.fillWidth: true
                        options: [{ id: "left", label: "Left" }, { id: "right", label: "Right" }, { id: "above", label: "Above" }, { id: "below", label: "Below" }]
                        current: od.o.rel
                        onPicked: id => pg.edit(od.index, { rel: id })
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: pg.outs.length > 0
            Item { Layout.fillWidth: true }
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
