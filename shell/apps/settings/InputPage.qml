// Input: touchpad / pointer / keyboard settings. Writes ~/.config/ultimit/compositor.ini (format in
// compositor/src/config.c) and runs `ultimitctl reload` so they apply live. Only its own keys are
// written (SetSys.iniSet): other keys and sections (numlock, [windows]...) stay as they are.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Page {
    id: pg
    title: "Input"

    // current values (defaults match config.c)
    property bool tap: true
    property bool natural: false
    property real accel: 0.0
    property bool dwt: false
    property bool leftHanded: false
    property string layout: "us"
    property string variant: ""
    property string options: ""
    property int repeatRate: 25
    property int repeatDelay: 600
    property bool loaded: false
    property var layouts: []
    property var variants: []

    function applyIni(text) {
        let sec = "";
        for (let line of text.split("\n")) {
            line = line.trim();
            if (line === "" || line[0] === "#" || line[0] === ";") continue;
            if (line[0] === "[") { sec = line.slice(1, line.indexOf("]")); continue; }
            const i = line.indexOf("="); if (i < 0) continue;
            const k = line.slice(0, i).trim(), v = line.slice(i + 1).trim();
            const b = v === "true" || v === "1" || v === "yes";
            if (sec === "pointer") {
                if (k === "tap") tap = b; else if (k === "natural_scroll") natural = b;
                else if (k === "accel_speed") accel = Math.max(-1, Math.min(1, parseFloat(v) || 0));
                else if (k === "disable_while_typing") dwt = b; else if (k === "left_handed") leftHanded = b;
            } else if (sec === "keyboard") {
                if (k === "layout") layout = v; else if (k === "variant") variant = v;
                else if (k === "options") options = v;
                else if (k === "repeat_rate") repeatRate = parseInt(v) || 25;
                else if (k === "repeat_delay") repeatDelay = parseInt(v) || 600;
            }
        }
    }
    function iniText(old) {
        let t = old.trim() === "" ? "# Written by Ultimit Settings. Re-read with: ultimitctl reload\n" : old;
        t = SetSys.iniSet(t, "pointer", { tap: tap, natural_scroll: natural, accel_speed: accel.toFixed(2),
                                           disable_while_typing: dwt, left_handed: leftHanded });
        return SetSys.iniSet(t, "keyboard", { layout: layout, variant: variant, options: options,
                                              repeat_rate: repeatRate, repeat_delay: repeatDelay });
    }
    function changed() { if (loaded) save.restart(); }
    onTapChanged: changed(); onNaturalChanged: changed(); onAccelChanged: changed()
    onDwtChanged: changed(); onLeftHandedChanged: changed(); onLayoutChanged: changed()
    onVariantChanged: changed(); onRepeatRateChanged: changed(); onRepeatDelayChanged: changed()

    Timer {
        id: save
        interval: 350
        onTriggered: { ini.saving = true; ini.go(); }   // re-read first: another page may have written it
    }
    Timer { id: reload; interval: 150; onTriggered: SetSys.reloadCompositor() }

    // dry-run reads back its own earlier output, falling back to the real file (read-only)
    Cmd {
        id: ini
        argv: ["sh", "-c", 'cat "$1" 2>/dev/null || cat "$2" 2>/dev/null; true', "sh", SetSys.cfgPath("compositor.ini"), SetSys.home + "/.config/ultimit/compositor.ini"]
        property bool saving: false
        onDone: out => {
            if (saving) { saving = false; SetSys.writeFile(SetSys.cfgPath("compositor.ini"), pg.iniText(out)); reload.start(); return; }
            pg.applyIni(out); pg.loaded = true; varCmd.go();
        }
    }
    Cmd {
        id: layoutsCmd
        argv: ["localectl", "list-x11-keymap-layouts"]
        onDone: out => pg.layouts = out.split("\n").filter(x => x !== "").map(x => ({ id: x, label: x }))
    }
    Cmd {
        id: varCmd
        argv: ["localectl", "list-x11-keymap-variants", pg.layout]
        onDone: (out, code) => {
            const v = code === 0 ? out.split("\n").filter(x => x !== "").map(x => ({ id: x, label: x })) : [];
            pg.variants = [{ id: "", label: "Default" }].concat(v);
        }
    }
    Component.onCompleted: { layoutsCmd.go(); ini.go(); }

    SectionLabel { text: "Touchpad" }
    ToggleRow { Layout.fillWidth: true; text: "Tap to click"; checked: pg.tap; onToggled: v => pg.tap = v }
    ToggleRow { Layout.fillWidth: true; text: "Natural scrolling"; checked: pg.natural; onToggled: v => pg.natural = v }
    ToggleRow { Layout.fillWidth: true; text: "Disable while typing"; checked: pg.dwt; onToggled: v => pg.dwt = v }
    Text {
        Layout.fillWidth: true
        text: "Warning: on this laptop's ELAN touchpad, disable-while-typing blocked every tap and click. Leave it off unless you need it."
        color: Theme.warn; font.family: Theme.ui; font.pixelSize: Theme.type.label; wrapMode: Text.WordWrap
    }

    SectionLabel { text: "Pointer" }
    SliderField {
        Layout.fillWidth: true
        label: "Pointer speed"
        from: -100; to: 100
        value: Math.round(pg.accel * 100)
        onMoved: v => pg.accel = v / 100
    }
    ToggleRow { Layout.fillWidth: true; text: "Left-handed (swap buttons)"; checked: pg.leftHanded; onToggled: v => pg.leftHanded = v }

    SectionLabel { text: "Keyboard" }
    Flow {
        Layout.fillWidth: true
        ChamferButton { text: "Keyboard shortcuts  (Super+/)"; onClicked: Config.shortcutsOpen = true }
    }
    Dropdown {
        label: "Layout"
        options: pg.layouts
        current: pg.layout
        onPicked: id => { pg.variant = ""; pg.layout = id; varCmd.go(); }
    }
    Dropdown {
        label: "Variant"
        options: pg.variants
        current: pg.variant
        placeholder: "Default"
        onPicked: id => pg.variant = id
    }
    SliderField {
        Layout.fillWidth: true
        label: "Repeat rate (keys / s)"
        from: 2; to: 60
        value: pg.repeatRate
        onMoved: v => pg.repeatRate = v
    }
    SliderField {
        Layout.fillWidth: true
        label: "Repeat delay (ms)"
        from: 150; to: 1000
        value: pg.repeatDelay
        onMoved: v => pg.repeatDelay = Math.round(v / 10) * 10
    }
}
