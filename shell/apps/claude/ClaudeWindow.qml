// ClaudeWindow.qml - the CLAUDE window: projects and their chats on the left, the chat on the right.
// "This PC" is the built-in project for troubleshooting (the system summary goes with its first
// message); every other project is a folder Claude works in, with its own account, model and notes.
// A normal xdg toplevel (the compositor draws the frame). Created by ClaudeApp.qml.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"

FloatingWindow {
    id: win

    title: (chat.meta.title ? chat.meta.title + " — " : "") + "CLAUDE"
    implicitWidth: 1180
    implicitHeight: 780
    minimumSize: Qt.size(760, 480)
    color: "transparent"   // the Theme.panel glass below fills it
    visible: true

    property string projectId: "system"
    readonly property var proj: Claude.project(projectId) || (Claude.projects.length ? Claude.projects[0] : null)
    property var chats: []
    property string overlay: ""         // "", "accounts", "project", "rename", "rmchat"
    property var editing: null          // the project open in the editor ({} = a new one)
    property var target: null           // the chat being renamed / removed
    property bool withSysinfo: true     // the system summary goes with the next message
    property bool closing: false
    readonly property alias panel: ov.item  // the open overlay (AccountsPanel, ProjectPanel, ...)
    readonly property alias session: chat
    property alias draft: input.text

    // The account this chat runs as: a saved chat keeps the one it started with.
    readonly property string accountId: chat.chatId !== "" && chat.meta.account ? chat.meta.account : Claude.accountFor(proj)
    readonly property var accountStatus: Claude.status[accountId] || {}
    readonly property bool ready: Claude.cliPath !== "" && Claude.accounts.length > 0
    readonly property bool canSend: ready && !chat.busy && !chat.loading && input.text.trim() !== ""

    ChatSession { id: chat; onChanged: win.loadChats() }

    function selectProject(id) {
        projectId = id;
        chat.load(id, "");
        withSysinfo = id === "system";
        chats = [];
        loadChats();
        input.forceActiveFocus();
    }
    function loadChats() {
        const pid = projectId;
        Claude.run(["chats", pid], o => { if (win.projectId === pid) win.chats = o.chats || []; });
    }
    function openChat(c) { chat.load(projectId, c.id); withSysinfo = false; input.forceActiveFocus(); }
    function newChat() { chat.load(projectId, ""); withSysinfo = projectId === "system"; input.forceActiveFocus(); }
    function sendNow() {
        if (!canSend || !proj) return;
        const text = input.text, sys = withSysinfo;
        const go = () => { chat.send(text, sys); input.text = ""; win.withSysinfo = false; };
        // a project without a usable account gets the one shown in the header, so its first chat can start
        if (chat.chatId === "" && !Claude.account(proj.account) && accountId !== "")
            Claude.saveProject({ id: proj.id, name: proj.name, dir: proj.dir, account: accountId, model: proj.model,
                                 perm: proj.perm, notes: proj.notes }, o => { if (o.ok) go(); });
        else go();
    }
    function editProject(p) { editing = p ? JSON.parse(JSON.stringify(p)) : ({}); overlay = "project"; }
    function showFolder(d) { Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-data"), d]); }
    function when(t) {
        const d = new Date(t * 1000), now = new Date();
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "hh:mm");
        if (now - d < 6 * 86400000) return Qt.formatDate(d, "ddd");
        return Qt.formatDate(d, "d MMM");
    }
    function tilde(p) { const h = Quickshell.env("HOME"); return p && h && p.startsWith(h) ? "~" + p.substring(h.length) : (p || ""); }
    readonly property var permLabels: ({ default: "Ask first", acceptEdits: "Edits allowed", plan: "Plan only",
                                         auto: "Auto", bypassPermissions: "No asking" })

    Component.onCompleted: {
        if (Claude.wantProject !== "") { selectProject(Claude.wantProject); Claude.wantProject = ""; }
        else selectProject("system");
        if (Claude.wantDir !== "") takeDir();
    }
    // "open this folder": its project, or a new one for it
    function takeDir() {
        const d = Claude.wantDir;
        Claude.wantDir = "";
        const p = Claude.projects.find(x => !x.builtin && x.dir === d);
        if (p) selectProject(p.id);
        else editProject({ name: d.substring(d.lastIndexOf("/") + 1), dir: d });
    }
    Connections {
        target: Claude
        function onRaiseChanged() {
            if (Claude.wantProject !== "") { win.selectProject(Claude.wantProject); Claude.wantProject = ""; }
            if (Claude.wantDir !== "") win.takeDir();
            input.forceActiveFocus();
        }
        function onProjectsChanged() { if (!Claude.project(win.projectId)) win.selectProject("system"); }
    }

    function doClose() { closing = true; chat.stopProc(); visible = false; Claude.closeWin(); }
    onClosed: if (!closing) doClose()

    Shortcut { sequences: ["Ctrl+N"]; enabled: win.overlay === ""; onActivated: win.newChat() }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.doClose() }
    Shortcut { sequences: ["Escape"]; enabled: win.overlay === "" && chat.busy; onActivated: chat.interrupt() }

    // ================================================================ UI
    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---------------------------------------------------- sidebar
            Rectangle {
                Layout.fillHeight: true; Layout.preferredWidth: 270
                color: Theme.panel
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; anchors.rightMargin: 15
                    spacing: 10

                    Text {
                        text: "[ CLAUDE ]"
                        color: Theme.fg; font.family: Theme.display; font.pixelSize: 15; font.letterSpacing: 3
                    }
                    Text {
                        Layout.fillWidth: true; Layout.topMargin: -6
                        text: Claude.cliVersion !== "" ? "CLAUDE CODE " + Claude.cliVersion : (Claude.cliChecked ? "CLAUDE CODE NOT INSTALLED" : "")
                        color: Claude.cliVersion !== "" ? Theme.dim : Theme.warn
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                    }

                    // the account this chat uses
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 52; Layout.topMargin: 4
                        color: accMa.containsMouse ? Theme.panel2 : "transparent"
                        border.width: 1; border.color: Theme.lineStrong
                        Rectangle {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: win.accountStatus.checking ? Theme.dim : (win.accountStatus.loggedIn ? Theme.ok : Theme.warn)
                        }
                        Column {
                            x: 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: Claude.accountName(win.accountId) || "No account"
                                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: win.accountStatus.checking ? "CHECKING" : win.accountStatus.loggedIn
                                    ? (win.accountStatus.email || win.accountStatus.method || "SIGNED IN") : "NOT SIGNED IN"
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
                            }
                        }
                        MouseArea { id: accMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.overlay = "accounts" }
                    }

                    // projects
                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 6
                        SectionLabel { text: "Projects"; Layout.fillWidth: true }
                        SmallLink { text: "+ NEW"; onClicked: win.editProject(null) }
                    }
                    ListView {
                        id: projList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 40 * 6)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: Claude.projects
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: SideRow {
                            required property var modelData
                            width: ListView.view.width
                            text: modelData.name
                            sub: modelData.builtin ? "TROUBLESHOOT · SYSTEM" : win.tilde(modelData.dir)
                            selected: modelData.id === win.projectId
                            onClicked: if (modelData.id !== win.projectId) win.selectProject(modelData.id)
                        }
                    }

                    // chats in this project
                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 6
                        SectionLabel { text: "Chats"; Layout.fillWidth: true }
                        SmallLink { text: "+ NEW"; onClicked: win.newChat() }
                    }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: win.chats
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: SideRow {
                            required property var modelData
                            width: ListView.view.width
                            text: modelData.title || "Chat"
                            sub: win.when(modelData.updated) + (modelData.account && modelData.account !== win.proj.account
                                 ? " · " + (Claude.accountName(modelData.account) || "removed account").toUpperCase() : "")
                            selected: modelData.id === chat.chatId
                            actions: true
                            onClicked: win.openChat(modelData)
                            onRename: { win.target = modelData; win.overlay = "rename"; }
                            onRemove: { win.target = modelData; win.overlay = "rmchat"; }
                        }
                        Text {
                            visible: win.chats.length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: "No chats here yet."
                            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                        }
                    }
                }
            }

            // ---------------------------------------------------- main
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true

                // set-up states: Claude Code missing, no account yet
                Loader {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 60, 560)
                    active: !win.ready
                    sourceComponent: Setup { onAccounts: win.overlay = "accounts" }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    visible: win.ready

                    // header: project, folder, account, model, permissions
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 64
                        color: Theme.panel
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                        Column {
                            x: 18; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - headBtns.width - 50
                            spacing: 3
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: win.proj ? win.proj.name.toUpperCase() : ""
                                color: Theme.fg; font.family: Theme.display; font.pixelSize: 14; font.letterSpacing: 2
                            }
                            Text {
                                width: parent.width; elide: Text.ElideMiddle
                                text: win.proj ? [win.tilde(win.proj.dir), (win.proj.model || chat.modelName || "default model"),
                                                  win.permLabels[win.proj.perm || "default"]].join("   ·   ").toUpperCase() : ""
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                            }
                        }
                        Row {
                            id: headBtns
                            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            ChamferButton { implicitHeight: 30; text: "Folder"; visible: !!win.proj; onClicked: win.showFolder(win.proj.dir) }
                            ChamferButton { implicitHeight: 30; text: "Project"; onClicked: win.editProject(win.proj) }
                            ChamferButton { implicitHeight: 30; text: "New chat"; onClicked: win.newChat() }
                        }
                    }

                    // the conversation
                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true

                        ListView {
                            id: convo
                            anchors.fill: parent
                            anchors.leftMargin: 18; anchors.rightMargin: 8
                            topMargin: 16; bottomMargin: 16
                            spacing: 10
                            boundsBehavior: Flickable.StopAtBounds
                            model: chat.items
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            property bool stick: true       // follow new text unless scrolled up
                            onMovementEnded: stick = atYEnd
                            onContentHeightChanged: if (stick) Qt.callLater(positionViewAtEnd)
                            onCountChanged: if (stick) Qt.callLater(positionViewAtEnd)
                            delegate: ChatItem {
                                required property var model
                                width: convo.width - 14
                                k: model.k; text: model.text; name: model.name; summary: model.summary
                                status: model.status; out: model.out; kind: model.kind; sysinfo: model.sysinfo
                            }
                            footer: Column {
                                width: convo.width - 14
                                spacing: 10
                                topPadding: chat.items.count ? 10 : 0
                                ChatItem {
                                    width: parent.width
                                    visible: chat.liveText !== ""
                                    k: "claude"; text: chat.liveText; streaming: true
                                }
                                Text {
                                    visible: chat.busy && chat.liveText === ""
                                    text: (chat.thinking ? "THINKING" : chat.statusText !== "" ? chat.statusText.toUpperCase() : "WORKING") + dots.s
                                    color: Theme.accent; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.6
                                    Timer {
                                        id: dots
                                        property string s: ""
                                        interval: 400; repeat: true; running: chat.busy
                                        onTriggered: s = s.length >= 3 ? "" : s + "."
                                    }
                                }
                            }
                        }

                        // an empty chat: what this project is for
                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 60, 520)
                            spacing: 10
                            visible: chat.items.count === 0 && !chat.busy && !chat.loading
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter
                                text: win.projectId === "system" ? "WHAT'S UP WITH THIS PC?" : "NEW CHAT"
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 2
                            }
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                text: win.projectId === "system"
                                    ? "Describe the problem. Claude gets a summary of this PC (Ultimit version, graphics, monitors, recent errors) with your first message, can read the logs, and asks before it changes anything."
                                    : "Claude works in " + win.tilde(win.proj ? win.proj.dir : "") + " and keeps to this project's notes. Chats stay in the list on the left, so you can pick one up later."
                                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                            }
                        }
                    }

                    // a permission request: Claude waits for the answer
                    Rectangle {
                        visible: chat.ask !== null
                        Layout.fillWidth: true
                        Layout.preferredHeight: askCol.implicitHeight + 28
                        color: Theme.panel
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.lineStrong }
                        Rectangle { width: 3; height: parent.height; color: Theme.warn }
                        Column {
                            id: askCol
                            x: 18; y: 14; width: parent.width - 36
                            spacing: 8
                            Text {
                                text: chat.ask ? ("Claude wants to use " + chat.ask.tool).toUpperCase() + (chat.askQueue.length ? "   (+" + chat.askQueue.length + " MORE)" : "") : ""
                                color: Theme.warn; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.8
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: 6; elide: Text.ElideRight
                                text: chat.ask ? chat.ask.summary : ""
                                color: Theme.fg; font.family: Theme.mono; font.pixelSize: 13
                            }
                            Text {
                                visible: !!chat.ask && chat.ask.reason !== "" && chat.ask.reason !== chat.ask.summary
                                width: parent.width; wrapMode: Text.Wrap
                                text: chat.ask ? chat.ask.reason : ""
                                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                            }
                            Rectangle {
                                visible: askMore.checked
                                width: parent.width; height: Math.min(detail.implicitHeight + 16, 220)
                                color: Theme.bg1; border.width: 1; border.color: Theme.line
                                Flickable {
                                    anchors.fill: parent; anchors.margins: 8
                                    contentHeight: detail.implicitHeight; clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    TextEdit {
                                        id: detail
                                        width: parent.width; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
                                        text: chat.ask ? chat.ask.detail : ""
                                        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                                        font.family: Theme.mono; font.pixelSize: 11
                                    }
                                }
                            }
                            Row {
                                spacing: 8
                                ChamferButton { text: "Allow"; primary: true; onClicked: chat.permit(true, false) }
                                ChamferButton { text: "Always allow"; visible: !!chat.ask && chat.ask.always; onClicked: chat.permit(true, true) }
                                ChamferButton { text: "Deny"; onClicked: chat.permit(false, false) }
                                SmallLink {
                                    id: askMore
                                    property bool checked: false
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: checked ? "HIDE DETAILS" : "DETAILS"
                                    onClicked: checked = !checked
                                }
                            }
                        }
                    }

                    // composer
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(Math.max(input.contentHeight + 24, 48), 220) + 46
                        color: Theme.panel
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }

                        Rectangle {
                            id: box
                            x: 14; y: 12; width: parent.width - 28; height: parent.height - 52
                            color: "transparent"
                            border.width: 1; border.color: input.activeFocus ? Theme.accent : Theme.lineStrong
                            ScrollView {
                                anchors.fill: parent; anchors.margins: 1
                                TextArea {
                                    id: input
                                    wrapMode: TextArea.Wrap
                                    background: null
                                    padding: 10
                                    color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                                    placeholderText: win.projectId === "system" ? "Describe what's wrong, or ask anything about this PC…"
                                                                                 : "Ask Claude about " + (win.proj ? win.proj.name : "this project") + "…"
                                    placeholderTextColor: Theme.dim
                                    font.family: Theme.ui; font.pixelSize: 14
                                    enabled: win.ready
                                    Keys.onPressed: e => {
                                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                            win.sendNow(); e.accepted = true;
                                        }
                                    }
                                }
                            }
                        }
                        Row {
                            x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                            spacing: 8
                            Toggle {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "SYSTEM INFO"
                                checked: win.withSysinfo
                                onToggled: win.withSysinfo = !win.withSysinfo
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: [chat.info, chat.limit].filter(s => s !== "").join("   ·   ").toUpperCase()
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                            }
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "ENTER SENDS · SHIFT+ENTER NEW LINE"
                                visible: !chat.busy
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.2
                            }
                            ChamferButton { implicitHeight: 28; text: "Stop"; visible: chat.busy; onClicked: chat.interrupt() }
                            ChamferButton { implicitHeight: 28; text: "Send"; primary: win.canSend; onClicked: win.sendNow() }
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------- overlays
        Item {
            anchors.fill: parent
            visible: win.overlay !== ""
            Rectangle { anchors.fill: parent; color: Theme.bg1; opacity: 0.6 }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: wheel => wheel.accepted = true }
            Keys.onEscapePressed: win.overlay = ""
            Loader {
                id: ov
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, win.overlay === "accounts" || win.overlay === "project" ? 620 : 440)
                height: Math.min(parent.height - 40, item ? item.implicitHeight : 0)
                active: win.overlay !== ""
                sourceComponent: win.overlay === "accounts" ? accountsC : win.overlay === "project" ? projectC : smallC
                onLoaded: item.forceActiveFocus()
            }
        }
        Component { id: accountsC; AccountsPanel { host: win } }
        Component { id: projectC; ProjectPanel { host: win; project: win.editing } }
        Component {
            id: smallC
            Rectangle {
                implicitHeight: col.implicitHeight + 40
                color: Theme.bg1
                border.width: 1; border.color: Theme.lineStrong
                Keys.onEscapePressed: win.overlay = ""
                Column {
                    id: col
                    x: 20; y: 20; width: parent.width - 40
                    spacing: 14
                    SectionLabel { text: win.overlay === "rename" ? "Rename chat" : "Remove chat" }
                    Text {
                        visible: win.overlay === "rmchat"
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Remove \"" + (win.target ? win.target.title : "") + "\" from this list? Claude Code keeps its own copy of the conversation in the account's folder."
                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                    }
                    Entry {
                        id: nameEntry
                        visible: win.overlay === "rename"
                        width: parent.width
                        text: win.target ? win.target.title : ""
                        onAccepted: okBtn.clicked()
                        Component.onCompleted: if (visible) { focusEntry(); selectAll(); }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 10
                        ChamferButton { text: "Cancel"; onClicked: win.overlay = "" }
                        ChamferButton {
                            id: okBtn
                            text: win.overlay === "rename" ? "Rename" : "Remove"; primary: true
                            onClicked: {
                                const c = win.target;
                                if (win.overlay === "rename")
                                    Claude.run(["chat-rename", win.projectId, c.id, nameEntry.text], () => win.loadChats());
                                else
                                    Claude.run(["chat-remove", win.projectId, c.id], () => { if (chat.chatId === c.id) win.newChat(); win.loadChats(); });
                                win.overlay = "";
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- small pieces ----
    component Toggle: Rectangle {
        id: tg
        property string text: ""
        property bool checked: false
        signal toggled()
        width: tgT.implicitWidth + 30; height: 24
        color: checked ? Theme.panel2 : "transparent"
        border.width: 1; border.color: checked ? Theme.accent : Theme.lineStrong
        Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: tg.checked ? Theme.accent : Theme.dim }
        Text {
            id: tgT
            x: 20; anchors.verticalCenter: parent.verticalCenter
            text: tg.text
            color: tg.checked ? Theme.fg : Theme.dim
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }
}
