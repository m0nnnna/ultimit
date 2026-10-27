// Windows: the snap widths Super+Left/Right cycles through. Writes [windows] snap_widths in
// ~/.config/ultimit/compositor.ini (format in compositor/src/config.c; other keys are kept, see
// SetSys.iniSet) and runs `ultimitctl reload` so they apply live.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Page {
    id: pg
    title: "Windows"
    subtitle: "Super+Left / Super+Right snaps a window to that side of the screen; pressing it again steps to the next width. " +
              "The first width is also what dragging a window to the left or right edge gives."

    readonly property var defaults: [1 / 2, 1 / 3, 2 / 3]
    readonly property int maxWidths: 8                   // UL_SNAP_MAX
    property var widths: defaults.slice()
    property int sel: 0
    property bool loaded: false

    // Fractions people mean when they pick 33% or 67%: written as "1/3" so they stay exact.
    readonly property var named: [[1, 2], [1, 3], [2, 3], [1, 4], [3, 4], [1, 5], [2, 5], [3, 5], [4, 5]]
    function fromPercent(p) {
        for (const [n, d] of named) if (Math.round(100 * n / d) === p) return n / d;
        return p / 100;
    }
    function label(w) {
        for (const [n, d] of named) if (Math.abs(w - n / d) < 1e-4) return n + "/" + d;
        return Math.round(w * 100) + "%";
    }
    function parse(v) {   // same rules as config.c: a/b, n%, 0.n; 10-90%; nothing usable -> defaults
        const out = [];
        for (const tok of v.split(/[ ,]+/)) {
            if (tok === "" || out.length >= maxWidths) continue;
            let m, w = NaN;
            if ((m = tok.match(/^([\d.]+)\/([\d.]+)$/)) && parseFloat(m[2]) > 0) w = parseFloat(m[1]) / parseFloat(m[2]);
            else if ((m = tok.match(/^([\d.]+)%$/))) w = parseFloat(m[1]) / 100;
            else if (/^[\d.]+$/.test(tok)) w = parseFloat(tok);
            if (w >= 0.1 - 1e-9 && w <= 0.9 + 1e-9) out.push(w);
        }
        return out.length ? out : defaults.slice();
    }
    function applyIni(text) {
        let sec = "";
        for (let line of text.split("\n")) {
            line = line.trim();
            if (line === "" || line[0] === "#" || line[0] === ";") continue;
            if (line[0] === "[") { sec = line.slice(1, line.indexOf("]")); continue; }
            const i = line.indexOf("="); if (i < 0) continue;
            if (sec === "windows" && line.slice(0, i).trim() === "snap_widths") widths = parse(line.slice(i + 1).trim());
        }
    }
    function iniText(old) {
        const t = old.trim() === "" ? "# Written by Ultimit Settings. Re-read with: ultimitctl reload\n" : old;
        return SetSys.iniSet(t, "windows", { snap_widths: widths.map(label).join(", ") });
    }
    function setWidths(w) { widths = w; sel = Math.min(sel, w.length - 1); if (loaded) save.restart(); }
    function setAt(i, w) { const a = widths.slice(); a[i] = w; setWidths(a); }
    function move(i, d) {
        const j = i + d; if (j < 0 || j >= widths.length) return;
        const a = widths.slice(); [a[i], a[j]] = [a[j], a[i]]; sel = j; setWidths(a);
    }
    function remove(i) { if (widths.length > 1) { const a = widths.slice(); a.splice(i, 1); setWidths(a); } }
    function add() {
        if (widths.length >= maxWidths) return;
        const free = [1 / 4, 3 / 4, 1 / 3, 2 / 3, 1 / 2, 2 / 5, 3 / 5].find(c => !widths.some(w => Math.abs(w - c) < 1e-4));
        sel = widths.length;
        setWidths(widths.concat([free !== undefined ? free : 1 / 2]));
    }

    readonly property var presets: [
        { id: "classic",  label: "Classic",          w: [1 / 2, 1 / 3, 2 / 3] },
        { id: "quarters", label: "Halves + quarters", w: [1 / 2, 1 / 4, 3 / 4] },
        { id: "all",      label: "Thirds + quarters", w: [1 / 2, 1 / 3, 2 / 3, 1 / 4, 3 / 4] },
        { id: "wide",     label: "Wide first",        w: [2 / 3, 3 / 4, 1 / 2] },
        { id: "fifths",   label: "Fifths",            w: [1 / 2, 2 / 5, 3 / 5, 1 / 5, 4 / 5] }
    ]
    function presetId() {
        for (const p of presets)
            if (p.w.length === widths.length && p.w.every((w, i) => Math.abs(w - widths[i]) < 1e-4)) return p.id;
        return "";
    }

    Timer {
        id: save
        interval: 350
        onTriggered: { ini.saving = true; ini.go(); }   // re-read first: another page may have written it
    }
    Timer { id: reload; interval: 150; onTriggered: SetSys.reloadCompositor() }

    // dry-run reads back its own earlier output, falling back to the real file (read-only)
    Cmd {
        id: ini
        property bool saving: false
        argv: ["sh", "-c", 'cat "$1" 2>/dev/null || cat "$2" 2>/dev/null; true', "sh", SetSys.cfgPath("compositor.ini"), SetSys.home + "/.config/ultimit/compositor.ini"]
        onDone: out => {
            if (saving) { saving = false; SetSys.writeFile(SetSys.cfgPath("compositor.ini"), pg.iniText(out)); reload.start(); return; }
            pg.applyIni(out); pg.loaded = true;
        }
    }
    Component.onCompleted: ini.go()

    SectionLabel { text: "Preview" }
    Rectangle {   // a screen with the selected width snapped left and the rest of the cycle marked
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(width / 5)
        color: Theme.field
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        Rectangle {
            id: snapped
            x: 1; y: 1; height: parent.height - 2
            width: (parent.width - 2) * (pg.widths[pg.sel] || 0.5)
            color: Theme.accent; opacity: 0.35
            Behavior on width { NumberAnimation { duration: Config.dur(150); easing.type: Easing.OutCubic } }
        }
        Rectangle { x: snapped.width; y: 1; width: 2; height: parent.height - 2; color: Theme.accent }
        Repeater {   // the other stops in the cycle
            model: pg.widths
            delegate: Rectangle {
                required property var modelData
                required property int index
                visible: index !== pg.sel
                x: 1 + (parent.width - 2) * modelData; y: parent.height - 10
                width: 1; height: 9; color: Theme.dim
            }
        }
        Text {
            anchors.centerIn: snapped
            text: pg.label(pg.widths[pg.sel] || 0.5)
            color: Theme.fg
            font.family: Theme.display; font.pixelSize: Theme.ds(18); font.letterSpacing: Theme.dt(1.6)
        }
    }

    SectionLabel { text: "Presets" }
    Chips {
        Layout.fillWidth: true
        options: pg.presets
        current: pg.presetId()
        onPicked: id => { for (const p of pg.presets) if (p.id === id) { pg.sel = 0; pg.setWidths(p.w.slice()); } }
    }

    SectionLabel { text: "Snap widths, in the order Super+Left/Right steps through them" }
    Repeater {
        model: pg.widths
        delegate: RowLayout {
            id: row
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 8
            Rectangle {   // selects the row for the preview
                Layout.preferredWidth: 2; Layout.fillHeight: true
                color: pg.sel === row.index ? Theme.accent : "transparent"
            }
            SliderField {
                Layout.fillWidth: true
                label: (row.index === 0 ? "1st · also drag-to-edge" : (row.index + 1) + (row.index === 1 ? "nd" : row.index === 2 ? "rd" : "th"))
                from: 10; to: 90
                value: Math.round(row.modelData * 100)
                valueText: pg.label(row.modelData)
                onMoved: v => { pg.sel = row.index; pg.setAt(row.index, pg.fromPercent(v)); }
                onActiveFocusChanged: if (activeFocus) pg.sel = row.index
            }
            ChamferButton { text: "↑"; implicitWidth: 34; enabled: row.index > 0; opacity: enabled ? 1 : 0.3; onClicked: pg.move(row.index, -1) }
            ChamferButton { text: "↓"; implicitWidth: 34; enabled: row.index < pg.widths.length - 1; opacity: enabled ? 1 : 0.3; onClicked: pg.move(row.index, 1) }
            ChamferButton { text: "✕"; implicitWidth: 34; enabled: pg.widths.length > 1; opacity: enabled ? 1 : 0.3; onClicked: pg.remove(row.index) }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        ChamferButton { text: "Add width"; visible: pg.widths.length < pg.maxWidths; onClicked: pg.add() }
        ChamferButton { text: "Reset to default"; onClicked: { pg.sel = 0; pg.setWidths(pg.defaults.slice()); } }
    }
    Text {
        Layout.fillWidth: true
        text: "Widths are 10–90% of the screen. Super+Down (or the opposite arrow) puts a snapped window back as it was."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label; wrapMode: Text.WordWrap
    }
}
