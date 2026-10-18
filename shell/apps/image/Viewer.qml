pragma Singleton

// Viewer.qml - state of IMAGE, the Ultimit image viewer: the open windows (one FloatingWindow each,
// see ImageApp.qml), what each was asked to show, and the file helper (image.py).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/image/image.py")

    property var ids: []                // open window ids (Variants model)
    property var requests: ({})         // id -> { path } (its folder), { set: [paths] } or { gallery: dir }
    property var current: ({})          // id -> path on screen (for IPC state and re-open)
    property int nextId: 1
    property int raise: 0               // bumped to ask a window to grab focus
    property int raiseId: 0

    // Open one image (and browse its folder). A window already showing it is focused instead.
    function openFile(p) {
        quitTimer.stop();
        for (const id of ids) if (current[id] === p) { raiseId = id; raise++; return id; }
        return add({ path: p });
    }
    // Open several images as one set (a selection opened from DATA).
    function openSet(paths) {
        quitTimer.stop();
        return paths.length === 1 ? openFile(paths[0]) : add({ set: paths });
    }
    // The library: a folder as thumbnails ("" = Pictures). Always a new window.
    function openGallery(dir) {
        quitTimer.stop();
        return add({ gallery: dir });
    }
    function add(req) {
        const id = nextId++;
        requests[id] = req;
        ids = ids.concat([id]);
        return id;
    }
    function closeWin(id) {
        ids = ids.filter(x => x !== id);
        delete requests[id]; delete current[id];
        if (ids.length === 0) quitTimer.restart();
    }
    function setCurrent(id, p) { current[id] = p; }
    function stateJson() { return JSON.stringify(ids.map(id => ({ id: id, path: current[id] || "" }))); }

    // IMAGE runs as its own quickshell process; it exits shortly after its last window closes
    // (the delay lets a new open request cancel it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (root.ids.length === 0) Qt.quit() }

    // ---- helper process: run(args, callback(parsedJson)) ----
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
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, err: "helper failed" }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }
}
