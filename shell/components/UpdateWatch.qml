// UpdateWatch.qml - says when a new Ultimit release is out (GitHub, see docs/updates.md): checks
// 3 minutes after login, then every 6 hours, and shows each new version once. Clicking the card
// opens Settings > Updates. Ubuntu's own updates are left to Ubuntu (they install by themselves).
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Scope {
    id: root
    readonly property string seenFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ultimit/update-seen"
    property string seen: ""

    FileView {
        path: root.seenFile
        printErrors: false
        onLoaded: root.seen = text().trim()
    }

    Timer {
        // Not in a devbox (scripts/devbox.sh), unless it is testing this with fake data
        running: !Quickshell.env("ULTIMIT_DEVBOX") || !!Quickshell.env("UPDATES_FAKE_DIR")
        interval: Quickshell.env("UPDATES_FAKE_DIR") ? 5000 : 3 * 60 * 1000
        repeat: true
        onTriggered: {
            interval = 6 * 3600 * 1000;
            if (!check.running) check.running = true;
        }
    }

    Process {
        id: check
        command: ["python3", Quickshell.shellPath("apps/settings/updates.py"), "ultimit"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o;
                try { o = JSON.parse(text); } catch (e) { return; }
                if (!o.newer || !o.latest || o.updating || o.latest.tag === root.seen) return;
                root.seen = o.latest.tag;
                Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"', "sh", root.seenFile, o.latest.tag]);
                Toasts.show("Ultimit " + o.latest.version,
                    "A new version of Ultimit is out. Click to see what changed and install it.",
                    "", 0, 1, () => Config.openSettings("updates"));
            }
        }
    }
}
