pragma Singleton

// Tasks.qml - state of TASKS, the Ultimit task manager: the process table and the PERFORMANCE history, fed once a
// second by the long-running helper tasks.py (`watch`: one JSON line per tick on stdout). Ending, killing, pausing go
// through `tasks.py signal`; another user's process asks for the password through polkit (the Ultimit agent shows the
// dialog), and a dismissed prompt is a calm note, never an error.
//
// With TASKS_FAKE=1 in the environment the helper shows a pretend machine and signals do nothing.
import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/tasks/tasks.py")
    readonly property bool fake: Quickshell.env("TASKS_FAKE") === "1"
    readonly property string me: Quickshell.env("USER")

    // A fixed warning red for destructive things: Theme.bad turns orange on red-ish accents.
    readonly property color danger: Theme.light ? "#c62828" : "#ff4d4f"

    // ---- window state ----
    property bool open: false
    property string tab: "processes"        // processes | performance
    property string overlay: ""             // "" | "kill" | "term" | "stop" | "critical"

    function show() { quitTimer.stop(); open = true; }

    // ---- process table view ----
    property string filter: "apps"          // apps | mine | all
    property string search: ""
    property string sortKey: "cpu"
    property bool sortDesc: true
    property int selPid: -1                 // stays on the same process across ticks
    // column widths shared by the header and the rows (the name column takes what is left)
    readonly property var colW: ({ pid: 64, user: 92, cpu: 66, mem: 88, gpu: 88, threads: 64, state: 86 })
    readonly property int colTotal: colW.pid + colW.user + colW.cpu + colW.mem + colW.gpu + colW.threads + colW.state
    property string note: ""
    property string noteKind: "info"        // info | error
    function say(text, kind) { note = text; noteKind = kind || "info"; }

    function sortBy(key) {
        if (sortKey === key) sortDesc = !sortDesc;
        else { sortKey = key; sortDesc = key !== "name" && key !== "user" && key !== "pid" && key !== "state"; }
    }
    onFilterChanged: syncRows()
    onSearchChanged: syncRows()
    onSortKeyChanged: syncRows()
    onSortDescChanged: syncRows()
    onTabChanged: { note = ""; if (tab === "processes") syncRows(); }

    // ---- the latest tick ----
    property bool loaded: false
    property var snap: ({})                 // everything but the process list
    property var byPid: ({})                // pid -> process of the last tick
    property var hist: ({ cpu: [], mem: [], swap: [], gpu: [], vram: [], read: [], write: [], rx: [], tx: [] })
    readonly property int histLen: 60

    readonly property var sel: byPid[selPid] || null
    readonly property var gpu: snap.gpu || null

    // ---- the helper: tasks.py watch ----
    Process {
        id: watcher
        command: ["python3", root.helper, "watch"]
        running: root.open
        stdout: SplitParser {
            onRead: line => {
                let o;
                try { o = JSON.parse(line); } catch (e) { return; }
                if (o.ok) root.apply(o);
            }
        }
        // the helper only stops when we are closing; if it died on its own, start it again
        onExited: if (root.open) restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: if (root.open) watcher.running = true }

    function push(arr, v) {
        const a = arr.length >= histLen ? arr.slice(arr.length - histLen + 1) : arr.slice();
        a.push(v);
        return a;
    }
    function apply(o) {
        const procs = o.procs;
        delete o.procs;
        const m = {};
        for (const p of procs) m[p.pid] = p;
        byPid = m;
        snap = o;
        const g = o.gpu;
        hist = {
            cpu: push(hist.cpu, o.cpu.total),
            mem: push(hist.mem, o.mem.total > 0 ? o.mem.used * 100 / o.mem.total : 0),
            swap: push(hist.swap, o.mem.swap_total > 0 ? o.mem.swap_used * 100 / o.mem.swap_total : 0),
            gpu: push(hist.gpu, g && g.util !== null ? g.util : 0),
            vram: push(hist.vram, g && g.mem_total ? g.mem_used * 100 / g.mem_total : 0),
            read: push(hist.read, o.disk.read), write: push(hist.write, o.disk.write),
            rx: push(hist.rx, o.net.rx), tx: push(hist.tx, o.net.tx)
        };
        loaded = true;
        if (tab === "processes") syncRows();
    }

    // ---- the table model: updated in place (rows move, change or go; the list keeps its scroll position) ----
    property ListModel rows: ListModel {}
    property int shown: 0
    property int matching: 0

    function rowOf(p) {
        const n = p.titles.length;
        return {
            pid: p.pid, name: p.name, cmd: p.cmd, user: p.user, cpu: p.cpu, rss: p.rss,
            gpuMem: p.gpu_mem === null || p.gpu_mem === undefined ? -1 : p.gpu_mem,
            threads: p.threads, state: p.state, app: p.app, critical: p.critical,
            title: n === 0 ? "" : p.titles[0] + (n > 1 ? "  +" + (n - 1) : "")
        };
    }
    function wanted(p) {
        if (filter === "apps" && p.app === "") return false;
        if (filter === "mine" && p.user !== me) return false;
        const q = search.trim().toLowerCase();
        if (q === "") return true;
        return String(p.pid) === q || p.name.toLowerCase().indexOf(q) >= 0 || p.cmd.toLowerCase().indexOf(q) >= 0
            || p.user.toLowerCase().indexOf(q) >= 0 || p.titles.join(" ").toLowerCase().indexOf(q) >= 0
            || String(p.pid).indexOf(q) === 0;
    }
    function compare(a, b) {
        let r;
        switch (sortKey) {
        case "name": r = a.name.toLowerCase().localeCompare(b.name.toLowerCase()); break;
        case "user": r = a.user.localeCompare(b.user); break;
        case "state": r = a.state.localeCompare(b.state); break;
        case "gpu": r = (a.gpu_mem || 0) - (b.gpu_mem || 0); break;
        case "mem": r = a.rss - b.rss; break;
        case "threads": r = a.threads - b.threads; break;
        case "pid": r = a.pid - b.pid; break;
        default: r = a.cpu - b.cpu;
        }
        if (sortDesc) r = -r;
        return r !== 0 ? r : a.pid - b.pid;
    }
    function syncRows() {
        const want = [];
        for (const pid in byPid) {
            const p = byPid[pid];
            if (wanted(p)) want.push(p);
        }
        want.sort(compare);
        matching = want.length;
        for (let i = 0; i < want.length; i++) {
            const r = rowOf(want[i]);
            if (i < rows.count && rows.get(i).pid === r.pid) { update(i, r); continue; }
            let j = -1;
            for (let k = i + 1; k < rows.count; k++) if (rows.get(k).pid === r.pid) { j = k; break; }
            if (j >= 0) { rows.move(j, i, 1); update(i, r); }
            else rows.insert(i, r);
        }
        if (rows.count > want.length) rows.remove(want.length, rows.count - want.length);
        shown = rows.count;
    }
    function update(i, r) {
        const old = rows.get(i);
        for (const k in r) if (old[k] !== r[k]) rows.setProperty(i, k, r[k]);
    }

    // ---- actions ----
    signal submitRequested()                // ipc submitDialog (tests): press the open dialog's main button
    property var pending: null              // {pid, name, sig, critical} waiting for the person's answer
    property bool busy: false

    // End / Kill / Pause / Resume on the selected process; warns first when it is the system or the desktop.
    function ask(mode) {
        const p = sel;
        if (!p) return;
        const sig = { term: "TERM", kill: "KILL", stop: "STOP", cont: "CONT" }[mode];
        if (!sig) return;
        pending = { pid: p.pid, name: p.name, sig: sig, critical: p.critical };
        if (p.critical) overlay = "critical";
        else if (sig === "KILL") overlay = "kill";
        else confirm();
    }
    function confirm() {
        const t = pending;
        overlay = "";
        pending = null;
        if (!t || busy) return;
        busy = true;
        const verb = { TERM: "Asked", KILL: "Killed", STOP: "Paused", CONT: "Resumed" }[t.sig];
        say({ TERM: "Asking ", KILL: "Killing ", STOP: "Pausing ", CONT: "Resuming " }[t.sig] + t.name + "… enter your password if asked.");
        run(["signal", String(t.pid), t.sig].concat(t.critical ? ["--force"] : []), o => {
            busy = false;
            if (o.cancelled) say("Cancelled. Nothing was changed.");
            else if (o.gone) say(t.name + " was already gone.");
            else if (!o.ok) say(o.error || "That did not work.", "error");
            else say(t.sig === "TERM" ? "Asked " + t.name + " to quit." : verb + " " + t.name + ".");
        });
    }

    function run(args, cb) {
        procC.createObject(root, { command: ["python3", root.helper].concat(args), cb: cb });
    }
    Component {
        id: procC
        Process {
            id: p
            property var cb
            stdout: StdioCollector {
                onStreamFinished: {
                    let o;
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "The TASKS helper failed." }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }
    function copy(text) { Quickshell.execDetached(["wl-copy", text]); say("Copied."); }

    // TASKS is its own process: exit shortly after the window closes (a new open request cancels it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open) Qt.quit() }
    onOpenChanged: if (!open) quitTimer.restart();

    // ---- formatting ----
    function fmt(b) {                       // memory: binary units, as htop does
        if (b === null || b === undefined || b < 0) return "";
        const u = ["B", "KiB", "MiB", "GiB", "TiB"];
        let i = 0, v = b;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (i === 0 || v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }
    function rate(b) { return fmt(b) + "/s"; }
    function pct(v) { return (v < 10 ? v.toFixed(1) : Math.round(v)) + "%"; }
    function duration(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d > 0 ? d + " d " : "") + (d > 0 || h > 0 ? h + " h " : "") + m + " min";
    }
    function stateText(s) {
        return { R: "Running", S: "Sleeping", D: "Waiting", T: "Paused", t: "Paused", Z: "Zombie", I: "Idle", X: "Dead" }[s] || s;
    }

    function dump() {
        const s = snap;
        return JSON.stringify({ loaded: loaded, open: open, tab: tab, overlay: overlay, filter: filter, search: search, sortKey: sortKey,
            sortDesc: sortDesc, selPid: selPid, sel: sel ? sel.name : "", shown: shown, matching: matching, note: note, fake: fake,
            procs: loaded ? s.counts.procs : 0, threads: loaded ? s.counts.threads : 0, cpu: loaded ? s.cpu.total : -1,
            cores: loaded ? s.cpu.cores.length : 0, memUsed: loaded ? s.mem.used : -1, gpu: gpu ? gpu.name + " " + gpu.util + "%" : "",
            apps: Object.keys(byPid).filter(k => byPid[k].app !== "").map(k => byPid[k].name + ":" + byPid[k].pid),
            top: rows.count > 0 ? rows.get(0).name + ":" + rows.get(0).cpu : "", hist: hist.cpu.length });
    }
}
