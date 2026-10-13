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
//   ULTIMIT_7Z=<exe>           7-Zip binary used by arc.py (default: 7zz / 7z / 7za on PATH)
// Archives (see arc.py): archives open like folders (read-only "archive view", virtual location
// "arc:<archive>\u0001<inner dir>"), context menu Extract here / Extract to / Compress, passwords go to
// 7z over stdin only.  Extraction never overwrites: it lands in a new, non-conflicting name.
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
        const wasOpen = open;
        open = true;
        // Already showing something: a folder opened from elsewhere gets its own tab.
        if (p && p !== "") { if (wasOpen && path !== "") newTab(p, false); else goTo(p); }
        else if (path === "") goTo(Quickshell.env("ULTIMIT_DATA_START") || home);
        raise++;
    }
    property int raise: 0          // bumped on show(): the window grabs focus
    property bool started: false

    // ---------------------------------------------------------------- location + history
    property string path: ""
    readonly property bool isTrash: path === trashUri
    // archive view: path = "arc:" + archive file + arcSep + inner directory ("" = archive root)
    readonly property string arcSep: "\u0001"
    readonly property bool isArc: path.startsWith("arc:")
    readonly property string arcFile: isArc ? path.slice(4, path.indexOf(arcSep)) : ""
    readonly property string arcInner: isArc ? path.slice(path.indexOf(arcSep) + 1) : ""
    function arcLoc(file, inner) { return "arc:" + file + arcSep + inner; }
    // a real directory on disk that "here" means (df meter, terminal, extraction destination)
    readonly property string fsPath: isTrash ? home : (isArc ? dirname(arcFile) : (path || home))
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
    function title() { return titleOf(path); }
    function titleOf(p) {
        if (p === trashUri) return "Trash";
        if (p.startsWith("arc:")) { const f = p.slice(4, p.indexOf(arcSep)), i = p.slice(p.indexOf(arcSep) + 1); return i === "" ? basename(f) : basename(i); }
        if (p === home) return "Home";
        return p === "/" ? "/" : basename(p);
    }

    // ---------------------------------------------------------------- tabs
    // The live properties (path, history, entries, selection...) always belong to the active tab;
    // tabs[] holds snapshots, and tabs[tabIndex] is only refreshed when the tab is left.  A tab that
    // was never shown ({path} only) lists its folder when first switched to.  View mode, sort and
    // hidden files are window-wide.
    property var tabs: [{ path: "" }]
    property int tabIndex: 0
    property var closedTabs: []      // most recent last, for Ctrl+Shift+T
    property real scrollY: 0         // kept up to date by DataWindow (saved with the tab)
    property real restoreScroll: -1  // DataWindow applies it to the next view change
    function tabPath(i) { return i === tabIndex ? path : (i < tabs.length ? tabs[i].path : ""); }
    function snapTab() {
        return { path: path, back: backStack, fwd: fwdStack, filter: filter, entries: entries, error: error,
                 selected: selected, selCount: selCount, curPath: curPath, anchor: anchor, arc: arcListing, scrollY: scrollY };
    }
    function saveTab() { const t = tabs.slice(); t[tabIndex] = snapTab(); tabs = t; }
    function restoreTab(t) {
        renamePath = ""; pendingSelect = ""; pendingRename = "";
        backStack = t.back || []; fwdStack = t.fwd || [];
        if (t.entries === undefined) {   // never shown: list it now
            path = "";
            goTo(t.path, true);
            return;
        }
        arcListing = t.arc;
        path = t.path;
        lastStat = "";
        filter = t.filter;
        error = t.error; entries = t.entries;
        selected = t.selected; selCount = t.selCount; curPath = t.curPath; anchor = t.anchor;
        restoreScroll = t.scrollY;
        loading = false;
        rebuild();
        refresh(true);   // pick up changes made while the tab was in the background
    }
    function switchTab(i) {
        if (i < 0 || i >= tabs.length || i === tabIndex) return;
        saveTab();
        tabIndex = i;
        restoreTab(tabs[i]);
    }
    function nextTab(d) { if (tabs.length > 1) switchTab((tabIndex + d + tabs.length) % tabs.length); }
    // background = open behind the current tab (middle-click), placed right after it
    function newTab(p, background) {
        p = p || (isTrash || isArc ? fsPath : path) || home;
        const at = tabIndex + 1 + (background ? backgroundRun : 0);
        const t = tabs.slice();
        if (background) {
            t.splice(at, 0, { path: p });
            tabs = t;
            backgroundRun++;
            return;
        }
        t[tabIndex] = snapTab();
        t.splice(at, 0, { path: p });
        tabs = t;
        tabIndex = at;
        restoreTab(tabs[at]);
    }
    // consecutive background tabs open in order (1, 2, 3 after the current one), like browsers
    property int backgroundRun: 0
    onTabIndexChanged: backgroundRun = 0
    function duplicateTab(i) {
        if (i === undefined) i = tabIndex;
        const src = i === tabIndex ? snapTab() : tabs[i];
        const t = tabs.slice();
        if (i === tabIndex) t[tabIndex] = src;
        t.splice(i + 1, 0, Object.assign({}, src, { back: (src.back || []).slice(), fwd: (src.fwd || []).slice() }));
        tabs = t;
        if (tabIndex > i) tabIndex++;
        switchTab(i + 1);
    }
    function closeTab(i) {
        if (i === undefined) i = tabIndex;
        if (i < 0 || i >= tabs.length) return;
        if (tabs.length === 1) { hide(); return; }   // closing the last tab closes the window
        const snap = Object.assign({}, i === tabIndex ? snapTab() : tabs[i], { idx: i });
        const c = closedTabs.slice(); c.push(snap); if (c.length > 20) c.shift(); closedTabs = c;
        const t = tabs.slice(); t.splice(i, 1);
        if (i !== tabIndex) {
            tabs = t;
            if (i < tabIndex) tabIndex--;
            return;
        }
        tabs = t;
        tabIndex = Math.min(i, t.length - 1);
        restoreTab(tabs[tabIndex]);
    }
    function closeOtherTabs(i) {
        if (i === undefined) i = tabIndex;
        if (tabs.length < 2) return;
        if (i !== tabIndex) switchTab(i);
        const c = closedTabs.slice();
        tabs.forEach((x, k) => { if (k !== tabIndex) c.push(Object.assign({}, x, { idx: k })); });
        closedTabs = c.slice(-20);
        tabs = [tabs[tabIndex]];
        tabIndex = 0;
    }
    function closeTabsRight(i) {
        if (i === undefined) i = tabIndex;
        if (i >= tabs.length - 1) return;
        if (tabIndex > i) switchTab(i);
        closedTabs = closedTabs.concat(tabs.slice(i + 1).map((x, k) => Object.assign({}, x, { idx: i + 1 + k }))).slice(-20);
        tabs = tabs.slice(0, i + 1);
    }
    function reopenTab() {
        if (!closedTabs.length) return;
        const c = closedTabs.slice(); const snap = c.pop(); closedTabs = c;
        const at = snap.idx !== undefined ? Math.min(snap.idx, tabs.length) : tabIndex + 1;   // back where it was
        const t = tabs.slice();
        t[tabIndex] = snapTab();
        t.splice(at, 0, snap);
        tabs = t;
        tabIndex = at;
        restoreTab(snap);
    }
    function moveTab(from, to) {
        to = Math.max(0, Math.min(tabs.length - 1, to));
        if (from === to || from < 0 || from >= tabs.length) return;
        const t = tabs.slice(); const x = t.splice(from, 1)[0]; t.splice(to, 0, x);
        tabs = t;
        if (tabIndex === from) tabIndex = to;
        else if (from < tabIndex && to >= tabIndex) tabIndex--;
        else if (from > tabIndex && to <= tabIndex) tabIndex++;
    }
    // open these entries (folders / archives) in background tabs
    function openInTabs(list) {
        for (const e of list) {
            if (isTrash) continue;
            if (e.d) newTab(e.p, true);
            else if (!isArc && isArchive(e)) newTab(arcLoc(e.p, ""), true);
        }
    }
    function tabbable(list) { return !isTrash && list.length > 0 && list.every(e => e.d || (!isArc && isArchive(e))); }

    function goTo(p, noHistory) {
        const toArc = p.startsWith("arc:");
        p = (p === trashUri || toArc) ? p : expand(p);
        if (p !== trashUri && !toArc && !p.startsWith("/")) p = join(path === trashUri ? home : (isArc ? dirname(arcFile) : path), p);
        if (!toArc) arcListing = null;
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
    // Address bar (Explorer-style): a folder opens, a file opens its folder
    // with the file selected, anything else says so.
    function goAddress(t) {
        t = t.trim();
        if (t === "") return;
        if (t === "trash:" || t === "trash") { goTo(trashUri); return; }
        if (isNetAddress(t)) { connectNetwork(t); return; }
        if (t.startsWith("file://")) t = decodeURIComponent(t.slice(7));
        let p = expand(t);
        if (!p.startsWith("/")) p = join(path === trashUri ? home : (isArc ? dirname(arcFile) : path), p);
        addrProbe.target = p;
        addrProbe.exec(["sh", "-c", 'if [ -d "$1" ]; then echo dir; elif [ -e "$1" ]; then echo file; else echo none; fi', "sh", p]);
    }
    // ---- network shares (gvfs, through SHARES' connect.py). smb://host/share, \\host\share, sftp://, ftp://, dav:// ...
    readonly property string netHelper: Quickshell.shellPath("apps/shares/connect.py")
    function isNetAddress(t) { return /^(smb|sftp|ftps?|davs?|nfs):\/\//i.test(t) || t.startsWith("\\\\"); }
    function connectNetwork(addr) {
        if (netConnect.running) { toast("Network", "Busy, try again in a moment."); return; }
        netConnect.addr = addr;
        netConnect.command = ["python3", netHelper, "connect", addr, "--no-prompt"];
        netConnect.running = true;
        toast("Network", "Connecting…");
    }
    // Needs a password (or is a whole computer, not a share): SHARES asks and opens the folder afterwards.
    function connectViaShares(addr) {
        Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-shares"), "--connect", addr, "--open"]);
    }
    Process {
        id: netConnect
        property string addr: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text.trim().split("\n").pop()); } catch (e) { r = { ok: false, code: "failed", error: "helper failed" }; }
                root.scanNetwork();
                if (r.ok && r.path) { root.goTo(r.path); return; }
                if (r.ok) { root.toast("Network", r.note || "Connected, but the files cannot be opened here yet."); return; }
                if (r.code === "needs_password" || r.code === "denied" || r.code === "bad_address") { root.connectViaShares(netConnect.addr); return; }
                root.toast("Network", r.error || "Could not connect.");
            }
        }
    }
    property var networks: []        // [{uri, name, path, scheme}] connected network locations
    function scanNetwork() { if (!netScan.running) netScan.running = true; }
    Process {
        id: netScan
        command: ["python3", root.netHelper, "mounts"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                if (!d.ok) return;
                const sig = JSON.stringify(d.mounts);
                if (sig !== JSON.stringify(root.networks)) root.networks = d.mounts;
            }
        }
    }
    function disconnectNetwork(m) {
        netOff.mp = m.path;
        netOff.command = ["python3", netHelper, "disconnect", m.uri];
        netOff.running = true;
    }
    Process {
        id: netOff
        property string mp: ""
        stdout: StdioCollector { onStreamFinished: root.scanNetwork() }
        onExited: if (netOff.mp !== "" && (root.path === netOff.mp || root.path.startsWith(netOff.mp + "/"))) root.goTo(root.home)
    }

    Process {
        id: addrProbe
        property string target: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const kind = text.trim();
                if (kind === "dir") root.goTo(addrProbe.target);
                else if (kind === "file") { root.pendingSelect = addrProbe.target; root.goTo(root.dirname(addrProbe.target)); }
                else root.toast("Can't find", addrProbe.target);
            }
        }
    }
    function copyAddress() {
        const a = isTrash ? "trash:" : (isArc ? arcFile : path);
        Quickshell.clipboardText = a;
        toast("Address copied", a);
    }
    function pasteAddress() {
        const t = (Quickshell.clipboardText || "").split("\n")[0];
        if (t.trim() !== "") goAddress(t);
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
        if (isArc) {
            if (arcInner !== "") { const i = arcInner.lastIndexOf("/"); pendingSelect = path; goTo(arcLoc(arcFile, i < 0 ? "" : arcInner.slice(0, i))); }
            else { pendingSelect = arcFile; goTo(dirname(arcFile)); }
            return;
        }
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
        if (isArc) { loadArc(); return; }
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
        running: root.open && root.path !== "" && !root.loading && !root.isTrash && !root.isArc
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
        if (isArc) { if (e.d) goTo(e.p); else openArcFile(e); return; }
        if (e.d) { goTo(e.p); return; }
        if (isArchive(e)) { goTo(arcLoc(e.p, "")); return; }   // archives open like folders
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
        const dir = fsPath;
        if (!Config.terminalCmd) { toast("Terminal", "No terminal installed. Try: sudo apt install foot"); return; }
        if (dryRun) { console.log("DATA dry-run: terminal in " + dir + " via " + Config.terminalCmd); return; }
        Quickshell.execDetached({ command: ["sh", "-c", Config.terminalCmd], workingDirectory: dir });
    }

    // ---------------------------------------------------------------- open with
    property var apps: []
    property string appsMime: ""
    function showOpenWith() {
        const t = targets();
        if (!t.length || t[0].d || isTrash || isArc) return;
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
    // | { kind: "password", title, text, ok, action: fn({pw}), onCancel? }
    // | { kind: "input", title, text, value, ok, action: fn({text}) }
    // | { kind: "compress", count, name, fmt, action: fn({name, fmt, pw}) }
    property var dialog: null
    function closeDialog() {
        const d = dialog;
        if (d && d.kind === "props") propsProc.running = false;
        dialog = null;
        if (d && d.onCancel) d.onCancel();
    }
    // password / input / compress dialogs: DDialog hands the entered values here
    function submitDialog(v) {
        const d = dialog;
        if (!d || !d.action) return;
        dialog = null;
        d.action(v);
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
    function copySel() { const t = targets(); if (isTrash || isArc || !t.length) return; clipPaths = t.map(e => e.p); clipCut = false; }
    function cutSel() { const t = targets(); if (isTrash || isArc || !t.length) return; clipPaths = t.map(e => e.p); clipCut = true; }
    function paste() {
        if (isTrash || isArc || !clipPaths.length) return;
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
        if (isTrash || isArc) return;
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
        const pwFail = m.retry && m.retry.length > 0;          // archive needs / rejected a password: ask again
        const warn = m.warns && m.warns.length ? "  (" + m.warns.join("; ") + ")" : "";
        if (pwFail && m.errors.length === m.retry.length) { /* handled by the password prompt below */ }
        else if (m.errors.length) toast(j.fail ? j.fail : (j.done ? j.done : "Error"), (j.fail ? "" : m.errors.length + " failed: ") + m.errors[0]);
        else if (j.doneMsg) toast(j.done, j.doneMsg(m) + warn);
        else if (j.done) toast(j.done, n + (n === 1 ? " item" : " items") + (j.dest ? " → " + (j.dest === trashUri ? "Trash" : basename(j.dest) || "/") : ""));
        refresh(true);
        if (j.selectResults && m.results.length) {
            const sel = {}; for (const r of m.results) sel[r] = true;
            pendingSel = sel; selectAfterLoad.restart();
        }
        if (pwFail && j.items) retryWithPassword(j, m);
        else if (j.after) j.after(m);
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

    // ---------------------------------------------------------------- archives
    // Recognition: by extension or MIME.  7z (via arc.py) does the work; passwords are only ever written to
    // 7z's stdin (listing: `data.py arc-ls --pw` reads line 1 of its stdin; jobs: inside the JSON job line).
    readonly property var archiveMimes: ({
        "application/zip": 1, "application/x-zip-compressed": 1, "application/x-7z-compressed": 1, "application/vnd.rar": 1,
        "application/x-rar": 1, "application/x-rar-compressed": 1, "application/x-tar": 1, "application/gzip": 1,
        "application/x-gzip": 1, "application/x-bzip2": 1, "application/x-bzip": 1, "application/x-xz": 1,
        "application/zstd": 1, "application/x-zstd": 1, "application/x-compressed-tar": 1, "application/x-bzip-compressed-tar": 1,
        "application/x-bzip2-compressed-tar": 1, "application/x-xz-compressed-tar": 1, "application/x-zstd-compressed-tar": 1,
        "application/x-lzma-compressed-tar": 1, "application/x-lzma": 1, "application/x-cd-image": 1, "application/x-iso9660-image": 1,
        "application/vnd.ms-cab-compressed": 1, "application/x-cab": 1, "application/java-archive": 1,
        "application/vnd.android.package-archive": 1, "application/vnd.debian.binary-package": 1, "application/x-deb": 1,
        "application/x-rpm": 1, "application/x-cpio": 1, "application/x-lzh-compressed": 1, "application/x-war": 1
    })
    readonly property var archiveExtRe: /\.(zip|7z|rar|tar|tgz|tbz2?|txz|tzst|gz|bz2|xz|zst|lzma|iso|cab|jar|apk|deb|rpm|war|ear|whl|cpio|lzh|lha)$/i
    function isArchive(e) { return !!e && !e.d && !e.ar && (archiveMimes[e.t] === 1 || archiveExtRe.test(e.n)); }
    // "foo.tar.gz" -> "foo"   (mirrors arc.py arc_split)
    function archiveStem(n) {
        const m = n.match(/^(.+?)\.(tar\.(gz|bz2|xz|zst|lzma|z)|tgz|tbz2|tbz|txz|tzst|taz|tar|zip|7z|rar|gz|bz2|xz|zst|lzma|z|iso|cab|jar|apk|deb|rpm|war|ear|whl|cpio|lzh|lha)$/i);
        return m ? m[1] : n;
    }
    property var arcPw: ({})                 // archive path -> password typed this session (memory only; cleared on hide)
    onOpenChanged: if (!open) arcPw = ({})
    property var arcListing: null            // {file, dirs{inner:[entries]}, count, size, truncated, cap, enc, unsafe, type}

    // ---- archive view: listing
    property bool arcLoadQueued: false
    function loadArc() {
        if (arcListing && arcListing.file === arcFile) { showArcDir(); return; }
        if (arcLister.running) { arcLoadQueued = true; return; }
        loading = true;
        entries = []; rebuild();
        arcLister.file = arcFile;
        const pw = arcPw[arcFile] || "";
        arcLister.pw = pw;
        arcLister.command = ["python3", helper, "arc-ls", arcFile].concat(pw !== "" ? ["--pw"] : []);
        arcLister.running = true;
    }
    function showArcDir() {
        const d = arcListing.dirs[arcInner];
        error = d === undefined ? "Folder not found in archive" : "";
        entries = d === undefined ? [] : d;
        loading = false;
        rebuild();
        if (pendingSelect !== "") {
            const i = view.findIndex(x => x.p === pendingSelect);
            pendingSelect = "";
            if (i >= 0) selectOnly(i);
        }
    }
    Process {
        id: arcLister
        property string file: ""
        property string pw: ""
        stdinEnabled: true
        onStarted: if (pw !== "") write(pw + "\n")
        stdout: StdioCollector { onStreamFinished: root.arcListed(arcLister.file, text) }
        onExited: if (root.arcLoadQueued) { root.arcLoadQueued = false; root.loadArc(); }
    }
    Timer {   // an unresponsive phone must not leave the archive "READING…" forever
        interval: 120000
        running: arcLister.running && root.onMtp
        onTriggered: { arcLister.running = false; root.loading = false; root.error = "Phone not responding. Is it unlocked?"; }
    }
    function arcListed(file, text) {
        if (!isArc || file !== arcFile) return;
        let d;
        try { d = JSON.parse(text); } catch (e) { d = { ok: false, err: "listing failed" }; }
        if (d.needpw || d.wrongpw) {
            if (d.wrongpw) toast("Wrong password", "That password did not open “" + basename(file) + "”.");
            askPassword("Password required", "“" + basename(file) + "” is encrypted. Enter its password to open it.", "Open",
                        v => { arcPw[file] = v.pw; loadArc(); }, () => { if (isArc && arcFile === file) goUp(); });
            return;
        }
        if (!d.ok) {
            loading = false; entries = []; rebuild();
            error = d.err || "Cannot open archive";
            return;
        }
        arcListing = { file: file, dirs: d.dirs, count: d.count, size: d.size, truncated: d.truncated, cap: d.cap, enc: d.enc, unsafe: d.unsafe, type: d.type };
        if (d.truncated) toast("Archive", "Showing only the first " + d.cap.toLocaleString(Qt.locale("en_US"), "f", 0) + " entries of “" + basename(file) + "”.");
        if (d.unsafe > 0) toast("Archive", d.unsafe + " unsafe path" + (d.unsafe === 1 ? "" : "s") + " (.. or absolute) hidden. Extraction of this archive is refused.");
        showArcDir();
    }
    function askPassword(title, text, ok, action, onCancel) {
        dialog = { kind: "password", title: title, text: text, ok: ok, action: action, onCancel: onCancel };
    }

    // ---- extraction (jobs run by data.py `serve`, op "extract")
    // Where things land: "Extract here" extracts a lone top-level file/folder as is, otherwise into a new folder
    // named after the archive; "Extract to “name/”" always makes that folder.  Nothing is ever overwritten:
    // a taken name becomes "name (1)".  (This replaces the Replace / Keep both / Skip conflict dialog.)
    function archiveTargets() {
        if (isTrash || isArc) return [];
        const t = targets();
        return t.length && t.every(isArchive) ? t : [];
    }
    function extractArchives(list, mode, into) {
        if (!list.length) return;
        const items = list.map(e => ({ op: "extract", src: e.p, dst: dirname(e.p), mode: mode, into: into || "", pw: arcPw[e.p] || "" }));
        runExtract(items);
    }
    function runExtract(items, opts) {
        opts = opts || {};
        const one = items.length === 1;
        enqueue({ title: opts.title || (one ? "Extracting " + basename(items[0].src) : "Extracting " + items.length + " archives"),
                  items: items, done: "Extracted", fail: "Extract failed", selectResults: true,
                  doneMsg: m => one && m.results.length ? basename(items[0].src) + " → " + (basename(m.results[0]) || "/")
                                                       : (m.count - m.errors.length) + " archives" });
    }
    // an archive asked for a password (or rejected ours): prompt, then run the failed items again
    function retryWithPassword(j, m) {
        const bad = m.retry.map(i => j.items[i]);
        const first = bad[0];
        if (m.codes[0] === "wrongpw") toast("Wrong password", "That password did not open “" + basename(first.src) + "”.");
        askPassword("Password required", "“" + basename(first.src) + "” is encrypted. Enter its password.", "Extract", v => {
            arcPw[first.src] = v.pw;
            const items = bad.map(it => Object.assign({}, it, { pw: arcPw[it.src] || "" }));
            enqueue(Object.assign({}, j, { items: items }));
        });
    }
    function extractToDialog() {
        const t = archiveTargets();
        if (!t.length) return;
        const one = t.length === 1;
        dialog = { kind: "input", title: "Extract to…",
                   text: one ? "Extract “" + t[0].n + "” into this folder (created if needed):" : "Extract " + t.length + " archives, each into its own folder inside:",
                   value: one ? join(dirname(t[0].p), archiveStem(t[0].n)) : dirname(t[0].p), ok: "Extract",
                   action: v => extractToPath(t, v.text) };
    }
    function resolveDest(p, base) {
        p = expand(p);
        return p.startsWith("/") ? p : join(base, p);
    }
    function extractToPath(list, dest) {
        if (!dest.trim()) return;
        const d = resolveDest(dest, dirname(list[0].p));
        const mk = (e, mode) => ({ op: "extract", src: e.p, dst: mode === "folder" ? d : dirname(e.p), mode: mode,
                                   into: mode === "into" ? d : "", pw: arcPw[e.p] || "" });
        runExtract(list.length === 1 ? [mk(list[0], "into")] : list.map(e => mk(e, "folder")));
    }
    // ---- archive view actions
    function extractAllDialog() {
        if (!isArc) return;
        dialog = { kind: "input", title: "Extract all…", text: "Extract everything in “" + basename(arcFile) + "” into this folder (created if needed):",
                   value: join(dirname(arcFile), archiveStem(basename(arcFile))), ok: "Extract",
                   action: v => extractFromArc(null, v.text) };
    }
    function extractSelectedDialog() {
        if (!isArc) return;
        const t = targets();
        if (!t.length) { toast("Archive", "Select something to extract first."); return; }
        dialog = { kind: "input", title: "Extract selected…",
                   text: "Extract " + (t.length === 1 ? "“" + t[0].n + "”" : t.length + " items") + " into this folder:",
                   value: dirname(arcFile), ok: "Extract",
                   action: v => extractFromArc(t.map(e => e.ip), v.text) };
    }
    function extractFromArc(sel, dest) {
        if (!isArc || !dest.trim()) return;
        const d = resolveDest(dest, dirname(arcFile));
        const it = { op: "extract", src: arcFile, mode: sel ? "selected" : "into", into: d, pw: arcPw[arcFile] || "" };
        if (sel) it.sel = sel;
        enqueue({ title: "Extracting " + (sel ? (sel.length === 1 ? basename(sel[0]) : sel.length + " items") : basename(arcFile)),
                  items: [it], done: "Extracted", fail: "Extract failed", selectResults: false,
                  doneMsg: m => (m.results.length === 1 ? basename(m.results[0]) : m.results.length + " items") + " → " + (basename(d) || "/") });
    }
    // a file inside the archive: extract it to $XDG_RUNTIME_DIR/ultimit-data/arc-<hash>/ and hand it to xdg-open
    function openArcFile(e) {
        if (!isArc || e.d) return;
        enqueue({ title: "Opening " + e.n, fail: "Open failed", items: [{ op: "extract", src: arcFile, mode: "open", sel: [e.ip], pw: arcPw[arcFile] || "" }],
                  after: m => { if (m.results.length && !m.errors.length) run(["xdg-open", m.results[0]], "xdg-open " + m.results[0]); } });
    }

    // ---- compression (job op "compress")
    function compressBase(t) {
        if (t.length === 1) {
            const n = t[0].n;
            const i = n.lastIndexOf(".");
            return t[0].d || i <= 0 ? n : (isArchive(t[0]) ? archiveStem(n) : n.slice(0, i));
        }
        return basename(path) || "Archive";
    }
    function compressable() { return !isTrash && !isArc ? targets() : []; }
    function compressQuick() {
        const t = compressable();
        if (t.length) compress(t, compressBase(t), "zip", "");
    }
    function compressDialog() {
        const t = compressable();
        if (!t.length) return;
        dialog = { kind: "compress", count: t.length, name: compressBase(t), fmt: "zip", action: v => compress(t, v.name, v.fmt, v.pw) };
    }
    function compress(t, base, fmt, pw) {
        base = base.trim();
        const ext = "." + fmt;
        if (base.toLowerCase().endsWith(ext)) base = base.slice(0, -ext.length);
        if (base === "" || base.indexOf("/") >= 0) { toast("Compress", "Give the archive a name without slashes."); return; }
        const dst = join(dirname(t[0].p), base + ext);
        enqueue({ title: "Compressing to " + base + ext,
                  items: [{ op: "compress", srcs: t.map(e => e.p), dst: dst, fmt: fmt, pw: pw || "" }],
                  done: "Compressed", fail: "Compress failed", selectResults: true,
                  doneMsg: m => (m.results.length ? basename(m.results[0]) : base + ext) });
    }

    // ---------------------------------------------------------------- file operations
    function trashSel() {
        const t = targets();
        if (isTrash || isArc || !t.length) return;
        if (onMtp) { deleteSel(); return; }   // the trash lives on another filesystem: moving would be a copy
        enqueue({ title: "Moving to Trash", items: t.map(e => ({ op: "trash", src: e.p })),
                  done: "Trashed", dest: trashUri });
    }
    function deleteSel() {
        const t = targets();
        if (!t.length || isArc) return;
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
        if (isTrash || isArc) return;
        const p = join(path, uniqueName("New Folder"));
        enqueue({ title: "Creating folder", items: [{ op: "mkdir", dst: p }],
                  after: m => { if (m.results.length) { pendingRename = m.results[0]; renameTimer.restart(); } } });
    }
    function newFile() {
        if (isTrash || isArc) return;
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
        if (isTrash || isArc) return;
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
        const paths = isArc ? [arcFile] : (t.length ? t.map(e => e.p) : (isTrash ? [] : [path]));
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
        scanNetwork();
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
        onTriggered: { if (!drivesProc.running) drivesProc.running = true; root.scanPhones(); root.scanNetwork(); }
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
    readonly property bool onMtp: isMtpPath(isArc ? arcFile : path)
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
            const p = Icons.path(n);
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
        command: ["df", "-P", "-B1", "--", root.fsPath]
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
        if (!t) return "—";     // folders implied by an archive's paths have no date
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
        const key = Theme.skin + "|" + (e.d ? "inode/directory" : e.t + (e.x ? "!x" : ""));
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
        const tbl = Icons.table;   // dependency: re-evaluate once the skin's names.json has loaded
        // Ultimit's own art first for the whole candidate list (so audio/mpeg gets the Ultimit audio
        // icon rather than a fallback theme's audio-mpeg), then the startup icon theme.
        for (const t of tries) { const q = Icons.own(t); if (q !== "") { r = q; break; } }
        if (r === "") for (const t of tries) { const q = Icons.path(t); if (q !== "") { r = q; break; } }
        if (tbl && Object.keys(tbl).length > 0) iconCache[key] = r;
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
                    trash: "user-trash", root: "drive-harddisk", drive: "drive-removable-media", network: "network-workgroup" };
        const n = m[id] || "folder";
        const p = Icons.path(n);
        return p !== "" ? p : Icons.path("folder");
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
        return view.length + (view.length === 1 ? " ITEM" : " ITEMS") + (filter !== "" ? " MATCH" : "")
            + (isArc && arcListing && arcListing.truncated ? " · LISTING CAPPED AT " + arcListing.cap.toLocaleString(Qt.locale("en_US"), "f", 0) : "");
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
        case "address": goAddress(arg); return "ok";
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
        // tabs
        case "newtab": newTab(arg, false); return "ok";
        case "bgtab": newTab(arg, true); return "ok";
        case "tab": switchTab(parseInt(arg)); return "ok";
        case "nexttab": nextTab(arg === "-1" ? -1 : 1); return "ok";
        case "closetab": closeTab(arg === "" ? tabIndex : parseInt(arg)); return "ok";
        case "closeothers": closeOtherTabs(); return "ok";
        case "closeright": closeTabsRight(); return "ok";
        case "duptab": duplicateTab(); return "ok";
        case "reopentab": reopenTab(); return "ok";
        case "movetab": { const a = arg.split("|"); moveTab(parseInt(a[0]), parseInt(a[1])); return "ok"; }
        case "opentabs": openInTabs(targets()); return "ok";
        // archives (test hooks; passwords are read from a file given as "@/path", never from argv)
        case "extract": {   // here | folder | into:<dir>  -- applies to the selected archive(s)
            const t = archiveTargets(); if (!t.length) return "no archive selected";
            if (arg.startsWith("into:")) extractToPath(t, arg.slice(5)); else extractArchives(t, arg === "folder" ? "folder" : "here", "");
            return "ok";
        }
        case "canceljob": cancelJob(); return "ok";
        case "extractdlg": extractToDialog(); return "ok";
        case "arcall": extractFromArc(null, arg); return "ok";
        case "arcsel": { const t = targets(); if (!t.length) return "nothing selected"; extractFromArc(t.map(e => e.ip), arg); return "ok"; }
        case "arcalldlg": extractAllDialog(); return "ok";
        case "arcseldlg": extractSelectedDialog(); return "ok";
        case "compress": {  // fmt|name|@pwfile
            const t = compressable(); if (!t.length) return "nothing selected";
            const a = arg.split("|"); compress(t, a[1] || compressBase(t), a[0] || "zip", secret(a[2] || "")); return "ok";
        }
        case "compressdlg": compressDialog(); return "ok";
        case "dialogtext": submitDialog({ text: arg }); return "ok";
        case "dialogpw": submitDialog({ pw: secret(arg) }); return "ok";
        case "dialogcompress": { const a = arg.split("|"); submitDialog({ name: a[1], fmt: a[0], pw: secret(a[2] || "") }); return "ok"; }
        }
        return "unknown action";
    }
    FileView { id: secretFile; blockLoading: true; printErrors: false }
    function secret(ref) {   // "@/path/file" -> first line of that file (test hook; keeps passwords out of argv)
        if (!ref.startsWith("@")) return ref;
        secretFile.path = "";
        secretFile.path = ref.slice(1);
        secretFile.reload();
        return (secretFile.text() || "").split("\n")[0];
    }
    function stateJson() {
        return JSON.stringify({ path: path, tabs: tabs.map((t, i) => tabPath(i)), tab: tabIndex, closedTabs: closedTabs.length, count: view.length, total: entries.length, sel: selectedEntries().map(e => e.n),
            cur: cur, job: jobActive, queue: jobQueue.length, dialog: dialog ? dialog.kind : "", rename: renamePath, filter: filter,
            hidden: showHidden, sort: sortKey, desc: sortDesc, view: viewMode, clip: clipPaths.length, cut: clipCut,
            first: view.slice(0, 5).map(e => e.n), drives: drives.length, phones: phones.map(p => ({ id: p.id, label: p.label, mount: p.mount })), mtpBusy: mtpOp.running,
            mtpTool: mtpTool, onMtp: onMtp, disk: disk, err: error,
            arc: isArc ? { file: arcFile, inner: arcInner, count: arcListing ? arcListing.count : -1, type: arcListing ? arcListing.type : "",
                           truncated: arcListing ? arcListing.truncated : false } : null,
            jobTitle: jobTitle, jobName: jobName, jobFrac: jobFrac, dialogTitle: dialog && dialog.title ? dialog.title : "",
            props: propsStat ? { size: propsStat.size, mode: propsStat.mode, mime: propsStat.mime, du: propsDu } : null });
    }
}
