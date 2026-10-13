// Updates: Ultimit itself (releases on GitHub), system packages (apt), Flatpak apps and firmware
// (fwupd), restart-needed, the last automatic update. Reading needs nothing (updates.py); "Check now" and installing system updates go
// through the root helper /usr/libexec/ultimit/updates-helper via pkexec (polkit: checking is free for
// admins, installing asks). Flatpak and firmware updates use flatpak / fwupdmgr, which ask polkit
// themselves. An Ultimit update is downloaded and installed by the same root helper
// (`updates-helper ultimit TAG`) and takes effect at the next login. With ULTIMIT_DRY_RUN=1 nothing is installed.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"
import "../../components"

Page {
    id: pg
    title: "Updates"
    subtitle: "Security updates also install by themselves every day. Everything else waits for you here."

    readonly property string script: Quickshell.shellPath("apps/settings/updates.py")
    readonly property string helper: "/usr/libexec/ultimit/updates-helper"

    property var st: ({})            // updates.py status
    property var fp: ({})            // updates.py flatpak
    property var ul: ({})            // updates.py ultimit
    property bool ulLoading: false
    property bool loading: false
    property bool fpLoading: false
    property string busy: ""         // "", "refresh", "install", "ultimit", "flatpak", "firmware", "setup"
    property real pct: -1            // progress of the running job, -1 = unknown
    property string msg: ""          // what the running job is doing
    property string result: ""       // last outcome line
    property color resultColor: Theme.dim
    property bool showAll: false
    property var setupCmd: null

    readonly property var apt: st.apt || []
    readonly property int security: apt.filter(p => p.security).length
    readonly property var fwList: st.firmware || []
    readonly property var fpList: fp.flatpak || []
    readonly property int total: apt.length + fwList.length + fpList.length + (ul.newer ? 1 : 0)
    // Ultimit was updated since this session started: the new version runs after logging out and in
    readonly property bool relogin: !!ul.running && !!ul.installed && ul.running !== ul.installed

    function reload() {
        if (loading) return;
        loading = true;
        statusProc.running = true;
        if (!fpLoading) { fpLoading = true; fpProc.running = true; }
        if (!ulLoading) { ulLoading = true; ulProc.running = true; }
    }
    Component.onCompleted: { reload(); setupProc.running = true; }

    function ago(t) {
        if (!t || !st.now) return "never";
        const s = st.now - t;
        if (s < 90) return "just now";
        if (s < 5400) return Math.round(s / 60) + " min ago";
        if (s < 129600) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " days ago";
    }

    // ---- reading ----
    Process {
        id: statusProc
        command: ["python3", pg.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { pg.st = JSON.parse(text); } catch (e) { pg.st = { aptError: "Could not read the update status." }; }
                pg.loading = false;
            }
        }
    }
    Process {
        id: fpProc
        command: ["python3", pg.script, "flatpak"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { pg.fp = JSON.parse(text); } catch (e) { pg.fp = { flatpakError: "Could not ask Flathub." }; }
                pg.fpLoading = false;
            }
        }
    }
    Process {
        id: ulProc
        command: ["python3", pg.script, "ultimit"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { pg.ul = JSON.parse(text); } catch (e) { pg.ul = { error: "Could not check for Ultimit updates." }; }
                pg.ulLoading = false;
            }
        }
    }
    Process {
        id: setupProc
        command: ["python3", pg.script, "setup"]
        stdout: StdioCollector { onStreamFinished: { try { pg.setupCmd = JSON.parse(text); } catch (e) {} } }
    }

    // ---- jobs: one at a time; stdout is JSON lines (helper) or plain text (flatpak, fwupdmgr) ----
    function start(kind, argv, okText) {
        if (busy !== "") return;
        result = "";
        if (SetSys.dryRun) { console.log("[dry-run] " + argv.join(" ")); result = "Dry run: nothing installed."; return; }
        busy = kind; pct = -1; msg = ""; job.okText = okText; job.err = "";
        job.command = argv;
        job.running = true;
    }
    Process {
        id: job
        property string okText: ""
        property string err: ""
        stdout: SplitParser {
            onRead: line => {
                let o = null;
                try { o = JSON.parse(line); } catch (e) {}
                if (o && o.stage !== undefined) { pg.pct = o.pct; pg.msg = o.msg; return; }
                if (o && o.ok !== undefined) { if (!o.ok) job.err = o.error || "failed"; return; }
                const t = line.trim();
                if (t !== "") { pg.msg = t; const m = t.match(/(\d+)%/); if (m) pg.pct = parseInt(m[1]); }
            }
        }
        stderr: SplitParser { onRead: line => { if (line.trim() !== "") job.err = line.trim(); } }
        onExited: code => {
            // pkexec: 126 = the password prompt was dismissed, 127 = not authorized
            const viaPkexec = job.command[0] === "pkexec";
            if (code === 0 && job.err === "" || code === 0 && !viaPkexec) {
                pg.result = job.okText; pg.resultColor = Theme.ok;
            } else if (viaPkexec && (code === 126 || code === 127)) {
                pg.result = "Cancelled."; pg.resultColor = Theme.dim;
            } else if (pg.busy === "firmware" && code === 2) {
                pg.result = "No firmware to update."; pg.resultColor = Theme.dim;   // fwupdmgr: nothing to do
            } else {
                pg.result = job.err || ("Failed (exit " + code + ")."); pg.resultColor = Theme.bad;
            }
            pg.busy = ""; pg.pct = -1; pg.msg = "";
            pg.reload();
        }
    }

    function checkNow() { start("refresh", ["pkexec", helper, "refresh"], "Checked for updates."); }
    function installSystem() { start("install", ["pkexec", helper, "upgrade"], "System updates installed."); }
    function installUltimit() {
        if (ul.latest)
            start("ultimit", ["pkexec", helper, "ultimit", ul.latest.tag],
                  "Ultimit " + ul.latest.version + " installed. Log out and back in to start it.");
    }
    function updateFlatpaks() { start("flatpak", ["flatpak", "update", "-y", "--noninteractive"], "Apps updated."); }
    function updateFirmware() { start("firmware", ["fwupdmgr", "update", "-y", "--no-reboot-check"], "Firmware updated. Restart to finish."); }
    function setupHelper() { if (setupCmd) start("setup", ["pkexec"].concat(setupCmd.argv), "Updates are set up."); }

    // ================= summary =================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: sum.implicitHeight + 28
        color: Theme.panel2
        border.color: st.reboot ? Theme.warn : Theme.line
        ColumnLayout {
            id: sum
            x: 16; y: 14; width: parent.width - 32
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    width: 8; height: 8
                    color: st.reboot ? Theme.warn : pg.security > 0 ? Theme.warn : pg.total > 0 ? Theme.accent : Theme.ok
                }
                Text {
                    Layout.fillWidth: true
                    text: pg.loading && st.apt === undefined ? "Checking…"
                        : st.reboot ? "Restart to finish updating"
                        : pg.relogin && pg.total === 0 ? "Log out to finish updating Ultimit"
                        : pg.total === 0 ? "Up to date"
                        : pg.total + (pg.total === 1 ? " update" : " updates") + (pg.security > 0 ? " · " + pg.security + " security" : "")
                    color: Theme.fg
                    font.family: Theme.display; font.pixelSize: 14; font.letterSpacing: 1
                }
                ChamferButton {
                    visible: st.helper === true
                    text: pg.busy === "refresh" ? "Checking…" : "Check now"
                    enabled: pg.busy === ""
                    onClicked: pg.checkNow()
                }
                PowerButton {
                    visible: st.reboot === true
                    text: "Restart"; confirm: true
                    onActivated: Quickshell.execDetached(["systemctl", "reboot"])
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 0.6
                text: "Last checked " + pg.ago(st.checkedAt)
                    + (st.auto ? "  ·  automatic updates ran " + st.auto.time.slice(0, 16) + (st.auto.text ? ": " + st.auto.text : "") : "")
                    + (st.reboot && st.rebootPkgs && st.rebootPkgs.length ? "  ·  restart needed for " + st.rebootPkgs.join(", ") : "")
            }
            // progress of the running job
            ColumnLayout {
                visible: pg.busy !== ""
                Layout.fillWidth: true
                spacing: 4
                Rectangle {
                    Layout.fillWidth: true; height: 2; color: Theme.line
                    Rectangle {
                        height: parent.height; color: Theme.accent
                        width: pg.pct >= 0 ? parent.width * pg.pct / 100 : parent.width * 0.3
                        x: pg.pct >= 0 ? 0 : (parent.width - width) * (0.5 + 0.5 * Math.sin(ind.t))
                    }
                }
                Text {
                    Layout.fillWidth: true; elide: Text.ElideRight
                    text: pg.msg || "Working…"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                }
                Timer { id: ind; property real t: 0; interval: 30; repeat: true; running: pg.busy !== "" && pg.pct < 0; onTriggered: t += 0.06 }
            }
            Text {
                visible: pg.result !== "" && pg.busy === ""
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: pg.result; color: pg.resultColor; font.family: Theme.ui; font.pixelSize: 12
            }
        }
    }

    // ================= one-time setup (root helper) =================
    Rectangle {
        visible: st.helper === false
        Layout.fillWidth: true
        implicitHeight: setupCol.implicitHeight + 28
        color: Theme.panel2; border.color: Theme.warn
        ColumnLayout {
            id: setupCol
            x: 16; y: 14; width: parent.width - 32
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: "One-time setup: installing system updates needs a small helper installed in the system. Every install still asks for your password."
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12
                }
                ChamferButton {
                    primary: true
                    text: pg.busy === "setup" ? "Setting up…" : "Set up"
                    enabled: pg.busy === "" && pg.setupCmd !== null
                    onClicked: pg.setupHelper()
                }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                text: pg.setupCmd ? pg.setupCmd.display : ""
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9
            }
        }
    }

    // ================= Ultimit =================
    RowLayout {
        Layout.fillWidth: true
        SectionLabel { text: "Ultimit"; Layout.fillWidth: true }
        ChamferButton {
            visible: ul.newer === true && st.helper === true
            primary: true
            text: pg.busy === "ultimit" || ul.updating ? "Installing…" : "Install " + (ul.latest ? ul.latest.version : "")
            enabled: pg.busy === "" && !ul.updating
            onClicked: pg.installUltimit()
        }
        PowerButton {
            visible: pg.relogin
            text: "Log out"; confirm: true
            onActivated: Quickshell.execDetached(["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""])
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        color: ul.newer ? Theme.fg : Theme.dim; font.family: Theme.ui; font.pixelSize: 12
        text: {
            const inst = ul.installed ? "Installed: " + ul.installed : "";
            if (pg.ulLoading && ul.installed === undefined) return "Asking GitHub…";
            if (ul.updating && pg.busy !== "ultimit") return "Ultimit is being updated (log: /var/log/ultimit-update.log). Check again in a minute.";
            if (pg.relogin) return "Ultimit " + ul.installed + " is installed; this session is still running " + ul.running + ". Log out and back in to start it.";
            if (ul.error) return ul.error + (inst ? "  " + inst + "." : "");
            if (!ul.latest) return inst;
            if (ul.newer) return "Ultimit " + ul.latest.version + " is available"
                + (ul.latest.published ? " (" + ul.latest.published + ")" : "")
                + (ul.latest.size ? ", " + Math.max(1, Math.round(ul.latest.size / 1048576)) + " MB" : "")
                + ".  " + inst + ".";
            return "Up to date: Ultimit " + (ul.installed || ul.latest.version) + ".";
        }
    }
    Text {
        visible: ul.newer === true && !!ul.latest && ul.latest.notes !== ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        maximumLineCount: 10; elide: Text.ElideRight
        textFormat: Text.MarkdownText
        text: ul.latest ? ul.latest.notes : ""
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
    Text {
        visible: !!ul.latest && ul.newer === true
        text: "Release notes on GitHub"
        color: Theme.accent; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(pg.ul.latest.url) }
    }

    // ================= system =================
    RowLayout {
        Layout.fillWidth: true
        SectionLabel { text: "System"; Layout.fillWidth: true }
        ChamferButton {
            visible: pg.apt.length > 0 && st.helper === true
            primary: true
            text: pg.busy === "install" ? "Installing…" : "Install " + pg.apt.length + (pg.apt.length === 1 ? " update" : " updates")
            enabled: pg.busy === ""
            onClicked: pg.installSystem()
        }
    }
    Text {
        visible: !!st.aptError
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: st.aptError || ""; color: Theme.bad; font.family: Theme.ui; font.pixelSize: 12
    }
    Text {
        visible: st.apt !== undefined && pg.apt.length === 0 && !st.aptError
        text: "No system updates."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: pg.showAll ? pg.apt : pg.apt.slice(0, 8)
            delegate: ItemRow {
                required property var modelData
                implicitHeight: 40
                title: modelData.name + (modelData.archs.length > 1 ? "  (" + modelData.archs.join(", ") + ")" : "")
                subtitle: (modelData.new ? "new package · " : modelData.from + "  →  ") + modelData.to
                badge: modelData.security ? "security" : ""
                badgeColor: Theme.warn
            }
        }
    }
    Text {
        visible: pg.apt.length > 8
        text: pg.showAll ? "Show fewer" : "Show all " + pg.apt.length
        color: Theme.accent; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pg.showAll = !pg.showAll }
    }
    Text {
        visible: (st.held || []).length > 0
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: (st.held || []).length + " more held back by Ubuntu for now (rolled out to everyone gradually): " + (st.held || []).join(", ")
        color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
    }

    // ================= apps =================
    RowLayout {
        Layout.fillWidth: true
        SectionLabel { text: "Apps (Flatpak)"; Layout.fillWidth: true }
        ChamferButton {
            visible: pg.fpList.length > 0
            primary: true
            text: pg.busy === "flatpak" ? "Updating…" : "Update " + pg.fpList.length + (pg.fpList.length === 1 ? " app" : " apps")
            enabled: pg.busy === ""
            onClicked: pg.updateFlatpaks()
        }
    }
    Text {
        visible: pg.fpList.length === 0
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: pg.fpLoading ? "Asking Flathub…" : (fp.flatpakError || "No app updates.")
        color: fp.flatpakError ? Theme.bad : Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: pg.fpList
            delegate: ItemRow {
                required property var modelData
                implicitHeight: 40
                title: modelData.name
                subtitle: modelData.id + (modelData.version ? "  ·  " + modelData.version : "")
            }
        }
    }

    // ================= firmware =================
    RowLayout {
        Layout.fillWidth: true
        visible: pg.fwList.length > 0
        SectionLabel { text: "Firmware"; Layout.fillWidth: true }
        PowerButton {
            text: pg.busy === "firmware" ? "Updating…" : "Update firmware"
            confirm: true
            enabled: pg.busy === ""
            onActivated: pg.updateFirmware()
        }
    }
    Text {
        visible: pg.fwList.length > 0
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Firmware updates are applied by your PC's firmware on the next restart. Keep it plugged in."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: pg.fwList
            delegate: ItemRow {
                required property var modelData
                implicitHeight: 40
                title: modelData.device + (modelData.vendor ? "  ·  " + modelData.vendor : "")
                subtitle: modelData.from + "  →  " + modelData.to + (modelData.summary ? "  ·  " + modelData.summary : "")
                badge: modelData.reboot ? "restart" : ""
            }
        }
    }
}
