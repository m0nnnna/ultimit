pragma Singleton

// SysStats.qml - live CPU / GPU / RAM / network figures for the status block's graphs.
// `tasks.py glance` (apps/tasks, the TASKS sampler without the process table) prints one JSON line a
// second; it runs only while something that draws the figures is visible (users > 0) and the
// desktop is not paused by a fullscreen window / lock, so a game never pays for it.
// Histories hold the last `keep` samples, oldest first. Rates are bytes per second.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int users: 0
    readonly property bool running: root.users > 0 && !Config.desktopPaused
    readonly property int keep: 40

    property real cpu: 0
    property real mem: 0
    property real gpu: -1          // -1: no GPU figure
    property real vram: -1
    property real rx: 0
    property real tx: 0
    property var cpuHist: []
    property var gpuHist: []
    property var memHist: []
    property var netHist: []       // rx + tx

    function push(arr, v) {
        const a = arr.length >= root.keep ? arr.slice(arr.length - root.keep + 1) : arr.slice();
        a.push(v);
        return a;
    }
    function take(line) {
        let o;
        try { o = JSON.parse(line); } catch (e) { return; }
        if (!o.ok) return;
        cpu = o.cpu; mem = o.mem;
        gpu = o.gpu === null || o.gpu === undefined ? -1 : o.gpu;
        vram = o.vram === null || o.vram === undefined ? -1 : o.vram;
        rx = o.rx; tx = o.tx;
        cpuHist = push(cpuHist, cpu);
        memHist = push(memHist, mem);
        gpuHist = push(gpuHist, Math.max(0, gpu));
        netHist = push(netHist, rx + tx);
    }

    // "1.2 MB/s" style rate, short enough for a small cell.
    function rate(b) {
        if (b >= 1048576) return (b / 1048576).toFixed(1) + "M";
        if (b >= 1024) return Math.round(b / 1024) + "K";
        return Math.round(b) + "B";
    }

    Process {
        running: root.running
        command: ["python3", Quickshell.shellPath("apps/tasks/tasks.py"), "glance", "1"]
        stdout: SplitParser { onRead: line => root.take(line) }
    }
}
