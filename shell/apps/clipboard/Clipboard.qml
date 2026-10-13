pragma Singleton

// Clipboard.qml - clipboard history (Super+V). Keeps `clip.py watch` running for the session (it
// records every copy), loads the list when the panel opens, and pastes a picked item: put it back on
// the clipboard, close the panel so the previous window gets the keyboard back, then send Ctrl+V
// (Ctrl+Shift+V to terminals) with wtype.
// IPC: qs ipc call clipboard toggle | open | close | list
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/clipboard/clip.py")
    property bool open: false
    property var items: []
    property bool loaded: false

    function show() { refresh(); open = true; }
    function toggle() { if (open) open = false; else show(); }

    // ---- the recorder: restarted if it stops (backing off if it keeps failing) ----
    property int watchFails: 0
    Process {
        id: watcher
        running: true
        command: ["python3", "-I", root.helper, "watch"]
        onExited: { root.watchFails++; rewatch.interval = Math.min(60000, 1000 * root.watchFails); rewatch.start(); }
    }
    Timer { id: rewatch; onTriggered: watcher.running = true }
    Timer { interval: 120000; running: watcher.running; repeat: true; onTriggered: root.watchFails = 0 }

    // ---- clip.py runs ----
    function run(args, cb) { procC.createObject(root, { command: ["python3", "-I", root.helper].concat(args), cb: cb }); }
    Component {
        id: procC
        Process {
            id: p
            property var cb
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    let o = {};
                    try { o = JSON.parse(text); } catch (e) {}
                    if (p.cb) p.cb(o);
                    p.destroy();
                }
            }
        }
    }
    function refresh() { run(["list"], o => { root.items = o.items || []; root.loaded = true; }); }
    function pin(id, on) { run(["pin", id, on ? "on" : "off"], () => refresh()); }
    function remove(id) { run(["delete", id], () => refresh()); }
    function clear() { run(["clear"], () => refresh()); }

    readonly property var terminals: ["foot", "footclient", "kitty", "alacritty", "org.wezfurlong.wezterm", "xterm",
        "uxterm", "org.kde.konsole", "konsole", "org.gnome.ptyxis", "org.gnome.console", "com.mitchellh.ghostty"]
    function paste(id) {
        const t = ToplevelManager.activeToplevel;
        const term = !!t && terminals.indexOf((t.appId || "").toLowerCase()) >= 0;
        run(["copy", id], o => {
            if (!o.ok) { Toasts.show("Clipboard", "Couldn't put that back on the clipboard."); return; }
            pasteKeys.command = term ? ["wtype", "-M", "ctrl", "-M", "shift", "v", "-m", "shift", "-m", "ctrl"]
                                     : ["wtype", "-M", "ctrl", "v", "-m", "ctrl"];
            pasteDelay.start();
        });
        open = false;
    }
    // Give the previous window the keyboard back before pressing Ctrl+V into it.
    Timer { id: pasteDelay; interval: 120; onTriggered: pasteKeys.running = true }
    Process { id: pasteKeys }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.open = false; }
        function list(): string { return JSON.stringify(root.items.map(i => ({ id: i.id, kind: i.kind, text: i.text.slice(0, 60), pinned: !!i.pinned }))); }
    }
}
