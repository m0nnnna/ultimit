pragma Singleton

// Store.qml - state of STORE, the Ultimit app store over Flathub. Reading goes through store.py (JSON
// on stdout); installing, removing and opening apps are plain flatpak runs (system installation: flatpak
// asks polkit, the Ultimit agent shows the prompt). One job at a time; more queue up. The process stays
// alive while a job runs, even after the window is closed.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/store/store.py")

    // ---- window state ----
    property bool open: false
    property string view: "home"            // home | results | app | installed
    property string query: ""
    property string category: ""           // AppStream main category id, "" = all
    property string categoryLabel: ""
    property string appId: ""               // view === "app"
    property string backView: "home"

    function show() { quitTimer.stop(); open = true; if (!homeLoaded) loadHome(); }
    function showSearch(q) { show(); search(q, ""); }
    function showApp(id) { show(); openApp(id); }

    // ---- data ----
    property bool homeLoaded: false
    property var picks: []
    property var categories: []
    property int total: 0
    property var installedIds: []
    property var results: []
    property int resultCount: 0
    property bool searching: false
    property var app: null                  // full record of appId
    property var installedApps: []          // [{id, name, version, origin, size}]
    property string error: ""

    function isInstalled(id) { return installedIds.indexOf(id) >= 0; }

    // ---- store.py runs: run(args, cb(json)) ----
    function run(args, cb) { procC.createObject(root, { command: ["python3", root.helper].concat(args), cb: cb }); }
    Component {
        id: procC
        Process {
            id: p
            property var cb
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    let o;
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "STORE could not read Flathub's catalogue." }; }
                    if (p.cb) p.cb(o);
                    p.destroy();
                }
            }
        }
    }

    function loadHome() {
        run(["home"], o => {
            if (!o.ok && o.fix && !setup.tried) { setup.start(o.fix); return; }
            if (!o.ok) { root.error = o.error || "Flathub is not available."; return; }
            root.error = "";
            root.picks = o.picks; root.categories = o.categories; root.total = o.total;
            root.installedIds = o.installed; root.homeLoaded = true;
        });
    }
    property int _searchSeq: 0
    function search(q, cat) {
        query = q; category = cat || "";
        categoryLabel = "";
        for (const c of categories) if (c.id === category) categoryLabel = c.label;
        if (query.trim() === "" && category === "") { view = "home"; return; }
        view = "results"; searching = true;
        const seq = ++_searchSeq;
        run(["search", query, category], o => {
            if (seq !== root._searchSeq) return;     // a newer search is on its way
            root.searching = false;
            root.results = o.ok ? o.apps : []; root.resultCount = o.ok ? o.count : 0;
            if (!o.ok) root.error = o.error || "";
        });
    }
    function openApp(id) {
        if (view !== "app") backView = view;
        appId = id; app = null; view = "app";
        run(["app", id], o => { if (o.ok && root.appId === id) root.app = o.app; });
    }
    function back() { view = backView === "app" ? "home" : backView; }
    function showInstalled() { view = "installed"; refreshInstalled(); }
    function refreshInstalled() {
        run(["installed"], o => {
            if (!o.ok) return;
            root.installedApps = o.apps;
            root.installedIds = o.apps.map(a => a.id);
        });
    }

    // ---- first run: add Flathub and/or download its catalogue, then load again ----
    // `flatpak remote-add` does not fetch the AppStream catalogue STORE reads; that only arrives with
    // the next `flatpak update`. Downloading it needs no password (polkit appstream-update); adding
    // the remote asks for one through the Ultimit agent. Tried once per run.
    readonly property string flathubRepo: "https://dl.flathub.org/repo/flathub.flatpakrepo"
    property bool settingUp: setup.running
    Process {
        id: setup
        property bool tried: false
        property bool addFirst: false
        property string err: ""
        function start(fix) {
            tried = true; err = ""; addFirst = fix === "remote";
            root.error = "";
            command = addFirst
                ? ["sh", "-c", "flatpak remote-add --system --if-not-exists flathub \"$1\" && flatpak update -y --noninteractive --appstream --system flathub", "sh", root.flathubRepo]
                : ["flatpak", "update", "-y", "--noninteractive", "--appstream", "--system", "flathub"];
            running = true;
        }
        stderr: SplitParser { onRead: line => { const t = line.trim(); if (t !== "") setup.err = t; } }
        onExited: code => {
            if (code === 0) { root.loadHome(); return; }
            root.error = /not authorized|authentication|dismissed/i.test(err)
                ? "Flathub isn't set up. Open STORE again to set it up."
                : "Couldn't download Flathub's catalogue" + (err ? ": " + err.replace(/^error:\s*/i, "") : ".")
                  + " Check the internet connection and open STORE again.";
        }
    }

    // ---- jobs: install / remove (queued) ----
    property var queue: []                  // [{kind: "install"|"remove", id, name}]
    property var job: null                  // the running one
    property real pct: -1
    property string jobMsg: ""
    property string note: ""
    property string noteKind: "info"        // info | ok | error
    readonly property bool busy: job !== null

    function jobFor(id) {
        if (job && job.id === id) return job.kind;
        for (const j of queue) if (j.id === id) return j.kind + "-queued";
        return "";
    }
    function install(id, name) { enqueue({ kind: "install", id: id, name: name || id }); }
    function remove(id, name) { enqueue({ kind: "remove", id: id, name: name || id }); }
    function enqueue(j) {
        if (jobFor(j.id) !== "") return;
        queue = queue.concat([j]);
        next();
    }
    function next() {
        if (job || queue.length === 0) return;
        job = queue[0]; queue = queue.slice(1);
        pct = -1; jobMsg = job.kind === "install" ? "Getting ready…" : "Removing…"; note = "";
        flatpak.err = "";
        flatpak.command = job.kind === "install"
            ? ["flatpak", "install", "-y", "--noninteractive", "--system", "flathub", job.id]
            : ["flatpak", "uninstall", "-y", "--noninteractive", job.id];
        flatpak.running = true;
    }
    Process {
        id: flatpak
        property string err: ""
        stdout: SplitParser {
            // flatpak without a terminal prints lines like "Installing 1/3… 45%" or "Installing… done"
            splitMarker: "\n"
            onRead: line => {
                const t = line.replace(/\r/g, "").trim();
                if (t === "") return;
                const m = t.match(/(\d+)%/);
                if (m) root.pct = parseInt(m[1]);
                const step = t.match(/^(Installing|Updating|Uninstalling)\s+(\d+)\/(\d+)/);
                if (step) root.jobMsg = step[1] + " " + step[2] + " of " + step[3] + "…";
            }
        }
        stderr: SplitParser { onRead: line => { const t = line.trim(); if (t !== "") flatpak.err = t; } }
        onExited: code => {
            const j = root.job;
            if (code === 0) {
                root.note = j.kind === "install" ? j.name + " is installed." : j.name + " was removed.";
                root.noteKind = "ok";
            } else if (/not authorized|authentication|dismissed/i.test(flatpak.err)) {
                root.note = "Cancelled."; root.noteKind = "info";
            } else {
                root.note = (j.kind === "install" ? "Couldn't install " : "Couldn't remove ") + j.name
                    + (flatpak.err ? ": " + flatpak.err.replace(/^error:\s*/i, "") : ".");
                root.noteKind = "error";
            }
            root.job = null; root.pct = -1; root.jobMsg = "";
            root.refreshInstalled();
            if (root.queue.length > 0) root.next();
            else if (!root.open) quitTimer.restart();
        }
    }

    function launch(id) { Quickshell.execDetached(["flatpak", "run", id]); }

    // ---- lifetime: exit once the window is closed and nothing is running ----
    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open && !root.busy) Qt.quit() }
    onOpenChanged: if (!open) quitTimer.restart()

    function dump() {
        return JSON.stringify({ open: open, view: view, query: query, category: category, appId: appId,
            total: total, picks: picks.length, results: results.length, resultCount: resultCount,
            installed: installedIds, job: job, queue: queue, note: note, error: error });
    }
}
