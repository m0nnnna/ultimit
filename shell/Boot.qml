// Boot.qml - boot sequence overlay controller + per-screen overlay windows.
// Port of boot() from docs/design/mockup.html: emblem stroke-draw, wordmark fade-in,
// log lines, fade out, click to skip. Shown once at startup (unless Config.bootOnStart
// is false) and whenever Config.playBoot() is called (Accessory button, rail emblem).
// Real data: kernel from `uname -r`, GPU names from `lspci -mm`; the rest is static.
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
    readonly property int shown: {
        if (!Config.motion) return lines.length;
        return Math.max(0, Math.min(lines.length, Math.floor((elapsed - lineStart) / lineStep) + 1));
    }
    readonly property string logText: lines.slice(0, shown).join("\n")

    function start() {
        if (boot.active && !boot.fading) return;   // already running
        timeline.stop();
        fadeEnd.stop();
        boot.lines = buildLines();
        boot.elapsed = 0;
        boot.fading = false;
        boot.active = true;
        timeline.duration = Config.motion ? 3200 : 800;
        timeline.start();
    }
    function end() {
        if (!boot.active || boot.fading) return;
        timeline.stop();
        boot.fading = true;
        fadeEnd.interval = Math.max(1, Config.dur(600));
        fadeEnd.restart();
    }

    NumberAnimation {
        id: timeline
        target: boot; property: "elapsed"; from: 0; to: duration
        onFinished: boot.end()
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

            Rectangle {
                id: stage
                anchors.fill: parent
                color: "#000000"
                opacity: boot.fading ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Config.dur(600) } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: boot.end()
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 18

                    Emblem {
                        id: emb
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: 84
                        strokeWidth: 1.2
                        color: "#e9edf2"
                        draw: Config.motion ? Math.min(1, boot.elapsed / 1400) : -1
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "[ ULTIMIT ]"
                        color: "#e9edf2"
                        font.family: Theme.display
                        font.pixelSize: 30
                        font.letterSpacing: 6   // .2em
                        opacity: Config.motion ? Math.max(0, Math.min(1, (boot.elapsed - 1100) / 600)) : 1
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(420, win.width - 32)
                        height: Math.max(implicitHeight, 9 * 11 * 1.7)
                        text: boot.logText
                        color: "#8d949e"
                        font.family: Theme.mono
                        font.pixelSize: 11
                        lineHeight: 1.7
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }
}
