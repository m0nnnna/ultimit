// GamesWindow.qml - the Games app: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Library of Steam titles + desktop-entry games + manually added games, with per-game launch
// options. Instantiate once from shell.qml:  GamesWindow {}
// Open/close: Games.toggle() or  `qs -p <shell> ipc call games toggle`.
//
// Keyboard: arrows move the selection, Enter launches, "/" or Ctrl+F searches, Esc leaves search.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../.."
import "../../components"

FloatingWindow {
    id: win
    title: "Games"
    visible: Games.open
    implicitWidth: 900
    implicitHeight: 620
    minimumSize: Qt.size(640, 440)
    color: Theme.bg1

    onVisibleChanged: {
        if (visible !== Games.open) Games.open = visible;
        if (visible) Qt.callLater(() => grid.forceActiveFocus());
    }

    // qs -p <shell> ipc call games <fn>   (select/tab/search/sort/launchSelected/addDialog/dump are for scripting + tests)
    IpcHandler {
        target: "games"
        function toggle(): void { Games.toggle(); }
        function open(): void { Games.show(); }
        function close(): void { Games.hide(); }
        function rescan(): void { Games.rescan(); }
        function select(id: string): void { Games.selectedId = id; }
        function tab(name: string): void { win.tab = name === "options" ? "options" : "overview"; }
        function search(text: string): void { Games.query = text; }
        function sort(mode: string): void { Games.setSort(mode === "name" ? "name" : "recent"); }
        function launchSelected(): void { if (Games.selected) Games.launch(Games.selected.id); }
        function addDialog(): void { addDlg.open(); }
        function scroll(y: int): void { detail.contentY = Math.max(0, Math.min(y, detail.contentHeight - detail.height)); }
        function dump(): string {
            return JSON.stringify({
                steamState: Games.steamState, count: Games.games.length, query: Games.query, sort: Games.sortMode,
                selected: Games.selectedKey, tab: win.tab,
                ids: Games.games.map(g => g.id),
                steamOptions: Games.selected && Games.selected.source === "steam" ? Games.steamLaunchOptions(Games.selected.id) : ""
            });
        }
    }

    property string tab: "overview"            // overview | options
    readonly property var sel: Games.selected
    readonly property var cfg: sel ? Games.setting(sel.id) : null
    readonly property bool isSteam: sel !== null && sel.source === "steam"
    readonly property bool isWine: Games.isWine(sel)
    readonly property bool anyGames: Games.allGames.length > 0

    property alias content: panelRoot   // root item (used for screenshots/tests)

    function sourceChip(g) { return g.source === "steam" ? "Steam" : "App"; }

    Rectangle {
        id: panelRoot
        anchors.fill: parent
        color: Theme.panel

        // ---- section label (.lbl) ----
        Item {
            id: lbl
            x: 16; y: 14
            width: parent.width - 32
            height: 16
            Rectangle { id: sq; width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
            GLabel {
                anchors.left: sq.right; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Library"
                strong: true
            }
            GLabel {
                id: count
                anchors.right: rescan.left; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: win.anyGames
                    ? (Games.games.length === Games.allGames.length ? Games.allGames.length + (Games.allGames.length === 1 ? " title" : " titles")
                                                                    : Games.games.length + " of " + Games.allGames.length)
                    : ""
            }
            GLabel {
                id: rescan
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Rescan"
                color: rescanMouse.containsMouse ? Theme.accent : Theme.dim
                MouseArea {
                    id: rescanMouse
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Games.rescan()
                }
            }
        }

        // ---- toolbar: search / sort / add ----
        Item {
            id: toolbar
            x: 16; y: 40
            width: parent.width - 32
            height: 32
            GInput {
                id: search
                width: Math.min(260, parent.width - sortSeg.width - addBtn.width - 32)
                height: parent.height
                placeholder: "Search  ( / )"
                value: Games.query
                onEdited: v => Games.query = v
                onCommitted: grid.forceActiveFocus()
                onEscaped: { Games.query = ""; grid.forceActiveFocus(); }
                onDownPressed: grid.forceActiveFocus()
            }
            GSeg {
                id: sortSeg
                anchors.left: search.right; anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                options: [{ id: "recent", label: "Recent" }, { id: "name", label: "Name" }]
                current: Games.sortMode
                onPicked: id => Games.setSort(id)
            }
            GButton {
                id: addBtn
                anchors.right: parent.right
                height: parent.height
                text: "Add game…"
                onClicked: addDlg.open()
            }
        }

        // ---- Steam status strip (not installed / not set up) above the library ----
        SteamCard {
            id: steamStrip
            x: 16; y: toolbar.y + toolbar.height + 10
            width: parent.width - 32
            visible: win.anyGames && Games.loaded && Games.steamState !== "ready"
            mode: Games.steamState
            compact: true
        }

        // ---- empty state: no games at all ----
        Item {
            id: emptyState
            anchors { left: parent.left; right: parent.right; top: toolbar.bottom; bottom: parent.bottom; margins: 16 }
            visible: Games.loaded && !win.anyGames
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width, 460)
                spacing: 14
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "games"; color: Theme.dim; size: 40 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No games yet"
                    color: Theme.fg
                    font.family: Theme.display; font.pixelSize: 16; font.letterSpacing: 0.5
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Ultimit lists your installed Steam games and any app with a Game desktop entry. You can also add a Windows program (run with Wine) or any command by hand."
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 13
                }
                GButton { anchors.horizontalCenter: parent.horizontalCenter; primary: true; text: "Add game…"; onClicked: addDlg.open() }
                SteamCard { width: parent.width; mode: Games.steamState === "ready" ? "tip" : Games.steamState }
            }
        }

        // ---- library + detail ----
        Item {
            id: body
            anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
            y: steamStrip.visible ? steamStrip.y + steamStrip.height + 12 : toolbar.y + toolbar.height + 12
            height: parent.height - y - 16
            visible: win.anyGames
            readonly property real leftW: Math.min(width * 0.46, 440)

            // no matches for the search
            GLabel {
                visible: win.anyGames && Games.games.length === 0
                x: 4; y: 8
                text: "No games match “" + Games.query + "”"
            }

            // library grid
            GridView {
                id: grid
                width: body.leftW
                height: parent.height
                clip: true
                focus: true
                model: Games.games
                readonly property int cols: Math.max(2, Math.floor(width / 128))
                cellWidth: Math.floor(width / cols)
                cellHeight: Math.round(cellWidth * 4 / 3) + 10
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                function move(to) {
                    const n = Games.games.length;
                    if (!n) return;
                    const i = Math.max(0, Math.min(n - 1, to));
                    Games.selectedId = Games.games[i].id;
                    positionViewAtIndex(i, GridView.Contain);
                }
                Keys.onPressed: event => {
                    const i = Math.max(0, Games.indexOfSelected()), n = Games.games.length, c = cols;
                    event.accepted = true;
                    switch (event.key) {
                    case Qt.Key_Left: move(i - 1); break;
                    case Qt.Key_Right: move(i + 1); break;
                    case Qt.Key_Up: move(i - c); break;
                    case Qt.Key_Down: move((i + c >= n && Math.floor(i / c) < Math.floor((n - 1) / c)) ? n - 1 : i + c); break;
                    case Qt.Key_Home: move(0); break;
                    case Qt.Key_End: move(n - 1); break;
                    case Qt.Key_Return: case Qt.Key_Enter:
                        if (Games.selected) Games.launch(Games.selected.id);
                        break;
                    case Qt.Key_Slash: search.input.forceActiveFocus(); break;
                    case Qt.Key_F:
                        if (event.modifiers & Qt.ControlModifier) search.input.forceActiveFocus();
                        else event.accepted = false;
                        break;
                    case Qt.Key_Tab: win.tab = win.tab === "overview" ? "options" : "overview"; break;
                    default: event.accepted = false;
                    }
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    readonly property bool isSel: Games.selectedKey === modelData.id

                    Item {
                        id: tile
                        x: 3; y: 3
                        width: parent.width - 12; height: parent.height - 12
                        // glass backing
                        Rectangle { anchors.fill: parent; color: Theme.panel2 }
                        Item {
                            anchors.fill: parent
                            clip: true
                            GameArt {
                                id: art
                                anchors.fill: parent
                                game: cell.modelData
                                scale: tileMouse.containsMouse || cell.isSel ? 1.04 : 1
                                Behavior on scale { NumberAnimation { duration: Config.dur(300); easing.type: Easing.OutCubic } }
                            }
                            // glass sheen: light top edge, dark label scrim
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: parent.height * 0.4
                                gradient: Gradient {
                                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10) }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                            }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: nm.implicitHeight + 30
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.8) }
                                }
                            }
                            Text {
                                id: nm
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                                text: cell.modelData.name
                                color: "#ffffff"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                lineHeight: 1.0
                                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 12
                            }
                        }
                        // source chip
                        Rectangle {
                            x: 6; y: 6
                            width: srcTxt.implicitWidth + 10; height: srcTxt.implicitHeight + 4
                            color: Qt.rgba(0, 0, 0, 0.55)
                            border.color: cell.modelData.source === "steam" ? Theme.line : Theme.accent
                            border.width: 1
                            Text {
                                id: srcTxt
                                anchors.centerIn: parent
                                text: win.sourceChip(cell.modelData).toUpperCase()
                                color: cell.modelData.source === "steam" ? "#ffffff" : Theme.accent
                                font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.4
                            }
                        }
                        Rectangle {
                            anchors.fill: parent; color: "transparent"
                            border.color: tileMouse.containsMouse ? Theme.lineStrong : Theme.line
                            border.width: 1
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { grid.forceActiveFocus(); Games.selectedId = cell.modelData.id; }
                            onDoubleClicked: Games.launch(cell.modelData.id)
                        }
                    }
                    // selection brackets (offset outside the tile)
                    Item {
                        x: tile.x - 3; y: tile.y - 3
                        width: tile.width + 6; height: tile.height + 6
                        opacity: cell.isSel ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.dur(150) } }
                        Brackets { color: Theme.accent; size: 14; thickness: 2 }
                    }
                }
            }

            // detail pane
            Item {
                id: detailBox
                x: body.leftW + 16
                width: parent.width - x
                height: parent.height
                visible: win.sel !== null

                GSeg {
                    id: tabs
                    options: [{ id: "overview", label: "Overview" }, { id: "options", label: "Launch options" }]
                    current: win.tab
                    onPicked: id => win.tab = id
                }

                Flickable {
                    id: detail
                    y: tabs.height + 10
                    width: parent.width
                    height: parent.height - y - 46
                    clip: true
                    contentWidth: width
                    contentHeight: win.tab === "overview" ? overviewCol.implicitHeight : optionsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    // ---------------- overview ----------------
                    Column {
                        id: overviewCol
                        visible: win.tab === "overview"
                        width: detail.width - 10
                        spacing: 12

                        Rectangle {
                            width: parent.width; height: 120
                            color: Theme.panel2
                            border.color: Theme.line; border.width: 1
                            GameArt { anchors.fill: parent; anchors.margins: 1; game: win.sel; portrait: false; iconSize: 64 }
                            Brackets { color: Theme.accent; size: 10; anchors.margins: 0 }
                        }
                        Text {
                            width: parent.width
                            text: win.sel ? win.sel.name : ""
                            color: Theme.fg
                            wrapMode: Text.WordWrap
                            font.family: Theme.display; font.pixelSize: 16; font.letterSpacing: 0.5
                        }
                        Flow {
                            width: parent.width; spacing: 8
                            GChip { text: win.sel ? win.sourceChip(win.sel) : ""; tone: Theme.accent }
                            GChip { text: Games.kindLabel(win.sel); tone: win.isSteam && win.sel.compat !== "proton" ? Theme.ok : Theme.dim }
                            GChip {
                                visible: win.isSteam
                                text: win.sel && win.sel.ready ? "Installed" : "Update pending"
                                tone: win.sel && win.sel.ready ? Theme.ok : Theme.warn
                            }
                        }
                        Text {
                            visible: !win.isSteam && win.sel && (win.sel.comment || "") !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: win.sel ? (win.sel.comment || "") : ""
                            color: Theme.dim
                            font.family: Theme.ui; font.pixelSize: 12
                        }
                        Grid {
                            columns: 1; rowSpacing: 5
                            width: parent.width
                            Repeater {
                                model: !win.sel ? [] : win.isSteam ? [
                                    ["Size", Games.fmtSize(win.sel.size)],
                                    ["Last", Games.fmtLast(Games.lastTs(win.sel))],
                                    ["App ID", win.sel.id]
                                ] : [
                                    ["Last", Games.fmtLast(Games.lastTs(win.sel))],
                                    [win.isWine ? "Program" : "Runs", win.sel.target || (win.sel.exec ? win.sel.exec.join(" ") : "")],
                                    ["ID", win.sel.id]
                                ]
                                delegate: Row {
                                    id: kvRow
                                    required property var modelData
                                    spacing: 6
                                    GLabel { width: 56; topPadding: 2; text: kvRow.modelData[0] }
                                    Text {
                                        width: overviewCol.width - 62
                                        text: kvRow.modelData[1]
                                        color: Theme.fg
                                        wrapMode: Text.WrapAnywhere
                                        font.family: Theme.ui; font.pixelSize: 12
                                    }
                                }
                            }
                        }
                        GButton {
                            visible: win.sel && win.sel.manual === true
                            text: "Remove from library"
                            onClicked: Games.removeManual(win.sel.id)
                        }
                        SteamCard { visible: win.isSteam; width: parent.width; mode: "tip" }
                    }

                    // ---------------- launch options ----------------
                    Column {
                        id: optionsCol
                        visible: win.tab === "options"
                        width: detail.width - 10
                        spacing: 12

                        Text {
                            visible: win.isSteam
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.family: Theme.ui; font.pixelSize: 12
                            text: "Steam controls how this game starts. Set the options below, then paste the generated line into Steam."
                        }

                        // GPU
                        Column {
                            width: parent.width; spacing: 6
                            GLabel { text: "Render on" }
                            GSeg {
                                options: [
                                    { id: "auto", label: "Auto" },
                                    { id: "discrete", label: "Discrete", disabled: !Games.tools.nvidia },
                                    { id: "integrated", label: "Integrated" }
                                ]
                                current: win.cfg ? win.cfg.gpu : "auto"
                                onPicked: id => Games.setSetting(win.sel.id, "gpu", id)
                            }
                            Text {
                                visible: !Games.tools.nvidia
                                width: parent.width; wrapMode: Text.WordWrap
                                color: Theme.warn; font.family: Theme.ui; font.pixelSize: 11
                                text: "No NVIDIA driver is loaded, so Discrete is unavailable."
                            }
                        }

                        GToggle {
                            width: parent.width
                            label: "GameMode"
                            available: Games.tools.gamemode
                            checked: win.cfg ? win.cfg.gamemode : false
                            onToggled: v => Games.setSetting(win.sel.id, "gamemode", v)
                        }
                        Column {
                            width: parent.width; spacing: 4
                            GToggle {
                                width: parent.width
                                label: "MangoHud overlay"
                                available: Games.tools.mangohud
                                checked: win.cfg ? win.cfg.overlay : false
                                onToggled: v => Games.setSetting(win.sel.id, "overlay", v)
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
                                text: "MangoHud is 64-bit only here (mangohud:i386 isn't packaged), so 32-bit games can't show the overlay."
                            }
                        }
                        Column {
                            width: parent.width; spacing: 8
                            GToggle {
                                width: parent.width
                                label: "Gamescope"
                                available: Games.tools.gamescope
                                checked: win.cfg ? win.cfg.gamescope : false
                                onToggled: v => Games.setSetting(win.sel.id, "gamescope", v)
                            }
                            Row {
                                visible: win.cfg && win.cfg.gamescope && Games.tools.gamescope
                                spacing: 10
                                Column {
                                    spacing: 4
                                    GLabel { text: "Resolution" }
                                    GInput {
                                        width: 130
                                        placeholder: "1920x1080"
                                        value: win.cfg ? win.cfg.scopeRes : ""
                                        onCommitted: v => { if (v === "" || /^\d{3,5}x\d{3,5}$/.test(v)) Games.setSetting(win.sel.id, "scopeRes", v); }
                                    }
                                }
                                Column {
                                    spacing: 4
                                    GLabel { text: "FPS cap" }
                                    GInput {
                                        width: 80
                                        placeholder: "none"
                                        value: win.cfg && win.cfg.scopeFps > 0 ? String(win.cfg.scopeFps) : ""
                                        onCommitted: v => { const n = parseInt(v); Games.setSetting(win.sel.id, "scopeFps", n > 0 && n <= 1000 ? n : 0); }
                                    }
                                }
                            }
                        }

                        // Wine / manual: DXVK + prefix
                        Column {
                            visible: win.isWine
                            width: parent.width; spacing: 8
                            GToggle {
                                width: parent.width
                                label: "DXVK"
                                available: Games.tools.dxvk
                                unavailableText: "run scripts/get-dxvk.sh"
                                checked: win.cfg ? win.cfg.dxvk : false
                                onToggled: v => Games.setSetting(win.sel.id, "dxvk", v)
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
                                text: "Copies Ultimit's DXVK (d3d9, d3d10core, d3d11, dxgi) into the Wine prefix at launch."
                            }
                            GLabel { text: "Wine prefix" }
                            GSeg {
                                options: [{ id: "default", label: "Shared default" }, { id: "custom", label: "Custom" }]
                                current: win.cfg && win.cfg.prefix !== "default" ? "custom" : "default"
                                onPicked: id => Games.setSetting(win.sel.id, "prefix",
                                    id === "default" ? "default" : (win.cfg.prefix !== "default" ? win.cfg.prefix : Games.winePrefix.replace(/default$/, win.sel.name.toLowerCase().replace(/[^a-z0-9]+/g, "-"))))
                            }
                            GInput {
                                visible: win.cfg && win.cfg.prefix !== "default"
                                width: parent.width
                                value: win.cfg && win.cfg.prefix !== "default" ? win.cfg.prefix : ""
                                placeholder: "/path/to/prefix"
                                onCommitted: v => { if (v.trim() !== "") Games.setSetting(win.sel.id, "prefix", v.trim()); }
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
                                text: win.cfg && win.cfg.prefix === "default" ? "Shared: " + Games.winePrefix : "Created on first launch if it doesn't exist."
                            }
                        }

                        Column {
                            width: parent.width; spacing: 6
                            GLabel { text: "Environment variables" }
                            GInput {
                                width: parent.width
                                placeholder: "KEY=value  OTHER=\"two words\""
                                value: win.cfg ? win.cfg.env : ""
                                onCommitted: v => Games.setSetting(win.sel.id, "env", v.trim())
                            }
                            GLabel { text: "Launch arguments" }
                            GInput {
                                width: parent.width
                                placeholder: "-windowed -nosplash"
                                value: win.cfg ? win.cfg.args : ""
                                onCommitted: v => Games.setSetting(win.sel.id, "args", v.trim())
                            }
                        }

                        // Steam: the launch-options string
                        Rectangle {
                            id: steamOpt
                            visible: win.isSteam
                            width: parent.width
                            implicitHeight: soCol.implicitHeight + 24
                            height: implicitHeight
                            color: "transparent"
                            border.color: Theme.lineStrong; border.width: 1
                            Brackets { color: Theme.accent; size: 8; thickness: 1 }
                            Column {
                                id: soCol
                                x: 12; y: 12
                                width: parent.width - 24
                                spacing: 8
                                GLabel { text: "Steam launch options"; color: Theme.accent }
                                CopyText { id: soText; width: parent.width; text: win.isSteam ? Games.steamLaunchOptions(win.sel.id) : "" }
                                Row {
                                    spacing: 10
                                    GButton {
                                        text: copied.running ? "Copied" : "Copy"
                                        onClicked: { soText.copy(); copied.restart(); }
                                        Timer { id: copied; interval: 1500 }
                                    }
                                }
                                Text {
                                    width: parent.width; wrapMode: Text.WordWrap
                                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11
                                    text: "Paste into Steam > right-click the game > Properties > General > Launch options. "
                                        + "Steam, not Ultimit, starts this game, so these settings only apply through that line. "
                                        + (win.isSteam ? Games.steamOptionsNote(win.sel.id) : "")
                                }
                            }
                        }
                    }
                }

                // Launch stays pinned under the scrolling detail pane
                GButton {
                    anchors.bottom: parent.bottom
                    width: detail.width - 10
                    primary: true
                    text: win.isSteam ? "Launch with Steam" : "Launch"
                    onClicked: Games.launch(win.sel.id)
                }
            }
        }

        AddGameDialog { id: addDlg }
    }
}
