// CrashNotice.qml - after the compositor crashed (session/ultimit-run-compositor wrote last-crash),
// say so once on the next shell start: what happened, whether the desktop came back by itself, and
// where the report is. The note is then renamed to last-crash.seen.
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Scope {
    id: root
    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ultimit"

    FileView {
        path: root.dir + "/last-crash"
        printErrors: false
        onLoaded: {
            let c;
            try { c = JSON.parse(text()); } catch (e) { return; }
            Quickshell.execDetached(["mv", "-f", root.dir + "/last-crash", root.dir + "/last-crash.seen"]);
            if (Date.now() / 1000 - c.time > 24 * 3600) return;   // old news
            const when = new Date(c.time * 1000).toLocaleTimeString(Qt.locale(), "HH:mm");
            Toasts.show("Ultimit crashed",
                "The desktop stopped at " + when + " (" + c.what + ")"
                + (c.restarted ? " and started again by itself; apps that were open had to close." : ".")
                + " The report is saved:", c.report, 0);
        }
    }
}
