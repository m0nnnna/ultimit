// MemoWindow.qml - one MEMO document: a normal xdg toplevel (the compositor draws the frame).
// Created by MemoApp.qml through a Variants over Memo.ids.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../.."
import "../accessory"

FloatingWindow {
    id: win
    required property int docId

    // ---- document state ----
    property string path: ""
    property string eol: "lf"
    property bool bom: false
    property string stamp: ""
    property string savedText: ""
    property bool modified: false
    property bool loading: false
    property bool saving: false
    property bool closing: false
    property string banner: ""          // "", "changed", "deleted", or an error message (kind "error")
    property string bannerKind: ""
    property string overlay: ""         // "", "open", "saveas", "close"
    property bool closeAfterSave: false
    property string draftId: ""         // crash-recovery draft (see memo.py draft-*), "" until first needed
    property bool hasDraft: false
    property int line: 1
    property int col: 1
    property int lineCount: 1
    property var lineStarts: [0]
    property var gutterModel: []
    readonly property int untitledNo: Memo.untitledNos[docId] || 1
    readonly property string untitled: untitledNo <= 1 ? "Untitled" : "Untitled " + untitledNo
    readonly property string name: path === "" ? untitled : path.substring(path.lastIndexOf("/") + 1)

    title: (modified ? "● " : "") + name + " — MEMO"
    implicitWidth: 880
    implicitHeight: 620
    minimumSize: Qt.size(520, 360)
    color: "transparent"   // the Theme.panel glass below fills it
    visible: true

    // ---- find state ----
    property bool findOpen: false
    property bool replaceOpen: false
    property bool gotoOpen: false
    property bool matchCase: false
    property int matchCount: 0

    function publish() {
        Memo.setInfo(docId, { path: path, name: name, modified: modified, line: line, col: col, lines: lineCount,
                              chars: ta.length, overlay: overlay, banner: banner, eol: eol, find: findOpen });
    }
    onModifiedChanged: publish()
    onPathChanged: publish()
    onOverlayChanged: publish()
    onBannerChanged: publish()

    // ---- loading ----
    function showError(msg) { banner = msg; bannerKind = "error"; }
    function setText(t) {
        loading = true;
        ta.text = t;
        loading = false;
        savedText = t;
        modified = false;
        ta.cursorPosition = 0;
        rebuildLines();
    }
    function loadFile(p, quietMissing) {
        loading = true;
        Memo.run(["read", p], "", o => {
            loading = false;
            if (o.ok) {
                win.path = p; win.eol = o.eol; win.bom = o.bom; win.stamp = o.stamp;
                win.setText(o.text);
                win.banner = ""; win.bannerKind = "";
            } else if (o.missing && quietMissing) {
                win.path = p; win.stamp = ""; win.setText("");
            } else {
                win.showError("Cannot open " + p + ": " + o.err);
            }
        });
    }
    function reload() {
        const keep = ta.cursorPosition;
        Memo.run(["read", path], "", o => {
            if (o.ok) {
                win.eol = o.eol; win.bom = o.bom; win.stamp = o.stamp;
                win.setText(o.text);
                ta.cursorPosition = Math.min(keep, ta.length);
                win.banner = "";
            } else win.showError("Reload failed: " + o.err);
        });
    }
    Component.onCompleted: {
        const p = Memo.paths[docId] || "";
        draftId = Memo.draftIds[docId] || (Date.now() + "-" + docId);
        if (Memo.draftIds[docId]) recover();
        else if (p !== "") loadFile(p, true);
        else publish();
        Qt.callLater(() => ta.forceActiveFocus());
    }
    // ---- crash recovery ----
    function recover() {
        const meta = Memo.draftMeta[docId] || {};
        Memo.run(["draft-read", draftId], "", o => {
            if (!o.ok) { win.showError("Could not recover draft: " + o.err); return; }
            win.path = meta.path || ""; win.eol = meta.eol || "lf"; win.bom = !!meta.bom;
            win.hasDraft = true;
            win.loading = true; ta.text = o.text; win.loading = false;
            win.savedText = "\u0000recovered";      // never equal to the text: stays modified until saved
            win.modified = true;
            ta.cursorPosition = 0;
            win.rebuildLines();
            win.banner = "recovered"; win.bannerKind = "info";
            if (win.path !== "") Memo.run(["stat", win.path], "", s => { if (s.ok) win.stamp = s.stamp; });
        });
    }
    function dropDraft() {
        draftTimer.stop();
        if (hasDraft) { hasDraft = false; Memo.run(["draft-rm", draftId], "", () => {}); }
    }
    Timer {
        id: draftTimer
        interval: 3000
        onTriggered: {
            if (win.modified) {
                win.hasDraft = true;
                Memo.run(["draft-write"], JSON.stringify({ id: win.draftId, text: ta.text, path: win.path, eol: win.eol, bom: win.bom }), () => {});
            } else win.dropDraft();
        }
    }
    function openHere(p) {   // Open dialog result: reuse this window if it is a pristine untitled doc
        if (path === "" && !modified && ta.length === 0) loadFile(p, true);
        else Memo.openFile(p);
    }

    // ---- saving ----
    function save() { if (path === "") overlay = "saveas"; else writeTo(path); }
    function writeTo(p) {
        if (saving) return;
        saving = true;
        const snap = ta.text;
        Memo.run(["write"], JSON.stringify({ path: p, text: snap, eol: eol, bom: bom }), o => {
            win.saving = false;
            if (o.ok) {
                win.path = p; win.stamp = o.stamp; win.savedText = snap;
                win.modified = ta.text !== snap;
                if (win.modified) draftTimer.restart(); else win.dropDraft();
                if (win.banner === "recovered") win.banner = "";
                win.banner = "";
                if (win.closeAfterSave) { win.closeAfterSave = false; win.doClose(); }
            } else {
                win.closeAfterSave = false;
                win.showError("Save failed: " + o.err);
            }
        });
    }
    function doClose() { dropDraft(); closing = true; visible = false; Memo.closeDoc(docId); }
    function requestClose() {
        if (modified) { overlay = "close"; visible = true; }
        else doClose();
    }
    onClosed: if (!closing) { if (modified) { win.overlay = "close"; win.visible = false; reopen.restart(); } else doClose(); }
    Timer { id: reopen; interval: 50; onTriggered: { win.visible = true; } }

    // ---- disk change watcher ----
    Timer {
        interval: 1500; repeat: true
        running: win.path !== "" && win.stamp !== "" && !win.loading && !win.saving
        onTriggered: Memo.run(["stat", win.path], "", o => {
            if (win.saving || win.loading) return;
            if (!o.ok) { if (win.banner === "") { win.banner = "deleted"; win.bannerKind = "warn"; } }
            else if (o.stamp !== win.stamp && win.banner !== "changed") { win.banner = "changed"; win.bannerKind = "warn"; win.pendingStamp = o.stamp; }
        });
    }
    property string pendingStamp: ""

    // ---- line table / status ----
    function rebuildLines() {
        const t = ta.text;
        const a = [0];
        let i = -1;
        while ((i = t.indexOf("\n", i + 1)) !== -1) a.push(i + 1);
        lineStarts = a;
        lineCount = a.length;
        updateCursor();
        updateGutter();
    }
    function lineOf(pos) {
        const a = lineStarts;
        let lo = 0, hi = a.length - 1;
        while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (a[mid] <= pos) lo = mid; else hi = mid - 1; }
        return lo;
    }
    function updateCursor() {
        const l = lineOf(ta.cursorPosition);
        line = l + 1;
        col = ta.cursorPosition - lineStarts[l] + 1;
        publish();
    }
    function updateGutter() {
        if (!ta) return;
        const top = flick.contentY, bot = top + flick.height;
        const res = [];
        let ln = lineOf(ta.positionAt(0, top));
        for (; ln < lineStarts.length && res.length < 300; ln++) {
            if (lineStarts[ln] > ta.length) break;
            const r = ta.positionToRectangle(lineStarts[ln]);
            if (lineStarts[ln] > ta.length || r.y > bot) break;
            res.push({ n: ln + 1, y: r.y - top, h: r.height });
        }
        gutterModel = res;
    }
    function gotoLine(n) {
        n = Math.max(1, Math.min(lineCount, n));
        ta.cursorPosition = lineStarts[n - 1];
        ta.forceActiveFocus();
    }

    // ---- find / replace ----
    function needle() { return findField.text; }
    function norm(s) { return matchCase ? s : s.toLowerCase(); }
    function recount() {
        const n = norm(needle());
        if (n === "") { matchCount = 0; return; }
        const t = norm(ta.text);
        let c = 0, i = -n.length;
        while (c < 100000 && (i = t.indexOf(n, i + n.length)) !== -1) c++;
        matchCount = c;
    }
    function findNext(back) {
        const n = norm(needle());
        if (n === "") return false;
        const t = norm(ta.text);
        let i;
        if (!back) {
            i = t.indexOf(n, ta.selectionEnd);
            if (i < 0) i = t.indexOf(n, 0);
        } else {
            const from = ta.selectionStart - 1;
            i = from >= 0 ? t.lastIndexOf(n, from) : -1;
            if (i < 0) i = t.lastIndexOf(n);
        }
        if (i < 0) return false;
        ta.select(i, i + n.length);
        return true;
    }
    function selectionMatches() {
        const n = norm(needle());
        return n !== "" && ta.selectionEnd > ta.selectionStart && norm(ta.selectedText) === n;
    }
    function replaceOne() {
        if (!selectionMatches()) { findNext(false); return; }
        const s = ta.selectionStart;
        ta.remove(s, ta.selectionEnd);
        ta.insert(s, replField.text);
        ta.cursorPosition = s + replField.text.length;
        findNext(false);
        recount();
    }
    function replaceAll() {
        const n = needle();
        if (n === "") return;
        const t = ta.text;
        const re = new RegExp(n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), matchCase ? "g" : "gi");
        const r = replField.text;
        const nt = t.replace(re, () => r);
        if (nt === t) return;
        const pos = ta.cursorPosition;
        ta.remove(0, ta.length);
        ta.insert(0, nt);
        ta.cursorPosition = Math.min(pos, ta.length);
        recount();
    }
    function openFind(withReplace) {
        findOpen = true; replaceOpen = withReplace; gotoOpen = false;
        if (ta.selectedText !== "" && ta.selectedText.indexOf("\n") < 0) findField.text = ta.selectedText;
        recount();
        Qt.callLater(() => { findField.forceActiveFocus(); findField.selectAll(); });
    }
    function closeBars() { findOpen = false; replaceOpen = false; gotoOpen = false; ta.forceActiveFocus(); }

    // ---- editing helpers ----
    function indentSelection(back) {
        const s = ta.selectionStart, e = ta.selectionEnd;
        const l0 = lineOf(s), l1 = lineOf(e > s && lineStarts[lineOf(e)] === e ? e - 1 : e);
        const t = ta.text;
        const unit = Memo.tabSpaces ? "    " : "\t";
        let out = [], delta0 = 0, deltaAll = 0;
        for (let l = l0; l <= l1; l++) {
            const a = lineStarts[l];
            const b = l + 1 < lineStarts.length ? lineStarts[l + 1] - 1 : t.length;
            let ln = t.substring(a, b);
            if (!back) { ln = unit + ln; deltaAll += unit.length; if (l === l0) delta0 = unit.length; }
            else {
                const m = ln.match(/^(\t| {1,4})/);
                if (m) { ln = ln.substring(m[0].length); deltaAll -= m[0].length; if (l === l0) delta0 = -m[0].length; }
            }
            out.push(ln);
        }
        const a0 = lineStarts[l0];
        const b0 = l1 + 1 < lineStarts.length ? lineStarts[l1 + 1] - 1 : t.length;
        if (deltaAll === 0) return;
        ta.remove(a0, b0);
        ta.insert(a0, out.join("\n"));
        ta.select(Math.max(a0, s + delta0), e + deltaAll);
    }

    // ---- shortcuts ----
    Item {
        id: keys
        width: 0; height: 0
        readonly property bool active: win.overlay === ""
        Shortcut { sequences: [StandardKey.New];  enabled: keys.active; onActivated: Memo.newDoc() }
        Shortcut { sequences: [StandardKey.Open]; enabled: keys.active; onActivated: win.overlay = "open" }
        Shortcut { sequences: ["Ctrl+S"]; enabled: keys.active; onActivated: win.save() }
        Shortcut { sequences: ["Ctrl+Shift+S"]; enabled: keys.active; onActivated: win.overlay = "saveas" }
        Shortcut { sequences: ["Ctrl+W"]; enabled: keys.active; onActivated: win.requestClose() }
        Shortcut { sequences: ["Ctrl+F"]; enabled: keys.active; onActivated: win.openFind(false) }
        Shortcut { sequences: ["Ctrl+H"]; enabled: keys.active; onActivated: win.openFind(true) }
        Shortcut { sequences: ["F3"]; enabled: keys.active; onActivated: win.findNext(false) }
        Shortcut { sequences: ["Shift+F3"]; enabled: keys.active; onActivated: win.findNext(true) }
        Shortcut { sequences: ["Ctrl+L"]; enabled: keys.active; onActivated: { win.gotoOpen = true; win.findOpen = false; Qt.callLater(() => { gotoField.text = ""; gotoField.forceActiveFocus(); }); } }
        Shortcut { sequences: ["Ctrl+="]; enabled: keys.active; onActivated: Memo.fontSize = Math.min(40, Memo.fontSize + 1) }
        Shortcut { sequences: ["Ctrl++"]; enabled: keys.active; onActivated: Memo.fontSize = Math.min(40, Memo.fontSize + 1) }
        Shortcut { sequences: ["Ctrl+-"]; enabled: keys.active; onActivated: Memo.fontSize = Math.max(8, Memo.fontSize - 1) }
        Shortcut { sequences: ["Ctrl+0"]; enabled: keys.active; onActivated: Memo.fontSize = 15 }
        Shortcut { sequences: ["Alt+Z"]; enabled: keys.active; onActivated: Memo.wrap = !Memo.wrap }
    }

    Connections {
        target: Memo
        function onRaiseChanged() { if (Memo.raiseId === win.docId) ta.forceActiveFocus(); }
    }

    // ---- UI ----
    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // toolbar
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: tbFlow.implicitHeight + 14
                color: Theme.panel2
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                Flow {
                    id: tbFlow
                    x: 10; y: 7; width: parent.width - 20
                    spacing: 6
                    ChamferButton { implicitHeight: 30; text: "New"; onClicked: { Memo.newDoc(); ta.forceActiveFocus() } }
                    ChamferButton { implicitHeight: 30; text: "Open"; onClicked: { win.overlay = "open"; ta.forceActiveFocus() } }
                    ChamferButton { implicitHeight: 30; text: "Save"; primary: win.modified; onClicked: { win.save(); ta.forceActiveFocus() } }
                    ChamferButton { implicitHeight: 30; text: "Save as"; onClicked: { win.overlay = "saveas"; ta.forceActiveFocus() } }
                    Item { width: 8; height: 1 }
                    ChamferButton { implicitHeight: 30; text: "Undo"; onClicked: { ta.undo(); ta.forceActiveFocus() } }
                    ChamferButton { implicitHeight: 30; text: "Redo"; onClicked: { ta.redo(); ta.forceActiveFocus() } }
                    Item { width: 8; height: 1 }
                    ChamferButton { implicitHeight: 30; text: "Find"; onClicked: { win.openFind(false); ta.forceActiveFocus() } }
                    ChamferButton { implicitHeight: 30; text: "Goto"; onClicked: { win.gotoOpen = true; win.findOpen = false; Qt.callLater(() => { gotoField.text = ""; gotoField.forceActiveFocus(); }); ta.forceActiveFocus() } }
                    Item { width: 8; height: 1 }
                    MemoToggle { text: "WRAP"; on: Memo.wrap; implicitHeight: 30; onClicked: Memo.wrap = !Memo.wrap }
                    MemoToggle { text: "TAB=4SP"; on: Memo.tabSpaces; implicitHeight: 30; onClicked: Memo.tabSpaces = !Memo.tabSpaces }
                }
            }

            // disk-change / error banner
            Rectangle {
                visible: win.banner !== ""
                Layout.fillWidth: true; Layout.preferredHeight: 38
                color: Theme.panel2
                Rectangle { anchors.left: parent.left; width: 3; height: parent.height; color: win.bannerKind === "error" ? Theme.bad : (win.bannerKind === "info" ? Theme.accent : Theme.warn) }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 14; anchors.right: bannerBtns.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: win.banner === "changed" ? "File changed on disk." + (win.modified ? " Reloading discards your edits." : "")
                        : win.banner === "deleted" ? "File was deleted or moved on disk."
                        : win.banner === "recovered" ? "Recovered unsaved changes."
                        : win.banner
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                }
                Row {
                    id: bannerBtns
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    ChamferButton { visible: win.banner === "changed"; implicitHeight: 26; text: "Reload"; onClicked: win.reload() }
                    ChamferButton { visible: win.banner === "recovered"; implicitHeight: 26; text: "Discard"; onClicked: win.doClose() }
                    ChamferButton {
                        implicitHeight: 26
                        text: win.banner === "recovered" ? "Keep" : (win.banner === "changed" || win.banner === "deleted" ? "Keep mine" : "Dismiss")
                        onClicked: {
                            if (win.banner === "changed") win.stamp = win.pendingStamp;
                            else if (win.banner === "deleted") win.stamp = "";
                            win.banner = "";
                        }
                    }
                }
            }

            // find / replace bar
            Rectangle {
                visible: win.findOpen
                Layout.fillWidth: true; Layout.preferredHeight: win.replaceOpen ? 76 : 42
                color: Theme.panel2
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                Column {
                    x: 10; y: 6; spacing: 6
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 240; height: 28; color: "transparent"
                            border.width: 1; border.color: findField.activeFocus ? Theme.accent : Theme.lineStrong
                            TextInput {
                                id: findField
                                anchors.fill: parent; anchors.margins: 6; clip: true
                                color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                                font.family: Theme.mono; font.pixelSize: 13
                                onTextChanged: win.recount()
                                KeyNavigation.tab: replField
                                onAccepted: win.findNext(false)
                                Keys.onEscapePressed: win.closeBars()
                                Keys.onPressed: event => {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) { win.findNext(true); event.accepted = true; }
                                }
                                Text { visible: findField.text === ""; text: "find"; color: Theme.dim; font: findField.font }
                            }
                        }
                        ChamferButton { implicitHeight: 28; text: "Prev"; onClicked: win.findNext(true) }
                        ChamferButton { implicitHeight: 28; text: "Next"; onClicked: win.findNext(false) }
                        MemoToggle { text: "Aa"; on: win.matchCase; y: 1; onClicked: { win.matchCase = !win.matchCase; win.recount(); } }
                        MemoToggle { text: "REPLACE"; on: win.replaceOpen; y: 1; onClicked: win.replaceOpen = !win.replaceOpen }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: findField.text === "" ? "" : win.matchCount + (win.matchCount === 1 ? " match" : " matches")
                            color: findField.text !== "" && win.matchCount === 0 ? Theme.bad : Theme.dim
                            font.family: Theme.mono; font.pixelSize: 11
                        }
                    }
                    Row {
                        visible: win.replaceOpen
                        spacing: 6
                        Rectangle {
                            width: 240; height: 28; color: "transparent"
                            border.width: 1; border.color: replField.activeFocus ? Theme.accent : Theme.lineStrong
                            TextInput {
                                id: replField
                                anchors.fill: parent; anchors.margins: 6; clip: true
                                color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                                font.family: Theme.mono; font.pixelSize: 13
                                KeyNavigation.tab: findField
                                KeyNavigation.backtab: findField
                                onAccepted: win.replaceOne()
                                Keys.onEscapePressed: win.closeBars()
                                Text { visible: replField.text === ""; text: "replace with"; color: Theme.dim; font: replField.font }
                            }
                        }
                        ChamferButton { implicitHeight: 28; text: "Replace"; onClicked: win.replaceOne() }
                        ChamferButton { implicitHeight: 28; text: "Replace all"; onClicked: win.replaceAll() }
                    }
                }
            }

            // go-to-line bar
            Rectangle {
                visible: win.gotoOpen
                Layout.fillWidth: true; Layout.preferredHeight: 42
                color: Theme.panel2
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                Row {
                    x: 10; y: 7; spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "GO TO LINE"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.5 }
                    Rectangle {
                        width: 120; height: 28; color: "transparent"
                        border.width: 1; border.color: gotoField.activeFocus ? Theme.accent : Theme.lineStrong
                        TextInput {
                            id: gotoField
                            anchors.fill: parent; anchors.margins: 6; clip: true
                            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                            font.family: Theme.mono; font.pixelSize: 13
                            validator: IntValidator { bottom: 1 }
                            onAccepted: { const n = parseInt(text); if (!isNaN(n)) win.gotoLine(n); win.closeBars(); }
                            Keys.onEscapePressed: win.closeBars()
                        }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "1 - " + win.lineCount; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11 }
                }
            }

            // editor
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "transparent"; clip: true

                // gutter
                Rectangle {
                    id: gutter
                    width: Math.max(44, String(win.lineCount).length * (Memo.fontSize * 0.62) + 22)
                    height: parent.height
                    color: Theme.panel2
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
                    Item {
                        anchors.fill: parent; clip: true
                        Repeater {
                            model: win.gutterModel
                            delegate: Text {
                                required property var modelData
                                y: modelData.y; height: modelData.h
                                anchors.right: parent.right; anchors.rightMargin: 10
                                verticalAlignment: Text.AlignVCenter
                                text: modelData.n
                                color: modelData.n === win.line ? Theme.accent : Theme.dim
                                font.family: Theme.mono; font.pixelSize: Memo.fontSize - 2
                            }
                        }
                    }
                }

                Flickable {
                    id: flick
                    anchors.left: gutter.right; anchors.right: parent.right
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: Memo.wrap ? width : Math.max(width, ta.implicitWidth + 20)
                    contentHeight: ta.implicitHeight
                    onContentYChanged: win.updateGutter()
                    onHeightChanged: win.updateGutter()
                    ScrollBar.vertical: ScrollBar { }
                    ScrollBar.horizontal: ScrollBar { }

                    // current-line highlight
                    Rectangle {
                        y: ta.cursorRectangle.y; height: ta.cursorRectangle.height
                        width: Math.max(flick.width, flick.contentWidth)
                        color: Theme.panel2
                        Rectangle { anchors.left: parent.left; width: 2; height: parent.height; color: Theme.accent }
                    }

                    TextArea.flickable: TextArea {
                        id: ta
                        width: Memo.wrap ? flick.width : implicitWidth
                        wrapMode: Memo.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                        color: Theme.fg
                        selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                        font.family: Theme.mono; font.pixelSize: Memo.fontSize
                        leftPadding: 12; rightPadding: 12; topPadding: 6; bottomPadding: 6
                        background: null
                        readOnly: win.overlay !== ""
                        selectByMouse: true
                        persistentSelection: true
                        textFormat: TextEdit.PlainText
                        tabStopDistance: font.pixelSize * 2.4
                        onTextChanged: {
                            if (win.loading) return;
                            win.modified = ta.text !== win.savedText;
                            draftTimer.restart();
                            if (length < 2000000) win.rebuildLines(); else rebuildTimer.restart();
                            if (win.findOpen) recountTimer.restart();
                        }
                        onCursorPositionChanged: win.updateCursor()
                        onWidthChanged: win.updateGutter()
                        onContentHeightChanged: win.updateGutter()
                        onWrapModeChanged: win.updateGutter()
                        onPixelSizeChanged: win.updateGutter()
                        readonly property int pixelSize: font.pixelSize
                        Keys.onTabPressed: event => {
                            if (selectedText.indexOf("\n") >= 0) win.indentSelection(false);
                            else insertTab();
                            event.accepted = true;
                        }
                        Keys.onBacktabPressed: event => { win.indentSelection(true); event.accepted = true; }
                        Keys.onPressed: event => {
                            if (win.overlay !== "") { event.accepted = true; return; }
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                                // auto-indent: copy the current line's leading whitespace
                                const l = win.lineOf(cursorPosition);
                                const lead = text.substring(win.lineStarts[l], cursorPosition).match(/^[ \t]*/)[0];
                                remove(selectionStart, selectionEnd);
                                insert(cursorPosition, "\n" + lead);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                win.closeBars();
                            }
                        }
                        function insertTab() {
                            const s = selectionStart;
                            remove(s, selectionEnd);
                            if (Memo.tabSpaces) {
                                const l = win.lineOf(s);
                                const c = s - win.lineStarts[l];
                                insert(s, " ".repeat(4 - (c % 4)));
                            } else insert(s, "\t");
                        }
                    }
                }
            }

            // status line
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 26
                color: Theme.panel2
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width / 2 - 20
                    elide: Text.ElideMiddle
                    text: win.path === "" ? "UNSAVED DOCUMENT" : win.path
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: "LN " + win.line + ", COL " + win.col + "   " + win.lineCount + " LINES   UTF-8   " + win.eol.toUpperCase()
                        + (win.modified ? "   ● MODIFIED" : "   SAVED")
                    color: win.modified ? Theme.warn : Theme.dim
                    font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 0.8
                }
            }
        }

        // ---- modal overlays ----
        Loader {
            anchors.fill: parent
            active: win.overlay === "open" || win.overlay === "saveas"
            sourceComponent: MemoDialog {
                saveMode: win.overlay === "saveas"
                startPath: win.path !== "" ? win.path : (saveMode ? Memo.home + "/" + win.untitled.toLowerCase().replace(" ", "-") + ".txt" : Memo.home + "/")
                onAccepted: p => {
                    const wasSave = win.overlay === "saveas";
                    win.overlay = "";
                    if (wasSave) win.writeTo(p); else win.openHere(p);
                    ta.forceActiveFocus();
                }
                onCancelled: { win.overlay = ""; win.closeAfterSave = false; ta.forceActiveFocus(); }
            }
        }
        Loader {
            anchors.fill: parent
            active: win.overlay === "close"
            sourceComponent: MemoPrompt {
                title: "Unsaved changes"
                message: "Save changes to \"" + win.name + "\" before closing?"
                buttons: [{ id: "discard", text: "Discard" }, { id: "cancel", text: "Cancel" }, { id: "save", text: "Save", primary: true }]
                onChosen: id => {
                    win.overlay = "";
                    if (id === "discard") win.doClose();
                    else if (id === "save") { win.closeAfterSave = true; win.save(); }
                    else ta.forceActiveFocus();
                }
            }
        }
    }

    Timer { id: rebuildTimer; interval: 200; onTriggered: win.rebuildLines() }
    Timer { id: recountTimer; interval: 250; onTriggered: win.recount() }
}
