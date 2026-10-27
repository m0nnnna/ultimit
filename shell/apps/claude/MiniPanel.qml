// MiniPanel.qml - CLAUDE in the bottom-right corner: a small chat above the bottom bar, opened from the
// Claude button in the tray cluster (StatusTray.qml -> ultimit-claude --mini). It talks to one project
// ("This PC" unless a project is picked from its header menu); EXPAND carries the chat, still running,
// into the full window (Claude.expand -> ClaudeWindow.adopt). Hiding it leaves a working chat running.
// A layer-shell panel, so it sits above windows without a frame or a taskbar entry. Created by ClaudeApp.qml.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../.."
import "../accessory"

PanelWindow {
    id: win

    screen: Quickshell.screens.find(s => s.name === Claude.miniScreen) || Quickshell.screens[0] || null
    anchors { right: true; bottom: true }
    margins { right: 12; bottom: 30 + 12 }   // above the bottom bar (Config.tickerHeight in the desktop shell)
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 440
    implicitHeight: 620
    color: "transparent"
    visible: Claude.miniShown
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ultimit-claude-mini"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property string projectId: "system"
    readonly property var proj: Claude.project(projectId) || (Claude.projects.length ? Claude.projects[0] : null)
    readonly property bool ready: Claude.cliPath !== "" && Claude.accounts.length > 0
    property ChatSession chat: null
    readonly property bool canSend: ready && chat !== null && !chat.busy && !chat.loading && input.text.trim() !== ""

    // Its chats live in `keep`, not in the views, so EXPAND can hand one over (the panel itself is kept once
    // made, see ClaudeApp.qml; the full window lets a handed-over chat go when it is done with it).
    Item { id: keep; visible: false }
    Component { id: chatC; ChatSession {} }
    function fresh() {
        const c = chatC.createObject(keep);
        c.done.connect(() => Claude.maybeQuit());
        c.load(projectId, "");
        chat = c;
    }
    function newChat() {
        const prev = chat;
        fresh();
        if (prev) { prev.stopProc(); prev.destroy(); }
        input.forceActiveFocus();
    }
    function pickProject(id) { if (id === projectId) return; projectId = id; newChat(); }
    function expand() {
        const c = chat;
        fresh();
        Claude.expand(c, input.text);
        input.text = "";
    }
    function sendNow() {
        if (!canSend || !proj) return;
        if (chat.chatId === "" && !Claude.account(proj.account)) chat.account = Claude.accountFor(proj);
        // "This PC": the system summary goes with a chat's first message, as in the full window
        chat.send(input.text, projectId === "system" && chat.items.count === 0, []);
        input.text = "";
    }
    readonly property bool working: chat !== null && chat.working
    onWorkingChanged: Claude.miniWorking = working

    Component.onCompleted: fresh()
    onVisibleChanged: if (visible) input.forceActiveFocus()
    Connections {
        target: Claude
        function onMiniRaiseChanged() { input.forceActiveFocus(); }
    }

    Shortcut { sequences: ["Escape"]; onActivated: if (win.chat && win.chat.busy) win.chat.interrupt(); else Claude.hideMini() }

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        // ---- header: CLAUDE · project, new chat, expand, close ----
        Rectangle {
            id: head
            width: parent.width; height: 40
            color: "transparent"
                        Rectangle { width: 3; height: parent.height; color: Theme.accent }
            Text {
                id: title
                x: 14; anchors.verticalCenter: parent.verticalCenter
                text: "CLAUDE"
                color: Theme.accent; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2
            }
            SmallLink {
                anchors.left: title.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 160); elide: Text.ElideRight
                text: (win.proj ? win.proj.name : "").toUpperCase() + " ▾"
                onClicked: projMenu.visible = !projMenu.visible
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                SmallLink { text: "NEW"; onClicked: win.newChat() }
                SmallLink { text: "EXPAND ⤢"; onClicked: win.expand() }
                SmallLink { text: "✕"; onClicked: Claude.hideMini() }
            }
        }

        // ---- the conversation ----
        Item {
            id: convoArea
            anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: askBox.top }
            clip: true

            ListView {
                id: convo
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 6
                topMargin: 12; bottomMargin: 12
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: win.chat ? win.chat.items : null
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                property bool stick: true
                onMovementEnded: stick = atYEnd
                onContentHeightChanged: if (stick) Qt.callLater(positionViewAtEnd)
                onCountChanged: if (stick) Qt.callLater(positionViewAtEnd)
                delegate: ChatItem {
                    required property var model
                    width: convo.width - 10
                    k: model.k; text: model.text; name: model.name; summary: model.summary
                    status: model.status; out: model.out; kind: model.kind; sysinfo: model.sysinfo; images: model.images
                }
                footer: Column {
                    width: convo.width - 10
                    spacing: 8
                    topPadding: win.chat && win.chat.items.count ? 8 : 0
                    ChatItem {
                        width: parent.width
                        visible: !!win.chat && win.chat.liveText !== ""
                        k: "claude"; text: win.chat ? win.chat.liveText : ""; streaming: true
                    }
                    Text {
                        visible: !!win.chat && win.chat.busy && win.chat.liveText === ""
                        text: !win.chat ? "" : (win.chat.thinking ? "THINKING" : win.chat.statusText !== "" ? win.chat.statusText.toUpperCase() : "WORKING") + dots.s
                        width: parent.width; elide: Text.ElideRight
                        color: Theme.accent; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
                        Timer {
                            id: dots
                            property string s: ""
                            interval: 400; repeat: true; running: !!win.chat && win.chat.busy
                            onTriggered: s = s.length >= 3 ? "" : s + "."
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 8
                visible: !!win.chat && win.chat.items.count === 0 && !win.chat.busy
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: !win.ready ? "CLAUDE ISN'T SET UP YET" : win.projectId === "system" ? "WHAT'S UP WITH THIS PC?" : "NEW CHAT"
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: !win.ready ? "Open the full window (EXPAND) to install Claude Code and sign in."
                        : win.projectId === "system" ? "Ask anything about this PC. EXPAND opens this chat in the full window."
                        : "Claude works in " + (win.proj ? win.proj.dir : "") + ". EXPAND opens this chat in the full window."
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: Theme.type.body
                }
            }
        }

        // ---- a permission request ----
        Rectangle {
            id: askBox
            anchors { left: parent.left; right: parent.right; bottom: composer.top }
            height: win.chat && win.chat.ask ? askCol.implicitHeight + 20 : 0
            visible: height > 0
            color: Theme.panel
            
            Rectangle { width: 3; height: parent.height; color: Theme.warn }
            Column {
                id: askCol
                x: 14; y: 10; width: parent.width - 28
                spacing: 6
                readonly property bool isQuestion: !!win.chat && !!win.chat.ask && !!win.chat.ask.questions && win.chat.ask.questions.length > 0
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: askCol.isQuestion ? "CLAUDE HAS A QUESTION" + (win.chat.askQueue.length ? "   (+" + win.chat.askQueue.length + " MORE)" : "")
                          : win.chat && win.chat.ask ? ("Claude wants to use " + win.chat.ask.tool).toUpperCase()
                          + (win.chat.askQueue.length ? "   (+" + win.chat.askQueue.length + " MORE)" : "") : ""
                    color: Theme.warn; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
                }
                QuestionPanel {
                    visible: askCol.isQuestion
                    width: parent.width; compact: true
                    ask: askCol.isQuestion ? win.chat.ask : null
                    onAnswered: a => win.chat.answer(a)
                    onSkipped: win.chat.permit(false, false)
                }
                Text {
                    visible: !askCol.isQuestion
                    width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: 4; elide: Text.ElideRight
                    text: win.chat && win.chat.ask ? win.chat.ask.summary : ""
                    color: Theme.fg; font.family: Theme.mono; font.pixelSize: Theme.type.label
                }
                Row {
                    visible: !askCol.isQuestion
                    spacing: 8
                    ChamferButton { implicitHeight: 28; text: "Allow"; primary: true; onClicked: win.chat.permit(true, false) }
                    ChamferButton { implicitHeight: 28; text: "Always"; visible: !!win.chat && !!win.chat.ask && win.chat.ask.always; onClicked: win.chat.permit(true, true) }
                    ChamferButton { implicitHeight: 28; text: "Deny"; onClicked: win.chat.permit(false, false) }
                }
            }
        }

        // ---- composer ----
        Rectangle {
            id: composer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.min(Math.max(input.contentHeight + 22, 44), 160) + 40
            color: "transparent"
                        Rectangle {
                x: 12; y: 10; width: parent.width - 24; height: parent.height - 50
                color: Theme.field
                border.width: input.activeFocus ? 1 : 0; border.color: Theme.accent
                ScrollView {
                    anchors.fill: parent; anchors.margins: 1
                    TextArea {
                        id: input
                        wrapMode: TextArea.Wrap
                        background: null
                        padding: 9
                        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                        placeholderText: win.projectId === "system" ? "Ask about this PC…" : "Ask Claude about " + (win.proj ? win.proj.name : "this project") + "…"
                        placeholderTextColor: Theme.dim
                        font.family: Theme.ui; font.pixelSize: Theme.type.body
                        enabled: win.ready
                        Keys.onPressed: e => {
                            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                win.sendNow(); e.accepted = true;
                            }
                        }
                    }
                }
            }
            Text {
                x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                width: parent.width - 150; elide: Text.ElideRight
                text: win.chat ? [win.chat.info, win.chat.limit].filter(s => s !== "").join("  ·  ").toUpperCase() : ""
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.2
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                spacing: 8
                ChamferButton { implicitHeight: 28; text: "Stop"; visible: !!win.chat && win.chat.busy; onClicked: win.chat.interrupt() }
                ChamferButton { implicitHeight: 28; text: "Send"; primary: win.canSend; onClicked: win.sendNow() }
            }
        }

        // ---- the project menu (header) ----
        Rectangle {
            id: projMenu
            visible: false
            x: 60; y: head.height - 2
            width: 240; height: Math.min(projCol.implicitHeight + 8, 300)
            color: Theme.bg1
            Flickable {
                anchors.fill: parent; anchors.margins: 4
                contentHeight: projCol.implicitHeight; clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: projCol
                    width: parent.width
                    Repeater {
                        model: Claude.projects
                        Rectangle {
                            required property var modelData
                            width: projCol.width; height: 32
                            color: pHover.hovered ? Theme.accent : Theme.clear(Theme.accent)
                            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                            Text {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 20; elide: Text.ElideRight
                                text: (modelData.id === win.projectId ? "✓ " : "") + modelData.name
                                color: pHover.hovered ? Theme.onAccent : Theme.fg
                                font.family: Theme.ui; font.pixelSize: Theme.type.body
                            }
                            HoverHandler { id: pHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { projMenu.visible = false; win.pickProject(modelData.id); } }
                        }
                    }
                }
            }
        }
    }
}
