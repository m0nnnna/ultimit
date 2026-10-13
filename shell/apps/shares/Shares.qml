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


    // =====================================================================================================
    // CONNECT: other computers' shares through gvfs (connect.py; no admin rights)
    // =====================================================================================================
    readonly property string connectHelper: Quickshell.shellPath("apps/shares/connect.py")
    property string tab: "mine"             // mine | connect
    property var caps: ({})                 // connect.py caps
    property var servers: []                // [{name, host, address}]
    property bool discovering: false
    property bool discovered: false
    property string discoverNote: ""
    property var mounts: []                 // [{uri, name, path, scheme}]
    property var saved: []                  // [{name, uri, user, domain, remember, reconnectAtLogin}]
    property var browseServer: null         // {name, host} being browsed
    property var browseShares: []
    property bool browsing: false
    property string browseError: ""
    property var credReq: null              // {kind: "browse"|"connect", host, uri, name, user, domain, wrong}
    property var connInfo: ({})             // uri -> {user, domain, remember} of connections made here (never a password)
    property string connecting: ""          // uri / host being connected
    property bool openAfter: false          // open the folder after the next successful connect (launcher / DATA driven)

    function runC(args, input, cb) {
        procC.createObject(root, { command: ["python3", root.connectHelper].concat(args), input: input || "", cb: cb });
    }
    function showConnect() { show(); tab = "connect"; refreshConnect(); if (!discovered) discover(); }
    function refreshConnect() {
        runC(["mounts"], "", o => { if (o.ok) mounts = o.mounts; });
        runC(["saved"], "", o => { if (o.ok) saved = o.saved; });
        if (!loadedCaps) { loadedCaps = true; runC(["caps"], "", o => { if (o.ok) caps = o.caps; }); }
    }
    property bool loadedCaps: false
    Timer { interval: 5000; repeat: true; running: root.open && root.tab === "connect"; onTriggered: root.refreshConnect() }

    function discover() {
        if (discovering) return;
        discovering = true; discoverNote = "";
        runC(["discover"], "", o => {
            discovering = false; discovered = true;
            servers = (o.servers || []).filter(s => !s.self);
            discoverNote = o.err || "";
        });
    }
    function isMounted(uri) {
        const k = uri.replace(/\/+$/, "").toLowerCase();
        for (const m of mounts) if (m.uri.replace(/\/+$/, "").toLowerCase() === k) return true;
        return false;
    }
    function isSaved(uri) {
        const k = uri.replace(/\/+$/, "").toLowerCase();
        for (const c of saved) if (c.uri.replace(/\/+$/, "").toLowerCase() === k) return true;
        return false;
    }
    function browseHost(server) {
        browseServer = server; browseShares = []; browseError = "";
        doBrowse(server, null);
    }
    // creds: {user, domain, password, remember} or null. The password travels over stdin only.
    function doBrowse(server, creds) {
        browsing = true; browseError = "";
        const a = ["browse", server.host];
        if (creds) { a.push("--user", creds.user, "--domain", creds.domain, "--password-stdin"); }
        runC(a, creds ? creds.password : "", o => {
            browsing = false;
            if (o.ok) { browseShares = o.shares; if (creds) hostCreds[server.host] = { user: creds.user, domain: creds.domain }; }
            else if (o.code === "needs_password" || o.code === "denied") {
                const h = hostCreds[server.host] || {};
                credReq = { kind: "browse", host: server.host, name: server.name || server.host, user: (creds ? creds.user : h.user) || "",
                            domain: (creds ? creds.domain : h.domain) || "", wrong: o.code === "denied" };
                overlay = "creds";
            } else browseError = o.error || "Could not list the shares.";
        });
    }
    property var hostCreds: ({})
    function connectShare(host, share) { connectAddress("smb://" + host + "/" + encodeURIComponent(share), false); }

    // address: any form. openFolder: open the mounted folder afterwards.
    function connectAddress(address, openFolder) {
        showConnect();
        openAfter = openFolder === true;
        runC(["normalize", address], "", n => {
            if (!n.ok) { say(n.error, "error"); return; }
            if (n.kind === "server") { browseHost({ name: n.host, host: n.host }); return; }
            if (n.kind === "share" || n.kind === "other") doConnect(n.uri, null, n.user ? { user: n.user, domain: n.domain } : null);
        });
    }
    function doConnect(uri, creds, hint) {
        if (connecting !== "") return;
        connecting = uri;
        say("Connecting\u2026");
        const a = ["connect", uri];
        const remember = !!(creds && creds.remember);
        if (creds) { a.push("--user", creds.user, "--domain", creds.domain, "--password-stdin"); if (remember) a.push("--remember"); }
        runC(a, creds ? creds.password : "", o => {
            connecting = "";
            if (o.ok) {
                connInfo[o.uri] = { user: creds ? creds.user : "", domain: creds ? creds.domain : "", remember: remember && o.passwordSaved !== false };
                say(o.note || ("Connected to " + o.name + "."), o.note ? "info" : "info");
                refreshConnect();
                if (openAfter) { openAfter = false; if (o.path) openFolder(o.path); }
            } else if (o.code === "needs_password" || o.code === "denied") {
                const p = hint || creds || {};
                credReq = { kind: "connect", uri: uri, name: uri, user: p.user || "", domain: p.domain || "", wrong: o.code === "denied" };
                overlay = "creds";
                say("");
            } else say(o.error || "Could not connect.", "error");
        });
    }
    // The credentials dialog's answer (fields are cleared by the dialog right after this call).
    function submitCreds(user, domain, pw, remember) {
        const r = credReq; credReq = null;
        if (!r) return;
        const c = { user: user, domain: domain, password: pw, remember: remember };
        if (r.kind === "browse") doBrowse({ name: r.name, host: r.host }, c);
        else doConnect(r.uri, c, null);
    }
    function disconnect(uri) {
        runC(["disconnect", uri], "", o => {
            say(o.ok ? "Disconnected." : (o.error || "Could not disconnect."), o.ok ? "info" : "error");
            refreshConnect();
        });
    }
    function saveMount(m) {
        const i = connInfo[m.uri] || {};
        const a = ["save", m.uri, "--name", m.name];
        if (i.user) a.push("--user", i.user);
        if (i.domain) a.push("--domain", i.domain);
        if (i.remember) a.push("--remember");
        runC(a, "", o => { if (o.ok) { saved = o.saved; say("Saved \u201c" + m.name + "\u201d."); } else say(o.error, "error"); });
    }
    function unsave(uri) { runC(["unsave", uri], "", o => { if (o.ok) saved = o.saved; }); }
    function setReconnect(uri, on) { runC(["set-reconnect", uri, on ? "on" : "off"], "", o => { if (o.ok) saved = o.saved; }); }
    function connectSaved(c) {
        doConnect(c.uri, null, c.user ? { user: c.user, domain: c.domain } : null);
    }

    function dump() {
        return JSON.stringify({ loaded: loaded, open: open, overlay: overlay, busy: busy, note: note,
            ready: canShare, host: host, tab: tab, servers: servers.length, mounts: mounts.length, saved: saved.length,
            browse: browseShares, credReq: credReq !== null, connecting: connecting, shares: shares.map(s => s.name), steps: steps.map(s => s.id + ":" + s.state) });
    }
}
