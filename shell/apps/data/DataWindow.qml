// DataWindow.qml - DATA, the Ultimit file manager: a normal xdg toplevel (the compositor draws
// the frame). Instantiate once from shell.qml:  DataWindow {}
// Open / toggle:  Data.show(path) / Data.toggle()  or
//   qs -p <shell> ipc call data open <path> | toggle     (also: shell/bin/ultimit-data [path])
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../.."
import "../../components"
import "../games"

FloatingWindow {
    id: win
    title: "DATA"
    visible: Data.open
    implicitWidth: 960
    implicitHeight: 600
    minimumSize: Qt.size(760, 440)
    color: Theme.bg1

    onVisibleChanged: { if (visible !== Data.open) Data.open = visible; if (visible) Qt.callLater(() => ui.forceActiveFocus()); }
    Component.onCompleted: Qt.callLater(() => ui.forceActiveFocus())

    IpcHandler {
        target: "data"
        function open(path: string): void { Data.show(path); }
        function toggle(): void { Data.toggle(); }
        function close(): void { Data.hide(); }
        function run(action: string, arg: string): string { return Data.act(action, arg); }
        function state(): string { return Data.stateJson(); }
    }

    property alias ui: ui
    property alias content: ui   // root item (used for screenshots/tests)

    readonly property bool grid: Data.viewMode === "grid"
    readonly property var lv: grid ? gridView : listView
    readonly property int sideW: 196
    readonly property int cols: Math.max(1, Math.floor(gridView.width / gridView.cellWidth))

    // -------- drag ghost (internal drag and drop inside DATA)
    function ghostStart(paths, label) { ghost.paths = paths; ghost.label = label; ghost.Drag.active = true; }
    function ghostMove(x, y) { ghost.x = x; ghost.y = y; }
    function ghostDrop(ctrl) { ghost.copy = !!ctrl; ghost.Drag.drop(); }
    function forceActiveFocus() { ui.forceActiveFocus(); }

    Connections {
        target: Data
        function onRaiseChanged() { ui.forceActiveFocus(); }
        function onCurChanged() {
            if (Data.cur < 0) return;
            if (win.grid) gridView.positionViewAtIndex(Data.cur, GridView.Contain);
            else listView.positionViewAtIndex(Data.cur, ListView.Contain);
        }
        function onViewChanged() {
            if (Data.keepScroll) { const y = win.lv.contentY; Qt.callLater(() => { win.lv.contentY = y; }); }
            else win.lv.contentY = 0;
        }
        function onRenamePathChanged() {
            if (Data.renamePath === "") ui.forceActiveFocus();
            else if (Data.cur >= 0) { if (win.grid) gridView.positionViewAtIndex(Data.cur, GridView.Contain); else listView.positionViewAtIndex(Data.cur, ListView.Contain); }
        }
        function onDialogChanged() { if (Data.dialog === null) ui.forceActiveFocus(); }
    }

    // -------- menus
    function openItemMenu(x, y) {
        const t = Data.targets();
        const one = t.length === 1 ? t[0] : null;
        let items;
        if (Data.isTrash) {
            items = [{ id: "restore", label: "Restore" }, { id: "delete", label: "Delete permanently", hint: "Del" },
                     { kind: "sep" }, { id: "props", label: "Properties" }];
        } else {
            items = [{ id: "open", label: one && one.d ? "Open" : "Open", hint: "Enter" }];
            if (one && !one.d) items.push({ id: "openwith", label: "Open with…" });
            if (one && one.d) items.push({ id: "openterm", label: "Open terminal here" });
            items.push({ kind: "sep" });
            items.push({ id: "cut", label: "Cut", hint: "Ctrl+X" });
            items.push({ id: "copy", label: "Copy", hint: "Ctrl+C" });
            if (one && one.d && Data.clipPaths.length) items.push({ id: "pasteinto", label: "Paste into folder" });
            items.push({ kind: "sep" });
            items.push({ id: "rename", label: "Rename", hint: "F2", disabled: t.length !== 1 });
            items.push({ id: "trash", label: "Move to Trash", hint: "Del" });
            items.push({ id: "delete", label: "Delete permanently", hint: "Shift+Del" });
            items.push({ kind: "sep" });
            items.push({ id: "props", label: "Properties" });
        }
        menu.items = items;
        menu.kind = "item";
        menu.popup(x, y);
    }
    function openBgMenu(x, y) {
        let items;
        if (Data.isTrash) {
            items = [{ id: "emptytrash", label: "Empty Trash", disabled: Data.entries.length === 0 },
                     { id: "selectall", label: "Select all", hint: "Ctrl+A" }];
        } else {
            items = [{ id: "newfolder", label: "New folder", hint: "Ctrl+Shift+N" }, { id: "newfile", label: "New file" },
                     { id: "paste", label: "Paste", hint: "Ctrl+V", disabled: Data.clipPaths.length === 0 },
                     { kind: "sep" }, { id: "openterm", label: "Open terminal here" },
                     { kind: "sep" }, { id: "hidden", label: "Show hidden files", hint: "Ctrl+H", check: Data.showHidden },
                     { id: "viewlist", label: "List view", check: !win.grid }, { id: "viewgrid", label: "Grid view", check: win.grid },
                     { kind: "sep" }].concat(sortItems()).concat([
                     { kind: "sep" }, { id: "selectall", label: "Select all", hint: "Ctrl+A" },
                     { id: "props", label: "Properties" }]);
        }
        menu.items = items;
        menu.kind = "bg";
        menu.popup(x, y);
    }
    function sortItems() {
        return [{ id: "sort:name", label: "Sort by name", check: Data.sortKey === "name" },
                { id: "sort:size", label: "Sort by size", check: Data.sortKey === "size" },
                { id: "sort:modified", label: "Sort by modified", check: Data.sortKey === "modified" },
                { id: "sort:type", label: "Sort by type", check: Data.sortKey === "type" },
                { id: "sortdir", label: Data.sortDesc ? "Order: descending" : "Order: ascending" }];
    }
    function openDriveMenu(drv, x, y) {
        menu.items = [{ id: "d-open", label: drv.mount ? "Open" : "Mount" },
                      { id: "d-unmount", label: "Unmount", disabled: !drv.mount },
                      { id: "d-power", label: "Power off", disabled: !!drv.mount }];
        menu.kind = "drive"; menu.drive = drv;
        menu.popup(x, y);
    }
    function onMenuPicked(id) {
        switch (id) {
        case "open": Data.openSelected(); break;
        case "openwith": Data.showOpenWith(); break;
        case "openterm": {
            const t = Data.targets();
            if (menu.kind === "item" && t.length === 1 && t[0].d) { Data.goTo(t[0].p); }
            Data.openTerminalHere(); break;
        }
        case "cut": Data.cutSel(); break;
        case "copy": Data.copySel(); break;
        case "paste": Data.paste(); break;
        case "pasteinto": { const t = Data.targets(); if (t.length === 1 && t[0].d) Data.transfer(Data.clipPaths, t[0].p, Data.clipCut ? "move" : "copy"); if (Data.clipCut) Data.clipPaths = []; break; }
        case "rename": Data.startRename(); break;
        case "trash": Data.trashSel(); break;
        case "delete": Data.deleteSel(); break;
        case "restore": Data.restoreSel(); break;
        case "emptytrash": Data.emptyTrash(); break;
        case "props": Data.showProps(); break;
        case "newfolder": Data.newFolder(); break;
        case "newfile": Data.newFile(); break;
        case "hidden": Data.showHidden = !Data.showHidden; break;
        case "viewlist": Data.viewMode = "list"; break;
        case "viewgrid": Data.viewMode = "grid"; break;
        case "selectall": Data.selectAll(); break;
        case "sortdir": Data.sortDesc = !Data.sortDesc; break;
        case "d-open": Data.openDrive(menu.drive); break;
        case "d-unmount": Data.driveAction(menu.drive, "unmount"); break;
        case "d-power": Data.driveAction(menu.drive, "poweroff"); break;
        default: if (id.startsWith("sort:")) { Data.sortKey = id.slice(5); Data.sortDesc = false; }
        }
    }

    // -------- small controls
    component TBtn: Item {
        id: tb
        property string glyph: ""
        property bool active: false
        property bool on: true
        signal clicked()
        width: 30; height: 28
        opacity: on ? 1 : 0.35
        Rectangle {
            anchors.fill: parent
            color: tm.containsMouse && tb.on ? Theme.panel2 : (tb.active ? Theme.panel2 : "transparent")
            border.width: 1; border.color: tb.active ? Theme.accent : Theme.line
        }
        Text {
            anchors.centerIn: parent; text: tb.glyph
            color: tb.active ? Theme.accent : Theme.fg
            font.family: Theme.mono; font.pixelSize: 13
        }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (tb.on) tb.clicked() }
    }
    component Lbl: Item {   // .lbl
        property string text: ""
        property string rtext: ""
        implicitHeight: 16
        Rectangle { id: lsq; width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
        Text {
            anchors.left: lsq.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            text: parent.text; color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.2
        }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: parent.rtext; color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
        }
    }
    // Sidebar row. drop = path accepting dropped files ("" = none).
    component SideRow: Item {
        id: sr
        property string label: ""
        property string icon: ""
        property string target: ""
        property string sub: ""
        property bool current: false
        property string dropPath: ""
        property bool eject: false
        signal clicked()
        signal ejectClicked()
        signal menuRequested(real x, real y)
        width: parent ? parent.width : 100; height: 30
        Rectangle {
            anchors.fill: parent
            color: sr.current || sm.containsMouse || sdrop.containsDrag ? Theme.panel2 : "transparent"
            border.width: sdrop.containsDrag ? 1 : 0; border.color: Theme.accent
            Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: sr.current }
        }
        Image {
            x: 14; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18
            sourceSize: Qt.size(36, 36); source: sr.icon
        }
        Text {
            x: 40; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 40 - (sr.eject ? 34 : 10) - (subT.visible ? subT.implicitWidth + 4 : 0)
            text: sr.label.toUpperCase(); elide: Text.ElideRight
            color: sr.current ? Theme.accent : Theme.fg
            font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.4
        }
        Text {
            id: subT
            visible: sr.sub !== ""
            anchors.right: parent.right; anchors.rightMargin: sr.eject ? 34 : 10; anchors.verticalCenter: parent.verticalCenter
            text: sr.sub; color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1
        }
        MouseArea {
            id: sm
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) { const p = mapToItem(ui, mouse.x, mouse.y); sr.menuRequested(p.x, p.y); }
                else sr.clicked();
            }
        }
        Item {
            visible: sr.eject
            anchors.right: parent.right; width: 30; height: parent.height
            Text {
                anchors.centerIn: parent; text: "⏏"
                color: em.containsMouse ? Theme.accent : Theme.dim
                font.family: Theme.mono; font.pixelSize: 14
            }
            MouseArea { id: em; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sr.ejectClicked() }
        }
        DropArea {
            id: sdrop
            anchors.fill: parent
            keys: ["data-file"]
            enabled: sr.dropPath !== "" && !Data.isTrash
            onDropped: drop => { drop.accept(); Data.dropOn(sr.dropPath, ghost.paths, ghost.copy); }
        }
    }

    // ================================================================ content
    FocusScope {
        id: ui
        anchors.fill: parent
        focus: true

        function moveKey(event) {
            const ext = !!(event.modifiers & Qt.ShiftModifier);
            let d = 0;
            switch (event.key) {
            case Qt.Key_Down: d = win.grid ? win.cols : 1; break;
            case Qt.Key_Up: d = win.grid ? -win.cols : -1; break;
            case Qt.Key_Right: if (win.grid) d = 1; else return false; break;
            case Qt.Key_Left: if (win.grid) d = -1; else return false; break;
            case Qt.Key_PageDown: d = Math.max(1, Math.floor(win.lv.height / (win.grid ? gridView.cellHeight : 32))) * (win.grid ? win.cols : 1); break;
            case Qt.Key_PageUp: d = -Math.max(1, Math.floor(win.lv.height / (win.grid ? gridView.cellHeight : 32))) * (win.grid ? win.cols : 1); break;
            case Qt.Key_Home: Data.moveTo(0, ext); return true;
            case Qt.Key_End: Data.moveTo(Data.view.length - 1, ext); return true;
            default: return false;
            }
            Data.moveCursor(d, ext);
            return true;
        }

        Keys.onPressed: event => {
            const ctrl = !!(event.modifiers & Qt.ControlModifier);
            const shift = !!(event.modifiers & Qt.ShiftModifier);
            const alt = !!(event.modifiers & Qt.AltModifier);
            event.accepted = true;
            if (alt) {
                if (event.key === Qt.Key_Left) Data.goBack();
                else if (event.key === Qt.Key_Right) Data.goForward();
                else if (event.key === Qt.Key_Up) Data.goUp();
                else if (event.key === Qt.Key_Home) Data.goTo(Data.home);
                else event.accepted = false;
                return;
            }
            if (ctrl) {
                switch (event.key) {
                case Qt.Key_A: Data.selectAll(); break;
                case Qt.Key_C: Data.copySel(); break;
                case Qt.Key_X: Data.cutSel(); break;
                case Qt.Key_V: Data.paste(); break;
                case Qt.Key_H: Data.showHidden = !Data.showHidden; break;
                case Qt.Key_L: crumb.beginEdit(); break;
                case Qt.Key_F: filterInput.forceActiveFocus(); filterInput.selectAll(); break;
                case Qt.Key_N: if (shift) Data.newFolder(); else event.accepted = false; break;
                case Qt.Key_R: Data.refresh(true); break;
                default: if (!moveKey(event)) event.accepted = false;
                }
                return;
            }
            if (moveKey(event)) return;
            switch (event.key) {
            case Qt.Key_Return: case Qt.Key_Enter: Data.openSelected(); return;
            case Qt.Key_Backspace:
                if (Data.filter !== "") Data.filter = Data.filter.slice(0, -1); else Data.goUp();
                return;
            case Qt.Key_Escape:
                if (Data.filter !== "") Data.filter = ""; else Data.clearSel();
                return;
            case Qt.Key_F2: Data.startRename(); return;
            case Qt.Key_F5: Data.refresh(true); return;
            case Qt.Key_Delete:
                if (shift || Data.isTrash) Data.deleteSel(); else Data.trashSel();
                return;
            case Qt.Key_Menu: win.openBgMenu(win.sideW + 40, 120); return;
            }
            // type to filter
            if (event.text.length === 1 && event.text >= " " && event.text !== "\x7f") {
                Data.filter = Data.filter + event.text;
                return;
            }
            event.accepted = false;
        }

        Rectangle { anchors.fill: parent; color: Theme.panel }

        // ============================================================ sidebar
        Rectangle {
            id: side
            x: 0; y: 0; width: win.sideW; height: parent.height
            color: Qt.rgba(0, 0, 0, 0.18)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

            Flickable {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: meterBox.top }
                clip: true
                contentWidth: width; contentHeight: sideCol.implicitHeight + 24
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: sideCol
                    x: 0; y: 14; width: parent.width; spacing: 2
                    Lbl { x: 14; width: parent.width - 28; text: "PLACES" }
                    Item { width: 1; height: 6 }
                    Repeater {
                        model: Data.places
                        delegate: SideRow {
                            required property var modelData
                            label: modelData.label; icon: Data.placeIcon(modelData.icon); sub: ""
                            current: !Data.isTrash && Data.path === modelData.path
                            dropPath: modelData.path
                            onClicked: Data.goTo(modelData.path)
                        }
                    }
                    SideRow {
                        label: "Trash"; icon: Data.placeIcon("trash")
                        current: Data.isTrash
                        onClicked: Data.goTo(Data.trashUri)
                    }
                    Item { width: 1; height: 10 }
                    Lbl { x: 14; width: parent.width - 28; text: "DRIVES"; rtext: Data.drives.length ? "" : "NONE" }
                    Item { width: 1; height: 6 }
                    Repeater {
                        model: Data.drives
                        delegate: SideRow {
                            required property var modelData
                            label: modelData.label; icon: Data.placeIcon("drive"); sub: modelData.size
                            eject: modelData.mount !== ""
                            current: !Data.isTrash && modelData.mount !== "" && Data.path === modelData.mount
                            dropPath: modelData.mount
                            onClicked: Data.openDrive(modelData)
                            onEjectClicked: Data.driveAction(modelData, "unmount")
                            onMenuRequested: (x, y) => win.openDriveMenu(modelData, x, y)
                        }
                    }
                    Item { width: 1; height: 10 }
                    Lbl { x: 14; width: parent.width - 28; text: "OTHER LOCATIONS" }
                    Item { width: 1; height: 6 }
                    SideRow {
                        label: "File System"; icon: Data.placeIcon("root")
                        current: !Data.isTrash && Data.path === "/"
                        dropPath: "/"
                        onClicked: Data.goTo("/")
                    }
                }
            }

            // disk meter for the current filesystem (mockup .meter)
            Item {
                id: meterBox
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 62
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                Text {
                    x: 14; y: 12; width: parent.width - 28
                    text: "DISK · " + (Data.disk.total > 0 ? Data.fmtSize(Data.disk.used).toUpperCase() + " OF " + Data.fmtSize(Data.disk.total).toUpperCase() + " USED" : "—")
                    color: Theme.dim; elide: Text.ElideRight
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                }
                Rectangle {   // .meter
                    id: meter
                    x: 14; y: 30; width: parent.width - 28; height: 6
                    color: Theme.panel2; border.width: 1; border.color: Theme.line
                    Rectangle {
                        x: 0; y: 0; height: parent.height
                        width: Data.disk.total > 0 ? parent.width * Math.min(1, Data.disk.used / Data.disk.total) : 0
                        color: Data.disk.total > 0 && Data.disk.used / Data.disk.total > 0.9 ? Theme.bad
                             : (Data.disk.total > 0 && Data.disk.used / Data.disk.total > 0.8 ? Theme.warn : Theme.accent)
                    }
                }
                Text {
                    x: 14; y: 42; width: parent.width - 28
                    text: Data.disk.total > 0 ? Data.fmtSize(Data.disk.avail).toUpperCase() + " FREE · " + Data.disk.mount : ""
                    color: Theme.dim; elide: Text.ElideMiddle
                    font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1
                }
            }
        }

        // ============================================================ main column
        Item {
            id: main
            x: win.sideW + 1; y: 0
            width: parent.width - x; height: parent.height

            // ---- toolbar
            Item {
                id: bar
                x: 12; y: 10; width: parent.width - 24; height: 28

                Row {
                    id: navBtns
                    spacing: 4
                    TBtn { glyph: "‹"; on: Data.backStack.length > 0; onClicked: Data.goBack() }
                    TBtn { glyph: "›"; on: Data.fwdStack.length > 0; onClicked: Data.goForward() }
                    TBtn { glyph: "↑"; on: !Data.isTrash ? Data.path !== "/" : true; onClicked: Data.goUp() }
                }

                // right-side controls
                Row {
                    id: rightBtns
                    anchors.right: parent.right
                    spacing: 4
                    TBtn { glyph: "☰"; active: !win.grid; onClicked: Data.viewMode = "list" }
                    TBtn { glyph: "▦"; active: win.grid; onClicked: Data.viewMode = "grid" }
                    TBtn { glyph: "⇅"; onClicked: { win.openSortMenu(); } }
                    TBtn { glyph: "."; active: Data.showHidden; onClicked: Data.showHidden = !Data.showHidden }
                    Rectangle {   // filter field
                        width: 150; height: 28
                        color: "transparent"; border.width: 1
                        border.color: filterInput.activeFocus || Data.filter !== "" ? Theme.accent : Theme.line
                        Text {
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            visible: Data.filter === "" && !filterInput.activeFocus
                            text: "FILTER"; color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                        }
                        TextInput {
                            id: filterInput
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
                            text: Data.filter
                            onTextEdited: Data.filter = text
                            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                            font.family: Theme.mono; font.pixelSize: 12; clip: true
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) { Data.filter = ""; ui.forceActiveFocus(); event.accepted = true; }
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Down) {
                                    ui.forceActiveFocus(); if (Data.cur < 0 && Data.view.length) Data.selectOnly(0); event.accepted = true;
                                }
                            }
                        }
                    }
                }

                // breadcrumb / path bar
                Item {
                    id: crumb
                    anchors { left: navBtns.right; leftMargin: 10; right: rightBtns.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    height: 28
                    property bool editing: false
                    readonly property var segs: {
                        const out = [];
                        if (Data.isTrash) { out.push({ label: "trash", path: Data.trashUri }); return out; }
                        const parts = Data.path.split("/").filter(x => x !== "");
                        let acc = "";
                        for (const p of parts) { acc += "/" + p; out.push({ label: p, path: acc }); }
                        return out;
                    }
                    function beginEdit() { editing = true; pathInput.text = Data.isTrash ? "trash:" : Data.path; pathInput.forceActiveFocus(); pathInput.selectAll(); }
                    function endEdit() { editing = false; ui.forceActiveFocus(); }

                    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: crumb.editing ? Theme.accent : Theme.line }
                    MouseArea { anchors.fill: parent; onClicked: crumb.beginEdit(); cursorShape: Qt.IBeamCursor }

                    Item {
                        id: crumbClip
                        visible: !crumb.editing
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        clip: true
                        Row {
                            id: crumbRow
                            height: parent.height
                            x: Math.min(0, crumbClip.width - width)
                            spacing: 6
                            Item {
                                width: rootT.implicitWidth + 8; height: parent.height
                                Text {
                                    id: rootT; anchors.verticalCenter: parent.verticalCenter
                                    text: "/"; color: rootMa.containsMouse || rootDrop.containsDrag ? Theme.accent : (crumb.segs.length === 0 ? Theme.fg : Theme.dim)
                                    font.family: Theme.mono; font.pixelSize: 12
                                }
                                MouseArea { id: rootMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Data.goTo("/") }
                                DropArea { id: rootDrop; anchors.fill: parent; keys: ["data-file"]; enabled: !Data.isTrash
                                    onDropped: drop => { drop.accept(); Data.dropOn("/", ghost.paths, ghost.copy); } }
                            }
                            Repeater {
                                model: crumb.segs
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    height: crumbRow.height; spacing: 6
                                    Text {
                                        visible: index > 0 || true
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: index > 0 ? "/" : ""; color: Theme.dim
                                        font.family: Theme.mono; font.pixelSize: 12
                                    }
                                    Item {
                                        width: segT.implicitWidth + 4; height: parent.height
                                        Text {
                                            id: segT; anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            color: segMa.containsMouse || segDrop.containsDrag ? Theme.accent : (index === crumb.segs.length - 1 ? Theme.fg : Theme.dim)
                                            font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 0.7
                                        }
                                        MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Data.goTo(modelData.path) }
                                        DropArea { id: segDrop; anchors.fill: parent; keys: ["data-file"]; enabled: !Data.isTrash && modelData.path !== Data.trashUri
                                            onDropped: drop => { drop.accept(); Data.dropOn(modelData.path, ghost.paths, ghost.copy); } }
                                    }
                                }
                            }
                        }
                    }
                    TextInput {
                        id: pathInput
                        visible: crumb.editing
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                        font.family: Theme.mono; font.pixelSize: 12; clip: true
                        onAccepted: { const t = text.trim(); crumb.endEdit(); if (t === "trash:" || t === "trash") Data.goTo(Data.trashUri); else if (t !== "") Data.goTo(t); }
                        onActiveFocusChanged: if (!activeFocus && crumb.editing) crumb.editing = false
                        Keys.onPressed: event => { if (event.key === Qt.Key_Escape) { crumb.endEdit(); event.accepted = true; } }
                    }
                }
            }

            // ---- column header (list mode)
            Item {
                id: header
                visible: !win.grid
                x: 12; y: 48; width: parent.width - 24; height: 24
                readonly property int sizeW: 84
                readonly property int modW: 128
                readonly property int typeW: width > 620 ? 150 : 0
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                Repeater {
                    model: [
                        { k: "name", t: "NAME", x: 0, w: header.width - header.sizeW - header.modW - header.typeW - 8, al: Text.AlignLeft },
                        { k: "size", t: "SIZE", x: header.width - header.sizeW - header.modW - header.typeW - 8, w: header.sizeW, al: Text.AlignRight },
                        { k: "modified", t: Data.isTrash ? "DELETED" : "MODIFIED", x: header.width - header.modW - header.typeW, w: header.modW, al: Text.AlignRight },
                        { k: "type", t: Data.isTrash ? "ORIGIN" : "TYPE", x: header.width - header.typeW, w: header.typeW, al: Text.AlignLeft }
                    ]
                    delegate: Item {
                        required property var modelData
                        visible: modelData.w > 0
                        x: modelData.x; width: modelData.w; height: header.height
                        Text {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: modelData.k === "name" ? 38 : 8; rightMargin: modelData.k === "size" || modelData.k === "modified" ? 14 : 0 }
                            horizontalAlignment: modelData.al
                            text: modelData.t + (Data.sortKey === modelData.k ? (Data.sortDesc ? " ▾" : " ▴") : "")
                            color: hma.containsMouse || Data.sortKey === modelData.k ? Theme.accent : Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                        }
                        MouseArea { id: hma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Data.setSort(modelData.k) }
                    }
                }
            }

            // ---- listing area
            Item {
                id: area
                x: 12; y: win.grid ? 48 : 73
                width: parent.width - 24
                height: parent.height - y - statusBar.height - (progress.visible ? progress.height : 0)
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    visible: !win.grid
                    model: win.grid ? [] : Data.view
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 320
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width; height: 32
                        readonly property bool sel: Data.selected[modelData.p] === true
                        readonly property bool isCur: Data.cur === index
                        readonly property bool renaming: Data.renamePath === modelData.p

                        Rectangle {
                            anchors.fill: parent
                            color: row.sel ? Theme.panel2 : (rowMa.containsMouse || rowDrop.containsDrag ? Qt.rgba(Theme.panel2.r, Theme.panel2.g, Theme.panel2.b, Theme.panel2.a * 0.6) : "transparent")
                            border.width: rowDrop.containsDrag ? 1 : 0; border.color: Theme.accent
                            Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: row.sel }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; opacity: 0.6 }
                            Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.lineStrong; visible: row.isCur && ui.activeFocus && !row.sel }
                        }
                        EntryMouse { id: rowMa; anchors.fill: parent; host: win; entry: row.modelData; idx: row.index }
                        DropArea {
                            id: rowDrop; anchors.fill: parent; keys: ["data-file"]
                            enabled: row.modelData.d && !Data.isTrash && !row.sel
                            onDropped: drop => { drop.accept(); Data.dropOn(row.modelData.p, ghost.paths, ghost.copy); }
                        }
                        Item {
                            x: 10; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22
                            Image {
                                anchors.fill: parent; sourceSize: Qt.size(44, 44); smooth: true
                                source: Data.iconName(row.modelData)
                                opacity: row.modelData.h ? 0.55 : 1
                            }
                            Image {
                                anchors.fill: parent; asynchronous: true; cache: true; smooth: true
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                source: Data.isImage(row.modelData) ? Data.fileUrl(row.modelData.p) : ""
                                sourceSize: Qt.size(44, 44)
                            }
                        }
                        Text {
                            id: nameT
                            visible: !row.renaming
                            x: 42; width: header.width - header.sizeW - header.modW - header.typeW - 8 - 42 - 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.n; elide: Text.ElideMiddle
                            color: row.modelData.d ? Theme.accent : Theme.fg
                            opacity: row.modelData.h ? 0.6 : 1
                            font.family: Theme.ui; font.pixelSize: 13
                        }
                        Loader {
                            active: row.renaming
                            x: 40; width: header.width - header.sizeW - header.modW - header.typeW - 8 - 40 - 4; height: 24
                            anchors.verticalCenter: parent.verticalCenter
                            sourceComponent: renameEditor
                            property string initial: row.modelData.n
                            property bool isDir: row.modelData.d
                        }
                        Text {
                            x: header.width - header.sizeW - header.modW - header.typeW - 8; width: header.sizeW - 14
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: row.modelData.d ? "—" : Data.fmtSize(row.modelData.s)
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                        }
                        Text {
                            x: header.width - header.modW - header.typeW; width: header.modW - 14
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: Data.fmtDate(row.modelData.m)
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                        }
                        Text {
                            visible: header.typeW > 0
                            x: header.width - header.typeW + 8; width: header.typeW - 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: Data.isTrash ? Data.dirname(row.modelData.o || "") : (row.modelData.d ? "folder" : row.modelData.t)
                            elide: Text.ElideMiddle
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                        }
                    }
                }

                GridView {
                    id: gridView
                    anchors.fill: parent
                    visible: win.grid
                    model: win.grid ? Data.view : []
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: 112; cellHeight: 116
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: GridView.view.cellWidth; height: GridView.view.cellHeight
                        readonly property bool sel: Data.selected[modelData.p] === true
                        readonly property bool isCur: Data.cur === index
                        readonly property bool renaming: Data.renamePath === modelData.p

                        Rectangle {
                            anchors.fill: parent; anchors.margins: 3
                            color: cell.sel ? Theme.panel2 : (cellMa.containsMouse || cellDrop.containsDrag ? Qt.rgba(Theme.panel2.r, Theme.panel2.g, Theme.panel2.b, Theme.panel2.a * 0.6) : "transparent")
                            border.width: cellDrop.containsDrag || cell.sel || (cell.isCur && ui.activeFocus) ? 1 : 0
                            border.color: cellDrop.containsDrag || cell.sel ? Theme.accent : Theme.lineStrong
                        }
                        EntryMouse { id: cellMa; anchors.fill: parent; host: win; entry: cell.modelData; idx: cell.index }
                        DropArea {
                            id: cellDrop; anchors.fill: parent; keys: ["data-file"]
                            enabled: cell.modelData.d && !Data.isTrash && !cell.sel
                            onDropped: drop => { drop.accept(); Data.dropOn(cell.modelData.p, ghost.paths, ghost.copy); }
                        }
                        Item {
                            x: (parent.width - 64) / 2; y: 10; width: 64; height: 64
                            Image {
                                anchors.fill: parent; sourceSize: Qt.size(128, 128); smooth: true
                                fillMode: Image.PreserveAspectFit
                                source: Data.iconName(cell.modelData)
                                opacity: cell.modelData.h ? 0.55 : 1
                            }
                            Image {
                                anchors.fill: parent; asynchronous: true; cache: true; smooth: true
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                source: Data.isImage(cell.modelData) ? Data.fileUrl(cell.modelData.p) : ""
                                sourceSize: Qt.size(128, 128)
                            }
                        }
                        Text {
                            visible: !cell.renaming
                            x: 8; y: 80; width: parent.width - 16; height: 30
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignTop
                            text: cell.modelData.n; wrapMode: Text.WrapAnywhere; elide: Text.ElideRight; maximumLineCount: 2
                            color: cell.modelData.d ? Theme.accent : Theme.fg
                            opacity: cell.modelData.h ? 0.6 : 1
                            font.family: Theme.ui; font.pixelSize: 12
                        }
                        Loader {
                            active: cell.renaming
                            x: 4; y: 82; width: parent.width - 8; height: 24
                            sourceComponent: renameEditor
                            property string initial: cell.modelData.n
                            property bool isDir: cell.modelData.d
                        }
                    }
                }

                // clicks on empty space: clear selection / background context menu
                MouseArea {
                    id: bgArea
                    readonly property real contentEnd: win.grid ? Math.ceil(Data.view.length / win.cols) * gridView.cellHeight : listView.contentHeight
                    x: 0; width: parent.width
                    y: Math.max(0, Math.min(parent.height, contentEnd - win.lv.contentY))
                    height: parent.height - y
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: mouse => {
                        ui.forceActiveFocus();
                        if (mouse.button === Qt.RightButton) { Data.clearSel(); const pt = mapToItem(ui, mouse.x, mouse.y); win.openBgMenu(pt.x, pt.y); }
                        else if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) Data.clearSel();
                    }
                }

                // empty / error state
                Column {
                    anchors.centerIn: parent
                    visible: Data.view.length === 0 && !Data.loading
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Data.error !== "" ? Data.error.toUpperCase() : (Data.filter !== "" ? "NO MATCHES" : (Data.isTrash ? "TRASH IS EMPTY" : "EMPTY FOLDER"))
                        color: Data.error !== "" ? Theme.bad : Theme.dim
                        font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 2.4
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: Data.filter !== "" || (Data.entries.length > 0 && !Data.showHidden)
                        text: Data.filter !== "" ? "ESC CLEARS THE FILTER" : "CTRL+H SHOWS HIDDEN FILES"
                        color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.6
                    }
                }
            }

            // ---- progress strip (async jobs)
            Item {
                id: progress
                visible: Data.jobActive
                anchors { left: parent.left; right: parent.right; bottom: statusBar.top }
                height: 34
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                Text {
                    x: 14; y: 5; width: parent.width - 120
                    text: Data.jobTitle.toUpperCase() + "  ·  " + Data.jobIndex + "/" + Data.jobCount + (Data.jobName !== "" ? "  ·  " + Data.jobName : "") + (Data.jobQueue.length ? "  ·  +" + Data.jobQueue.length + " QUEUED" : "")
                    elide: Text.ElideMiddle; color: Theme.fg
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                }
                Rectangle {
                    x: 14; y: 22; width: parent.width - 120; height: 6
                    color: Theme.panel2; border.width: 1; border.color: Theme.line
                    Rectangle { height: parent.height; width: parent.width * Data.jobFrac; color: Theme.accent
                        Behavior on width { NumberAnimation { duration: Config.dur(120) } } }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    text: "CANCEL"; color: pcm.containsMouse ? Theme.accent : Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                    MouseArea { id: pcm; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Data.cancelJob() }
                }
            }

            // ---- status bar
            Item {
                id: statusBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 28
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    text: Data.statusText()
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    GChip { visible: Data.clipPaths.length > 0; text: (Data.clipCut ? "cut " : "copied ") + Data.clipPaths.length; tone: Theme.accent }
                    GChip { visible: Data.showHidden; text: "hidden shown"; tone: Theme.dim }
                    GChip { visible: Data.isTrash; text: "trash"; tone: Theme.warn }
                    GButton {
                        visible: Data.isTrash
                        height: 22; text: "Empty"
                        onClicked: Data.emptyTrash()
                    }
                    GButton {
                        visible: Data.isTrash && Data.selCount > 0
                        height: 22; primary: true; text: "Restore"
                        onClicked: Data.restoreSel()
                    }
                }
            }
        }

        // ============================================================ overlays
        DMenu {
            id: menu
            property string kind: ""
            property var drive: null
            onPicked: id => win.onMenuPicked(id)
            onDismissed: ui.forceActiveFocus()
        }
        DDialog { id: dialogs }

        // drag ghost
        Item {
            id: ghost
            width: 1; height: 1
            z: 200
            property var paths: []
            property string label: ""
            property bool copy: false
            Drag.dragType: Drag.Internal
            Drag.keys: ["data-file"]
            Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
            Rectangle {
                visible: ghost.Drag.active
                x: 12; y: 10; width: gl.implicitWidth + 24; height: 24
                color: Theme.bg1; border.width: 1; border.color: Theme.accent; opacity: 0.92
                Text {
                    id: gl; anchors.centerIn: parent
                    text: (ghost.paths.length > 1 ? ghost.paths.length + " ITEMS" : ghost.label.toUpperCase())
                    color: Theme.accent; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                }
            }
        }
    }

    function openSortMenu() {
        menu.items = sortItems();
        menu.kind = "sort";
        menu.popup(win.width - 250, 44);
    }

    // inline rename editor; selects the base name (not the extension)
    Component {
        id: renameEditor
        Rectangle {
            color: Theme.bg1; border.width: 1; border.color: Theme.accent
            TextInput {
                id: ed
                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                verticalAlignment: TextInput.AlignVCenter
                text: initial; clip: true
                color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                font.family: Theme.ui; font.pixelSize: 13
                property bool had: false
                Component.onCompleted: Qt.callLater(() => {
                    forceActiveFocus();
                    const dot = initial.lastIndexOf(".");
                    if (!isDir && dot > 0) select(0, dot); else selectAll();
                })
                onAccepted: Data.commitRename(text)
                Keys.onPressed: event => { if (event.key === Qt.Key_Escape) { Data.cancelRename(); event.accepted = true; } }
                onActiveFocusChanged: {
                    if (activeFocus) had = true;
                    else if (had && Data.renamePath !== "") { const t = text; Qt.callLater(() => Data.commitRename(t)); }
                }
            }
        }
    }
}
