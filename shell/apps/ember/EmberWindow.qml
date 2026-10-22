// EmberWindow.qml - the EMBER window: Ember herself on the left (her animated portrait, what she is
// doing, the AI she thinks with, your chats), the conversation on the right. She can run commands,
// read and write files, open apps, files and web pages, manage windows, search and read the web and
// use the clipboard; commands, file writes and closing windows wait for your Allow unless you let her
// act without asking (Settings). A normal xdg toplevel (the compositor draws the frame). Created by
// EmberApp.qml.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../.."
import "../accessory"
import "../claude" as C
import "../data" as DataApp

FloatingWindow {
    id: win

    title: (chatTitle !== "" ? chatTitle + " — " : "") + "EMBER"
    implicitWidth: 1160
    implicitHeight: 800
    minimumSize: Config.mobile ? Qt.size(0, 0) : Qt.size(820, 560)
    color: "transparent"
    visible: true

    property string overlay: ""         // "", "settings", "rename", "rmchat"
    property var target: null           // the chat being renamed / removed
    property bool closing: false

    // ================================================================ the chat on screen
    property string chatId: ""
    property bool mobileList: true      // phone: the Ember + chat list, or the conversation
    property string chatTitle: ""
    property bool busy: false
    property bool loading: false
    property string liveText: ""
    property string tool: ""            // the tool running now
    property var ask: null              // { id, name, summary, detail }
    property var proc: null
    property int talk: 0
    property bool speaking: false
    property string flash: ""           // "happy" / "error" for a moment after a turn
    property var usage: ({ input: 0, output: 0 })
    ListModel { id: items }

    readonly property string mood: ask !== null ? "asking"
                                 : busy ? (tool !== "" ? "working" : speaking ? "speaking" : "thinking")
                                 : flash !== "" ? flash : "idle"
    readonly property string moodText: !Ember.loaded ? "WAKING"
        : !Ember.ready && !busy ? "PLUG IN AN AI TO BEGIN"
        : ({ asking: "AWAITING YOUR WORD", working: "WORKING · " + tool.replace(/_/g, " ").toUpperCase(),
             speaking: "SPEAKING", thinking: "THINKING", happy: "NOT THAT I CARE", error: "...THAT WASN'T MY FAULT",
             idle: "WHAT DO YOU WANT" })[mood]
    readonly property bool canSend: Ember.ready && !busy && !loading && input.text.trim() !== ""

    Timer { id: speakTimer; interval: 450; onTriggered: win.speaking = false }
    Timer { id: flashTimer; interval: 2600; onTriggered: win.flash = "" }
    function setFlash(f) { flash = f; flashTimer.restart(); }

    function add(o) {
        items.append({ k: o.k || "note", text: o.text || "", name: o.name || "", summary: o.summary || "",
                       status: o.status || "", out: o.out || "", tid: o.id || "", kind: o.kind || "" });
    }
    function commitLive() { if (liveText !== "") { add({ k: "ember", text: liveText }); liveText = ""; } }
    function toolDone(id, ok, out) {
        for (let i = items.count - 1; i >= 0; i--) {
            if (items.get(i).k === "tool" && items.get(i).tid === id) {
                items.setProperty(i, "status", ok ? "ok" : "error");
                items.setProperty(i, "out", out || "");
                return;
            }
        }
    }

    function onEvent(o) {
        switch (o.ev) {
        case "chat": chatId = o.id; chatTitle = o.title; Ember.loadChats(); break;
        case "busy": busy = true; break;
        case "thinking": break;
        case "working": commitLive(); tool = o.name; break;
        case "text": liveText += o.delta; talk++; speaking = true; speakTimer.restart(); break;
        case "tool": commitLive(); tool = o.name; add({ k: "tool", id: o.id, name: o.name, summary: o.summary, status: "run" }); break;
        case "tool_done": toolDone(o.id, o.ok, o.out); tool = ""; break;
        case "ask": ask = o; win.requestActivate(); break;
        case "note": commitLive(); add({ k: "note", kind: o.kind, text: o.text }); break;
        case "error": commitLive(); add({ k: "note", kind: "error", text: o.text }); setFlash("error"); break;
        case "usage": usage = { input: usage.input + (o.input || 0), output: usage.output + (o.output || 0) }; break;
        case "done":
            commitLive();
            const ok = flash !== "error" && o.stop === "";
            busy = false; ask = null; tool = ""; speaking = false;
            if (ok) setFlash("happy");
            Ember.loadChats();
            break;
        }
    }
    function stopProc() { if (proc) { proc.onEvent = null; proc.running = false; proc = null; } }
    function send(text) {
        if (!proc) proc = Ember.stream(chatId !== "" ? ["session", chatId] : ["session"], o => win.onEvent(o));
        add({ k: "user", text: text });
        busy = true; flash = "";
        proc.send({ type: "send", text: text });
    }
    function sendNow() {
        if (!canSend) return;
        send(input.text.trim());
        input.text = "";
    }
    function interrupt() { if (proc && busy) proc.send({ type: "stop" }); }
    function permit(allow, always) {
        if (!ask || !proc) return;
        proc.send({ type: "permit", id: ask.id, allow: allow, always: always });
        ask = null;
    }
    function reset() {
        stopProc();
        items.clear(); liveText = ""; tool = ""; ask = null; busy = false; flash = ""; usage = { input: 0, output: 0 };
    }
    function newChat() { reset(); chatId = ""; chatTitle = ""; mobileList = false; input.forceActiveFocus(); }
    function openChat(id) {
        if (id === chatId && !loading) { mobileList = false; return; }
        mobileList = false;
        reset();
        chatId = id; chatTitle = ""; loading = true;
        Ember.run(["chat", id], o => {
            if (win.chatId !== id) return;
            win.loading = false;
            if (!o.ok) { win.add({ k: "note", kind: "error", text: o.err }); return; }
            win.chatTitle = o.title;
            for (const it of o.items) win.add(it);
        });
        input.forceActiveFocus();
    }

    // ---- menus ----
    property var menuCtx: null
    function popMenu(list, from, x, y, c) {
        menuCtx = c;
        ctx.items = list;
        const pt = from.mapToItem(ui, x, y);
        ctx.popup(pt.x, pt.y);
    }
    function copy(t) { if (t) Quickshell.execDetached(["wl-copy", "--", t]); }
    function providerMenu(from, x, y) {
        const list = Ember.providers.map(p => ({
            id: "prov:" + p.id,
            label: p.name + (p.model !== "" ? "  ·  " + p.model : ""),
            hint: p.id === Ember.provider ? "✓" : Ember.usable(p) ? "" : "set up",
            disabled: !Ember.usable(p) }));
        list.push({ kind: "sep" }, { id: "settings", label: "Settings…" });
        popMenu(list, from, x, y, {});
    }
    function itemMenu(item, x, y, link) {
        const sel = item.selection(), list = [];
        if (sel) list.push({ id: "copysel", label: "Copy", hint: "Ctrl+C" });
        if (item.k === "tool") list.push({ id: "copycmd", label: "Copy " + (item.name === "run_command" ? "command" : "details") },
                                         { id: "copyout", label: "Copy output", disabled: item.out === "" });
        else list.push({ id: "copymsg", label: "Copy message" });
        if (link) list.push({ id: "openlink", label: "Open link" }, { id: "copylink", label: "Copy link" });
        popMenu(list, item, x, y, { item: item, sel: sel, link: link });
    }
    function chatMenu(row, c, x, y) {
        popMenu([{ id: "rename", label: "Rename…" }, { id: "remove", label: "Remove…" }], row, x, y, { chat: c });
    }
    function menuPicked(id) {
        const c = menuCtx || {};
        menuCtx = null;
        if (id.startsWith("prov:")) { Ember.use(id.substring(5)); return; }
        switch (id) {
        case "settings": overlay = "settings"; break;
        case "copysel": copy(c.sel); break;
        case "copymsg": copy(c.item.text); break;
        case "copycmd": copy(c.item.summary); break;
        case "copyout": copy(c.item.out); break;
        case "openlink": Qt.openUrlExternally(c.link); break;
        case "copylink": copy(c.link); break;
        case "rename": target = c.chat; overlay = "rename"; break;
        case "remove": target = c.chat; overlay = "rmchat"; break;
        }
    }
    function when(t) {
        const d = new Date(t * 1000), now = new Date();
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "hh:mm");
        if (now - d < 6 * 86400000) return Qt.formatDate(d, "ddd");
        return Qt.formatDate(d, "d MMM");
    }

    Connections {
        target: Ember
        function onRaiseChanged() {
            if (Ember.wantText !== "") { input.text = Ember.wantText; Ember.wantText = ""; mobileList = false; }
            input.forceActiveFocus();
        }
        function onLoadedChanged() { if (Ember.loaded && !Ember.ready) win.overlay = "settings"; }
    }
    Component.onCompleted: {
        if (Ember.wantText !== "") { input.text = Ember.wantText; Ember.wantText = ""; mobileList = false; }
        if (Ember.loaded && !Ember.ready) overlay = "settings";
        input.forceActiveFocus();
    }

    function doClose() { closing = true; stopProc(); visible = false; Ember.closeWin(); }
    onClosed: if (!closing) doClose()

    Shortcut { sequences: ["Ctrl+N"]; enabled: win.overlay === ""; onActivated: win.newChat() }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.doClose() }
    Shortcut { sequences: ["Ctrl+,"]; onActivated: win.overlay = "settings" }
    Shortcut { sequences: ["Escape"]; enabled: win.overlay === "" && win.busy; onActivated: win.interrupt() }

    // ================================================================ UI
    Rectangle {
        id: ui
        anchors.fill: parent
        color: Theme.panel

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---------------------------------------------------- Ember
            Rectangle {
                Layout.fillHeight: true; Layout.preferredWidth: Config.mobile ? ui.width : 380
                visible: !Config.mobile || win.mobileList
                color: Theme.panel
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; anchors.rightMargin: 15
                    spacing: 8

                    EmberFace {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(width * 1.25, win.height * (Config.mobile ? 0.34 : 0.6))
                        mood: win.mood
                        talk: win.talk
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "[ EMBER ]"
                        color: Theme.fg; font.family: Theme.display; font.pixelSize: 15; font.letterSpacing: 3
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter; Layout.topMargin: -4
                        text: win.moodText + (win.busy && win.mood !== "asking" ? dots.s : "")
                        color: win.mood === "asking" ? Theme.warn : win.mood === "error" ? Theme.bad : Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                        Timer {
                            id: dots
                            property string s: ""
                            interval: 400; repeat: true; running: win.busy
                            onTriggered: s = s.length >= 3 ? "" : s + "."
                        }
                    }

                    // the AI she thinks with
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 46; Layout.topMargin: 4
                        color: provMa.containsMouse ? Theme.panel2 : "transparent"
                        border.width: 1; border.color: Theme.lineStrong
                        Rectangle {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: Ember.ready ? Theme.ok : Theme.warn
                        }
                        Column {
                            x: 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: Ember.current ? Ember.current.name + "  ·  " + Ember.current.maker : "…"
                                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width; elide: Text.ElideMiddle
                                text: Ember.current && Ember.current.model !== "" ? Ember.current.model.toUpperCase() : "NO MODEL PICKED"
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
                            }
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            text: "▾"; color: Theme.dim; font.pixelSize: 12
                        }
                        MouseArea { id: provMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => win.providerMenu(provMa, mouse.x, mouse.y) }
                    }

                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 6
                        SectionLabel { text: "Chats"; Layout.fillWidth: true }
                        C.SmallLink { visible: !Config.mobile; text: "+ NEW"; onClicked: win.newChat() }
                    }
                    RowLayout {
                        visible: Config.mobile
                        Layout.fillWidth: true; spacing: 8
                        ChamferButton { Layout.fillWidth: true; implicitHeight: 40; text: "New chat"; onClicked: win.newChat() }
                        ChamferButton { Layout.fillWidth: true; implicitHeight: 40; text: "Settings"; onClicked: win.overlay = "settings" }
                    }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: Ember.chats
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: C.SideRow {
                            id: chatRow
                            required property var modelData
                            width: ListView.view.width
                            text: modelData.title || "Chat"
                            sub: win.when(modelData.updated) + (modelData.model ? " · " + modelData.model.toUpperCase() : "")
                            selected: modelData.id === win.chatId
                            actions: true
                            onClicked: win.openChat(modelData.id)
                            onRename: { win.target = modelData; win.overlay = "rename"; }
                            onRemove: { win.target = modelData; win.overlay = "rmchat"; }
                            onMenu: (x, y) => win.chatMenu(chatRow, modelData, x, y)
                        }
                        Text {
                            visible: Ember.chats.length === 0
                            width: parent.width; wrapMode: Text.Wrap
                            text: "No chats yet."
                            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                        }
                    }
                }
            }

            // ---------------------------------------------------- the conversation
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: !Config.mobile || !win.mobileList
                spacing: 0

                MobileBack { visible: Config.mobile; Layout.fillWidth: true; Layout.preferredHeight: 44
                             label: "Ember"; onBack: win.mobileList = true }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: Config.mobile ? 48 : 56
                    color: Theme.panel
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                    Text {
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - headBtns.width - 50; elide: Text.ElideRight
                        text: (win.chatTitle !== "" ? win.chatTitle : "New chat").toUpperCase()
                        color: Theme.fg; font.family: Theme.display; font.pixelSize: 13; font.letterSpacing: 2
                    }
                    Row {
                        id: headBtns
                        anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        ChamferButton { implicitHeight: Config.mobile ? 38 : 30; text: "New chat"; visible: !Config.mobile; onClicked: win.newChat() }
                        ChamferButton { implicitHeight: Config.mobile ? 38 : 30; text: "Settings"; onClicked: win.overlay = "settings" }
                    }
                }

                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: convo
                        anchors.fill: parent
                        anchors.leftMargin: 18; anchors.rightMargin: 8
                        topMargin: 16; bottomMargin: 16
                        spacing: 12
                        boundsBehavior: Flickable.StopAtBounds
                        model: items
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        property bool stick: true
                        onMovementEnded: stick = atYEnd
                        onContentHeightChanged: if (stick) Qt.callLater(positionViewAtEnd)
                        onCountChanged: if (stick) Qt.callLater(positionViewAtEnd)
                        delegate: EmberItem {
                            id: it
                            required property var model
                            width: convo.width - 14
                            k: model.k; text: model.text; name: model.name; summary: model.summary
                            status: model.status; out: model.out; kind: model.kind
                            onMenu: (x, y, link) => win.itemMenu(it, x, y, link)
                        }
                        footer: Column {
                            width: convo.width - 14
                            topPadding: items.count ? 12 : 0
                            EmberItem {
                                width: parent.width
                                visible: win.liveText !== ""
                                k: "ember"; text: win.liveText; streaming: true
                            }
                        }
                    }

                    // an empty chat: a greeting and a few things to try
                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 60, 540)
                        spacing: 14
                        visible: items.count === 0 && !win.busy && !win.loading
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: "OH. IT'S YOU."
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 2
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            text: Ember.ready
                                ? "Well? I can poke around this PC, open your apps, look things up and do the chores you can't be bothered with. I'll even ask before I change anything. Not that you deserve the courtesy."
                                : "Hmph. I can't think without a brain, dummy. Open Settings and plug in Claude, GPT, Grok or a local model."
                            color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                        }
                        Flow {
                            width: parent.width; spacing: 8
                            visible: Ember.ready
                            Repeater {
                                model: ["What's using my GPU right now?", "Open Steam", "What's the weather in my city?",
                                        "Which apps are open?", "Tidy my Downloads folder", "Why was my last session slow?"]
                                Rectangle {
                                    required property string modelData
                                    width: sug.implicitWidth + 22; height: 30
                                    color: sm.containsMouse ? Theme.panel2 : "transparent"
                                    border.width: 1; border.color: Theme.lineStrong
                                    Text { id: sug; anchors.centerIn: parent; text: parent.modelData; color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12 }
                                    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { input.text = parent.modelData; input.forceActiveFocus(); input.cursorPosition = input.length; } }
                                }
                            }
                        }
                        ChamferButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !Ember.ready
                            text: "Settings"; primary: true
                            onClicked: win.overlay = "settings"
                        }
                    }
                }

                // a permission request: Ember waits for your word
                Rectangle {
                    visible: win.ask !== null
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
                            text: win.ask ? ("Ember would like to " + ({ run_command: "run a command", write_file: "write a file",
                                                                         window: "close a window" })[win.ask.name] || win.ask.name).toUpperCase() : ""
                            color: Theme.warn; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.8
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: 6; elide: Text.ElideRight
                            text: win.ask ? win.ask.summary : ""
                            color: Theme.fg; font.family: Theme.mono; font.pixelSize: 13
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
                                    text: win.ask ? win.ask.detail : ""
                                    color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                                    font.family: Theme.mono; font.pixelSize: 11
                                }
                            }
                        }
                        Flow {
                            width: parent.width; spacing: 8
                            ChamferButton { implicitHeight: Config.mobile ? 40 : 34; text: "Allow"; primary: true; onClicked: win.permit(true, false) }
                            ChamferButton { implicitHeight: Config.mobile ? 40 : 34; text: Config.mobile ? "This chat" : "Allow for this chat"; onClicked: win.permit(true, true) }
                            ChamferButton { implicitHeight: Config.mobile ? 40 : 34; text: "Deny"; onClicked: win.permit(false, false) }
                            Item {
                                width: askMore.implicitWidth; height: Config.mobile ? 40 : 34
                                C.SmallLink {
                                    id: askMore
                                    property bool checked: false
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: checked ? "HIDE DETAILS" : "DETAILS"
                                    onClicked: checked = !checked
                                }
                            }
                        }
                    }
                }

                // composer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Math.max(input.contentHeight + 24, 48), 220) + (Config.mobile ? 54 : 46)
                    color: Theme.panel
                    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                    Rectangle {
                        x: 14; y: 12; width: parent.width - 28; height: parent.height - (Config.mobile ? 66 : 52)
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
                                placeholderText: Ember.ready ? "Ask Ember anything, or tell her what to do…" : "Plug in an AI in Settings first"
                                placeholderTextColor: Theme.dim
                                font.family: Theme.ui; font.pixelSize: 14
                                Keys.onPressed: e => {
                                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                        win.sendNow(); e.accepted = true;
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                        spacing: 14
                        Text {
                            text: Ember.trust ? "● ACTS WITHOUT ASKING" : "○ ASKS BEFORE ACTING"
                            color: Ember.trust ? Theme.warn : Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.overlay = "settings" }
                        }
                        Text {
                            visible: win.usage.input + win.usage.output > 0 && !Config.mobile
                            text: "TOKENS " + win.usage.input + " IN · " + win.usage.output + " OUT"
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
                            visible: !win.busy && !Config.mobile
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.2
                        }
                        ChamferButton { implicitHeight: Config.mobile ? 36 : 28; text: "Stop"; visible: win.busy; onClicked: win.interrupt() }
                        ChamferButton { implicitHeight: Config.mobile ? 36 : 28; text: "Send"; primary: win.canSend; onClicked: win.sendNow() }
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
            Loader {
                id: ov
                anchors.centerIn: parent
                width: Config.mobile ? parent.width - 24 : Math.min(parent.width - 40, win.overlay === "settings" ? 640 : 440)
                height: Math.min(parent.height - (Config.mobile ? 24 : 40), item ? item.implicitHeight : 0)
                active: win.overlay !== ""
                sourceComponent: win.overlay === "settings" ? settingsC : smallC
                onLoaded: item.forceActiveFocus()
            }
        }
        DataApp.DMenu {
            id: ctx
            onPicked: id => win.menuPicked(id)
        }

        Component {
            id: settingsC
            Flickable {
                implicitHeight: sp.implicitHeight
                contentHeight: sp.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
                Keys.onEscapePressed: win.overlay = ""
                SettingsPanel { id: sp; width: parent.width; host: win }
            }
        }
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
                        text: "Remove \"" + (win.target ? win.target.title : "") + "\"? It can't be brought back."
                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                    }
                    C.Entry {
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
                                if (win.overlay === "rename") {
                                    Ember.run(["chat-rename", c.id, nameEntry.text], () => Ember.loadChats());
                                    if (c.id === win.chatId) win.chatTitle = nameEntry.text;
                                } else {
                                    if (c.id === win.chatId) win.newChat();
                                    Ember.run(["chat-remove", c.id], () => Ember.loadChats());
                                }
                                win.overlay = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
