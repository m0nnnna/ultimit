pragma Singleton

// Disks.qml - state of DISKS, the Ultimit disks manager and disk-usage checker: drives with their partitions, SMART
// health, mount/unmount/eject/format, and the "what takes space" scanner, all through the helper disks.py (JSON on
// stdout). UDisks2 asks for authorization through polkit (the Ultimit agent shows the dialog); a dismissed prompt
// is a calm note, never an error.
//
// With DISKS_FAKE=1 in the environment the helper shows pretend drives whose actions all succeed (see fixtures/),
// so the UI can be tried without risk.
import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("apps/disks/disks.py")
    readonly property string dataBin: Quickshell.shellPath("bin/ultimit-data")
    readonly property bool fake: Quickshell.env("DISKS_FAKE") === "1"
    readonly property string home: st.home || Quickshell.env("HOME")

    // A fixed warning red for destructive things: Theme.bad turns orange on red-ish accents.
    readonly property color danger: Theme.light ? "#c62828" : "#ff4d4f"

    // ---- window state ----
    property bool open: false
    property string tab: "drives"           // drives | usage
    property string overlay: ""             // "" | "format" | "trash"

    function show() { quitTimer.stop(); open = true; refresh(); }

    // ---- snapshot ----
    property bool loaded: false
    property var st: ({})                   // disks.py state
    property string busy: ""                // action running ("" = idle): mount | unmount | eject | power-off | format | trash
    property string note: ""
    property string noteKind: "info"        // info | error
    property bool refreshing: false

    readonly property var drives: st.drives || []
    readonly property var formats: st.formats || []
    property string selDrive: ""            // drive id
    property string selDev: ""              // device of the selected partition ("" = none)
    property real selFree: -1               // offset of the selected free gap (-1 = none)
    readonly property var freeSeg: {
        if (selFree < 0 || !drive) return null;
        for (const p of drive.partitions) if (p.kind === "free" && p.offset === selFree) return p;
        return null;
    }
    onTabChanged: note = ""
    readonly property var drive: {
        for (const d of drives) if (d.id === selDrive) return d;
        return drives.length > 0 ? drives[0] : null;
    }
    readonly property var volume: {
        if (!drive) return null;
        for (const p of drive.partitions) if (p.kind === "partition" && p.device === selDev) return p;
        return null;
    }
    // Every mounted volume, for the usage picker: [{path, label}]
    readonly property var mounted: {
        const r = [];
        for (const d of drives) for (const p of d.partitions)
            if (p.kind === "partition" && p.mounted && p.mounts[0] !== "/boot/efi")
                r.push({ path: p.mounts[0], label: p.label !== "" ? p.label : p.mounts[0] === "/" ? "System" : p.device.replace("/dev/", "") });
        return r;
    }

    function select(driveId, dev) { selDrive = driveId; selDev = dev || ""; selFree = -1; }
    function selectFree(offset) { selDev = ""; selFree = offset; }

    // ---- helper process: run(args, callback(parsedJson)) ----
    function run(args, cb) {
        procC.createObject(root, { command: ["python3", root.helper].concat(args), cb: cb });
    }
    Component {
        id: procC
        Process {
            id: p
            property var cb
            stdout: StdioCollector {
                onStreamFinished: {
                    let o;
                    try { o = JSON.parse(text); } catch (e) { o = { ok: false, error: "The DISKS helper failed." }; }
                    if (p.cb) p.cb(o);
                }
            }
            onExited: Qt.callLater(() => p.destroy())
            Component.onCompleted: running = true
        }
    }

    function say(text, kind) { note = text; noteKind = kind || "info"; }

    // ---- refresh ----
    function refresh() {
        if (refreshing) return;
        refreshing = true;
        run(["state"], o => {
            refreshing = false;
            if (o.ok === false) { if (o.error) say(o.error, "error"); loaded = true; return; }
            if (JSON.stringify(o) !== JSON.stringify(st)) st = o;
            loaded = true;
            if (!drive) selDrive = "";
            else if (selDrive === "") selDrive = drive.id;
            if (drive && !volume) selDev = "";
            if (selFree >= 0 && !freeSeg) selFree = -1;
        });
    }
    Timer { interval: 5000; repeat: true; running: root.open && root.busy === "" && !root.scanning; onTriggered: root.refresh() }

    // DISKS is its own process: exit shortly after the window closes (a new open request cancels it).
    Timer { id: quitTimer; interval: 800; onTriggered: if (!root.open) Qt.quit() }
    onOpenChanged: if (!open) { quitTimer.restart(); cancelScan(); }

    // ---- actions ----
    function act(tag, args, waiting, done, cb) {
        if (busy !== "") return;
        busy = tag;
        say(waiting || "Working…");
        run(args, o => {
            busy = "";
            if (o.cancelled) say("Cancelled. Nothing was changed.");
            else if (!o.ok) say(o.error || "That did not work.", "error");
            else say(typeof done === "function" ? done(o) : done);
            if (cb) cb(o);
            refresh();
        });
    }
    function volName(v) { return v ? (v.label !== "" ? v.label : v.device.replace("/dev/", "")) : ""; }
    function mount(v) { act("mount", ["mount", v.target], "Mounting…", o => volName(v) + " is mounted at " + o.mountpoint + "."); }
    function unmount(v) { act("unmount", ["unmount", v.target], "Unmounting…", volName(v) + " is unmounted. It is safe to unplug once it is ejected."); }
    function eject(d) { act("eject", ["eject", d.id], "Ejecting…", d.name + " was ejected. You can unplug it."); }
    function powerOff(d) { act("power-off", ["power-off", d.id], "Powering off…", d.name + " is powered off. You can unplug it."); }
    function format(v, fs, label, cb) {
        act("format", ["format", v.device, fs, label], "Formatting… this can take a while.", volName(v) + " was formatted as " + fs + ".", cb);
    }
    // Partition management. Each runs through act(): one thing at a time, a calm note, state re-read afterwards.
    function createPartition(d, gap, bytes, fs, label, cb) {
        act("create", ["create-partition", d.id, String(gap.offset), String(Math.round(bytes)), fs, label], "Creating the partition…",
            o => "Created a " + fmt(o.size) + " partition.", cb);
    }
    function deletePartition(v, cb) {
        act("delete", ["delete-partition", v.device], "Deleting the partition…", volName(v) + " was deleted. Its space is free now.", cb);
    }
    function resizePartition(v, bytes, cb) {
        act("resize", ["resize-partition", v.device, String(Math.round(bytes))], "Resizing… this can take a while.",
            o => volName(v) + " is now " + fmt(o.size) + ".", cb);
    }
    function newTable(d, kind, cb) {
        act("table", ["new-table", d.id, kind], "Writing the new partition table…",
            d.name + " has a new, empty " + kind.toUpperCase() + " partition table.", cb);
    }
    function setLabel(v, label, cb) {
        act("label", ["set-label", v.device, label], "Saving the name…", label === "" ? "The name was removed." : "Renamed to " + label + ".", cb);
    }
    function peek(path, cb) { run(["peek", path], cb); }

    // ---- health ----
    property var healthBy: ({})             // drive id -> summary
    property string healthShown: ""         // drive id whose panel is open
    property string healthBusy: ""
    function toggleHealth(d) {
        if (healthShown === d.id && healthBy[d.id] && healthBusy === "") { healthShown = ""; return; }
        healthShown = d.id;
        checkHealth(d);
    }
    function checkHealth(d) {
        if (healthBusy !== "") return;
        healthBusy = d.id;
        run(["health", d.id], o => {
            healthBusy = "";
            if (o.cancelled) { say("Cancelled."); healthShown = ""; return; }
            if (!o.ok) o = { ok: false, verdict: "unknown", title: "Could not read health", lines: [{ text: o.error || "No answer from the drive.", tone: "bad" }], attributes: [] };
            const h = Object.assign({}, healthBy);
            h[d.id] = o;
            healthBy = h;
        });
    }

    // ---- other apps ----
    function openInData(path) { Quickshell.execDetached([root.dataBin, path]); }
    function revealInData(path) { Quickshell.execDetached([root.dataBin, "--reveal", path]); }

    // ---- usage ----
    property string usageRoot: ""           // scanned (or picked) location
    property string usagePath: ""           // folder being looked at (under usageRoot)
    property var listing: null              // disks.py children result
    property var largestFiles: null         // disks.py largest result
    property string usageView: "folders"    // folders | largest
    property bool scanning: false
    property var progress: ({ files: 0, bytes: 0, path: "" })
    property var lastScan: null             // final line of the last scan
    property bool noCache: false            // usageRoot has never been scanned

    function breadcrumbs() {
        const r = [];
        if (usageRoot === "") return r;
        r.push({ label: usageRoot === "/" ? "/" : usageRoot, path: usageRoot });
        if (usagePath !== usageRoot) {
            let cur = usageRoot;
            for (const part of usagePath.substring(usageRoot === "/" ? 1 : usageRoot.length + 1).split("/")) {
                cur = (cur === "/" ? "" : cur) + "/" + part;
                r.push({ label: part, path: cur });
            }
        }
        return r;
    }

    // Pick a place: show its last scan when there is one, else wait for the person to press Scan.
    function choose(path) {
        if (scanning) return;
        path = path.replace(/\/+$/, "") || "/";
        usageRoot = path; usagePath = path;
        listing = null; largestFiles = null; lastScan = null; noCache = false;
        browse(path);
    }
    function browse(path) {
        run(["children", path], o => {
            if (o.ok) { listing = o; usagePath = path; noCache = false; if (usageView === "largest") loadLargest(); }
            else if (o.notscanned) { listing = null; noCache = true; usagePath = path; }
            else say(o.error || "Could not read the scan.", "error");
        });
    }
    function loadLargest() {
        run(["largest", usagePath, "100"], o => { if (o.ok) largestFiles = o; });
    }
    function setUsageView(v) { usageView = v; if (v === "largest") loadLargest(); }

    function scan(path) {
        if (scanning) return;
        path = path.replace(/\/+$/, "") || "/";
        usageRoot = path; usagePath = path; noCache = false;
        listing = null; largestFiles = null; lastScan = null;
        progress = { files: 0, bytes: 0, path: path };
        scanning = true;
        say("Scanning " + path + "…");
        scanProc.command = ["python3", root.helper, "scan", path];
        scanProc.running = true;
    }
    function rescan() { if (usageRoot !== "") scan(usageRoot); }
    function cancelScan() {
        if (scanning) { cancelled = true; scanProc.running = false; }
    }
    property bool cancelled: false
    // The "Check usage" button of a volume and the command line's --usage.
    function checkUsage(path) { show(); tab = "usage"; scan(path); }

    Process {
        id: scanProc
        stdout: SplitParser {
            onRead: line => {
                let o;
                try { o = JSON.parse(line); } catch (e) { return; }
                if (o.progress !== undefined) root.progress = { files: o.progress, bytes: o.bytes, path: o.path };
                else if (o.done) root.lastScan = o;
                else if (o.ok === false) root.say(o.error || "The scan failed.", "error");
            }
        }
        onExited: {
            root.scanning = false;
            if (root.cancelled) { root.cancelled = false; root.say("Scan cancelled."); root.browse(root.usageRoot); return; }
            if (root.lastScan) {
                root.say("Scanned " + root.fmt(root.lastScan.size) + " in " + root.lastScan.seconds + " s.");
                root.browse(root.usageRoot);
            }
        }
    }

    // ---- trash ----
    property var trashTarget: null          // {name, path, size, kind}
    function askTrash(entry) {
        trashTarget = { name: entry.name, path: entry.path, size: entry.size, kind: entry.kind };
        overlay = "trash";
    }
    function doTrash() {
        const t = trashTarget;
        if (!t || busy !== "") return;
        busy = "trash";
        say("Moving " + t.name + " to the trash…");
        run(["trash", t.path], o => {
            busy = "";
            if (!o.ok) say(o.error || "Could not move it to the trash.", "error");
            else say(t.name + " is in the trash. " + fmt(o.freed || t.size) + " freed.");
            browse(usagePath);
            if (usageView === "largest") loadLargest();
        });
    }

    // ---- formatting ----
    function fmt(b) {
        if (b === null || b === undefined) return "";
        const u = ["B", "kB", "MB", "GB", "TB", "PB"];
        let i = 0, v = b;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return (i === 0 || v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }
    function fmtIec(b) {
        const u = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let i = 0, v = b;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (i === 0 || v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }
    function count(n) { return Number(n).toLocaleString(Qt.locale(), "f", 0); }
    function kindText(d) {
        return { nvme: "NVMe", ssd: "SSD", hdd: "HDD", usb: "USB", sd: "SD", optical: "DISC", image: "IMAGE", disk: "DISK" }[d.kind] || "DISK";
    }
    function busText(d) {
        return { nvme: "NVMe", sata: "SATA", usb: "USB", mmc: "SD / MMC", scsi: "SCSI", virtio: "Virtual", loop: "Disk image" }[d.bus] || "Unknown";
    }
    function ago(ts) {
        const s = Math.max(0, Math.round(Date.now() / 1000 - ts));
        if (s < 60) return "just now";
        if (s < 3600) return Math.round(s / 60) + " min ago";
        if (s < 86400) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " days ago";
    }

    function dump() {
        return JSON.stringify({ loaded: loaded, open: open, tab: tab, overlay: overlay, busy: busy, note: note, fake: fake,
            drives: drives.map(d => d.id + ":" + d.kind + ":" + d.partitions.length), selDrive: drive ? drive.id : "", selDev: selDev, selFree: selFree,
            health: healthShown, usageRoot: usageRoot, usagePath: usagePath, scanning: scanning, usageView: usageView,
            listing: listing ? listing.entries.length : -1, noCache: noCache });
    }
}
