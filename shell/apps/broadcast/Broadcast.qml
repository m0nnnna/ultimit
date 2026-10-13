pragma Singleton

// Broadcast.qml - state of BROADCAST: one snapshot from `broadcast.py status` (polled while the window is open)
// and every action, all through the helper broadcast.py (JSON on stdout). The helper drives the hidden engines
// (EasyEffects for audio, OBS Studio for the camera). With BROADCAST_FAKE=1 in the environment it uses fake
// engines instead (see fixtures/), so the UI can be tried without touching the real ones.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/broadcast/broadcast.py")
    readonly property bool fake: Quickshell.env("BROADCAST_FAKE") === "1"

    // ---- window state ----
    property bool open: false
    property string tab: "mic"              // mic | speakers | camera
    function show() { quitTimer.stop(); open = true; refresh(); }

    // ---- snapshot ----
    property bool loaded: false
    property var st: ({})
    property string busy: ""                // "" | audio | mic | speakers | camera | monitor | route
    property string note: ""
    property string noteKind: "info"        // info | error
    property bool refreshing: false

    readonly property var mic: st.mic || ({ devices: [] })
    readonly property var spk: st.speakers || ({ devices: [] })
    readonly property var cam: st.camera || ({ engine: {} })
    readonly property bool audioRunning: st.audioEngine ? st.audioEngine.running === true : false
    readonly property bool camRunning: cam.engine ? cam.engine.running === true : false
    readonly property bool camStarting: busy === "camera" && !camRunning
    readonly property bool monitorOn: st.monitor ? st.monitor.on === true : false
    readonly property var webcams: st.webcams || []
    // The microphone level shown: the processed one while the engine runs, else the raw device.
    readonly property string meterNode: mic.enabled && audioRunning && mic.eeNode ? mic.eeNode.name : (mic.device ? mic.device.name : "")

    function say(text, kind) { note = text; noteKind = kind || "info"; }
    function dump() { return JSON.stringify(st); }

    // ---- helper process ----
    function run(args, cb) { procC.createObject(root, { command: ["python3", root.helper].concat(args), cb: cb }); }
    Component {
        id: procC
        Process {
            id: p
            property var cb
            stdout: StdioCollector {
                onStreamFinished: {
                    let o;
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "The BROADCAST helper failed." }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }

    function refresh() {
        if (refreshing || busy !== "") return;
        refreshing = true;
        run(["status"], o => { refreshing = false; if (o.ok) { st = o; loaded = true; } });
    }
    Timer { interval: 3000; repeat: true; running: root.open && root.busy === ""; onTriggered: root.refresh() }

    // BROADCAST is its own process: exit shortly after the window closes (a new open request cancels it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open) Qt.quit() }
    onOpenChanged: if (!open) quitTimer.restart()

    // Run a helper command as a named busy action; the result becomes a note and the snapshot is refreshed.
    function act(kind, args, doneText, cb) {
        if (busy !== "") return;
        busy = kind;
        run(args, o => {
            busy = "";
            if (!o.ok) say(o.error || "That did not work.", "error");
            else if (doneText) say(doneText);
            else say("");
            if (cb) cb(o);
            refresh();
        });
    }
    // Show a change right away; the next status replaces it.
    function patch(section, key, value) {
        const s = JSON.parse(JSON.stringify(st));
        if (!s[section]) return;
        s[section][key] = value;
        st = s;
    }

    function engineStart() { act("audio", ["engine", "start"], "Audio engine started."); }
    function micSet(key, value) {
        patch("mic", key, value);
        const a = ["mic", "set", "--" + key, typeof value === "boolean" ? (value ? "on" : "off") : value];
        act("mic", a, "", o => { if (o.ok && key === "enabled" && !value && monitorOn) monitor(false); });
    }
    function speakersSet(key, value) {
        patch("speakers", key, value);
        act("speakers", ["speakers", "set", "--" + key, typeof value === "boolean" ? (value ? "on" : "off") : value]);
    }
    function useMic(id) { act("mic", ["mic", "use", String(id)], "That microphone is now your default."); }
    function route(what) {
        act("route", ["route", what], what === "mic" ? "Apps now use “Easy Effects Source” as the microphone."
                                                     : "Apps now play through “Easy Effects Sink”.");
    }
    function monitor(on) { patch("monitor", "on", on); act("monitor", ["monitor", on ? "on" : "off"]); }
    function camSet(key, value) {
        if (key === "effect" || key === "device" || key === "image" || key === "blur") patch("camera", key, value);
        const a = ["camera", "set", "--" + key, typeof value === "boolean" ? (value ? "on" : "off") : String(value)];
        act("camera", a, "");
    }
    function camOff() { act("camera", ["camera", "off"], ""); }

    // ---- live preview: one long-running helper writes a JPEG per tick, prints a line per frame ----
    property int previewSeq: 0
    readonly property bool previewWanted: open && tab === "camera" && camRunning && busy === ""
    Process {
        id: previewProc
        command: ["python3", root.helper, "camera", "preview", "--loop", "4"]
        running: root.previewWanted
        stdout: SplitParser {
            onRead: line => { try { if (JSON.parse(line).seq) root.previewSeq++; } catch (e) {} }
        }
    }
    readonly property string previewUrl: cam.previewPath && previewSeq > 0 ? "file://" + cam.previewPath + "?" + previewSeq : ""
}
