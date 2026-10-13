pragma Singleton

// Firewall.qml - state of FIREWALL, the Ultimit ufw manager: on/off, presets (VTube Studio, Steam Remote Play, ...),
// recently blocked connections and the rule list, all through the helper firewall.py (JSON on stdout). Changes go
// through the root helper via pkexec (the Ultimit polkit agent asks once, then remembers for a few minutes); a
// dismissed prompt is a calm note, never an error.
//
// With FIREWALL_FAKE=1 in the environment the helper talks to a fake ufw instead of the real one (see fixtures/),
// so the UI can be tried without root.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/firewall/firewall.py")
    readonly property bool fake: Quickshell.env("FIREWALL_FAKE") === "1"

    // ---- window state ----
    property bool open: false
    property string tab: "apps"             // apps | blocked | rules
    property string overlay: ""             // "" | "add" | "remove" | "disable"
    property var removeRule: null           // rule being confirmed for removal
    property var addPrefill: null           // {port, proto} for the Add rule dialog

    function show() { quitTimer.stop(); open = true; refresh(); }

    // ---- snapshot ----
    property bool loaded: false
    property var st: ({})                   // firewall.py state
    property string busy: ""                // action running ("" = idle): enable | disable | preset:<id> | allow | remove | setup:<step>
    property string note: ""
    property string noteKind: "info"        // info | error
    property bool refreshing: false

    readonly property bool helperInstalled: st.helper === true
    readonly property bool ufwInstalled: !st.ufw || st.ufw.installed !== false
    readonly property bool locked: st.locked === true
    readonly property bool ready: loaded && helperInstalled && ufwInstalled && !locked && st.ok !== false
    readonly property bool active: ready && st.ufw.active === true
    readonly property string subnet: st.subnet || ""
    readonly property var presets: st.presets || []
    readonly property var rules: st.rules || []
    readonly property var blocked: st.blocked || []
    readonly property int blockedOpen: blocked.filter(b => !b.allowed).length
    readonly property string logNote: st.logNote || ""
    readonly property var groups: {
        const g = [];
        for (const p of presets) if (g.indexOf(p.group) < 0) g.push(p.group);
        return g;
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
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "The FIREWALL helper failed." }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }

    function say(text, kind) { note = text; noteKind = kind || "info"; }

    // ---- refresh ----
    function refresh() {
        if (refreshing) return;
        refreshing = true;
        run(["state"], "", o => {
            refreshing = false;
            st = o;
            loaded = true;
            if (o.ok === false && o.error) say(o.error, "error");
        });
    }
    // Polls while the window is open; stops while locked so a non-admin is not asked every 5 s.
    Timer { interval: 5000; repeat: true; running: root.open && root.busy === "" && !root.locked; onTriggered: root.refresh() }

    // FIREWALL is its own process: exit shortly after the window closes (a new open request cancels it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open) Qt.quit() }
    onOpenChanged: if (!open) quitTimer.restart()

    // ---- actions (each one asks for authorization through polkit) ----
    function act(tag, args, waiting, done, cb) {
        if (busy !== "") return;
        busy = tag;
        say(waiting || "Waiting for your authorization…");
        run(args, "", o => {
            busy = "";
            if (o.cancelled) say("Cancelled. Nothing was changed.");
            else if (!o.ok) say(o.error || "That did not work.", "error");
            else say(typeof done === "function" ? done(o) : done);
            if (cb) cb(o);
            refresh();
        });
    }
    function setEnabled(on) {
        act(on ? "enable" : "disable", [on ? "enable" : "disable"], "",
            on ? "The firewall is on. Only what you allow below can reach this PC." : "The firewall is off.");
    }
    function presetById(id) { for (const p of presets) if (p.id === id) return p; return null; }
    function setPreset(id, on) {
        const p = presetById(id);
        const name = p ? p.name : id;
        act("preset:" + id, ["preset", id, on ? "on" : "off"], "",
            o => o.changed === 0 ? name + " was already " + (on ? "allowed." : "closed.")
                 : on ? name + " is allowed from your home network (" + subnet + ")." : name + " is closed again.");
    }
    function allow(port, proto, from, comment, cb) {
        act("allow", ["allow", port, proto, from, "--comment", comment], "", "Rule added.", cb);
    }
    // A blocked connection: turn on its preset when there is one, otherwise allow just that port from the home network.
    function allowBlocked(b) {
        if (b.preset !== "") setPreset(b.preset, true);
        else allow(String(b.port), b.proto, "lan", "Port " + b.port + " " + b.proto.toUpperCase());
    }
    function remove(line) { act("remove", ["remove", line], "", "Rule removed."); }
    function setup(step) {
        act("setup:" + step, ["setup", step], step === "install-ufw" ? "Installing ufw… this can take a minute." : "",
            step === "install-ufw" ? "ufw is installed." : "The firewall helper is installed.");
    }
    function unlock() { st = Object.assign({}, st, { locked: false }); refresh(); }
    function checkAllow(port, proto, cb) { run(["check-allow", port, proto], "", cb); }
    function setupCommands(cb) { run(["setup-commands"], "", cb); }

    function agoText(s) {
        if (s < 60) return "just now";
        if (s < 3600) return Math.round(s / 60) + " min ago";
        return Math.round(s / 3600) + " h ago";
    }

    function dump() {
        return JSON.stringify({ loaded: loaded, open: open, tab: tab, overlay: overlay, busy: busy, note: note,
            helper: helperInstalled, ufw: ufwInstalled, locked: locked, active: active, subnet: subnet,
            presets: presets.map(p => p.id + ":" + p.state), rules: rules.length, blocked: blocked.map(b => b.port + "/" + b.proto) });
    }
}
