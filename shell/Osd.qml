pragma Singleton

// Osd.qml - state for the volume / brightness on-screen display (components/OsdOverlay.qml)
// plus the "media" IPC target.
//   qs ipc call osd volume | brightness | mic    read the current value and flash the OSD
//   qs ipc call media playPause | next | previous   first MPRIS player (prefers a playing one)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    property bool shown: false
    property string kind: "volume"      // volume | brightness | mic
    property real value: 0              // percent, 0..100 (volume may exceed)
    property bool muted: false
    readonly property string label: muted ? (kind === "mic" ? "MIC MUTED" : "MUTED")
        : (kind === "volume" ? "VOLUME" : (kind === "mic" ? "MIC" : "BRIGHTNESS"))

    function flash(k, v, m) {
        kind = k; value = v; muted = m; shown = true;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 1200; onTriggered: root.shown = false }

    // wpctl get-volume -> "Volume: 0.45 [MUTED]"
    component WpProbe: Process {
        id: p
        required property string kindName
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /Volume:\s*([0-9.]+)/.exec(text);
                if (m) root.flash(p.kindName, Math.round(parseFloat(m[1]) * 100), text.indexOf("[MUTED]") >= 0);
            }
        }
    }
    WpProbe { id: volProc; kindName: "volume"; command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"] }
    WpProbe { id: micProc; kindName: "mic"; command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"] }

    Process {
        id: briProc
        command: ["sh", "-c", "d=$(ls -d /sys/class/backlight/*/ 2>/dev/null | head -n1); [ -n \"$d\" ] && echo $(cat \"$d/brightness\") $(cat \"$d/max_brightness\")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/);
                const cur = parseInt(p[0]), max = parseInt(p[1]);
                if (max > 0) root.flash("brightness", Math.round(cur * 100 / max), false);
            }
        }
    }

    IpcHandler {
        target: "osd"
        function volume(): void { volProc.running = true; }
        function brightness(): void { briProc.running = true; }
        function mic(): void { micProc.running = true; }
    }

    // ---- media keys ----
    function player() {
        const ps = Mpris.players.values;
        let first = null;
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying) return ps[i];
            if (!first && ps[i].canControl) first = ps[i];
        }
        return first || (ps.length > 0 ? ps[0] : null);
    }
    IpcHandler {
        target: "media"
        function playPause(): void { const p = root.player(); if (p) p.togglePlaying(); }
        function next(): void { const p = root.player(); if (p) p.next(); }
        function previous(): void { const p = root.player(); if (p) p.previous(); }
    }
}
