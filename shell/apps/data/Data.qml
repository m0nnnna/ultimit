pragma Singleton

// Data.qml - state and logic of DATA, the Ultimit file manager.
//
// Directory listings, file operations (copy/move/trash/delete/rename), properties and
// "open with" lookups are done by apps/data/data.py (stdlib python, JSON over stdout).
// Everything touching disks is gated by env vars for headless tests:
//   ULTIMIT_DATA_START=<dir>   first location (default: $HOME)
//   ULTIMIT_DRY_RUN=1          log udisksctl / opener commands instead of running them
//   ULTIMIT_FAKE_LSBLK=<file>  read lsblk JSON from a file (fake removable drives)
//   ULTIMIT_FAKE_MTP=<json>    fake MTP phones: [{id,vendor,model,serial,bus,dev}] (see data.py)
//   ULTIMIT_FAKE_MTPFS=<exe>   stand-in for go-mtpfs (called: exe [-dev RE] MOUNTPOINT)
// Entry points:  Data.show(path) / Data.toggle()  (QML)
//                qs -p <shell> ipc call data open <path> | toggle   (see DataWindow.qml)
import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

Singleton {
    id: root

    // ---------------------------------------------------------------- environment
    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string helper: Quickshell.shellPath("apps/data/data.py")
    readonly property bool dryRun: Quickshell.env("ULTIMIT_DRY_RUN") === "1"
    readonly property string trashUri: "trash:"

    // ---------------------------------------------------------------- window state
    property bool open: false
    function toggle() { if (open) hide(); else show(""); }
    function hide() { open = false; }
    function show(p) {
        if (!started) { started = true; init(); }
        open = true;
        if (p && p !== "") goTo(p);
        else if (path === "") goTo(Quickshell.env("ULTIMIT_DATA_START") || home);
        raise++;
    }
    property int raise: 0          // bumped on show(): the window grabs focus
    property bool started: false

    // ---------------------------------------------------------------- location + history
    property string path: ""
    readonly property bool isTrash: path === trashUri
    property var backStack: []
    property var fwdStack: []
    property bool loading: false
    property string error: ""
    property var entries: []        // raw listing from data.py
    property var view: []           // filtered + sorted
    property bool keepScroll: false
    property string pendingSelect: ""
    property string lastStat: ""

    function join(d, n) { return d === "/" ? "/" + n : d + "/" + n; }
    function dirname(p) { const i = p.lastIndexOf("/"); return i <= 0 ? "/" : p.slice(0, i); }
    function basename(p) { const i = p.lastIndexOf("/"); return p.slice(i + 1); }
    function expand(p) {
        p = p.trim();
        if (p === "~") return home;
        if (p.startsWith("~/")) return home + p.slice(1);
        if (p.length > 1 && p.endsWith("/")) p = p.replace(/\/+$/, "");
        return p === "" ? "/" : p;
    }
    function title() {
        if (isTrash) return "Trash";
        return path === "/" ? "/" : basename(path);
    }

    function goTo(p, noHistory) {
        p = p === trashUri ? p : expand(p);
        if (p !== trashUri && !p.startsWith("/")) p = join(path === trashUri ? home : path, p);
        if (!noHistory && path !== "" && p !== path) {
            const b = backStack.slice(); b.push(path); backStack = b; fwdStack = [];
        }
        path = p;
        filter = "";
        keepScroll = false;
        clearSel();
        curPath = "";
        load();
        refreshDisk();
    }
    function goBack() {
        if (!backStack.length) return;
        const b = backStack.slice(); const p = b.pop(); backStack = b;
        const f = fwdStack.slice(); f.push(path); fwdStack = f;
        goTo(p, true);
    }
    function goForward() {
        if (!fwdStack.length) return;
        const f = fwdStack.slice(); const p = f.pop(); fwdStack = f;
        const b = backStack.slice(); b.push(path); backStack = b;
        goTo(p, true);
    }
    function goUp() {
        if (isTrash) { goTo(home); return; }
        if (path === "/") return;
        const from = path;
        pendingSelect = from;
        goTo(dirname(path));
    }
    function refresh(keep) { keepScroll = !!keep; load(); refreshDisk(); }

    // ---------------------------------------------------------------- listing
    property bool loadQueued: false
    function load() {
        if (path === "") return;
        if (lister.running) { loadQueued = true; return; }
        loading = true;
        lister.listPath = path;
        lister.command = ["python3", helper, "ls", path];
        lister.running = true;
    }
    Process {
        id: lister
        property string listPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (lister.listPath !== root.path) return;
                if (root.listTimedOut) {
                    root.listTimedOut = false; root.loading = false; root.entries = [];
                    root.error = "Phone not responding. Is it unlocked?"; root.rebuild(); return;
                }
                try {
                    const d = JSON.parse(text);
                    root.error = d.err;
                    root.entries = d.entries;
                } catch (e) {
                    root.error = "listing failed";
                    root.entries = [];
                }
                root.loading = false;
                root.rebuild();
                if (root.pendingSelect !== "") {
                    const i = root.view.findIndex(x => x.p === root.pendingSelect);
                    root.pendingSelect = "";
                    if (i >= 0) root.selectOnly(i);
                }
            }
        }
        onExited: if (root.loadQueued) { root.loadQueued = false; root.load(); }
    }
    property bool listTimedOut: false
    Timer {   // a stalled phone must not leave the window "READING…" forever
        interval: 20000
        running: lister.running && root.onMtp
        onTriggered: { root.listTimedOut = true; lister.running = false; }
    }
    // Directory changes made elsewhere: poll the directory's mtime (cheap) while DATA is open.
    Timer {
        interval: 2000; repeat: true
        running: root.open && root.path !== "" && !root.loading && !root.isTrash
        onTriggered: if (!statProc.running && !lister.running) statProc.running = true
    }
    Timer {   // trash has no single mtime we can trust across entries: re-list while shown
        interval: 3000; repeat: true
        running: root.open && root.isTrash && !root.loading
        onTriggered: root.refresh(true)
    }
    Process {
        id: statProc
        command: ["stat", "-c", "%y %s", "--", root.path]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (root.lastStat !== "" && t !== root.lastStat && t !== "") root.refresh(true);
                root.lastStat = t;
            }
        }
    }
    onPathChanged: lastStat = ""

    // ---------------------------------------------------------------- filter / sort / hidden / view mode
    property string filter: ""
    property bool showHidden: false
    property string sortKey: "name"      // name | size | modified | type
    property bool sortDesc: false
    property string viewMode: "list"     // list | grid
    onFilterChanged: rebuildTimer.restart()
    onShowHiddenChanged: rebuild()
    onSortKeyChanged: rebuild()
    onSortDescChanged: rebuild()
    Timer { id: rebuildTimer; interval: 60; onTriggered: root.rebuild() }

    function setSort(k) {
        if (sortKey === k) sortDesc = !sortDesc;
        else { sortKey = k; sortDesc = false; }
    }

    function rebuild() {
        const f = filter.toLowerCase();
        const hid = showHidden;
        let a = entries.filter(e => (hid || !e.h) && (f === "" || e.n.toLowerCase().indexOf(f) >= 0));
        const dir = sortDesc ? -1 : 1;
        const key = sortKey;
        a.sort((x, y) => {
            if (x.d !== y.d) return x.d ? -1 : 1;
            let c = 0;
            if (key === "size") c = x.s - y.s;
            else if (key === "modified") c = x.m - y.m;
            else if (key === "type") c = x.t < y.t ? -1 : (x.t > y.t ? 1 : 0);
            if (c !== 0) return c * dir;
            c = x.k < y.k ? -1 : (x.k > y.k ? 1 : 0);
            return key === "name" ? c * dir : c;
        });
        view = a;
        // prune selection to what is visible, re-find the cursor
        const keep = {}; let n = 0;
        for (const e of a) if (selected[e.p]) { keep[e.p] = true; n++; }
        if (n !== selCount) { selected = keep; selCount = n; }
        cur = curPath !== "" ? a.findIndex(e => e.p === curPath) : -1;
        if (cur < 0) curPath = "";
    }

    // ---------------------------------------------------------------- selection
    property var selected: ({})
    property int selCount: 0
    property int cur: -1             // keyboard cursor index in view
    property string curPath: ""
    property int anchor: -1
    function isSel(p) { return selected[p] === true; }
    function clearSel() { selected = ({}); selCount = 0; anchor = -1; }
    function setCur(i) {
        if (i < 0 || i >= view.length) return;
        cur = i; curPath = view[i].p;
    }
    function selectOnly(i) {
        if (i < 0 || i >= view.length) return;
        const s = {}; s[view[i].p] = true;
        selected = s; selCount = 1; anchor = i; setCur(i);
    }
    function toggleSel(i) {
        if (i < 0 || i >= view.length) return;
        const s = Object.assign({}, selected); const p = view[i].p;
        if (s[p]) delete s[p]; else s[p] = true;
        selected = s; selCount = Object.keys(s).length; anchor = i; setCur(i);
    }
    function selectRange(i) {
        if (i < 0 || i >= view.length) return;
        if (anchor < 0) anchor = cur >= 0 ? cur : 0;
        const s = {}; const a = Math.min(anchor, i), b = Math.max(anchor, i);
        for (let k = a; k <= b; k++) s[view[k].p] = true;
        selected = s; selCount = b - a + 1; setCur(i);
    }
    function selectAll() {
        const s = {}; for (const e of view) s[e.p] = true;
        selected = s; selCount = view.length;
        if (cur < 0 && view.length) setCur(0);
    }
    function selectByName(n) {
        const i = view.findIndex(e => e.n === n);
        if (i >= 0) selectOnly(i);
        return i >= 0;
    }
    function selectedEntries() {
        const r = [];
        for (const e of view) if (selected[e.p]) r.push(e);
        return r;
    }
    // Entries an action applies to: the selection, or the cursor row when nothing is selected.
    function targets() {
        const r = selectedEntries();
        if (!r.length && cur >= 0 && cur < view.length) r.push(view[cur]);
        return r;
    }
    // Move the cursor by delta (keyboard); extend = shift held.
    function moveCursor(delta, extend) {
        if (!view.length) return;
        let i = cur < 0 ? (delta > 0 ? 0 : view.length - 1) : cur + delta;
        i = Math.max(0, Math.min(view.length - 1, i));
        if (extend) selectRange(i); else selectOnly(i);
    }
    function moveTo(i, extend) {
        if (!view.length) return;
        i = Math.max(0, Math.min(view.length - 1, i));
        if (extend) selectRange(i); else selectOnly(i);
    }

    // ---------------------------------------------------------------- open
    function openEntry(e) {
        if (!e) return;
        if (isTrash) { toast("Trash", "Restore “" + e.n + "” to open it."); return; }
        if (e.d) { goTo(e.p); return; }
        run(["xdg-open", e.p], "xdg-open " + e.p);
    }
    function openSelected() {
        const t = targets();
        if (t.length === 1) { openEntry(t[0]); return; }
        for (const e of t) openEntry(e);
    }
    function run(argv, logLine) {
        if (dryRun) { console.log("DATA dry-run:", logLine || argv.join(" ")); return; }
        Quickshell.execDetached(argv);
    }
    function openTerminalHere() {
        const dir = isTrash ? home : path;
        if (!Config.terminalCmd) { toast("Terminal", "No terminal installed. Try: sudo apt install foot"); return; }
        if (dryRun) { console.log("DATA dry-run: terminal in " + dir + " via " + Config.terminalCmd); return; }
        Quickshell.execDetached({ command: ["sh", "-c", Config.terminalCmd], workingDirectory: dir });
    }

    // ---------------------------------------------------------------- open with
    property var apps: []
    property string appsMime: ""
    function showOpenWith() {
        const t = targets();
        if (!t.length || t[0].d || isTrash) return;
        appsTarget = t[0];
        apps = []; appsMime = t[0].t;
        dialog = { kind: "openwith", entry: t[0] };
        appsProc.command = ["python3", helper, "apps", t[0].t];
        appsProc.running = true;
    }
    property var appsTarget: null
    Process {
        id: appsProc
        stdout: StdioCollector {
            onStreamFinished: { try { root.apps = JSON.parse(text); } catch (e) { root.apps = []; } }
        }
    }
    function openWith(app) {
        if (!appsTarget) return;
        run(["gio", "launch", app.path, appsTarget.p], "gio launch " + app.path + " " + appsTarget.p);
        closeDialog();
    }

    // ---------------------------------------------------------------- dialogs
    // { kind: "confirm", title, text, ok, danger, action: fn } | { kind: "conflict", ... }
    // | { kind: "props" } | { kind: "openwith", entry }
    property var dialog: null
    function closeDialog() {
        if (dialog && dialog.kind === "props") propsProc.running = false;
        dialog = null;
    }
    function confirm(title, text, ok, action, danger) {
        dialog = { kind: "confirm", title: title, text: text, ok: ok, action: action, danger: !!danger };
    }
    function acceptDialog() {
        const d = dialog;
        if (!d) return;
        if (d.kind === "confirm") { dialog = null; d.action(); }
        else if (d.kind === "openwith") { if (apps.length) openWith(apps[0]); }
        else closeDialog();
    }

    // ---------------------------------------------------------------- toasts
    function toast(title, msg) { Toasts.show("DATA · " + title, msg); }

    // ---------------------------------------------------------------- clipboard
    property var clipPaths: []
    property bool clipCut: false
    function copySel() { const t = targets(); if (isTrash || !t.length) return; clipPaths = t.map(e => e.p); clipCut = false; }
    function cutSel() { const t = targets(); if (isTrash || !t.length) return; clipPaths = t.map(e => e.p); clipCut = true; }
    function paste() {
        if (isTrash || !clipPaths.length) return;
        transfer(clipPaths, path, clipCut ? "move" : "copy");
        if (clipCut) clipPaths = [];
    }

    // ---------------------------------------------------------------- transfers (copy / move) with conflicts
    function transfer(srcs, dstDir, op) {
        if (!srcs.length) return;
        const tx = { srcs: srcs, dst: dstDir, op: op };
        checkProc.tx = tx;
        checkProc.command = ["python3", helper, "check", dstDir].concat(srcs);
        checkProc.running = true;
    }
    Process {
        id: checkProc
        property var tx: null
        stdout: StdioCollector {
            onStreamFinished: {
                let conflicts = [];
                try { conflicts = JSON.parse(text); } catch (e) {}
                root.resolveConflicts(checkProc.tx, conflicts);
            }
        }
    }
    function resolveConflicts(tx, conflicts) {
        const modes = {};
        const real = conflicts.filter(c => !c.same);
        // same-folder paste (copy): silently becomes "name (copy)"; same-folder move: no-op
        for (const c of conflicts) if (c.same) modes[c.src] = "both";
        if (!real.length) { startTransfer(tx, modes); return; }
        askConflict(tx, real, 0, modes, "");
    }
    function askConflict(tx, list, i, modes, all) {
        if (i >= list.length) { startTransfer(tx, modes); return; }
        if (all !== "") { modes[list[i].src] = all; askConflict(tx, list, i + 1, modes, all); return; }
        dialog = { kind: "conflict", tx: tx, list: list, i: i, modes: modes, name: list[i].n, remaining: list.length - i,
                   dstDir: tx.dst };
    }
    function answerConflict(mode, applyAll) {
        const d = dialog;
        if (!d || d.kind !== "conflict") return;
        dialog = null;
        if (mode === "cancel") return;
        d.modes[d.list[d.i].src] = mode;
        askConflict(d.tx, d.list, d.i + 1, d.modes, applyAll ? mode : "");
    }
    function startTransfer(tx, modes) {
        const items = tx.srcs.map(s => ({ op: tx.op, src: s, dst: join(tx.dst, basename(s)), mode: modes[s] || "ask" }));
        const verb = tx.op === "move" ? "Moving" : "Copying";
        enqueue({ title: verb + " " + items.length + (items.length === 1 ? " item" : " items"), items: items,
                  done: tx.op === "move" ? "Moved" : "Copied", dest: tx.dst, selectResults: tx.dst === path });
    }
    // Drag and drop inside DATA (move; Ctrl = copy). Dropping on the current folder is a no-op.
    function dropOn(dir, srcs, copy) {
        if (isTrash) return;
        srcs = srcs.filter(s => dirname(s) !== dir || copy);
        if (!srcs.length) return;
        transfer(srcs, dir, copy ? "copy" : "move");
    }

    // ---------------------------------------------------------------- job queue
    property var jobQueue: []
    property bool jobActive: false
    property string jobTitle: ""
    property string jobName: ""
    property real jobFrac: 0
    property int jobIndex: 0
    property int jobCount: 0
    property var curJob: null
    function enqueue(job) {
        const q = jobQueue.slice(); q.push(job); jobQueue = q;
        if (!jobActive) nextJob();
    }
    function nextJob() {
        if (!jobQueue.length) { jobActive = false; return; }
        const q = jobQueue.slice(); curJob = q.shift(); jobQueue = q;
        jobActive = true; jobTitle = curJob.title; jobName = ""; jobFrac = 0; jobIndex = 0; jobCount = curJob.items.length;
        sendSpec(JSON.stringify({ items: curJob.items }));
    }
    function cancelJob() {
        if (runner.running) runner.running = false;
        jobQueue = [];
    }
    // One long-lived data.py ("serve") reads a JSON job per stdin line; killed on cancel.
    property string pendingSpec: ""
    function sendSpec(spec) {
        if (runner.running) runner.write(spec + "\n");
        else { pendingSpec = spec; runner.running = true; }
    }
    Process {
        id: runner
        command: ["python3", root.helper, "serve"]
        stdinEnabled: true
        onStarted: if (root.pendingSpec !== "") { write(root.pendingSpec + "\n"); root.pendingSpec = ""; }
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.done) { root.jobDone(m); return; }
                root.jobName = m.name;
                root.jobIndex = m.p + 1;
                root.jobFrac = m.total > 0 ? Math.min(1, m.bytes / m.total) : (m.n > 0 ? m.p / m.n : 0);
            }
        }
        onExited: (code, status) => { if (root.jobActive) root.jobCancelled(); }
    }
    function jobDone(m) {
        const j = curJob;
        const n = m.count - m.errors.length;
        if (m.errors.length) toast(j.done ? j.done : "Error", m.errors.length + " failed: " + m.errors[0]);
        else if (j.done) toast(j.done, n + (n === 1 ? " item" : " items") + (j.dest ? " → " + (j.dest === trashUri ? "Trash" : basename(j.dest) || "/") : ""));
        refresh(true);
        if (j.selectResults && m.results.length) {
            const sel = {}; for (const r of m.results) sel[r] = true;
            pendingSel = sel; selectAfterLoad.restart();
        }
        if (j.after) j.after(m);
        curJob = null; jobActive = false;
        refreshDisk();
        nextJob();
    }
    function jobCancelled() {
        toast("Cancelled", "Operation stopped.");
        refresh(true);
        curJob = null; jobActive = false;
    }
    property var pendingSel: ({})
    Timer {   // select freshly created/pasted items once the reload landed
        id: selectAfterLoad; interval: 250
        onTriggered: {
            const s = {}; let n = 0, first = -1;
            root.view.forEach((e, i) => { if (root.pendingSel[e.p]) { s[e.p] = true; n++; if (first < 0) first = i; } });
            if (n) { root.selected = s; root.selCount = n; root.anchor = first; root.setCur(first); }
        }
    }

    // ---------------------------------------------------------------- file operations
    function trashSel() {
        const t = targets();
        if (isTrash || !t.length) return;
        if (onMtp) { deleteSel(); return; }   // the trash lives on another filesystem: moving would be a copy
        enqueue({ title: "Moving to Trash", items: t.map(e => ({ op: "trash", src: e.p })),
                  done: "Trashed", dest: trashUri });
    }
    function deleteSel() {
        const t = targets();
        if (!t.length) return;
        const what = t.length === 1 ? "“" + t[0].n + "”" : t.length + " items";
        confirm("Delete permanently", what + " will be removed for good. This cannot be undone.", "Delete",
                () => enqueue({ title: "Deleting", items: t.map(e => ({ op: "delete", src: e.p })), done: "Deleted" }), true);
    }
    function uniqueName(base) {
        const names = {}; for (const e of entries) names[e.n] = true;
        if (!names[base]) return base;
        let k = 2; while (names[base + " " + k]) k++;
        return base + " " + k;
    }
    function newFolder() {
        if (isTrash) return;
        const p = join(path, uniqueName("New Folder"));
        enqueue({ title: "Creating folder", items: [{ op: "mkdir", dst: p }],
                  after: m => { if (m.results.length) { pendingRename = m.results[0]; renameTimer.restart(); } } });
    }
    function newFile() {
        if (isTrash) return;
        const p = join(path, uniqueName("New File"));
        enqueue({ title: "Creating file", items: [{ op: "newfile", dst: p }],
                  after: m => { if (m.results.length) { pendingRename = m.results[0]; renameTimer.restart(); } } });
    }
    property string pendingRename: ""
    Timer {
        id: renameTimer; interval: 300
        onTriggered: {
            const i = root.view.findIndex(e => e.p === root.pendingRename);
            if (i >= 0) { root.selectOnly(i); root.startRename(); }
            root.pendingRename = "";
        }
    }
    property string renamePath: ""
    function startRename() {
        if (isTrash) return;
        const t = targets();
        if (t.length !== 1) return;
        renamePath = t[0].p;
    }
    function cancelRename() { renamePath = ""; }
    function commitRename(newName) {
        const p = renamePath;
        renamePath = "";
        newName = newName.trim();
        if (p === "" || newName === "" || newName === basename(p)) return;
        if (newName.indexOf("/") >= 0) { toast("Rename", "Names cannot contain /."); return; }
        const dst = join(dirname(p), newName);
        pendingSel = {}; pendingSel[dst] = true;
        enqueue({ title: "Renaming", items: [{ op: "rename", src: p, dst: dst }], selectResults: true });
    }
    function restoreSel() {
        if (!isTrash) return;
        const t = targets();
        if (!t.length) return;
        enqueue({ title: "Restoring", items: t.map(e => ({ op: "restore", src: e.p })), done: "Restored" });
    }
    function emptyTrash() {
        if (!isTrash || !entries.length) return;
        confirm("Empty Trash", "All " + entries.length + " items in the Trash will be deleted for good.", "Empty Trash",
                () => enqueue({ title: "Emptying Trash", items: [{ op: "emptytrash" }], done: "Trash emptied" }), true);
    }
    function dragPaths(e) {   // what a drag starting on entry e carries
        return selected[e.p] ? selectedEntries().map(x => x.p) : [e.p];
    }

    // ---------------------------------------------------------------- properties
    property var propsStat: null
    property var propsDu: null
    function showProps() {
        const t = targets();
        const paths = t.length ? t.map(e => e.p) : (isTrash ? [] : [path]);
        if (!paths.length) return;
        propsStat = null; propsDu = null;
        dialog = { kind: "props", paths: paths };
        propsProc.command = ["python3", helper, "props"].concat(paths);
        propsProc.running = true;
    }
    Process {
        id: propsProc
        stdout: SplitParser {
            onRead: line => {
                try {
                    const m = JSON.parse(line);
                    if (m.stat) root.propsStat = m.stat;
                    if (m.du) root.propsDu = m.du;
                } catch (e) {}
            }
        }
    }

    // ---------------------------------------------------------------- places
    property var places: []
    function init() {
        placesProc.running = true;
        drivesProc.running = true;
        scanPhones();
    }
    Process {
        id: placesProc
        command: ["sh", "-c",
            "for d in DESKTOP DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS; do p=$(xdg-user-dir $d 2>/dev/null); " +
            "[ -n \"$p\" ] && [ -d \"$p\" ] && [ \"$p\" != \"$HOME\" ] && echo \"$d|$p\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = { DESKTOP: "Desktop", DOCUMENTS: "Documents", DOWNLOAD: "Downloads", MUSIC: "Music",
                                PICTURES: "Pictures", VIDEOS: "Videos" };
                const r = [{ id: "home", label: "Home", path: root.home, icon: "home" }];
                for (const l of text.split("\n")) {
                    const p = l.split("|");
                    if (p.length === 2) r.push({ id: p[0].toLowerCase(), label: names[p[0]], path: p[1], icon: p[0].toLowerCase() });
                }
                root.places = r;
            }
        }
    }

    // ---------------------------------------------------------------- removable drives (udisks, no gvfs)
    property var drives: []
    readonly property string fakeLsblk: Quickshell.env("ULTIMIT_FAKE_LSBLK")
    Timer {
        interval: 4000; repeat: true; triggeredOnStart: false
        running: root.open && root.started
        onTriggered: { if (!drivesProc.running) drivesProc.running = true; root.scanPhones(); }
    }
    Process {
        id: drivesProc
        command: root.fakeLsblk !== "" ? ["cat", root.fakeLsblk]
               : ["lsblk", "-J", "-o", "NAME,LABEL,SIZE,MOUNTPOINTS,RM,HOTPLUG,FSTYPE,TYPE,PATH,PKNAME,MODEL,VENDOR"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                const out = [];
                const truthy = v => v === true || v === "1" || v === 1;
                const walk = (n, parent) => {
                    const removable = truthy(n.rm) || truthy(n.hotplug) || (parent && parent.removable);
                    const mps = (n.mountpoints || (n.mountpoint ? [n.mountpoint] : [])).filter(m => m);
                    n.removable = removable;
                    if (removable && n.fstype && (n.type === "part" || n.type === "disk" || n.type === "crypt")) {
                        out.push({
                            dev: n.path || ("/dev/" + n.name), name: n.name, size: n.size || "",
                            label: n.label || n.model || (n.vendor ? n.vendor.trim() : "") || n.name,
                            mount: mps.length ? mps[0] : "", fstype: n.fstype, parent: n.pkname || (parent ? parent.name : "")
                        });
                    }
                    for (const c of (n.children || [])) walk(c, n);
                };
                for (const n of (d.blockdevices || [])) walk(n, null);
                const sig = JSON.stringify(out);
                if (sig !== JSON.stringify(root.drives)) root.drives = out;
            }
        }
    }
    function driveAction(drv, what) {
        // what: mount | unmount | poweroff
        const dev = drv.dev;
        let argv;
        if (what === "mount") argv = ["udisksctl", "mount", "-b", dev];
        else if (what === "unmount") argv = ["udisksctl", "unmount", "-b", dev];
        else argv = ["udisksctl", "power-off", "-b", "/dev/" + (drv.parent || drv.name)];
        if (dryRun) {
            console.log("DATA dry-run: " + argv.join(" "));
            toast(what === "poweroff" ? "Power off" : (what === "mount" ? "Mount" : "Unmount"), "dry run: " + argv.join(" "));
            return;
        }
        driveProc.what = what; driveProc.drv = drv;
        driveProc.command = argv;
        driveProc.running = true;
    }
    function openDrive(drv) {
        if (drv.mount) goTo(drv.mount);
        else driveAction(drv, "mount");
    }
    Process {
        id: driveProc
        property string what: ""
        property var drv: null
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/at (\/.*?)\.?\s*$/m);
                if (driveProc.what === "mount" && m) root.goTo(m[1]);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.toast("Drive", text.trim().split("\n")[0])
        }
        onExited: {
            drivesProc.running = true;
            if (driveProc.what === "unmount" && root.drv(root.path)) root.goTo(root.home);
        }
    }
    function drv(p) { return drives.some(d => d.mount !== "" && (p === d.mount || p.startsWith(d.mount + "/"))); }

    // ---------------------------------------------------------------- phones (MTP via go-mtpfs, no gvfs)
    // Detection + mounts come from `data.py mtp` (polled with the drives); mounting runs data.py mtp-mount,
    // which starts go-mtpfs detached. Mounts live in $XDG_RUNTIME_DIR/ultimit-mtp/<name>, belong to the
    // session (survive DATA/shell reloads) and are re-adopted from /proc/mounts on every scan.
    property var phones: []          // [{id, safe, label, mount ("" if not mounted), bus, dev}]
    property string mtpRoot: (Quickshell.env("XDG_RUNTIME_DIR") || "") !== "" ? Quickshell.env("XDG_RUNTIME_DIR") + "/ultimit-mtp" : ""
    readonly property bool onMtp: isMtpPath(path)
    function isMtpPath(p) { return mtpRoot !== "" && p.startsWith(mtpRoot + "/"); }
    property bool mtpTool: true
    property var mtpOrphans: []
    Process {
        id: mtpScan
        command: ["python3", root.helper, "mtp"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                if (!d.ok) return;           // detection failed: do NOT treat phones as unplugged
                if (d.root) root.mtpRoot = d.root;
                root.mtpTool = d.tool;
                const mounts = {};
                for (const m of d.mounts) mounts[m.name] = m.mp;
                const seen = {};
                const out = d.devices.map(x => {
                    seen[x.safe] = true;
                    return { id: x.id, safe: x.safe, label: x.label, mount: mounts[x.safe] || "", bus: x.bus, dev: x.dev };
                });
                const sig = JSON.stringify(out);
                if (sig !== JSON.stringify(root.phones)) root.phones = out;
                // mounted phones that vanished from USB: lazy-unmount and forget them
                root.mtpOrphans = d.mounts.filter(m => !seen[m.name]);
                root.reapOrphans();
            }
        }
    }
    function reapOrphans() {
        if (mtpOp.running || !mtpOrphans.length) return;
        const m = mtpOrphans[0];
        mtpOp.kind = "reap"; mtpOp.mp = m.mp; mtpOp.label = m.name;
        mtpOp.command = ["python3", helper, "mtp-umount", m.mp, "lazy"];
        mtpOp.running = true;
    }
    function scanPhones() { if (!mtpScan.running) mtpScan.running = true; }
    function phoneIcon() {
        for (const n of ["phone", "smartphone", "multimedia-player", "drive-removable-media"]) {
            const p = Quickshell.iconPath(n, true);
            if (p !== "") return p;
        }
        return "";
    }
    function openPhone(ph) {
        if (!ph) return;
        if (ph.mount) { goTo(ph.mount); return; }
        if (mtpOp.running) { toast("Phone", "Busy, try again in a moment."); return; }
        mtpOp.kind = "mount"; mtpOp.mp = ""; mtpOp.label = ph.label;
        mtpOp.command = ["python3", helper, "mtp-mount", ph.id];
        mtpOp.running = true;
        toast("Phone", "Opening " + ph.label + "…");
    }
    function ejectPhone(ph) {
        if (!ph || !ph.mount) return;
        if (mtpOp.running) { toast("Phone", "Busy, try again in a moment."); return; }
        mtpOp.kind = "eject"; mtpOp.mp = ph.mount; mtpOp.label = ph.label;
        mtpOp.command = ["python3", helper, "mtp-umount", ph.mount];
        mtpOp.running = true;
    }
    Process {
        id: mtpOp
        property string kind: ""
        property string mp: ""
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text.trim().split("\n").pop()); } catch (e) { r = { ok: false, err: "helper failed" }; }
                root.mtpDone(mtpOp.kind, mtpOp.mp, mtpOp.label, r);
            }
        }
        onExited: root.scanPhones()
    }
    function mtpDone(kind, mp, label, r) {
        if (r.dry) {
            for (const c of r.dry) console.log("DATA dry-run: " + c);
            toast("Phone", "dry run: " + r.dry.join(" ; "));
            return;
        }
        if (kind === "mount") {
            if (r.ok) {
                if (r.empty) toast("Phone", label + " shows no storage yet. Unlock it and choose File transfer, then reopen.");
                goTo(r.mp);
            } else if (r.err === "nomtpfs") {
                toast("Phone", "Install go-mtpfs to open phones: sudo apt install go-mtpfs");
            } else {
                toast("Phone", "Couldn't open " + label + ". Unlock the phone and set USB to File transfer, then try again."
                      + (r.log ? " (" + r.log + ")" : ""));
            }
        } else if (kind === "eject") {
            if (r.ok) {
                if (isMtpPath(path) && (path === mp || path.startsWith(mp + "/"))) goTo(home);
                toast("Phone", "Ejected " + label + ".");
            } else toast("Phone", "Couldn't eject " + label + ": " + (r.err || "unknown error"));
        } else if (kind === "reap") {
            mtpOrphans = mtpOrphans.filter(m => m.mp !== mp);
            if (isMtpPath(path) && (path === mp || path.startsWith(mp + "/"))) goTo(home);
            toast("Phone", label + " was unplugged." + (r.ok ? "" : " " + (r.err || "")));
        }
    }

    // ---------------------------------------------------------------- disk meter
    property var disk: ({ total: 0, used: 0, avail: 0, mount: "" })
    function refreshDisk() { if (!dfProc.running) dfProc.running = true; else dfQueued = true; }
    property bool dfQueued: false
    Process {
        id: dfProc
        command: ["df", "-P", "-B1", "--", root.isTrash ? root.home : (root.path || root.home)]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length < 2) return;
                const p = lines[lines.length - 1].trim().split(/\s+/);
                if (p.length < 6) return;
                root.disk = { total: parseFloat(p[1]), used: parseFloat(p[2]), avail: parseFloat(p[3]), mount: p.slice(5).join(" ") };
            }
        }
        onExited: if (root.dfQueued) { root.dfQueued = false; running = true; }
    }

    // ---------------------------------------------------------------- formatting
    function fmtSize(b) {
        if (b < 0) return "—";
        if (b < 1000) return b + " B";
        const u = ["kB", "MB", "GB", "TB"]; let i = -1;
        do { b /= 1000; i++; } while (b >= 1000 && i < u.length - 1);
        return (b >= 100 ? b.toFixed(0) : b.toFixed(1)) + " " + u[i];
    }
    function pad(n) { return n < 10 ? "0" + n : "" + n; }
    function fmtDate(t) {
        const d = new Date(t * 1000), now = new Date();
        const mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()];
        const hm = pad(d.getHours()) + ":" + pad(d.getMinutes());
        if (d.getFullYear() === now.getFullYear()) return mon + " " + d.getDate() + ", " + hm;
        return mon + " " + d.getDate() + ", " + d.getFullYear();
    }
    function fmtFull(t) {
        const d = new Date(t * 1000);
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds());
    }

    // ---------------------------------------------------------------- icons (themed, by MIME)
    property var iconCache: ({})
    readonly property var mimeFallbacks: ({
        "inode/directory": ["folder"],
        "text": ["text-x-generic"], "image": ["image-x-generic"], "audio": ["audio-x-generic"],
        "video": ["video-x-generic"], "font": ["font-x-generic"]
    })
    readonly property var specialMime: ({
        "application/pdf": ["application-pdf", "x-office-document"],
        "application/zip": ["package-x-generic", "application-x-archive"],
        "application/x-compressed-tar": ["package-x-generic"], "application/gzip": ["package-x-generic"],
        "application/x-tar": ["package-x-generic"], "application/x-7z-compressed": ["package-x-generic"],
        "application/vnd.rar": ["package-x-generic"], "application/x-xz-compressed-tar": ["package-x-generic"],
        "application/x-shellscript": ["text-x-script", "text-x-generic"],
        "application/json": ["text-x-generic"], "application/x-executable": ["application-x-executable"],
        "application/octet-stream": ["application-x-generic", "text-x-generic"],
        "unknown": ["text-x-generic"]
    })
    function iconName(e) {
        const key = e.d ? "inode/directory" : e.t + (e.x ? "!x" : "");
        let r = iconCache[key];
        if (r !== undefined) return r;
        const tries = [];
        if (!e.d && e.x) tries.push("application-x-executable");
        tries.push(e.t.replace("/", "-"));
        for (const t of (specialMime[e.t] || [])) tries.push(t);
        const major = e.t.split("/")[0];
        for (const t of (mimeFallbacks[e.d ? e.t : major] || [])) tries.push(t);
        tries.push("text-x-generic");
        r = "";
        for (const t of tries) { if (Quickshell.iconPath(t, true) !== "") { r = Quickshell.iconPath(t, true); break; } }
        iconCache[key] = r;
        return r;
    }
    readonly property var imageExts: ({ png: 1, jpg: 1, jpeg: 1, gif: 1, webp: 1, bmp: 1, svg: 1, ico: 1, tif: 1, tiff: 1, avif: 1 })
    function fileUrl(p) { return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F"); }
    function isImage(e) {
        if (e.d || e.s > 40 * 1000 * 1000) return false;
        const i = e.n.lastIndexOf(".");
        return i > 0 && imageExts[e.n.slice(i + 1).toLowerCase()] === 1;
    }
    function placeIcon(id) {
        const m = { home: "user-home", desktop: "user-desktop", documents: "folder-documents", download: "folder-download",
                    downloads: "folder-download", music: "folder-music", pictures: "folder-pictures", videos: "folder-videos",
                    trash: "user-trash", root: "drive-harddisk", drive: "drive-removable-media" };
        const n = m[id] || "folder";
        const p = Quickshell.iconPath(n, true);
        return p !== "" ? p : Quickshell.iconPath("folder", true);
    }

    // ---------------------------------------------------------------- status text
    function statusText() {
        if (loading && entries.length === 0) return "READING…";
        if (error !== "") return error.toUpperCase();
        if (selCount > 0) {
            let sz = 0, files = 0;
            for (const e of view) if (selected[e.p]) { if (!e.d) { sz += e.s; files++; } }
            return selCount + " SELECTED" + (files ? " · " + fmtSize(sz).toUpperCase() : "");
        }
        const hidden = entries.length - view.length;
        return view.length + (view.length === 1 ? " ITEM" : " ITEMS") + (filter !== "" ? " MATCH" : "");
    }

    // ---------------------------------------------------------------- scripted control (IPC "data run")
    function act(name, arg) {
        switch (name) {
        case "select": return selectByName(arg) ? "ok" : "no such entry";
        case "selectall": selectAll(); return "ok";
        case "copy": copySel(); return "ok";
        case "cut": cutSel(); return "ok";
        case "paste": paste(); return "ok";
        case "trash": trashSel(); return "ok";
        case "delete": deleteSel(); return "ok";
        case "mkdir": newFolder(); return "ok";
        case "rename": renamePath = targets().length === 1 ? targets()[0].p : ""; commitRename(arg); return "ok";
        case "restore": restoreSel(); return "ok";
        case "emptytrash": emptyTrash(); return "ok";
        case "filter": filter = arg; return "ok";
        case "hidden": showHidden = !showHidden; return "ok";
        case "sort": setSort(arg); return "ok";
        case "view": viewMode = arg === "grid" ? "grid" : "list"; return "ok";
        case "back": goBack(); return "ok";
        case "forward": goForward(); return "ok";
        case "up": goUp(); return "ok";
        case "go": goTo(arg); return "ok";
        case "trashview": goTo(trashUri); return "ok";
        case "props": showProps(); return "ok";
        case "openwith": showOpenWith(); return "ok";
        case "confirm": acceptDialog(); return "ok";
        case "cancel": closeDialog(); return "ok";
        case "conflict": answerConflict(arg, false); return "ok";
        case "conflictall": answerConflict(arg, true); return "ok";
        case "dropcopy": dropOn(arg.split("|")[0], selectedEntries().map(e => e.p), true); return "ok";
        case "dropmove": dropOn(arg.split("|")[0], selectedEntries().map(e => e.p), false); return "ok";
        case "open": openSelected(); return "ok";
        case "drive": { const d = drives.find(x => x.dev === arg); if (!d) return "no such drive"; openDrive(d); return "ok"; }
        case "unmount": { const d = drives.find(x => x.dev === arg); if (!d) return "no such drive"; driveAction(d, "unmount"); return "ok"; }
        case "poweroff": { const d = drives.find(x => x.dev === arg); if (!d) return "no such drive"; driveAction(d, "poweroff"); return "ok"; }
        case "phone": { const p = phones.find(x => x.id === arg); if (!p) return "no such phone"; openPhone(p); return "ok"; }
        case "eject": { const p = phones.find(x => x.id === arg); if (!p) return "no such phone"; ejectPhone(p); return "ok"; }
        case "scanphones": scanPhones(); return "ok";
        case "terminal": openTerminalHere(); return "ok";
        }
        return "unknown action";
    }
    function stateJson() {
        return JSON.stringify({ path: path, count: view.length, total: entries.length, sel: selectedEntries().map(e => e.n),
            cur: cur, job: jobActive, queue: jobQueue.length, dialog: dialog ? dialog.kind : "", rename: renamePath, filter: filter,
            hidden: showHidden, sort: sortKey, desc: sortDesc, view: viewMode, clip: clipPaths.length, cut: clipCut,
            first: view.slice(0, 5).map(e => e.n), drives: drives.length, phones: phones.map(p => ({ id: p.id, label: p.label, mount: p.mount })), mtpBusy: mtpOp.running,
            mtpTool: mtpTool, onMtp: onMtp, disk: disk, err: error,
            props: propsStat ? { size: propsStat.size, mode: propsStat.mode, mime: propsStat.mime, du: propsDu } : null });
    }
}
