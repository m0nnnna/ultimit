pragma Singleton

// Privacy.qml - what is using the microphone, the camera or the screen right now, and the screen
// recording ultimit-screenshot runs; StatusTray shows a marker for each (click REC to stop it).
//   mic     PipeWire audio capture streams (level meters that only peek are skipped)
//   screen  the screen-cast stream xdg-desktop-portal-wlr creates when an app shares the screen
//   camera  processes of this user holding a /dev/video* device open (apps use V4L2 directly, so
//           PipeWire doesn't see them); checked every 3 s
//   rec     $XDG_RUNTIME_DIR/ultimit-recording.json while ultimit-screenshot records
// Each list holds app names for the tooltips.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values
    PwObjectTracker { objects: root.nodes.filter(n => n.isStream || !n.audio) }
    function prop(n, k) { return String(((n && n.properties) || {})[k] || ""); }
    function appName(n) {
        return prop(n, "application.name") || prop(n, "application.process.binary") || n.description || n.name || "An app";
    }
    function uniq(a) { return a.filter((x, i) => a.indexOf(x) === i); }

    readonly property var micApps: uniq(nodes.filter(n => n.isStream && !n.isSink
        && prop(n, "media.class") === "Stream/Input/Audio" && prop(n, "stream.monitor") !== "true"
        && prop(n, "stream.capture.sink") !== "true").map(appName))
    readonly property var screenApps: nodes.some(n => /^xdpw/.test(n.name || "") || /xdg-desktop-portal-wlr/.test(prop(n, "application.name")))
        ? ["An app (through the screen-share dialog)"] : []
    property var cameraApps: []

    // ---- camera: /dev/video* held open ----
    Process {
        id: cam
        command: ["sh", "-c", "for p in $(find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/video*' 2>/dev/null | cut -d/ -f3 | sort -u); do cat /proc/$p/comm 2>/dev/null; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = root.uniq(text.split("\n").map(s => s.trim()).filter(s => s !== ""));
                if (JSON.stringify(names) !== JSON.stringify(root.cameraApps)) root.cameraApps = names;
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!cam.running) cam.running = true }

    // ---- screen recording (ultimit-screenshot record-*) ----
    property var rec: null          // {pid, file, started, what} or null
    FileView {
        id: recFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ultimit-recording.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.rec = JSON.parse(text()); } catch (e) { root.rec = null; } }
        onLoadFailed: root.rec = null
    }
    // the file is replaced and removed rather than edited, so look again now and then
    Timer { interval: 2000; running: true; repeat: true; onTriggered: recFile.reload() }
    SystemClock { id: tick; precision: SystemClock.Seconds; enabled: root.rec !== null }
    readonly property string recTime: {
        if (!rec) return "";
        const s = Math.max(0, Math.floor(tick.date.getTime() / 1000) - rec.started);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function stopRecording() { Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-screenshot"), "stop"]); }
}
