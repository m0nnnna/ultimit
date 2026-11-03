pragma Singleton

// Backup.qml - state of BACKUP, the Ultimit GUI for NekoShot full-system backups. All logic lives in nekoshot.py
// (JSON on stdout); root work goes through nekoshot-helper via pkexec. A dismissed password prompt is a calm note.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/nekoshot/nekoshot.py")

    property bool open: false
    property string tab: "overview"        // overview | snapshots | schedule | settings | recovery
    function show() { quitTimer.stop(); open = true; refresh(); }

    property bool loaded: false
    property var st: ({})
    property string busy: ""               // backup | prune | verify:<path> | schedule | ""
    property string note: ""
    property string noteKind: "info"
    property bool refreshing: false
    property var recoverySteps: []
    property var verified: ({})            // path -> true/false, this session only

    readonly property var settings: st.settings || ({})
    readonly property var snapshots: st.snapshots || []
    readonly property var running: st.running || null
    readonly property var last: st.last || null
    readonly property var schedule: st.schedule || []
    readonly property var warnings: st.warnings || []
    readonly property bool ready: loaded && st.cli === true
    readonly property bool backingUp: running !== null || busy === "backup"

    function run(args, cb) { procC.createObject(root, { command: ["python3", root.helper].concat(args), cb: cb }); }
    Component {
        id: procC
        Process {
            id: p
            property var cb
            stdout: StdioCollector {
                onStreamFinished: {
                    let o;
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "The BACKUP helper failed." }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }

    function say(text, kind) { note = text; noteKind = kind || "info"; }

    function refresh() {
        if (refreshing) return;
        refreshing = true;
        run(["state"], o => { refreshing = false; st = o; loaded = true; });
    }
    // Faster poll while a backup runs so the progress bar moves.
    Timer { interval: root.running ? 2000 : 8000; repeat: true; running: root.open && root.busy === ""; onTriggered: root.refresh() }

    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open) Qt.quit() }
    onOpenChanged: if (!open) quitTimer.restart()

    function act(tag, args, waiting, done) {
        if (busy !== "") return;
        busy = tag;
        say(waiting || "Waiting for your authorization…");
        run(args, o => {
            busy = "";
            if (o.cancelled) say("Cancelled. Nothing was changed.");
            else if (!o.ok) say(o.error || "That did not work.", "error");
            else say(typeof done === "function" ? done(o) : done);
            refresh();
        });
    }
    function backupNow() { act("backup", ["backup"], "", "Backup started. It keeps running if you close this window."); }
    function prune() { act("prune", ["prune"], "", "Old backups removed."); }
    function verify(path) {
        if (busy !== "") return;
        busy = "verify:" + path;
        say("Checking the backup…");
        run(["verify", path], o => {
            busy = "";
            const v = Object.assign({}, verified); v[path] = o.verified === true; verified = v;
            say(o.verified ? "Backup is intact." : (o.error || "This backup is damaged."), o.verified ? "info" : "error");
        });
    }
    function setSetting(key, value) { run(["set", key, String(value)], o => { if (!o.ok) say(o.error, "error"); refresh(); }); }
    function makePassphrase(cb) { run(["passphrase", "--generate"], o => { refresh(); if (cb) cb(o); }); }
    function addSchedule(cron) { act("schedule", ["schedule-add", "ultimit-backup", cron], "", "Scheduled."); }
    function removeSchedule() { act("schedule", ["schedule-remove", "ultimit-backup"], "", "Schedule removed."); }
    function loadRecovery() { run(["recovery"], o => { recoverySteps = o.steps || []; }); }
}
