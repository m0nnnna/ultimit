// VpnSection.qml - Settings > Network > VPN: the VPN profiles (connect / disconnect, sign in,
// remove), importing a WireGuard .conf or OpenVPN .ovpn file, or pasting a WireGuard config.
// All through vpn.py (NetworkManager); passwords go on stdin and end up in the keyring.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 8

    readonly property string script: Quickshell.shellPath("apps/settings/vpn.py")
    property var vpns: []
    property string error: ""
    property bool busy: false
    property string note: ""
    property color noteColor: Theme.dim
    property string loginFor: ""     // uuid whose sign-in form is open
    property string removeFor: ""    // uuid waiting for "Remove?" confirmation
    property bool pasting: false

    function reload() { listProc.running = false; listProc.running = true; }
    Component.onCompleted: reload()
    Timer { interval: 4000; running: true; repeat: true; onTriggered: if (!root.busy) root.reload() }
    Process {
        id: listProc
        command: ["python3", "-I", root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const o = JSON.parse(text); root.vpns = o.vpns || []; root.error = o.ok ? "" : (o.error || ""); } catch (e) {}
            }
        }
    }

    // ---- one change at a time ----
    function run(args, input, okText, after) {
        if (busy) return;
        if (SetSys.dryRun) { console.log("[dry-run] vpn.py " + args.join(" ")); note = "Dry run: nothing changed."; return; }
        busy = true; note = ""; job.okText = okText; job.input = input || ""; job.after = after || null;
        job.command = ["python3", "-I", script].concat(args);
        job.running = true;
    }
    Process {
        id: job
        property string okText: ""
        property string input: ""
        property var after: null
        stdinEnabled: true
        onStarted: { if (input !== "") write(input); stdinEnabled = false; }
        stdout: StdioCollector { id: jobOut }
        onExited: code => {
            root.busy = false; job.stdinEnabled = true;
            let o = {};
            try { o = JSON.parse(jobOut.text); } catch (e) {}
            if (o.ok) {
                root.note = job.okText; root.noteColor = Theme.ok;
                if (job.after) job.after(o);
            } else {
                root.note = o.error || "That didn't work."; root.noteColor = Theme.bad;
            }
            root.reload();
        }
    }
    Process {
        id: pick
        command: ["zenity", "--file-selection", "--title=Choose a VPN file",
                  "--file-filter=VPN files (WireGuard .conf, OpenVPN .ovpn) | *.conf *.ovpn *.CONF *.OVPN"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim();
                if (!f.startsWith("/")) return;
                root.run(["import", f], "", "VPN added. It connects only when you turn it on.",
                         o => { if (o.needsLogin) { root.loginFor = o.uuid; user.text = ""; pw.text = ""; } });
            }
        }
    }

    SectionLabel { text: "VPN" }
    Text {
        visible: root.error !== ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: root.error; color: Theme.bad; font.family: Theme.ui; font.pixelSize: Theme.type.label
    }
    Text {
        visible: root.vpns.length === 0 && root.error === ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "No VPNs yet. Add one from the file your VPN service gives you: WireGuard (.conf) or OpenVPN (.ovpn)."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
    }

    Repeater {
        model: root.vpns
        delegate: ColumnLayout {
            id: vr
            required property var modelData
            Layout.fillWidth: true
            spacing: 0
            ItemRow {
                title: vr.modelData.name
                subtitle: (vr.modelData.kind === "wireguard" ? "WireGuard" : vr.modelData.kind === "openvpn" ? "OpenVPN" : "VPN")
                    + (vr.modelData.user ? "  ·  " + vr.modelData.user : "")
                    + (vr.modelData.kind === "openvpn" ? (vr.modelData.saved ? "  ·  password saved" : "  ·  password asked each time") : "")
                badge: vr.modelData.active ? "connected" : ""
                badgeColor: Theme.ok
                ChamferButton {
                    text: vr.modelData.active ? "Disconnect" : "Connect"
                    primary: !vr.modelData.active
                    enabled: !root.busy
                    onClicked: root.run([vr.modelData.active ? "down" : "up", vr.modelData.uuid], "",
                                        vr.modelData.name + (vr.modelData.active ? " is disconnected." : " is connected."))
                }
                ChamferButton {
                    visible: vr.modelData.kind === "openvpn"
                    text: "Sign in"
                    onClicked: { root.loginFor = root.loginFor === vr.modelData.uuid ? "" : vr.modelData.uuid; user.text = vr.modelData.user; pw.text = ""; }
                }
                ChamferButton {
                    text: root.removeFor === vr.modelData.uuid ? "Remove it" : "Remove"
                    primary: root.removeFor === vr.modelData.uuid
                    enabled: !root.busy
                    onClicked: {
                        if (root.removeFor !== vr.modelData.uuid) { root.removeFor = vr.modelData.uuid; return; }
                        root.removeFor = "";
                        root.run(["delete", vr.modelData.uuid], "", vr.modelData.name + " is removed.");
                    }
                }
            }
            // sign-in form (OpenVPN: user name + password, remembered in the keyring or asked)
            Rectangle {
                visible: root.loginFor === vr.modelData.uuid
                Layout.fillWidth: true
                implicitHeight: lg.implicitHeight + 24
                color: Theme.field
                ColumnLayout {
                    id: lg
                    x: 14; y: 12; width: parent.width - 28
                    spacing: 8
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2; columnSpacing: 12; rowSpacing: 8
                        Text { text: "User name"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label }
                        TextEntry { id: user; Layout.fillWidth: true; placeholder: "from your VPN service (PIA: p1234567)" }
                        Text { text: "Password"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label }
                        TextEntry { id: pw; Layout.fillWidth: true; secret: true }
                    }
                    ToggleRow { id: remember; Layout.fillWidth: true; text: "Remember the password (in your keyring)"; checked: true }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        ChamferButton { text: "Cancel"; onClicked: root.loginFor = "" }
                        ChamferButton {
                            primary: true; text: "Save"
                            enabled: !root.busy && user.text.trim() !== "" && (!remember.checked || pw.text !== "")
                            onClicked: {
                                root.run(["login", vr.modelData.uuid, user.text.trim(), remember.checked ? "save" : "ask"],
                                         remember.checked ? pw.text + "\n" : "", "Sign-in saved for " + vr.modelData.name + ".",
                                         () => root.loginFor = "");
                                pw.text = "";
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: root.note !== ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: root.note; color: root.noteColor; font.family: Theme.ui; font.pixelSize: Theme.type.label
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        ChamferButton { text: "Add from a file…"; enabled: !root.busy; onClicked: pick.running = true }
        ChamferButton { text: "Paste a WireGuard config"; onClicked: root.pasting = !root.pasting }
    }

    // ---- paste a WireGuard config ----
    Rectangle {
        visible: root.pasting
        Layout.fillWidth: true
        implicitHeight: ps.implicitHeight + 24
        color: Theme.field
        ColumnLayout {
            id: ps
            x: 14; y: 12; width: parent.width - 28
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Name"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label }
                TextEntry { id: pasteName; Layout.fillWidth: true; placeholder: "Home, Office, Proton…" }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 150
                color: Theme.field; border.color: cfg.activeFocus ? Theme.accent : "transparent"
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                ScrollView {
                    anchors.fill: parent; anchors.margins: 6
                    TextArea {
                        id: cfg
                        placeholderText: "[Interface]\nPrivateKey = …\nAddress = …\n\n[Peer]\nPublicKey = …\nAllowedIPs = 0.0.0.0/0\nEndpoint = …"
                        placeholderTextColor: Theme.dim
                        color: Theme.fg; font.family: Theme.mono; font.pixelSize: Theme.type.label
                        background: null
                        wrapMode: TextEdit.NoWrap
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ChamferButton { text: "Cancel"; onClicked: { root.pasting = false; cfg.text = ""; } }
                ChamferButton {
                    primary: true; text: "Add VPN"
                    enabled: !root.busy && cfg.text.indexOf("[Interface]") >= 0
                    onClicked: root.run(["paste", pasteName.text.trim() || "WireGuard"], cfg.text, "VPN added. It connects only when you turn it on.",
                                        () => { root.pasting = false; cfg.text = ""; pasteName.text = ""; })
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Private Internet Access: their Linux app works here (its icon shows in the tray). Without it, download PIA's OpenVPN files, add one here and sign in with your PIA user name and password."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
    }
}
