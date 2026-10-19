pragma Singleton

// Items.qml - state of ITEMS, the Ultimit device settings app (mice and other peripherals with their own settings).
// items.py does the work: `list` (supported devices and which are plugged in), `get ID` (what the device can do, and
// the saved settings), `set ID` (JSON on stdin: check, save, send). Most gaming mice can't report their settings
// back, so the saved file is the source of truth and Apply sends everything.
//
// With ITEMS_FAKE=1 every device shows as plugged in and Apply writes to a file instead of the device.
import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/items/items.py")
    readonly property bool fake: Quickshell.env("ITEMS_FAKE") === "1"

    // ---- window state ----
    property bool open: false
    function show() { quitTimer.stop(); open = true; refresh(); }

    property var devices: []
    property string current: ""             // device id
    property var device: null               // {id, name, kind, present}
    property var schema: null
    property var config: null               // edited copy
    property string savedJson: ""           // what is saved, to tell if there are changes
    property var keys: []
    property var modifiers: []
    property int profile: 0
    property bool busy: false
    readonly property bool dirty: config !== null && JSON.stringify(config) !== savedJson

    property string note: ""
    property string noteKind: "info"        // info | error | ok
    function say(text, kind) { note = text; noteKind = kind || "info"; }

    function refresh() {
        run(["list"], "", o => {
            if (!o.ok) { say(o.error, "error"); return; }
            devices = o.devices;
            if (current === "" && devices.length > 0) {
                const p = devices.find(d => d.present);
                select((p || devices[0]).id);
            }
        });
    }
    function select(id) {
        current = id;
        note = "";
        run(["get", id], "", o => {
            if (!o.ok) { say(o.error, "error"); return; }
            device = o.device;
            schema = o.schema;
            keys = o.keys;
            modifiers = o.modifiers;
            savedJson = JSON.stringify(o.config);
            config = o.config;
            if (profile >= schema.profiles) profile = 0;
            if (!o.saved) say("These are the default settings. Apply sends them to the device.");
        });
    }
    function revert() { config = JSON.parse(savedJson); note = ""; }

    // ---- editing the current profile (a new object each time so bindings update) ----
    readonly property var prof: config ? config.profiles[profile] : null
    function setProf(key, value) {
        const c = JSON.parse(JSON.stringify(config));
        c.profiles[profile][key] = value;
        config = c;
    }
    function setDpi(i, value) {
        const d = prof.dpi.slice();
        d[i] = value;
        setProf("dpi", d);
    }
    function setButton(id, value) {
        const b = Object.assign({}, prof.buttons);
        b[id] = value;
        setProf("buttons", b);
    }
    function copyToAll() {
        const c = JSON.parse(JSON.stringify(config));
        for (let i = 0; i < c.profiles.length; i++) c.profiles[i] = JSON.parse(JSON.stringify(c.profiles[profile]));
        config = c;
        say("Profile " + (profile + 1) + " copied to every profile. Apply to send it.");
    }

    // ---- checks, so mistakes show while typing (items.py checks again before sending) ----
    // "" when fine, else a short reason
    function actionError(t) {
        t = String(t).trim().toLowerCase();
        if (t === "") return "empty";
        if (t.indexOf("raw:") === 0) return /^raw:([0-9a-f]{2}){1,4}$/.test(t) ? "" : "raw: takes 1 to 4 hex bytes";
        if (schema && schema.functions.indexOf(t) >= 0) return "";
        const parts = t.replace(/ /g, "").split("+").filter(p => p !== "");
        for (let i = 0; i < parts.length - 1; i++)
            if (modifiers.indexOf(parts[i]) < 0) return "'" + parts[i] + "' is not a modifier";
        return keys.indexOf(parts[parts.length - 1]) >= 0 ? "" : "'" + parts[parts.length - 1] + "' is not a key";
    }
    function dpiError(v) {
        if (!/^\d+$/.test(String(v))) return "a number";
        const n = Number(v);
        if (n === 0) return "";
        return n >= schema.dpi.min && n <= schema.dpi.max ? "" : schema.dpi.min + "–" + schema.dpi.max + ", 0 = off";
    }
    function colorOk(c) { return /^#?[0-9a-fA-F]{6}$/.test(String(c)); }
    readonly property int problems: {
        if (!config || !schema) return 0;
        let n = 0;
        for (const p of config.profiles) {
            if (!colorOk(p.color)) n++;
            for (const d of p.dpi) if (dpiError(d) !== "") n++;
            for (const b of schema.buttons) if (actionError(p.buttons[b.id] || "") !== "") n++;
        }
        return n;
    }

    function apply() {
        if (problems > 0) { say("Fix the fields marked in red first (some may be on other profiles).", "error"); return; }
        busy = true;
        const c = JSON.parse(JSON.stringify(config));
        for (const p of c.profiles) {
            p.color = String(p.color).replace("#", "").toLowerCase();
            p.dpi = p.dpi.map(Number);
        }
        run(["set", current], JSON.stringify(c), o => {
            busy = false;
            if (o.saved) savedJson = JSON.stringify(c);
            if (o.ok) { config = c; say("Sent to the " + (device ? device.kind : "device") + ".", "ok"); }
            else say(o.error, "error");
        });
    }

    // ---- helper process: run(args, stdinText, callback(parsedJson)) ----
    function run(args, input, cb) {
        procC.createObject(root, { command: ["python3", root.helper].concat(args), input: input || "", cb: cb });
    }
    Component {
        id: procC
        Process {
            id: p
            property string input: ""
            property var cb
            stdinEnabled: input !== ""
            onStarted: if (input !== "") { write(input + "\n"); input = ""; stdinEnabled = false; }
            stdout: StdioCollector {
                onStreamFinished: {
                    let o;
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "The ITEMS helper failed." }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }

    function dump() {
        return JSON.stringify({ open: open, current: current, profile: profile, dirty: dirty, problems: problems,
                                note: note, devices: devices, config: config });
    }

    // ITEMS is its own process: exit shortly after the window closes (a new open request cancels it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open) Qt.quit() }
    onOpenChanged: if (!open) quitTimer.restart();
}
