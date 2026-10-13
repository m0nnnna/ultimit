// Installer.qml - what the installer screen knows and does: the pages in order, the drives and
// the network (probe.py), the answers (answers.py -> /autoinstall.yaml), then the install's
// progress until "Restart". InstallerSurface.qml draws it.
// Env (installer/start.sh): ULTIMIT_INSTALLER_BASE (base.json), ULTIMIT_INSTALLER_RUN (/run/...).
// ULTIMIT_INSTALLER_DRY=1: try it anywhere; fake drives/network (PROBE_FAKE_DIR) and a pretend
// install, nothing is written but the answers into the run folder.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property bool dry: Quickshell.env("ULTIMIT_INSTALLER_DRY") === "1"
    readonly property string runDir: Quickshell.env("ULTIMIT_INSTALLER_RUN") || "/tmp/ultimit-installer-dry"
    readonly property string base: Quickshell.env("ULTIMIT_INSTALLER_BASE") || Quickshell.shellPath("installer/base-example.json")
    readonly property string probe: Quickshell.shellPath("installer/probe.py")

    // ---- where we are
    property string page: "welcome"   // welcome | network | disk | account | confirm | installing | done | failed
    // (the network step only counts when it was needed)
    readonly property var steps: net.online && !wifi && page !== "network" ? ["welcome", "disk", "account", "confirm"]
                                                                          : ["welcome", "network", "disk", "account", "confirm"]
    readonly property int stepNo: Math.max(0, steps.indexOf(page)) + 1
    property string error: ""

    // ---- the network
    property var net: ({})            // probe.py net
    property bool netChecking: false
    property var networks: []         // probe.py wifi-scan
    property bool scanning: false
    property string ssid: ""
    property string wifiPassword: ""
    property bool connecting: false
    property var wifi: null           // what joined (goes to the new system too)

    // ---- the drive
    property var disks: []
    property bool disksLoaded: false
    property int diskIndex: -1
    readonly property var disk: diskIndex >= 0 && diskIndex < disks.length ? disks[diskIndex] : null
    property string mode: ""          // erase | alongside
    property bool understood: false   // "I understand everything on it is erased"

    // ---- who
    property string realname: ""
    property string username: ""
    property string hostname: ""
    property bool userEdited: false
    property bool hostEdited: false
    property string password: ""
    property string password2: ""

    // ---- the install
    property var status: ({})         // probe.py status
    property string stepText: ""

    function gb(bytes) {
        const g = bytes / 1e9;
        return g >= 1000 ? (g / 1000).toFixed(g >= 10000 ? 0 : 1) + " TB" : Math.round(g) + " GB";
    }
    function suggestUser(name) {
        const first = (name.trim().split(/\s+/)[0] || "").toLowerCase().normalize("NFD").replace(/[^a-z0-9-]/g, "");
        return /^[a-z]/.test(first) ? first.slice(0, 32) : (first ? "user" + first : "");
    }
    onRealnameChanged: {
        if (!userEdited) username = suggestUser(realname);
        if (!hostEdited) hostname = username ? username + "-pc" : "";
    }

    readonly property string accountProblem: {
        if (realname.trim() === "") return "Type your name.";
        if (!/^[a-z][a-z0-9-]{0,31}$/.test(username)) return "The user name can use small letters, digits and -, starting with a letter.";
        if (!/^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(hostname)) return "The computer name can use letters, digits and - (no spaces).";
        if (password.length < 4) return "Choose a password (4 characters or more).";
        if (password !== password2) return "The two passwords are different.";
        return "";
    }

    // ---- moving between pages
    function next() {
        error = "";
        if (page === "welcome") { checkNet(true); return; }
        if (page === "network") { page = "disk"; loadDisks(); return; }
        if (page === "disk") { if (disk && mode) page = "account"; return; }
        if (page === "account") { if (accountProblem === "") { understood = false; page = "confirm"; } return; }
        if (page === "confirm") { install(); return; }
    }
    function back() {
        error = "";
        const order = ["welcome", net.online && !wifi ? "" : "network", "disk", "account", "confirm"].filter(p => p);
        const i = order.indexOf(page);
        if (i > 0) page = order[i - 1];
    }
    function pickDisk(i) {
        diskIndex = i;
        const d = disks[i];
        mode = d.canAlongside ? "alongside" : d.empty ? "erase" : "";   // never pre-pick erasing data
        understood = false;
    }
    function textInstaller() {
        Quickshell.execDetached(["touch", runDir + "/text"]);
        Qt.quit();
    }

    // ---- probes
    function checkNet(advance) {
        netChecking = true;
        netProc.advance = advance;
        netProc.running = true;
    }
    Process {
        id: netProc
        property bool advance: false
        command: ["python3", root.probe, "net"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.net = JSON.parse(text); } catch (e) { root.net = { online: false, wifi: [] }; }
                root.netChecking = false;
                if (!netProc.advance) return;
                if (root.net.online) { root.page = "disk"; root.loadDisks(); }
                else { root.page = "network"; root.scan(); }
            }
        }
    }
    Timer {   // on the network page: notice a cable being plugged in
        interval: 5000; repeat: true
        running: root.page === "network" && !root.net.online && !root.connecting
        onTriggered: if (!netProc.running) root.checkNet(false)
    }
    function scan() {
        if (!net.wifi || net.wifi.length === 0 || scanProc.running) return;
        scanning = true;
        scanProc.running = true;
    }
    Process {
        id: scanProc
        command: ["python3", root.probe, "wifi-scan", (root.net.wifi || [""])[0]]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.networks = JSON.parse(text).networks || []; } catch (e) { root.networks = []; }
                root.scanning = false;
            }
        }
    }
    function connect() {
        if (!ssid || connecting) return;
        error = "";
        connecting = true;
        joinProc.command = ["python3", probe, "wifi-connect", net.wifi[0], ssid].concat(wifiPassword ? [wifiPassword] : []);
        joinProc.running = true;
    }
    Process {
        id: joinProc
        stdout: StdioCollector {
            onStreamFinished: {
                let o = {};
                try { o = JSON.parse(text); } catch (e) {}
                root.connecting = false;
                if (o.ok) { root.wifi = { ssid: root.ssid, password: root.wifiPassword }; root.checkNet(false); }
                else root.error = o.error || "Couldn't connect.";
            }
        }
    }
    function loadDisks() {
        disksLoaded = false;
        diskProc.running = true;
    }
    Process {
        id: diskProc
        command: ["python3", root.probe, "disks"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = {};
                try { o = JSON.parse(text); } catch (e) {}
                root.disks = o.disks || [];
                root.disksLoaded = true;
                if (o.error) root.error = o.error;
                // One drive to choose from: choose it
                const usable = root.disks.filter(d => !d.boot);
                if (root.diskIndex < 0 && usable.length === 1) root.pickDisk(root.disks.indexOf(usable[0]));
            }
        }
    }

    // ---- the install
    function install() {
        if (mode === "erase" && disk && !disk.empty && !understood) { error = "Tick the box first: everything on this drive will be erased."; return; }
        error = "";
        answersProc.input = JSON.stringify({
            disk: disk.path, mode: mode, realname: realname.trim(), username: username, hostname: hostname,
            password: password, wifi: wifi, keyboard: "us", timezone: net.timezone || ""
        });
        answersProc.command = ["python3", Quickshell.shellPath("installer/answers.py"), base].concat(dry ? [runDir + "/autoinstall.yaml"] : []);
        answersProc.running = true;
    }
    Process {
        id: answersProc
        property string input: ""
        stdinEnabled: true
        environment: ({ INSTALLER_RUN: root.runDir })
        onStarted: { write(input); input = ""; stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                let o = {};
                try { o = JSON.parse(text); } catch (e) {}
                answersProc.stdinEnabled = true;
                if (!o.ok) { root.error = o.error || "Couldn't save the answers."; return; }

                Quickshell.execDetached(["touch", root.runDir + "/answered"]);
                root.page = "installing";
                root.stepText = "Starting";
            }
        }
    }
    Timer {
        interval: root.dry ? 1500 : 3000; repeat: true
        running: root.page === "installing"
        onTriggered: {
            if (root.dry) { root.fakeProgress(); return; }
            if (!statusProc.running) statusProc.running = true;
        }
    }
    Process {
        id: statusProc
        command: ["python3", root.probe, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = {};
                try { o = JSON.parse(text); } catch (e) { return; }
                root.status = o;
                if (o.step) root.stepText = o.step;
                if (o.installed) root.page = "done";
                else if (o.state === "ERROR" || o.error) { root.error = o.error || "The install stopped with an error."; root.page = "failed"; }
            }
        }
    }
    property int _fake: 0
    function fakeProgress() {
        const s = ["Preparing the drive", "Copying Ubuntu onto the drive", "Setting up the system", "Adding graphics drivers", "Installing Ultimit"];
        if (_fake < s.length) stepText = s[_fake++]; else page = "done";
    }
    function restart() {
        Quickshell.execDetached(["touch", runDir + "/restart"]);
        if (dry) Qt.quit();
    }
    function details() { Quickshell.execDetached(["chvt", "1"]); }

    Component.onCompleted: {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && touch "$1/ui-up"', "sh", runDir]);
        checkNet(false);   // so the step count knows whether the network step is needed
    }
}
