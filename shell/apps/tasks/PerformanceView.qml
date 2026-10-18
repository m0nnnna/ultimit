// PerformanceView.qml - the PERFORMANCE tab: a header line (uptime, load, counts) and cards with the last minute of
// CPU (with a bar per core), memory and swap, GPU, disk and network.
import QtQuick
import QtQuick.Controls
import "../.."
import "../games"

Flickable {
    id: root
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    readonly property var s: Tasks.snap
    readonly property var h: Tasks.hist
    readonly property var m: s.mem || ({ total: 0, used: 0, swap_total: 0, swap_used: 0, cached: 0 })
    readonly property var g: Tasks.gpu
    readonly property int cardW: Math.floor((col.width - 12) / 2)
    function last(a) { return a.length > 0 ? a[a.length - 1] : 0; }
    function tone(v) { return v >= 90 ? Theme.bad : v >= 70 ? Theme.warn : Theme.fg; }

    Column {
        id: col
        width: root.width - 10
        spacing: 12

        // ---- header line ----
        Text {
            width: parent.width
            elide: Text.ElideRight
            visible: !!root.s.counts
            text: root.s.counts ? "Up " + Tasks.duration(root.s.uptime) + "  ·  Load " + root.s.load.map(v => v.toFixed(2)).join("  ")
                + "  ·  " + root.s.counts.procs + " processes  ·  " + root.s.counts.threads + " threads  ·  " + root.s.running + " running" : ""
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
        }

        // ---- CPU ----
        StatCard {
            width: parent.width
            height: 210
            title: "CPU"
            value: Tasks.pct(root.last(root.h.cpu))
            tone: root.tone(root.last(root.h.cpu))
            detail: (root.s.ncpu || 0) + " threads  ·  last 60 seconds"
            Graph { id: cpuG; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: cores.left; rightMargin: 14 } values: root.h.cpu }
            Row {
                id: cores
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: Math.min(360, parent.width * 0.4)
                spacing: 3
                Repeater {
                    model: root.s.cpu ? root.s.cpu.cores : []
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: (cores.width - 3 * ((root.s.ncpu || 1) - 1)) / (root.s.ncpu || 1)
                        height: cores.height
                        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28); border.color: Theme.line }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
                            height: Math.max(1, (parent.height - 2) * parent.modelData / 100)
                            color: parent.modelData >= 90 ? Theme.bad : parent.modelData >= 70 ? Theme.warn : Theme.accent
                            opacity: 0.85
                        }
                    }
                }
            }
        }

        Grid {
            width: parent.width
            columns: 2
            spacing: 12

            // ---- memory ----
            StatCard {
                width: root.cardW; height: 190
                title: "Memory"
                value: Tasks.pct(root.last(root.h.mem))
                tone: root.tone(root.last(root.h.mem))
                detail: Tasks.fmt(root.m.used) + " of " + Tasks.fmt(root.m.total) + "  ·  cached " + Tasks.fmt(root.m.cached)
                Graph { anchors.fill: parent; values: root.h.mem; values2: root.m.swap_total > 0 ? root.h.swap : []; color2: Theme.warn }
            }
            StatCard {
                width: root.cardW; height: 190
                title: "Swap"
                value: root.m.swap_total > 0 ? Tasks.pct(root.last(root.h.swap)) : "none"
                tone: root.tone(root.last(root.h.swap))
                detail: root.m.swap_total > 0 ? Tasks.fmt(root.m.swap_used) + " of " + Tasks.fmt(root.m.swap_total) : "No swap is set up"
                Graph { anchors.fill: parent; values: root.h.swap; color: Theme.warn }
            }

            // ---- GPU ----
            StatCard {
                width: root.cardW; height: 190
                visible: !!root.g
                title: root.g ? "GPU" : ""
                value: root.g && root.g.util !== null ? Tasks.pct(root.g.util) : ""
                tone: root.tone(root.last(root.h.gpu))
                detail: root.g ? root.g.name : ""
                Graph { anchors.fill: parent; values: root.h.gpu }
            }
            StatCard {
                width: root.cardW; height: 190
                visible: !!root.g
                title: "GPU memory"
                value: root.g && root.g.mem_total ? Tasks.pct(root.last(root.h.vram)) : ""
                tone: root.tone(root.last(root.h.vram))
                detail: !root.g ? "" : (root.g.mem_total ? Tasks.fmt(root.g.mem_used) + " of " + Tasks.fmt(root.g.mem_total) : "")
                    + (root.g.temp !== null ? "  ·  " + Math.round(root.g.temp) + " °C" : "")
                    + (root.g.power !== null ? "  ·  " + root.g.power.toFixed(0) + " W" : "")
                Graph { anchors.fill: parent; values: root.h.vram; color: Theme.ok }
            }

            // ---- disk and network ----
            StatCard {
                width: root.cardW; height: 190
                title: "Disk"
                value: root.s.disk ? "↓ " + Tasks.rate(root.s.disk.read) : ""
                detail: root.s.disk ? "Read " + Tasks.rate(root.s.disk.read) + "  ·  Write " + Tasks.rate(root.s.disk.write) : ""
                Graph { id: dg; anchors.fill: parent; max: 0; floor: 1048576; values: root.h.read; values2: root.h.write }
            }
            StatCard {
                width: root.cardW; height: 190
                title: "Network"
                value: root.s.net ? "↓ " + Tasks.rate(root.s.net.rx) : ""
                detail: root.s.net ? "Down " + Tasks.rate(root.s.net.rx) + "  ·  Up " + Tasks.rate(root.s.net.tx) : ""
                Graph { anchors.fill: parent; max: 0; floor: 131072; values: root.h.rx; values2: root.h.tx }
            }
        }
    }
}
