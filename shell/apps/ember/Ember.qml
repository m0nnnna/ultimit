pragma Singleton

// Ember.qml - state of EMBER, the Ultimit desktop assistant: the AI providers you plugged in (Claude,
// GPT, Grok, a local model, a custom endpoint), which one she uses, the saved chats, whether she may act
// without asking, and the helper (ember.py). One EmberWindow, see EmberApp.qml.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/ember/ember.py")

    // ---- ember.py state ----
    property var providers: []          // [{ id, name, maker, kind, base, model, effort, key, hasKey, keyUrl }]
    property string provider: "anthropic"
    property bool trust: false          // commands, file writes and closing windows run without asking
    property var chats: []              // [{ id, title, updated, provider, model }]
    property bool keyring: false        // keys go to the login keyring (else a private file)
    property var efforts: []
    property bool loaded: false
    function reload(cb) {
        run(["state"], o => {
            if (!o.ok) return;
            root.providers = o.providers; root.provider = o.provider; root.trust = o.trust;
            root.chats = o.chats; root.keyring = o.keyring; root.efforts = o.efforts;
            root.loaded = true;
            if (cb) cb();
        });
    }
    function loadChats() { run(["chats"], o => { if (o.ok) root.chats = o.chats; }); }
    function prov(id) { return providers.find(p => p.id === id) || null; }
    readonly property var current: prov(provider)
    // ready to talk: a model is picked and, where one is needed, there is a key
    function usable(p) { return !!p && p.model !== "" && p.base !== "" && (p.hasKey || !p.key || p.id === "custom"); }
    readonly property bool ready: usable(current)

    function save(o, cb) { run(["settings-save"], () => reload(cb), JSON.stringify(o)); }
    function use(id) { provider = id; save({ provider: id }); }
    function setTrust(on) { trust = on; save({ trust: on }); }

    // ---- the window (IPC) ----
    property var ids: []
    property int raise: 0
    property string wantText: ""        // text to put in the composer ("ask" IPC)
    function open() { quitTimer.stop(); if (ids.length === 0) ids = [1]; else raise++; }
    function ask(t) { wantText = t; open(); raise++; }
    function closeWin() { ids = []; quitTimer.restart(); }
    function stateJson() { return JSON.stringify({ open: ids.length > 0, provider: provider, model: current ? current.model : "", chats: chats.length }); }

    // EMBER runs as its own quickshell process; it exits shortly after its window closes.
    Timer { id: quitTimer; interval: 800; onTriggered: if (root.ids.length === 0) Qt.quit() }

    Component.onCompleted: reload()

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
    // the chat session: JSON-line events out, send(object) a JSON line in; running = false stops it
    function stream(args, onEvent) {
        return streamC.createObject(root, { command: ["python3", root.helper].concat(args), onEvent: onEvent });
    }
    Component {
        id: streamC
        Process {
            id: s
            property var onEvent
            property var queue: []          // lines sent before the process was up
            function send(o) { if (running) write(JSON.stringify(o) + "\n"); else queue = queue.concat([o]); }
            onStarted: { for (const o of queue) write(JSON.stringify(o) + "\n"); queue = []; }
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
