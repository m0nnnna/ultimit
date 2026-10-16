// ClaudeWindow.qml - the CLAUDE window: projects and their chats on the left, the chat on the right.
// "This PC" is the built-in project for troubleshooting (the system summary goes with its first
// message); every other project is a folder Claude works in, with its own account, model and notes.
// The sidebar shows the account's plan limits; right-click a project, chat, message or the composer
// for a menu. A chat that is still working keeps running when you switch to another one (the chat
// list marks it); click the account box to carry on the open chat with another account. A normal xdg
// toplevel (the compositor draws the frame). Created by ClaudeApp.qml.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"
import "../data" as DataApp

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
    readonly property ChatSession session: chat
    property alias draft: input.text

    // The account this chat runs as: a saved chat keeps the one it started with.
    readonly property string accountId: chat.chatId !== "" && chat.meta.account ? chat.meta.account
                                        : (chat.account !== "" && Claude.account(chat.account) ? chat.account : Claude.accountFor(proj))
    readonly property var accountStatus: Claude.status[accountId] || {}
    readonly property bool ready: Claude.cliPath !== "" && Claude.accounts.length > 0
    readonly property bool canSend: ready && !chat.busy && !chat.loading && (input.text.trim() !== "" || attachments.length > 0)

    // ---- images to send with the next message: [{path, w, h}] (claude.py keeps the files) ----
    property var attachments: []
    property string attachNote: ""          // why the last paste or drop didn't attach
    function addAttachment(o) {
        if (o.ok) { attachments = attachments.concat([{ path: o.path, w: o.w, h: o.h }]); attachNote = ""; }
        else if (o.err) attachNote = o.err;
    }
    function removeAttachment(i) {
        Claude.run(["drop-image", attachments[i].path], () => {});
        attachments = attachments.filter((_, j) => j !== i);
    }
    function clearAttachments() {
        for (const a of attachments) Claude.run(["drop-image", a.path], () => {});
        attachments = [];
        attachNote = "";
    }
    // Ctrl+V: an image on the clipboard (or an image file copied in DATA) attaches, anything else pastes
    function pasteAny() {
        Claude.run(["paste-image"], o => {
            if (o.ok || !o.none) addAttachment(o);
            else input.paste();
        });
    }

    // ---- the chat on screen, and the ones still working in the background ----
    // Switching chats never stops a turn: a working chat moves to `background` and carries on; it is let
    // go (its Claude Code stops) once it has nothing left to do. Switching back picks it up live.
    property ChatSession chat: firstChat
    property var background: []
    ChatSession { id: firstChat; onChanged: win.loadChats(); onDone: win.letGo(firstChat) }
    Component { id: chatC; ChatSession {} }
    function showChat(pid, cid) {
        if (cid !== "" && chat.projectId === pid && chat.chatId === cid) return;
        const prev = chat;
        let next = cid !== "" ? background.find(b => b.projectId === pid && b.chatId === cid) : null;
        if (next) background = background.filter(b => b !== next);
        else {
            next = chatC.createObject(win);
            next.changed.connect(win.loadChats);
            next.done.connect(() => win.letGo(next));
            next.load(pid, cid);
        }
        chat = next;
        if (prev !== next) {
            if (prev.working) { background = background.concat([prev]); loadChats(); }   // a new chat shows up in the list
            else dropChat(prev);
        }
    }
    function dropChat(c) { c.stopProc(); if (c !== firstChat) c.destroy(); }
    function letGo(c) {
        if (background.indexOf(c) < 0) return;
        background = background.filter(b => b !== c);
        dropChat(c);
    }
    // "working" / "needs you" for a chat running in the background, else ""
    function chatState(pid, cid) {
        const b = background.find(x => x.projectId === pid && x.chatId === cid);
        return !b ? "" : b.ask !== null ? "needs you" : "working";
    }
    function stopChat(c) { c.stopProc(); c.busy = false; c.ask = null; c.askQueue = []; c.pending = []; }

    // ---- the account the open chat uses ----
    function accountMenu(from, x, y) {
        const items = Claude.accounts.map(a => ({
            id: "acc:" + a.id,
            label: a.name + ((Claude.status[a.id] || {}).loggedIn ? "" : "  (not signed in)"),
            hint: a.id === win.accountId ? "✓" : "",
            disabled: a.id === win.accountId || chat.working }));
        items.push({ kind: "sep" }, { id: "accounts", label: "Manage accounts…" });
        popMenu(items, from, x, y, {});
    }
    function useAccount(aid) {
        const c = chat;
        if (c.chatId === "") { c.account = aid; return; }      // a new chat starts with it
        if (c.working) return;
        c.stopProc();                                           // the next message resumes with the new account
        Claude.run(["chat-account", c.projectId, c.chatId, aid], o => {
            if (o.ok) {
                c.meta = o.meta;
                c.addItem({ k: "note", kind: "account", text: "This chat now uses " + Claude.accountName(aid) + "." });
                win.loadChats();
            } else c.addItem({ k: "note", kind: "error", text: o.err || "Couldn't switch accounts." });
        });
    }

    function selectProject(id) {
        projectId = id;
        showChat(id, "");
        withSysinfo = id === "system";
        chats = [];
        loadChats();
        input.forceActiveFocus();
    }
    function loadChats() {
        const pid = projectId;
        Claude.run(["chats", pid], o => { if (win.projectId === pid) win.chats = o.chats || []; });
    }
    function openChat(c) { showChat(projectId, c.id); withSysinfo = false; input.forceActiveFocus(); }
    function newChat() { showChat(projectId, ""); withSysinfo = projectId === "system"; input.forceActiveFocus(); }
    function sendNow() {
        if (!canSend || !proj) return;
        const text = input.text, sys = withSysinfo, imgs = attachments.map(a => a.path);
        const go = () => { chat.send(text, sys, imgs); input.text = ""; win.attachments = []; win.attachNote = ""; win.withSysinfo = false; };
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
    // ---- usage ----
    function tokens(n) { return n >= 1000000 ? (n / 1000000).toFixed(1) + "M" : n >= 1000 ? Math.round(n / 1000) + "K" : String(n); }
    readonly property string usageText: {
        const parts = [], c = chat.context, u = chat.usage;
        if (c && c.used) parts.push("Context " + tokens(c.used) + (c.window ? " / " + tokens(c.window) + " (" + Math.round(c.used / c.window * 100) + "%)" : ""));
        if (u && u.cost) parts.push("$" + Number(u.cost).toFixed(u.cost < 0.1 ? 3 : 2) + " this chat");
        return parts.join("   ·   ");
    }

    // ---- right-click menus (DataApp.DMenu); menuCtx says what the picked entry acts on ----
    property var menuCtx: null
    function popMenu(items, from, x, y, c) {
        menuCtx = c;
        ctx.items = items;
        const p = from.mapToItem(ui, x, y);
        ctx.popup(p.x, p.y);
    }
    function copy(t) { if (t) Quickshell.execDetached(["wl-copy", "--", t]); }
    function conversationText() {
        const out = [];
        for (let i = 0; i < chat.items.count; i++) {
            const it = chat.items.get(i);
            if (it.k === "user") out.push("**You:** " + it.text);
            else if (it.k === "claude") out.push("**Claude:** " + it.text);
            else if (it.k === "tool") out.push("`" + it.name + "` " + it.summary);
        }
        return out.join("\n\n");
    }
    function itemMenu(item, x, y, link) {
        const sel = item.selection(), items = [];
        if (item.k === "tool") {
            if (sel) items.push({ id: "copysel", label: "Copy", hint: "Ctrl+C" });
            items.push({ id: "copycmd", label: "Copy command" },
                       { id: "copyout", label: "Copy output", disabled: item.out === "" },
                       { id: "toggle", label: item.open ? "Hide output" : "Show output", disabled: item.out === "" });
        } else if (item.k === "note") {
            items.push({ id: "copymsg", label: "Copy note" });
        } else {
            items.push({ id: "copysel", label: "Copy", hint: "Ctrl+C", disabled: !sel },
                       { id: "copymsg", label: "Copy message" });
            if (link) items.push({ id: "copylink", label: "Copy link" }, { id: "openlink", label: "Open link" });
            items.push({ kind: "sep" },
                       { id: "quote", label: sel ? "Quote selection in reply" : "Quote in reply" },
                       { id: "selall", label: "Select all", hint: "Ctrl+A" });
        }
        items.push({ kind: "sep" }, { id: "copyall", label: "Copy conversation" });
        popMenu(items, item, x, y, { item: item, sel: sel, link: link });
    }
    function backgroundMenu(x, y) {
        Qt.callLater(() => {
            if (ctx.visible) return;        // a message's own menu took this click
            popMenu([{ id: "newchat", label: "New chat", hint: "Ctrl+N" },
                     { id: "copyall", label: "Copy conversation", disabled: chat.items.count === 0 }], convoArea, x, y, {});
        });
    }
    function inputMenu(x, y) {
        const sel = input.selectedText !== "";
        popMenu([{ id: "undo", label: "Undo", hint: "Ctrl+Z", disabled: !input.canUndo },
                 { id: "redo", label: "Redo", hint: "Ctrl+Shift+Z", disabled: !input.canRedo },
                 { kind: "sep" },
                 { id: "cut", label: "Cut", hint: "Ctrl+X", disabled: !sel },
                 { id: "copyin", label: "Copy", hint: "Ctrl+C", disabled: !sel },
                 { id: "paste", label: "Paste", hint: "Ctrl+V" },
                 { id: "delete", label: "Delete", hint: "Del", disabled: !sel },
                 { kind: "sep" },
                 { id: "selallin", label: "Select all", hint: "Ctrl+A", disabled: input.length === 0 },
                 { kind: "sep" },
                 { id: "send", label: "Send", hint: "Enter", disabled: !win.canSend }], input, x, y, { input: true });
    }
    function projectMenu(row, p, x, y) {
        popMenu([{ id: "projnew", label: "New chat" },
                 { id: "projedit", label: "Edit project" },
                 { id: "projshow", label: "Show in DATA" },
                 { kind: "sep" },
                 { id: "copypath", label: "Copy folder path" }], row, x, y, { project: p });
    }
    function chatMenu(row, c, x, y) {
        popMenu([{ id: "chatopen", label: "Open", disabled: c.id === chat.chatId },
                 { id: "chatrename", label: "Rename" },
                 { id: "copytitle", label: "Copy title" },
                 { kind: "sep" },
                 { id: "chatremove", label: "Remove" }], row, x, y, { chat: c });
    }
    function menuPicked(id) {
        const c = menuCtx || {};
        menuCtx = null;
        if (id.startsWith("acc:")) { useAccount(id.substring(4)); return; }
        switch (id) {
        case "copysel": copy(c.sel); break;
        case "copymsg": copy(c.item.text); break;
        case "copycmd": copy(c.item.summary); break;
        case "copyout": copy(c.item.out); break;
        case "toggle": c.item.open = !c.item.open; break;
        case "copylink": copy(c.link); break;
        case "openlink": Qt.openUrlExternally(c.link); break;
        case "selall": c.item.selectAll(); break;
        case "quote": {
            const q = (c.sel || c.item.text).trim().split("\n").map(l => "> " + l).join("\n");
            input.text = (input.text.trim() !== "" ? input.text.replace(/\s+$/, "") + "\n\n" : "") + q + "\n\n";
            input.forceActiveFocus();
            input.cursorPosition = input.length;
            break;
        }
        case "copyall": copy(conversationText()); break;
        case "newchat": newChat(); break;
        case "accounts": overlay = "accounts"; break;
        case "undo": input.undo(); break;
        case "redo": input.redo(); break;
        case "cut": input.cut(); break;
        case "copyin": input.copy(); break;
        case "paste": pasteAny(); break;
        case "delete": input.remove(input.selectionStart, input.selectionEnd); break;
        case "selallin": input.selectAll(); break;
        case "send": sendNow(); break;
        case "projnew": selectProject(c.project.id); break;
        case "projedit": editProject(c.project); break;
        case "projshow": showFolder(c.project.dir); break;
        case "copypath": copy(c.project.dir); break;
        case "chatopen": openChat(c.chat); break;
        case "chatrename": target = c.chat; overlay = "rename"; break;
        case "copytitle": copy(c.chat.title); break;
        case "chatremove": target = c.chat; overlay = "rmchat"; break;
        }
        if (c.input) input.forceActiveFocus();
    }

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

    function doClose() {
        closing = true;
        for (const b of background) b.stopProc();
        chat.stopProc(); visible = false; Claude.closeWin();
    }
    onClosed: if (!closing) doClose()

    Shortcut { sequences: ["Ctrl+N"]; enabled: win.overlay === ""; onActivated: win.newChat() }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.doClose() }
    Shortcut { sequences: ["Escape"]; enabled: win.overlay === "" && chat.busy; onActivated: chat.interrupt() }

    // ================================================================ UI
    Rectangle {
        id: ui
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
                        MouseArea { id: accMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mouse => win.accountMenu(accMa, mouse.x, mouse.y) }
                    }
                    UsageMeters {
                        Layout.fillWidth: true
                        visible: !!win.accountStatus.loggedIn
                        usage: Claude.usage[win.accountId] || null
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
                            id: projRow
                            required property var modelData
                            width: ListView.view.width
                            text: modelData.name
                            sub: modelData.builtin ? "TROUBLESHOOT · SYSTEM" : win.tilde(modelData.dir)
                            selected: modelData.id === win.projectId
                            onClicked: if (modelData.id !== win.projectId) win.selectProject(modelData.id)
                            onMenu: (x, y) => win.projectMenu(projRow, modelData, x, y)
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
                            id: chatRow
                            required property var modelData
                            width: ListView.view.width
                            text: modelData.title || "Chat"
                            readonly property string running: win.chatState(win.projectId, modelData.id)
                            sub: (running !== "" ? running.toUpperCase() + " · " : "") + win.when(modelData.updated)
                                 + (modelData.account && modelData.account !== win.proj.account
                                    ? " · " + (Claude.accountName(modelData.account) || "removed account").toUpperCase() : "")
                            selected: modelData.id === chat.chatId
                            actions: true
                            onClicked: win.openChat(modelData)
                            onRename: { win.target = modelData; win.overlay = "rename"; }
                            onRemove: { win.target = modelData; win.overlay = "rmchat"; }
                            onMenu: (x, y) => win.chatMenu(chatRow, modelData, x, y)
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
                            ChamferButton { implicitHeight: 30; text: "Show in DATA"; visible: !!win.proj; onClicked: win.showFolder(win.proj.dir) }
                            ChamferButton { implicitHeight: 30; text: "Project"; onClicked: win.editProject(win.proj) }
                            ChamferButton { implicitHeight: 30; text: "New chat"; onClicked: win.newChat() }
                        }
                    }

                    // the conversation
                    Item {
                        id: convoArea
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: pt => win.backgroundMenu(pt.position.x, pt.position.y)
                        }

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
                                id: chatItem
                                required property var model
                                width: convo.width - 14
                                k: model.k; text: model.text; name: model.name; summary: model.summary
                                status: model.status; out: model.out; kind: model.kind; sysinfo: model.sysinfo; images: model.images
                                onMenu: (x, y, link) => win.itemMenu(chatItem, x, y, link)
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
                        Layout.preferredHeight: Math.min(Math.max(input.contentHeight + 24, 48), 220) + 46 + strip.height
                        color: Theme.panel
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }

                        // images going with the next message, and why one couldn't be attached
                        Item {
                            id: strip
                            x: 14; y: 12; width: parent.width - 28
                            height: win.attachments.length > 0 || win.attachNote !== "" ? stripRow.height + 10 : 0
                            visible: height > 0
                            Row {
                                id: stripRow
                                spacing: 8
                                Repeater {
                                    model: win.attachments
                                    Rectangle {
                                        id: thumb
                                        required property var modelData
                                        required property int index
                                        width: 84; height: 64
                                        color: Theme.bg1; border.width: 1; border.color: Theme.lineStrong
                                        Image {
                                            anchors.fill: parent; anchors.margins: 1
                                            source: "file://" + thumb.modelData.path
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize.width: 168; asynchronous: true
                                        }
                                        Rectangle {
                                            anchors.right: parent.right; anchors.top: parent.top
                                            width: 20; height: 20
                                            color: rmHover.hovered ? Theme.bad : Qt.rgba(0, 0, 0, 0.6)
                                            Text {
                                                anchors.centerIn: parent; text: "×"
                                                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                                            }
                                            HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: win.removeAttachment(thumb.index) }
                                        }
                                    }
                                }
                                Text {
                                    visible: win.attachNote !== ""
                                    height: 64; verticalAlignment: Text.AlignVCenter
                                    text: win.attachNote
                                    color: Theme.bad; font.family: Theme.mono; font.pixelSize: 11
                                }
                            }
                        }

                        // image files dropped on the composer attach like pasted ones
                        DropArea {
                            anchors.fill: parent
                            keys: ["text/uri-list"]
                            onDropped: drop => {
                                for (const u of drop.urls) {
                                    const f = decodeURIComponent(String(u).replace(/^file:\/\//, ""));
                                    Claude.run(["add-image", f], o => win.addAttachment(o));
                                }
                                drop.accept();
                            }
                        }

                        Rectangle {
                            id: box
                            x: 14; y: 12 + strip.height; width: parent.width - 28; height: parent.height - 52 - strip.height
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
                                    ContextMenu.menu: null      // ours below, in the app's style
                                    Keys.onPressed: e => {
                                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                            win.sendNow(); e.accepted = true;
                                        } else if ((e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.ShiftModifier))
                                                   || (e.key === Qt.Key_Insert && (e.modifiers & Qt.ShiftModifier))) {
                                            win.pasteAny(); e.accepted = true;
                                        } else if (e.key === Qt.Key_Backspace && input.length === 0 && win.attachments.length > 0) {
                                            win.removeAttachment(win.attachments.length - 1); e.accepted = true;
                                        } else if (e.key === Qt.Key_Menu || (e.key === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier))) {
                                            const r = input.cursorRectangle;
                                            win.inputMenu(r.x, r.y + r.height); e.accepted = true;
                                        }
                                    }
                                    // right-click: keep a selection the click lands in, otherwise move the caret there first
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: pt => {
                                            const pos = input.positionAt(pt.position.x, pt.position.y);
                                            if (input.selectionStart === input.selectionEnd || pos < input.selectionStart || pos > input.selectionEnd)
                                                input.cursorPosition = pos;
                                            input.forceActiveFocus();
                                            win.inputMenu(pt.position.x, pt.position.y);
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
                                text: [chat.info, win.usageText, chat.limit].filter(s => s !== "").join("   ·   ").toUpperCase()
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
        DataApp.DMenu {
            id: ctx
            onPicked: id => win.menuPicked(id)
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
                                else {
                                    const b = win.background.find(x => x.projectId === win.projectId && x.chatId === c.id);
                                    if (b) { win.stopChat(b); win.letGo(b); }
                                    if (chat.chatId === c.id) { win.stopChat(chat); win.newChat(); }
                                    Claude.run(["chat-remove", win.projectId, c.id], () => win.loadChats());
                                }
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
