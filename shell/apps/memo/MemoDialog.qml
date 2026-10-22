// MemoDialog.qml - in-app file browser used for Open / Save As (no GTK portals).
// The path field holds the full target path; typing "dir/" lists that directory and the text
// after the last "/" filters the listing. Enter on a directory navigates, on a file accepts.
import QtQuick
import QtQuick.Controls
import "../.."
import "../accessory"

Item {
    id: root
    property bool saveMode: false
    property string startPath: ""       // initial full path (dir + "/" + name)
    signal accepted(string path)
    signal cancelled()
    anchors.fill: parent

    property string dir: "/"
    property var entries: []
    property string err: ""
    property bool confirmOver: false
    property bool hasHidden: false
    property bool showHidden: false
    property int sel: -1

    readonly property string typed: pathField.text
    readonly property string filter: typed.substring(typed.lastIndexOf("/") + 1)
    readonly property var shown: {
        const f = filter.toLowerCase();
        const out = [];
        if (dir !== "/") out.push({ n: "..", d: true, s: 0 });
        for (const e of entries) {
            if (e.n.startsWith(".") && !showHidden && !filter.startsWith(".")) continue;
            if (f !== "" && !e.n.toLowerCase().startsWith(f)) continue;
            out.push(e);
        }
        return out;
    }

    function expand(p) {
        if (p === "~") return Memo.home;
        if (p.startsWith("~/")) return Memo.home + p.substring(1);
        if (!p.startsWith("/")) return dir.replace(/\/$/, "") + "/" + p;
        return p;
    }
    function join(d, n) { return (d === "/" ? "" : d) + "/" + n; }
    function load(d) {
        const want = d;
        Memo.run(["list", d], "", o => {
            root.err = o.ok ? "" : (o.err || "cannot list");
            root.dir = o.dir || want;
            root.entries = o.entries || [];
            root.sel = -1;
        });
    }
    function goDir(d) {
        confirmOver = false;
        pathField.text = (d === "/" ? "/" : d + "/");
        pathField.cursorPosition = pathField.text.length;
        load(d);
    }
    function parentOf(d) { const i = d.replace(/\/$/, "").lastIndexOf("/"); return i <= 0 ? "/" : d.substring(0, i); }
    function activate(e) {
        if (e.n === "..") goDir(parentOf(dir));
        else if (e.d) goDir(join(dir, e.n));
        else { pathField.text = join(dir, e.n); pathField.cursorPosition = pathField.text.length; confirmOver = false; }
    }
    function submit() {
        let p = expand(pathField.text.trim());
        if (p === "" ) return;
        if (p.endsWith("/")) { goDir(p.length > 1 ? p.replace(/\/+$/, "") || "/" : "/"); return; }
        const base = p.substring(p.lastIndexOf("/") + 1);
        const hit = entries.find(e => e.n === base && p === join(dir, base));
        if (hit && hit.d) { goDir(p); return; }
        if (root.saveMode && hit && !confirmOver) { confirmOver = true; return; }
        root.accepted(p);
    }

    Component.onCompleted: {
        const sp = startPath !== "" ? startPath : Memo.home + "/";
        const i = sp.lastIndexOf("/");
        const d = i <= 0 ? "/" : sp.substring(0, i);
        pathField.text = sp;
        load(d);
        Qt.callLater(() => { pathField.forceActiveFocus(); if (saveMode) pathField.cursorPosition = pathField.text.length; else pathField.selectAll(); });
    }

    Rectangle { anchors.fill: parent; color: Theme.bg1; opacity: 0.7 }
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: wheel => wheel.accepted = true }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Config.mobile ? root.width - 16 : Math.min(root.width - 40, 640)
        height: Config.mobile ? root.height - 16 : Math.min(root.height - 40, 520)
        color: Theme.bg1
        border.width: 1; border.color: Theme.lineStrong
        Rectangle { anchors.fill: parent; color: Theme.panel }

        Column {
            x: 18; y: 16; width: parent.width - 36; spacing: 10
            Row {
                width: parent.width
                SectionLabel { text: root.saveMode ? "Save as" : "Open file" }
            }
            Rectangle {
                width: parent.width; height: Config.mobile ? 42 : 32; color: "transparent"
                border.width: 1; border.color: pathField.activeFocus ? Theme.accent : Theme.lineStrong
                TextInput {
                    id: pathField
                    anchors.fill: parent; anchors.margins: 8
                    color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                    font.family: Theme.mono; font.pixelSize: 13
                    clip: true
                    onTextEdited: {
                        root.confirmOver = false;
                        const i = text.lastIndexOf("/");
                        const d = text.startsWith("/") || text.startsWith("~") ? text.substring(0, i + 1) : root.dir;
                        if (i >= 0) {
                            const nd = root.expand(d.length > 1 ? d.replace(/\/+$/, "") : (d || "/"));
                            if (nd !== root.dir) root.load(nd);
                        }
                    }
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.cancelled()
                    Keys.onDownPressed: { if (root.shown.length) { root.sel = Math.min(root.sel + 1, root.shown.length - 1); list.positionViewAtIndex(root.sel, ListView.Contain); } }
                    Keys.onUpPressed: { root.sel = Math.max(root.sel - 1, -1); if (root.sel >= 0) list.positionViewAtIndex(root.sel, ListView.Contain); }
                    Keys.onTabPressed: { if (root.sel >= 0) root.activate(root.shown[root.sel]); else if (root.shown.length === 1 + (root.dir !== "/" ? 1 : 0)) root.activate(root.shown[root.shown.length - 1]); }
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.sel >= 0) {
                            root.activate(root.shown[root.sel]); event.accepted = true;
                        }
                    }
                    Text { visible: pathField.text === ""; text: "/path/to/file"; color: Theme.dim; font: pathField.font }
                }
            }
            Rectangle {
                width: parent.width; height: box.height - 170
                color: "transparent"; border.width: 1; border.color: Theme.line
                clip: true
                ListView {
                    id: list
                    anchors.fill: parent; anchors.margins: 1
                    model: root.shown
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: list.width; height: Config.mobile ? 40 : 28
                        color: root.sel === index ? Theme.accent : (m.containsMouse ? Theme.panel2 : "transparent")
                        readonly property color tc: root.sel === index ? Theme.onAccent : Theme.fg
                        Text {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.d ? "▸" : " "
                            color: root.sel === index ? Theme.onAccent : Theme.accent
                            font.family: Theme.mono; font.pixelSize: 13
                        }
                        Text {
                            x: 32; width: parent.width - 120; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.n + (modelData.d && modelData.n !== ".." ? "/" : "")
                            color: tc; elide: Text.ElideRight
                            font.family: Theme.mono; font.pixelSize: 13
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            visible: !modelData.d
                            text: modelData.s < 1024 ? modelData.s + " B" : (modelData.s < 1048576 ? (modelData.s / 1024).toFixed(1) + " KB" : (modelData.s / 1048576).toFixed(1) + " MB")
                            color: root.sel === index ? Theme.onAccent : Theme.dim
                            font.family: Theme.mono; font.pixelSize: 11
                        }
                        MouseArea {
                            id: m; anchors.fill: parent; hoverEnabled: true
                            onClicked: { root.sel = index; root.activate(modelData); pathField.forceActiveFocus(); }
                            onDoubleClicked: if (!modelData.d) root.submit()
                        }
                    }
                    Text {
                        anchors.centerIn: parent; visible: root.err !== "" || (root.shown.length === 0)
                        text: root.err !== "" ? root.err : "no matches"
                        color: root.err !== "" ? Theme.bad : Theme.dim
                        font.family: Theme.mono; font.pixelSize: 12
                    }
                }
            }
            Row {
                width: parent.width; spacing: 10
                MemoToggle { text: "HIDDEN"; on: root.showHidden; implicitHeight: Config.mobile ? 34 : 26; onClicked: root.showHidden = !root.showHidden; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Config.mobile ? parent.width - 90 : parent.width - 330
                    visible: root.confirmOver
                    text: Config.mobile ? "file exists - tap again" : "file exists - press again to overwrite"
                    color: Theme.warn; font.family: Theme.mono; font.pixelSize: 11; elide: Text.ElideRight
                }
                Item { width: 1; height: 1; visible: !root.confirmOver }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 18
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            spacing: 10
            ChamferButton { text: "Cancel"; onClicked: root.cancelled() }
            ChamferButton { text: root.confirmOver ? "Overwrite" : (root.saveMode ? "Save" : "Open"); primary: true; onClicked: root.submit() }
        }
    }
}
