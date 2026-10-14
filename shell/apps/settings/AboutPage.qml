// About: Ultimit version, OS, kernel, CPU, GPUs, memory, disk. One read-only shell probe.
// "Save a report" runs ultimit-report (logs, monitors, driver... in one file to send when
// something goes wrong) and shows the file.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"
import "../../components"

Page {
    id: pg
    title: "About"
    property var info: ({})
    property var gpus: []
    property string report: ""      // path of the last report saved
    property bool reporting: false

    Cmd {
        id: probe
        argv: ["sh", "-c", [
            // installed: /opt/ultimit/VERSION (a release tag or a commit); a checkout: git describe
            'echo "ver=$(cat "$1/../VERSION" 2>/dev/null || git -C "$1" describe --tags --always --dirty 2>/dev/null)"',
            '. /etc/os-release 2>/dev/null; echo "os=$PRETTY_NAME"',
            'echo "host=$(hostname)"',
            'echo "kernel=$(uname -r)"',
            'echo "cpu=$(lscpu 2>/dev/null | sed -n "s/^Model name: *//p" | head -n1) ($(nproc) threads)"',
            'lspci 2>/dev/null | grep -Ei "vga|3d controller|display controller" | sed "s/^[^ ]* [^:]*: /gpu=/"',
            'awk \'/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "mem=%.1f GB total, %.1f GB available\\n", t/1048576, a/1048576}\' /proc/meminfo',
            'echo "disk=$(df -h / | awk \'NR==2{print $3" used of "$2" ("$5")"}\')"'
        ].join("; "), "sh", SetSys.repoDir]
        onDone: out => {
            const o = {}; const g = [];
            for (const line of out.split("\n")) {
                const i = line.indexOf("=");
                if (i < 0) continue;
                const k = line.slice(0, i), v = line.slice(i + 1).trim();
                if (k === "gpu") g.push(v); else o[k] = v;
            }
            pg.info = o; pg.gpus = g;
        }
    }
    Component.onCompleted: probe.go()

    InfoRow { Layout.fillWidth: true; label: "Ultimit"; value: /^v?\d+\./.test(info.ver || "") ? info.ver.replace(/^v/, "")
                                                                       : Config.version + (info.ver ? " (" + info.ver + ")" : "") }
    InfoRow { Layout.fillWidth: true; label: "Operating system"; value: info.os || "…" }
    InfoRow { Layout.fillWidth: true; label: "Device name"; value: info.host || "…" }
    InfoRow { Layout.fillWidth: true; label: "Kernel"; value: info.kernel || "…" }
    InfoRow { Layout.fillWidth: true; label: "Processor"; value: info.cpu || "…" }
    Repeater {
        model: pg.gpus
        delegate: InfoRow {
            required property string modelData
            required property int index
            Layout.fillWidth: true
            label: pg.gpus.length > 1 ? "Graphics " + (index + 1) : "Graphics"
            value: modelData
        }
    }
    InfoRow { Layout.fillWidth: true; label: "Memory"; value: info.mem || "…" }
    InfoRow { Layout.fillWidth: true; label: "Disk (/)"; value: info.disk || "…" }

    // ---- problem report ----
    SectionLabel { text: "Something wrong?" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: pg.report !== "" ? "Saved: " + pg.report
                : "Saves the logs, monitor setup, graphics driver and recent crashes in one file you can send to whoever helps you. No passwords or personal files go in it."
            color: pg.report !== "" ? Theme.ok : Theme.dim; font.family: Theme.ui; font.pixelSize: 12
        }
        ChamferButton {
            text: pg.reporting ? "Saving…" : pg.report !== "" ? "Show file" : "Save a report"
            enabled: !pg.reporting
            onClicked: {
                if (pg.report !== "") Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-data"), pg.report.replace(/\/[^\/]*$/, "")]);
                else { pg.reporting = true; reportProc.running = true; }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Or ask Claude: CLAUDE gets a summary of this PC, can read the logs, and asks before it changes anything."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
        }
        ChamferButton {
            text: "Troubleshoot with Claude"
            onClicked: Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-claude"), "--troubleshoot"])
        }
    }
    Process {
        id: reportProc
        command: [Quickshell.shellPath("bin/ultimit-report")]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                pg.report = lines[lines.length - 1].endsWith(".tar.gz") ? lines[lines.length - 1] : "";
                pg.reporting = false;
                if (pg.report === "") Toasts.show("Report", "The report could not be saved.");
            }
        }
    }
}
