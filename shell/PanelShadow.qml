pragma Singleton

// PanelShadow.qml - tells the compositor where the shell's floating panels are, so it can draw
// their soft shadows (scenefx, like the window shadow). The panels sit inside full-screen
// transparent layer surfaces, and a shadow drawn by QML in the same surface would be
// backdrop-blurred with the panel, so Surface.qml reports its rect here instead:
//   panel-shadow NAMESPACE OUTPUT ID X Y W H ELEV ALPHA MS     (ELEV 0 removes it)
// A line goes out only when a rect or visibility changes (never per frame); the compositor does
// the fade. Same socket as ultimitctl (see AltTabState.qml); lines queue until it is connected.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string sockPath: {
        const rt = Quickshell.env("XDG_RUNTIME_DIR");
        const wd = Quickshell.env("WAYLAND_DISPLAY");
        if (rt && wd) return rt + "/ultimit-" + wd + ".sock";
        return Quickshell.env("ULTIMIT_SOCK") || "";
    }
    property var queue: []

    function report(ns, output, id, x, y, w, h, elev, alpha, ms) {
        const line = ["panel-shadow", ns, output || "-", id, Math.round(x), Math.round(y), Math.round(w), Math.round(h),
                      elev, alpha, Config.dur(ms)].join(" ") + "\n";
        if (sock.connected) { sock.write(line); sock.flush(); }
        else if (root.queue.length < 64) root.queue.push(line);
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: root.sockPath !== ""
        onConnectedChanged: {
            if (!connected) return;
            for (const l of root.queue) write(l);
            root.queue = [];
            flush();
        }
        parser: SplitParser { onRead: data => {} }   // replies are read and dropped
    }

    Timer {   // compositor restarted, or not up yet: try again
        interval: 2000
        repeat: true
        running: root.sockPath !== "" && !sock.connected
        onTriggered: { sock.connected = false; sock.connected = true; }
    }
}
