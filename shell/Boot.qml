// Boot.qml - boot sequence overlay controller + per-screen overlay windows.
// The continuation of the greeter's (and Plymouth's) hand-off frame: black, the emblem centred
// (84 px, stroke 1.2), "[ ULTIMIT ]" 18 px below, a 240 px accent line 20 px below that.
//   0-1500 ms     the emblem is re-traced in the accent colour with a soft glow, then settles
//   500 ms +      the log lines type in (real data: kernel from `uname -r`, GPUs from `lspci -mm`)
//   reveal (1300) an accent line sweeps out from the emblem across the screen while the black stage
//                 breaks into shards, radiating from the emblem (a crack lights along the shard borders, then each
//                 shard drifts outward, turns, shrinks and fades, staggered by distance). Click skips straight to the reveal.
// Shown once at startup (unless Config.bootOnStart is false) and whenever Config.playBoot() is called
// (Accessory button, rail emblem). Reduced motion: no tracing or shards, the stage just crossfades out.
// One linear clock (`elapsed`) drives everything; the overlay unmaps and nothing runs when it ends.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"

Scope {
    id: boot

    // Set by shell.qml once Persist has read the settings file.
    property bool settingsReady: false

    property bool active: false     // overlay mapped
    property bool fading: false     // fade-out in progress
    property real elapsed: 0        // ms since start (mockup timeline)
    property var lines: []

    // ---- system info (collected once) ----
    property string kernel: ""
    property var gpus: []
    property string qsVersion: ""
    property bool infoReady: false
    property bool autostartDone: false

    Process {
        running: true
        command: ["sh", "-c", "uname -r; (qs --version 2>/dev/null || ~/.local/ultimit-deps/bin/qs --version) | head -1; lspci -mm 2>/dev/null | grep -E 'VGA|3D controller|Display controller'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = text.split("\n").filter(r => r.length > 0);
                boot.kernel = rows.length ? rows[0].trim() : "";
                const qv = rows.length > 1 ? rows[1].match(/quickshell\s+([0-9][^\s,]*)/i) : null;
                boot.qsVersion = qv ? qv[1] : "";
                const out = [];
                for (let i = 2; i < rows.length; i++) {
                    const f = [];
                    const re = /"([^"]*)"/g;
                    let m;
                    while ((m = re.exec(rows[i])) !== null) f.push(m[1]);
                    if (f.length < 3) continue;
                    // vendor: strip corporate suffixes; device: prefer the [marketing name]
                    const vendor = f[1].replace(/\s*(Corporation|Corp\.?|Inc\.?|\[AMD\/ATI\]|Technologies.*)$/i, "").trim();
                    const br = f[2].match(/\[([^\]]+)\]/);
                    out.push((vendor + " " + (br ? br[1] : f[2])).trim());
                }
                boot.gpus = out;
                boot.infoReady = true;
                boot.maybeAutostart();
            }
        }
    }

    function pad(text) {
        const w = 38;
        if (text.length > w - 6) text = text.substring(0, w - 7) + "~";
        const dots = Math.max(2, w - text.length - 1);
        return text + " " + ".".repeat(dots) + " ok";
    }
    function buildLines() {
        const out = [];
        out.push(pad("kernel " + (boot.kernel || "unknown")));
        for (let i = 0; i < boot.gpus.length; i++) out.push(pad("gpu" + i + "  " + boot.gpus[i]));
        out.push(pad("compositor  ultimit (wlroots)"));
        out.push(pad("shell  quickshell " + (boot.qsVersion || "?")));
        out.push(pad("skin  " + Theme.skin));
        return out;
    }

    readonly property int lineStart: 500
    readonly property int lineStep: 260
    readonly property int revealMs: 1400
    // when the reveal starts: after the last log line has settled (moved up by a click to skip)
    property real revealStart: 1800
    readonly property int shown: {
        if (!Config.motion) return lines.length;
        return Math.max(0, Math.min(lines.length, Math.floor((elapsed - lineStart) / lineStep) + 1));
    }
    readonly property string logText: lines.slice(0, shown).join("\n")
    readonly property real reveal: fading ? elapsed - revealStart : -1   // ms into the reveal

    function start() {
        if (boot.active && !boot.fading) return;   // already running
        timeline.stop();
        fadeEnd.stop();
        boot.lines = buildLines();
        boot.elapsed = 0;
        boot.fading = false;
        boot.active = true;
        if (Config.motion) {
            boot.revealStart = Math.max(1800, lineStart + boot.lines.length * lineStep + 500);
            timeline.from = 0;
            timeline.to = boot.revealStart;
            timeline.duration = boot.revealStart;
        } else {
            boot.revealStart = 800;
            timeline.from = 0; timeline.to = 800; timeline.duration = 800;
        }
        timeline.start();
    }
    // Begin the reveal now (end of the timeline, or a click).
    function end() {
        if (!boot.active || boot.fading) return;
        timeline.stop();
        boot.revealStart = boot.elapsed;
        boot.fading = true;
        if (Config.motion) {
            timeline.from = boot.elapsed;
            timeline.to = boot.elapsed + boot.revealMs;
            timeline.duration = boot.revealMs;
            timeline.start();
        } else {
            fadeEnd.interval = 260;
            fadeEnd.restart();
        }
    }

    NumberAnimation {
        id: timeline
        target: boot; property: "elapsed"
        onFinished: { if (boot.fading) { boot.active = false; boot.fading = false; } else boot.end(); }
    }
    Timer {
        id: fadeEnd
        onTriggered: { boot.active = false; boot.fading = false; }
    }

    // Startup: once settings are read and system info is in (or after a grace period).
    function maybeAutostart() {
        if (boot.autostartDone || !boot.settingsReady || !boot.infoReady) return;
        boot.autostartDone = true;
        if (Config.bootOnStart) boot.start();
    }
    onSettingsReadyChanged: maybeAutostart()
    Timer {
        interval: 2500; running: true
        onTriggered: { boot.infoReady = true; boot.settingsReady = true; boot.maybeAutostart(); }
    }
    Connections {
        target: Config
        function onBootRequestChanged() { boot.start(); }
    }

    IpcHandler {
        target: "boot"
        function play(): void { Config.playBoot(); }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            visible: boot.active
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "ultimit-boot"

            readonly property real r: boot.reveal                 // ms into the reveal, -1 before
            readonly property bool revealing: r >= 0 && Config.motion
            // hand-off geometry (same constants as the greeter): emblem centred, wordmark 18 px
            // below it, accent line 20 px below the wordmark
            readonly property real cx: width / 2
            readonly property real cy: height / 2
            readonly property real wmTop: cy + 42 + 18
            readonly property real lineY: wmTop + wmText.implicitHeight + 20
            // tracing: the accent copy of the emblem is drawn over 100-1100 ms, then fades into the ink one
            readonly property real trace: Config.motion ? Anim.seg(boot.elapsed, 100, 1100) : 0
            readonly property real glowOp: Config.motion ? Anim.seg(boot.elapsed, 0, 150) * (1 - Anim.seg(boot.elapsed, 1100, 1600)) : 0
            // reveal pieces
            readonly property real sweep: revealing ? Anim.out3(Anim.seg(r, 0, 380)) : 0
            readonly property real sweepOp: revealing ? 1 - Anim.seg(r, 520, 1000) : 0
            readonly property real inkOp: revealing ? 1 - Anim.seg(r, 0, 300) : 1

            Rectangle {   // the intact stage
                anchors.fill: parent
                color: "#000000"
                visible: !win.revealing
                opacity: boot.fading ? 0 : 1      // reduced motion only: a short crossfade
                Behavior on opacity { NumberAnimation { duration: Config.motion ? 0 : 250 } }
            }

            // ---- the stage cracking into shards that fall away (one shader, shaders/bootshards.frag) ----
            ShaderEffect {
                anchors.fill: parent
                visible: win.revealing && win.r < boot.revealMs
                property size box: Qt.size(width, height)
                property point ctr: Qt.point(win.cx, win.cy)
                property real t: win.r
                property real far: Math.hypot(Math.max(win.cx, win.width - win.cx), Math.max(win.cy, win.height - win.cy))
                property real r0: Math.max(40, win.height * 0.10)
                property real seed: 0.37
                property color accent: Theme.accent
                property color edgeC: Theme.light ? "#ffffff" : Qt.rgba(Theme._csv(Theme.edge)[0] / 255, Theme._csv(Theme.edge)[1] / 255, Theme._csv(Theme.edge)[2] / 255, 1)
                fragmentShader: Qt.resolvedUrl("components/shaders/bootshards.frag.qsb")
            }

            // ---- the click target (skip) ----
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: boot.end()
            }

            // ---- hand-off frame: emblem, wordmark, accent line ----
            Item {
                anchors.fill: parent
                opacity: win.inkOp
                visible: opacity > .005
                scale: win.revealing ? 1 + .12 * Anim.out3(Anim.seg(win.r, 0, 350)) : 1
                transformOrigin: Item.Center

                Emblem {   // soft glow behind the trace
                    x: win.cx - 42; y: win.cy - 42
                    size: 84; strokeWidth: 4.5
                    color: Theme.accent
                    opacity: .22 * win.glowOp
                    visible: opacity > .005
                    draw: win.trace
                }
                Emblem {
                    x: win.cx - 42; y: win.cy - 42
                    size: 84; strokeWidth: 1.2
                    color: Theme.fg
                }
                Emblem {   // the accent re-trace
                    x: win.cx - 42; y: win.cy - 42
                    size: 84; strokeWidth: 1.2
                    color: Theme.accent
                    opacity: win.glowOp
                    visible: opacity > .005
                    draw: win.trace
                }
                Text {
                    id: wmText
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: win.wmTop
                    text: "[ ULTIMIT ]"
                    color: Theme.fg
                    font.family: Theme.display
                    font.pixelSize: 30
                    font.letterSpacing: 6
                }
                Rectangle {
                    width: 240; height: 2
                    x: win.cx - 120; y: win.lineY
                    color: Theme.accent
                }
                Text {
                    x: win.cx - width / 2
                    y: win.lineY + 2 + 22
                    width: Math.min(420, win.width - 32)
                    height: Math.max(implicitHeight, 9 * 11 * 1.7)
                    text: boot.logText
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 11
                    lineHeight: 1.7
                    wrapMode: Text.WrapAnywhere
                }
            }

            // the accent line sweeping out from the emblem, across the screen
            Rectangle {
                height: 2
                width: win.width * win.sweep
                x: win.cx - width / 2; y: win.cy - 1
                color: Theme.accent
                opacity: win.sweepOp
                visible: win.revealing && opacity > .005 && width > 1
            }
        }
    }
}
