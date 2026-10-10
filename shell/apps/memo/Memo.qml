pragma Singleton

// Memo.qml - state of MEMO, the Ultimit text editor: the list of open documents (one
// FloatingWindow each, see MemoApp.qml), editor settings and the file helper (memo.py).
// Settings persist in ~/.config/ultimit/memo.json.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || "/"
    readonly property string helper: Quickshell.shellPath("apps/memo/memo.py")

    // ---- editor settings (persisted) ----
    property bool wrap: true
    property bool tabSpaces: true       // Tab inserts 4 spaces (else a real tab)
    property int fontSize: 15
    onWrapChanged: saveTimer.restart()
    onTabSpacesChanged: saveTimer.restart()
    onFontSizeChanged: saveTimer.restart()

    // ---- documents ----
    property var ids: []                // open document ids (Variants model)
    property var draftIds: ({})         // id -> draft id of a recovered document
    property var paths: ({})            // id -> initial path ("" = untitled)
    property var infos: ({})            // id -> { path, name, modified, line, col, lines } (for IPC state)
    property int nextId: 1
    property var untitledNos: ({})      // id -> n for "Untitled n"
    property int untitledCount: 0
    property int raise: 0               // bumped to ask windows to grab focus
    property int raiseId: 0

    function openFile(p) {
        quitTimer.stop();
        for (const id of ids) {
            const i = infos[id];
            if (i && i.path === p && p !== "") { raiseId = id; raise++; return id; }
        }
        const id = nextId++;
        paths[id] = p;
        ids = ids.concat([id]);
        return id;
    }
    function newDoc() { untitledNos[nextId] = ++untitledCount; return openFile(""); }
    function closeDoc(id) {
        ids = ids.filter(x => x !== id);
        delete infos[id]; delete paths[id]; delete draftIds[id];
        infos = infos;
        if (ids.length === 0) quitTimer.restart();
    }
    function setInfo(id, o) { infos[id] = o; infos = infos; }
    function stateJson() {
        return JSON.stringify(ids.map(id => Object.assign({ id: id }, infos[id] || {})));
    }

    // MEMO runs as its own quickshell process; it exits shortly after its last window closes
    // (the delay lets pending draft deletions finish and lets a new open request cancel it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (root.ids.length === 0) Qt.quit() }

    // ---- crash recovery: restore drafts left by a previous run (one window per draft) ----
    function recoverDrafts() {
        run(["drafts"], "", o => {
            for (const d of (o.drafts || [])) {
                const id = nextId++;
                paths[id] = d.path; draftIds[id] = d.id; draftMeta[id] = d;
                ids = ids.concat([id]);
            }
        });
    }
    property var draftMeta: ({})

    // ---- helper process: run(args, stdinLine, callback(parsedJson)) ----
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

    // ---- settings file ----
    Timer { id: saveTimer; interval: 500; onTriggered: {
        if (!store.loaded) return;
        store.adapter.wrap = root.wrap; store.adapter.tabSpaces = root.tabSpaces; store.adapter.fontSize = root.fontSize;
        store.writeAdapter();
    } }
    FileView {
        id: store
        property bool loaded: false
        path: root.home + "/.config/ultimit/memo.json"
        printErrors: false
        atomicWrites: true
        watchChanges: false
        onLoaded: {
            root.wrap = adapter.wrap; root.tabSpaces = adapter.tabSpaces;
            root.fontSize = Math.max(8, Math.min(40, adapter.fontSize));
            loaded = true;
        }
        onLoadFailed: loaded = true
        adapter: JsonAdapter {
            property bool wrap: true
            property bool tabSpaces: true
            property int fontSize: 15
        }
    }
    Component.onCompleted: { Quickshell.execDetached(["mkdir", "-p", root.home + "/.config/ultimit"]); recoverDrafts(); }
}
