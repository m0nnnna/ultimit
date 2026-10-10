// About: Ultimit version, OS, kernel, CPU, GPUs, memory, disk. One read-only shell probe.
import QtQuick
import QtQuick.Layouts
import "../.."

Page {
    id: pg
    title: "About"
    property var info: ({})
    property var gpus: []

    Cmd {
        id: probe
        argv: ["sh", "-c", [
            'echo "ver=$(git -C "$1" describe --always --dirty 2>/dev/null)"',
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

    InfoRow { Layout.fillWidth: true; label: "Ultimit"; value: Config.version + (info.ver ? " (" + info.ver + ")" : "") }
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
}
