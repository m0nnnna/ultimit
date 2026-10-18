pragma Singleton

// Claude.qml - state of CLAUDE, the Ultimit Claude app: Claude Code (the CLI it runs on), the accounts,
// the projects, which window is open, and the helper (claude.py). One ClaudeWindow, see ClaudeApp.qml.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/claude/claude.py")

    // ---- Claude Code ----
    property string cliPath: ""
    property string cliVersion: ""
    property bool cliChecked: false
    function checkCli() { run(["cli"], o => { root.cliPath = o.path || ""; root.cliVersion = o.version || ""; root.cliChecked = true; }); }

    // ---- accounts and projects (claude.py state) ----
    property var accounts: []           // [{ id, name, dir }]  dir "" = the usual ~/.claude
    property var projects: []           // [{ id, name, dir, account, model, perm, notes, builtin? }]
    property bool defaultUsed: false    // an account already uses ~/.claude
    property var status: ({})           // account id -> { loggedIn, method, email, org } (or { checking: true })
    property bool loaded: false
    function reload(cb) {
        run(["state"], o => {
            if (!o.ok) return;
            root.accounts = o.accounts; root.projects = o.projects; root.defaultUsed = o.defaultUsed;
            root.loaded = true;
            for (const a of o.accounts) if (!(a.id in root.status)) root.checkAccount(a.id);
            if (cb) cb();
        });
    }
    function setStatus(id, s) { const all = Object.assign({}, status); all[id] = s; status = all; }
    function checkAccount(id) {
        setStatus(id, Object.assign({}, status[id] || {}, { checking: true }));
        run(["auth-status", id], o => root.setStatus(id, o.ok ? o : { loggedIn: false, err: o.err }));
    }
    function account(id) { return accounts.find(a => a.id === id) || null; }
    function accountName(id) { const a = account(id); return a ? a.name : ""; }
    function project(id) { return projects.find(p => p.id === id) || null; }
    // The account a project's new chats use: its own, else the first one signed in, else the first one.
    function accountFor(p) {
        if (p && account(p.account)) return p.account;
        const inn = accounts.find(a => (status[a.id] || {}).loggedIn);
        return inn ? inn.id : (accounts.length ? accounts[0].id : "");
    }
    function saveProject(p, cb) {
        run(["project-save"], o => { if (o.ok) reload(() => cb && cb(o)); else if (cb) cb(o); }, JSON.stringify(p));
    }

    // ---- plan usage: each account's limits as Claude Code last reported them (with every turn) ----
    property var usage: ({})            // account id -> { windows: { five_hour: { used 0-1, resets }, ... }, overage, t }
    function loadUsage() {
        run(["usage"], o => {
            if (!o.ok) return;
            const all = Object.assign({}, o.accounts);
            for (const id in root.usage) if (!all[id] || all[id].t < root.usage[id].t) all[id] = root.usage[id];
            root.usage = all;
        });
    }
    function setUsage(id, u) { const all = Object.assign({}, usage); all[id] = u; usage = all; }

    // ---- the window (IPC) ----
    property var ids: []
    property int raise: 0
    property string wantProject: ""     // a project to show when the window opens / is raised
    property string wantDir: ""         // a folder to open as a project ("Ask Claude about this folder")
    function open() { quitTimer.stop(); if (ids.length === 0) ids = [1]; else raise++; }
    function openProject(id) { wantProject = id; open(); }
    function openDir(d) { wantDir = d; open(); }
    function closeWin() { ids = []; maybeQuit(); }
    function stateJson() { return JSON.stringify({ open: ids.length > 0, mini: miniShown, cli: cliVersion, accounts: accounts.length, projects: projects.length }); }

    // ---- the corner panel (MiniPanel.qml, from the tray's Claude button) ----
    property bool miniMade: false       // created on first use, then kept while the process lives
    property bool miniShown: false
    property bool miniWorking: false    // its chat is running, so hiding it doesn't end the process
    property int miniRaise: 0
    property string miniScreen: ""      // the output it sits on (the bottom bar's)
    function showMini(screen) {
        quitTimer.stop();
        if (screen) miniScreen = screen;
        miniMade = true; miniShown = true; miniRaise++;
    }
    function toggleMini(screen) { if (miniShown) hideMini(); else showMini(screen); }
    function hideMini() { miniShown = false; maybeQuit(); }
    // EXPAND: the full window takes over the mini's chat (still running) and its draft
    property var handoff: null          // { chat: ChatSession, draft }
    function expand(chat, draft) { handoff = { chat: chat, draft: draft || "" }; miniShown = false; open(); }

    // CLAUDE runs as its own quickshell process; it exits shortly after its window and corner panel close
    // and nothing is left running.
    function maybeQuit() { quitTimer.restart(); }
    Timer {
        id: quitTimer; interval: 800
        onTriggered: if (root.ids.length === 0 && !root.miniShown && !root.miniWorking) Qt.quit()
    }

    Component.onCompleted: { checkCli(); reload(); loadUsage(); }

    // ---- helper process: run(args, callback(parsedJson), stdinLine?) ----
    function run(args, cb, input) {
        procC.createObject(root, { command: ["python3", root.helper].concat(args), cb: cb, input: input || "" });
    }
    Component {
        id: procC
        Process {
            id: p
            property var cb
            property string input: ""
            stdinEnabled: input !== ""
            onStarted: if (input !== "") write(input + "\n")
            stdout: StdioCollector {
                onStreamFinished: {
                    let o;
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, err: "helper failed" }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }
    // A long-running helper command with JSON-line events: stream(args, onEvent(o)) -> the Process
    // (write() a line to it; set running = false to stop it).
    function stream(args, onEvent) {
        return streamC.createObject(root, { command: ["python3", root.helper].concat(args), onEvent: onEvent });
    }
    Component {
        id: streamC
        Process {
            id: s
            property var onEvent
            property bool ready: false      // free for the caller (ChatSession: Claude Code has started)
            stdinEnabled: true
            stdout: SplitParser {
                onRead: line => {
                    let o = null;
                    try { o = JSON.parse(line); } catch (e) { return; }
                    if (s.onEvent) s.onEvent(o);
                }
            }
            onExited: Qt.callLater(() => s.destroy())
            Component.onCompleted: running = true
        }
    }
}
