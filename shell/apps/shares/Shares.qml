pragma Singleton

// Shares.qml - state of SHARES, the Ultimit file share maker: the Samba status, the list of usershares and
// every action, all through the helper shares.py (JSON on stdout). Privileged setup steps run there too, via
// pkexec (the Ultimit polkit agent shows the prompt); a dismissed prompt is a calm note, never an error.
//
// With SHARES_FAKE=1 in the environment the helper talks to fake programs instead of the real system
// (see fixtures/), so the UI can be tried without Samba or root.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/shares/shares.py")
    readonly property bool fake: Quickshell.env("SHARES_FAKE") === "1"

    // ---- window state ----
    property bool open: false
    property string overlay: ""             // "" | "new" | "password" | "remove"
    property string newPath: ""             // folder the New share dialog opens with
    property int newSeq: 0                  // bumped to (re)open the New share dialog
    property string removeName: ""

    function show() { quitTimer.stop(); open = true; refresh(); }
    property bool pendingNew: false         // New share requested before the first status arrived
    function showNew(path) {
        show(); newPath = path;
        if (loaded) newSeq++; else pendingNew = true;
    }

    // ---- snapshot ----
    property bool loaded: false
    property var st: ({})                   // shares.py status
    property var shares: []                 // [{name, path, comment, writable, guest}]
    property string listError: ""
    property string busy: ""                // setup step / action currently running ("" = idle)
    property string note: ""
    property string noteKind: "info"        // info | error
    property bool refreshing: false

    readonly property bool installed: st.installed === true
    readonly property bool active: st.active === true
    readonly property bool canShare: st.canShare === true
    readonly property bool guestsAllowed: !st.usershare || st.usershare.guests !== false
    readonly property string host: st.hostUpper || ""
    readonly property var addr: (st.addresses && st.addresses.length) ? st.addresses[0] : null
    readonly property string subnet: addr ? addr.subnet : ""
    readonly property string fwState: st.firewall ? st.firewall.state : "unknown"
    readonly property bool relogin: st.group ? st.group.reloginNeeded === true : false

    // Setup steps in order. state: done | needed | unknown | relogin | blocked (waits for an earlier step)
    readonly property var steps: {
        if (!loaded) return [];
        const g = st.group || {};
        const fw = fwState;
        const fwDone = fw === "allowed" || fw === "inactive" || fw === "none";
        return [
            { id: "install", label: "Install Samba", state: installed ? "done" : "needed",
              desc: "Samba is the program that shares folders with Windows, macOS, Linux and phones.", button: "Install" },
            { id: "service", label: "Start the sharing service", state: active ? "done" : (installed ? "needed" : "blocked"),
              desc: "The service that answers other computers; it starts by itself at every boot.", button: "Start" },
            { id: "group", label: "Allow sharing for your account",
              state: g.member && !g.reloginNeeded ? "done" : (g.reloginNeeded ? "relogin" : (installed ? "needed" : "blocked")),
              desc: g.reloginNeeded ? "Done. Log out and back in once so sharing works."
                                    : "Adds you to the “sambashare” group so you can create shares without a password prompt each time.",
              button: "Allow" },
            { id: "password", label: "Set your network password",
              state: st.password === "set" ? "done" : (installed ? (st.password === "unknown" ? "unknown" : "needed") : "blocked"),
              desc: "This is the password other computers use to open your shares. It can differ from your login password.",
              button: st.password === "set" ? "Change" : "Set password" },
            { id: "firewall", label: "Allow on home network",
              state: fwDone ? "done" : (fw === "unknown" ? "unknown" : "needed"),
              desc: fw === "inactive" || fw === "none" ? "No firewall is active, so nothing blocks your shares."
                    : fw === "allowed" ? "Computers on " + (st.firewall.subnet || subnet) + " can reach your shares."
                    : "Opens Samba to computers on your home network only (" + (subnet || "no network found") + ").",
              button: "Allow", extra: fw === "allowed" ? "Block again" : "" }
        ];
    }
    // Something still to do (a firewall that cannot be checked counts, so the button stays visible)
    readonly property bool setupNeeded: {
        for (const s of steps) if (s.state !== "done") return true;
        return false;
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
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "The SHARES helper failed." }; }
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
            if (!o.status) return;
            st = o.status;
            shares = o.shares.shares || [];
            listError = o.shares.ok ? "" : (o.shares.err || "");
            loaded = true;
            if (pendingNew) { pendingNew = false; newSeq++; }
        });
    }
    Timer { interval: 5000; repeat: true; running: root.open && root.busy === ""; onTriggered: root.refresh() }

    // SHARES is its own process: exit shortly after the window closes (a new open request cancels it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open) Qt.quit() }
    onOpenChanged: if (!open) quitTimer.restart()

    // ---- setup (privileged, user-confirmed) ----
    function setup(step) {
        if (busy !== "") return;
        busy = step;
        say(step === "install" ? "Installing Samba… this can take a minute." : "Waiting for your authorization…");
        run(["setup", step, "--subnet", subnet], "", o => {
            busy = "";
            if (o.cancelled) say("Cancelled. Nothing was changed.");
            else if (!o.ok) say(o.error || "That did not work.", "error");
            else say(step === "group" ? "Done. Log out and back in once so sharing works."
                    : step === "install" ? "Samba is installed."
                    : step === "firewall-allow" ? "Allowed on your home network (" + subnet + ")."
                    : step === "firewall-block" ? "Blocked again." : "Done.");
            refresh();
        });
    }
    function setPassword(pw) {
        if (busy !== "") return;
        busy = "password";
        say("Waiting for your authorization…");
        // the password goes through stdin only; the dialog fields are cleared by the caller
        run(["setup", "password"], pw, o => {
            busy = "";
            if (o.cancelled) say("Cancelled. Your password was not changed.");
            else if (!o.ok) say(o.error || "Could not set the password.", "error");
            else say("Your network password is set.");
            refresh();
        });
    }
    function mark(what) { run(["mark", what, "--subnet", subnet], "", o => refresh()); }

    // ---- shares ----
    function check(name, path, writable, guest, cb) {
        const a = ["check", name, path];
        if (writable) a.push("--writable");
        if (guest) a.push("--guest");
        run(a, "", cb);
    }
    function suggest(path, cb) { run(["suggest", path], "", cb); }
    function chmodOw(path, cb) { run(["chmod-ow", path], "", cb); }
    function add(name, path, writable, guest, comment, cb) {
        const a = ["add", name, path, "--comment", comment];
        if (writable) a.push("--writable");
        if (guest) a.push("--guest");
        busy = "add";
        run(a, "", o => {
            busy = "";
            if (o.ok) say("Sharing “" + o.share.name + "” as \\\\" + host + "\\" + o.share.name);
            cb(o);
            refresh();
        });
    }
    function remove(name) {
        busy = "remove";
        run(["remove", name], "", o => {
            busy = "";
            say(o.ok ? "Stopped sharing “" + name + "”." : (o.error || "Could not remove the share."), o.ok ? "info" : "error");
            refresh();
        });
    }
    function openFolder(path) { Quickshell.execDetached(["xdg-open", path]); }
    function copy(text, what) { Quickshell.clipboardText = text; say("Copied " + (what || text)); }
    function uncPath(name) { return "\\\\" + host + "\\" + name; }
    function smbUrl(name) { return "smb://" + (addr ? addr.ip : host) + "/" + encodeURIComponent(name); }

    function dump() {
        return JSON.stringify({ loaded: loaded, open: open, overlay: overlay, busy: busy, note: note,
            ready: canShare, host: host, shares: shares.map(s => s.name), steps: steps.map(s => s.id + ":" + s.state) });
    }
}
