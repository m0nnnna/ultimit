// AddGameDialog.qml - modal "Add game" card (also the editor for manual games):
//   * Windows program (Wine): an .exe in a shared or custom prefix
//   * Installer (.exe): run an installer into its own fresh prefix, pick the game exe.
//     Installer mode (on by default) maximizes the chance the install completes:
//     WineD3D instead of DXVK, an older Windows version for old installer
//     frameworks, and an optional Proton log so a crash is diagnosable.
//   * Command: anything
// Saved to games.json "manual" via Games.addManual()/Games.updateManual(); launching
// goes through bin/ultimit-game-run like every other non-Steam game.
import QtQuick
import Quickshell.Io
import "../.."

Item {
    id: root
    signal closed()

    property string kind: "wine"                 // wine | installer | command
    property string prefixMode: "default"
    property string runner: "wine"
    property string proton: ""
    property bool installerMode: true
    property string winver: "win10"              // win10 | win7 | winxp
    property bool instLog: false
    property string editId: ""                   // non-empty = editing an existing manual game
    property string editGameid: ""
    property var prefixPicks: []                 // executables found in the prefix (edit mode)
    readonly property string target: targetField.text.trim()
    readonly property bool valid: target !== ""
        && (kind !== "wine" || prefixMode === "default" || prefixField.text.trim() !== "")
    // installer flow: 0 = form, 1 = installer running, 2 = picking the executable
    property int phase: 0
    property var plan: null
    property var candidates: []
    property int picked: -1
    property int installRc: -1
    property string installError: ""
    property string errorText: ""

    function reset() {
        kind = "wine"; prefixMode = "default"; runner = "wine"; proton = "";
        installerMode = true; winver = "win10"; instLog = false;
        targetField.text = ""; nameField.text = ""; prefixField.text = "";
        editId = ""; editGameid = ""; prefixPicks = [];
        phase = 0; plan = null; candidates = []; picked = -1;
        installRc = -1; installError = ""; errorText = "";
    }
    function open() {
        reset();
        visible = true;
        targetField.input.forceActiveFocus();
    }
    function openEdit(game) {
        reset();
        const g = (Games.settings.games[game.id]) || {};
        kind = game.kind === "command" ? "command" : "wine";
        prefixMode = (g.prefix && g.prefix !== "default") ? "custom" : "default";
        runner = g.runner === "proton" ? "proton" : "wine";
        proton = g.proton || "";
        targetField.text = game.target || "";
        nameField.text = game.name || "";
        prefixField.text = prefixMode === "custom" ? (g.prefix || "") : "";
        editId = game.id;
        editGameid = g.gameid || "";
        visible = true;
    }
    function close() { visible = false; closed(); }
    function baseName(p) {
        const f = p.replace(/\\/g, "/").split("/").pop();
        const i = f.lastIndexOf(".");
        return (kind !== "command" && i > 0) ? f.slice(0, i) : f.split(" ")[0];
    }
    function submit() {
        if (!visible || !valid || kind === "installer") return;
        const nm = nameField.text.trim() || baseName(target);
        if (editId !== "") {
            Games.updateManual(editId, nm, kind, target,
                               kind === "wine" && prefixMode === "custom" ? prefixField.text.trim() : "",
                               kind === "wine" ? runner : "",
                               kind === "wine" && runner === "proton" ? proton : "",
                               editGameid);
        } else {
            Games.addManual(nm, kind, target, kind === "wine" && prefixMode === "custom" ? prefixField.text.trim() : "",
                            kind === "wine" ? runner : "", kind === "wine" && runner === "proton" ? proton : "");
        }
        close();
    }
    function startInstall() {
        if (!visible || !valid || kind !== "installer") return;
        errorText = "";
        installRc = -1; installError = "";
        planner.opts = JSON.stringify({ installer: target, name: nameField.text.trim(),
                                        runner: runner, proton: runner === "proton" ? proton : "",
                                        installerMode: installerMode,
                                        winver: installerMode ? winver : "win10",
                                        log: instLog });
        planner.running = true;
    }
    function finishInstall() {
        Games.addManual(plan.name, "wine", candidates[picked].path, plan.prefix,
                        plan.runner, plan.proton, plan.gameid);
        close();
    }
    function modeLine() {
        if (!root.plan) return "";
        const bits = [];
        if (root.plan.installer_mode)
            bits.push(root.plan.runner === "proton" ? "WineD3D (no DXVK)" : "Wine");
        const wv = root.plan.winver || "win10";
        if (wv === "win7") bits.push("Windows 7");
        else if (wv === "winxp") bits.push("Windows XP");
        if (root.plan.log) bits.push("Proton log");
        return bits.length ? "Compatibility: " + bits.join(" · ") : "Compatibility mode off";
    }

    visible: false
    anchors.fill: parent
    z: 50
    focus: visible
    Keys.onEscapePressed: if (root.phase === 0) root.close()

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: if (root.phase === 0) root.close() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Config.mobile ? parent.width - 24 : Math.min(480, parent.width - 32)
        height: col.implicitHeight + 40
        color: Theme.bg1
        border.color: Theme.lineStrong
        border.width: 1
        MouseArea { anchors.fill: parent }          // swallow clicks
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: Theme.accent; size: 12 }

        Flickable {   // phone: the form scrolls when it is taller than the window
            id: sc
            anchors.fill: parent
            contentHeight: col.implicitHeight + 40
            clip: true
            interactive: Config.mobile
            boundsBehavior: Flickable.StopAtBounds
        }
        Column {
            id: col
            parent: sc.contentItem
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                GLabel {
                    text: root.editId !== "" ? "Edit game"
                        : root.phase === 1 ? "Installing"
                        : root.phase === 2 ? "Pick the executable" : "Add game"
                    strong: true
                }
            }
            Text {
                visible: root.errorText !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.warn
                font.family: Theme.ui; font.pixelSize: 11
                text: root.errorText
            }
            GSeg {
                visible: root.phase === 0
                options: root.editId !== ""
                    ? [{ id: "wine", label: Config.mobile ? "Wine program" : "Windows program (Wine)" },
                       { id: "command", label: "Command" }]
                    : [{ id: "wine", label: Config.mobile ? "Wine program" : "Windows program (Wine)" },
                       { id: "installer", label: Config.mobile ? "Installer" : "Installer (.exe)" },
                       { id: "command", label: "Command" }]
                current: root.kind
                onPicked: id => root.kind = id
            }

            Column {   // ---- the form (phase 0)
                visible: root.phase === 0
                width: parent.width
                spacing: 12

                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: root.kind === "installer" ? "Installer (.exe / .msi)" : root.kind === "wine" ? "Program (.exe)" : "Command" }
                    Row {
                        width: parent.width
                        spacing: 8
                        GInput {
                            id: targetField
                            width: parent.width - (root.kind !== "command" ? browse.width + 8 : 0)
                            placeholder: root.kind === "installer" ? "/path/to/setup_game_1.0.exe"
                                     : root.kind === "wine" ? "/path/to/game.exe" : "e.g. retroarch -f"
                            onAccepted: root.kind === "installer" ? root.startInstall() : root.submit()
                            onEscaped: root.close()
                        }
                        GButton {
                            id: browse
                            visible: root.kind !== "command"
                            text: "Browse"
                            onClicked: picker.running = true
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Name" }
                    GInput {
                        id: nameField
                        width: parent.width
                        placeholder: root.target !== "" ? root.baseName(root.target) : "shown in the library"
                        onAccepted: root.kind === "installer" ? root.startInstall() : root.submit()
                        onEscaped: root.close()
                    }
                }
                Column {
                    visible: root.kind !== "command"
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Runner" }
                    GSeg {
                        options: [{ id: "wine", label: "Wine" }, { id: "proton", label: "Proton (umu)" }]
                        current: root.runner
                        onPicked: id => root.runner = id
                    }
                    ProtonPicker {
                        visible: root.runner === "proton"
                        width: parent.width
                        current: root.proton
                        onPicked: path => root.proton = path
                    }
                    Text {
                        visible: root.runner === "proton" && !Games.tools.umu
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.warn
                        font.family: Theme.ui; font.pixelSize: 11
                        text: "umu-launcher not installed; Proton games cannot start without umu-run."
                    }
                }
                Column {
                    visible: root.kind === "wine"
                    width: parent.width
                    spacing: 6
                    GLabel { text: root.runner === "proton" ? "Prefix" : "Wine prefix" }
                    GSeg {
                        options: [{ id: "default", label: "Shared default" }, { id: "custom", label: "Custom" }]
                        current: root.prefixMode
                        onPicked: id => root.prefixMode = id
                    }
                    GInput {
                        id: prefixField
                        visible: root.prefixMode === "custom"
                        width: parent.width
                        placeholder: "~/.local/share/ultimit/wine/my-game"
                        onAccepted: root.submit()
                        onEscaped: root.close()
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: 11
                        text: root.prefixMode === "default"
                            ? "All games with the shared prefix live in " + Games.winePrefix + ". A custom prefix is created on first launch."
                            : "A folder for this game's own Wine prefix. It is created on first launch."
                    }
                }
                Column {   // ---- pick an installed executable (edit mode, custom prefix)
                    visible: root.editId !== "" && root.kind === "wine" && prefixField.text.trim() !== ""
                    width: parent.width
                    spacing: 6
                    GButton {
                        text: "Scan prefix for executables"
                        onClicked: { prefixPicker.prefixArg = prefixField.text.trim(); prefixPicker.running = true; }
                    }
                    Text {
                        visible: root.prefixPicks.length > 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: 11
                        text: "Click one to make it the program:"
                    }
                    Flow {
                        visible: root.prefixPicks.length > 0
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: root.prefixPicks
                            delegate: GButton {
                                required property var modelData
                                text: modelData.path.split("/").pop() + "  (" + Games.fmtSize(modelData.size) + ")"
                                onClicked: targetField.text = modelData.path
                            }
                        }
                    }
                }
                Column {   // ---- installer compatibility (installer kind only)
                    visible: root.kind === "installer"
                    width: parent.width
                    spacing: 6
                    GToggle {
                        label: "Installer mode (best compatibility)"
                        checked: root.installerMode
                        onToggled: v => root.installerMode = v
                    }
                    Column {
                        visible: root.installerMode
                        width: parent.width
                        spacing: 6
                        GLabel { text: "Windows version for the install" }
                        GSeg {
                            options: [{ id: "win10", label: "Windows 10" },
                                      { id: "win7", label: "Windows 7" },
                                      { id: "winxp", label: "Windows XP" }]
                            current: root.winver
                            onPicked: id => root.winver = id
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.family: Theme.ui; font.pixelSize: 11
                            text: "Old installer frameworks (InstallShield, early Inno Setup) crash on Windows 10. Try Windows 7 if the install fails; XP is for very old games and needs the Wine runner (32-bit prefix)."
                        }
                    }
                    GToggle {
                        label: "Proton log"
                        checked: root.instLog
                        onToggled: v => root.instLog = v
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: 11
                        text: "Writes a proton log to your home directory while the installer runs. Include it when reporting a failed install."
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: 11
                        text: "Runs the installer in a prefix of its own (shown on the next step), then you pick the game it installed. The game launches from that prefix with the runner chosen above. If Proton keeps crashing it, try the Wine runner."
                    }
                }
                Row {
                    spacing: 10
                    anchors.right: parent.right
                    GButton { text: "Cancel"; onClicked: root.close() }
                    GButton {
                        primary: true
                        text: root.editId !== "" ? "Save changes" : root.kind === "installer" ? "Install…" : "Add game"
                        enabled: root.valid
                        onClicked: root.kind === "installer" && root.editId === "" ? root.startInstall() : root.submit()
                    }
                }
            }

            Column {   // ---- installer running (phase 1)
                visible: root.phase === 1
                width: parent.width
                spacing: 8
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.fg
                    font.family: Theme.ui; font.pixelSize: 12
                    text: "The installer's window is on screen — click through it like on Windows. This card waits for it to finish."
                }
                Text {
                    visible: !!root.plan
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 11
                    text: root.plan ? "prefix: " + root.plan.prefix : ""
                }
                Text {
                    visible: root.modeLine() !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 11
                    text: root.modeLine()
                }
                Text {
                    visible: !!root.plan && root.plan.notes.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.warn
                    font.family: Theme.ui; font.pixelSize: 11
                    text: root.plan ? root.plan.notes.join("\n") : ""
                }
            }

            Column {   // ---- pick the installed executable (phase 2)
                visible: root.phase === 2
                width: parent.width
                spacing: 8
                Text {
                    visible: root.installError !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.warn
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "The installer could not start: " + root.installError
                }
                Text {
                    visible: root.installError === "" && root.installRc > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.warn
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "The installer exited with code " + root.installRc + " — it crashed or was cancelled."
                }
                Text {
                    visible: root.installError === "" && root.installRc > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "Next attempts to try: Windows 7 above, the Wine runner instead of Proton, and the Proton log for the exact error. Files in the prefix are kept either way."
                }
                Text {
                    visible: root.candidates.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "Which one is the game? Largest first — the biggest is usually it."
                }
                Text {
                    visible: root.candidates.length === 0 && root.installRc <= 0 && root.installError === ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.warn
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "No executables found in the prefix. The installer may have failed or installed nothing; its files are kept at " + (root.plan ? root.plan.prefix : "") + "."
                }
                Column {
                    visible: root.candidates.length > 0
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: root.candidates
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.picked === index
                            width: parent.width
                            height: 34
                            color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                      : (m.containsMouse ? Theme.panel2 : "transparent")
                            border.color: on ? Theme.accent : Theme.line
                            border.width: 1
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10
                                Text {
                                    width: parent.width - sizeLbl.width - 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    color: parent.parent.on ? Theme.accent : Theme.fg
                                    font.family: Theme.ui; font.pixelSize: 12
                                    text: modelData.path.split("/").pop()
                                }
                                Text {
                                    id: sizeLbl
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.dim
                                    font.family: Theme.mono; font.pixelSize: 10
                                    text: Games.fmtSize(modelData.size)
                                }
                            }
                            MouseArea {
                                id: m
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.picked = index
                            }
                        }
                    }
                }
                Text {
                    visible: root.candidates.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "Full path: " + (root.picked >= 0 ? root.candidates[root.picked].path : "—")
                }
                Row {
                    spacing: 10
                    anchors.right: parent.right
                    GButton { text: "Cancel"; onClicked: root.close() }
                    GButton {
                        visible: root.candidates.length > 0
                        text: "Rescan"
                        onClicked: { root.picked = -1; scanner2.running = true; }
                    }
                    GButton {
                        primary: true
                        text: "Add to library"
                        enabled: root.picked >= 0
                        onClicked: root.finishInstall()
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 11
                    text: "Cancel keeps the installed files in the prefix (delete the folder yourself if unneeded)."
                }
            }
        }
    }

    Process {
        id: picker
        command: ["zenity", "--file-selection",
                  "--title=" + (root.kind === "installer" ? "Choose an installer" : "Choose a Windows program"),
                  "--file-filter=" + (root.kind === "installer" ? "Installers | *.exe *.EXE *.msi" : "Programs | *.exe *.EXE *.bat *.msi"),
                  "--file-filter=All files | *"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p !== "") { targetField.text = p; if (nameField.text === "") nameField.input.forceActiveFocus(); }
            }
        }
    }
    Process {
        id: prefixPicker
        property string prefixArg: ""
        command: ["python3", Games.scriptPath, "install-scan", prefixArg]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.prefixPicks = JSON.parse(text).candidates;
                } catch (e) { console.warn("install-scan:", text); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("install-scan:", text) }
    }
    Process {
        id: planner
        property string opts: ""
        command: ["python3", Games.scriptPath, "install-plan", opts]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.plan = d;
                    root.phase = 1;
                    installerProc.planJson = text;
                    installerProc.running = true;
                } catch (e) {
                    root.errorText = "Could not plan the install: " + text.slice(0, 160);
                    console.warn("install-plan:", text);
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("install-plan:", text) }
    }
    Process {
        id: installerProc
        property string planJson: ""
        command: ["python3", Games.scriptPath, "install-run", planJson]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.installRc = r.rc;
                    root.installError = r.error || "";
                } catch (e) { console.warn("install-run:", text); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("install-run:", text) }
        onExited: { root.picked = -1; scanner2.running = true; }
    }
    Process {
        id: scanner2
        command: ["python3", Games.scriptPath, "install-scan", root.plan ? root.plan.prefix : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.candidates = JSON.parse(text).candidates;
                    root.phase = 2;
                } catch (e) { console.warn("install-scan:", text); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("install-scan:", text) }
    }
}
