pragma Singleton

// AltTabState.qml - the Alt+Tab switcher's state, fed by the compositor.
//
// The compositor owns the switcher (MRU order, highlight, Alt release = go). It pushes events down
// its control socket once we send "subscribe": one JSON line per event,
//   {"event":"alttab","action":"show","index":1,"items":[{"id","app_id","title","minimized"}...]}
//   {"event":"alttab","action":"move","index":2,"items":[...]}   (index is all that changes)
//   {"event":"alttab","action":"hide","index":2}
// No process is spawned per keypress, so the highlight follows Tab with socket latency. The socket
// is $XDG_RUNTIME_DIR/ultimit-$WAYLAND_DISPLAY.sock (else $ULTIMIT_SOCK); we reconnect if it drops.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // The same socket also carries {"event":"dismiss","keep":NAME}: a shortcut ran, or a click
    // landed on another screen, while a menu or flyout held the keyboard (shell.qml closes them).
    signal dismiss(string keep)

    property bool shown: false
    property var items: []
    property int index: 0
    readonly property var current: items.length > 0 && index >= 0 && index < items.length ? items[index] : null

    readonly property string sockPath: {
        const rt = Quickshell.env("XDG_RUNTIME_DIR");
        const wd = Quickshell.env("WAYLAND_DISPLAY");
        if (rt && wd) return rt + "/ultimit-" + wd + ".sock";
        return Quickshell.env("ULTIMIT_SOCK") || "";
    }

    function handle(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        if (ev.event === "dismiss") { root.dismiss(ev.keep || ""); return; }
        if (ev.event !== "alttab") return;
        if (ev.action === "show") {
            root.items = ev.items || [];
            root.index = ev.index;
            root.shown = true;
        } else if (ev.action === "move") {
            root.index = ev.index;
        } else if (ev.action === "hide") {
            root.shown = false;
        }
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: root.sockPath !== ""
        onConnectedChanged: {
            if (connected) { write("subscribe\n"); flush(); }
            else root.shown = false;
        }
        parser: SplitParser {
            onRead: data => root.handle(data)
        }
    }

    Timer {   // compositor restarted, or not up yet: try again
        interval: 2000
        repeat: true
        running: root.sockPath !== "" && !sock.connected
        onTriggered: { sock.connected = false; sock.connected = true; }
    }
}
