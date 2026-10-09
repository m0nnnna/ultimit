// GamesWindow.qml - the Games app: a normal xdg toplevel (the compositor draws
// the titlebar/frame). Instantiate once from shell.qml:  GamesWindow {}
// Open/close: Games.toggle() or  `qs -p <shell> ipc call games toggle`.
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
    implicitWidth: 760
    implicitHeight: 500
    minimumSize: Qt.size(560, 380)
    color: Theme.bg1

    onVisibleChanged: if (visible !== Games.open) Games.open = visible

    IpcHandler {
        target: "games"
        function toggle(): void { Games.toggle(); }
        function open(): void { Games.show(); }
        function close(): void { Games.hide(); }
    }

    readonly property var sel: Games.selected
    readonly property var cfg: sel ? Games.setting(sel.appid) : null

    property alias content: panelRoot   // root item (used for screenshots/tests)

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
            Text {
                anchors.left: sq.right; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "LIBRARY"
                color: Theme.fg
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
            }
            Text {
                id: count
                anchors.right: rescan.left; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: Games.steamRoot !== "" ? Games.games.length + (Games.games.length === 1 ? " title" : " titles") : ""
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Text {
                id: rescan
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "RESCAN"
                color: rescanMouse.containsMouse ? Theme.accent : Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                MouseArea {
                    id: rescanMouse
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Games.rescan()
                }
            }
        }

        // ---- empty: Steam missing ----
        Item {
            anchors { left: parent.left; right: parent.right; top: lbl.bottom; bottom: parent.bottom; margins: 16 }
            visible: Games.loaded && Games.steamRoot === ""
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width, 420)
                spacing: 14
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "games"; color: Theme.dim }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Steam isn't installed"
                    color: Theme.fg
                    font.family: Theme.display; font.pixelSize: 16; font.letterSpacing: 0.5
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Ultimit reads your installed games from Steam. Install it from a terminal, sign in once, then press Rescan."
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 13
                }
                CopyText { width: parent.width; text: Games.installCommand }
                GButton { anchors.horizontalCenter: parent.horizontalCenter; text: "Rescan"; onClicked: Games.rescan() }
            }
        }

        // ---- empty: Steam present, no games ----
        Item {
            anchors { left: parent.left; right: parent.right; top: lbl.bottom; bottom: parent.bottom; margins: 16 }
            visible: Games.loaded && Games.steamRoot !== "" && Games.games.length === 0
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width, 420)
                spacing: 14
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No games installed"
                    color: Theme.fg
                    font.family: Theme.display; font.pixelSize: 16
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Steam was found but no installed games turned up. Install something from Steam and it will appear here."
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 13
                }
            }
        }

        // ---- library + detail ----
        Item {
            id: body
            anchors { left: parent.left; right: parent.right; top: lbl.bottom; bottom: parent.bottom
                      leftMargin: 16; rightMargin: 16; topMargin: 12; bottomMargin: 16 }
            visible: Games.games.length > 0
            readonly property real leftW: (width - 16) / 2.3

            // library grid
            GridView {
                id: grid
                width: body.leftW
                height: parent.height
                clip: true
                model: Games.games
                readonly property int cols: Math.max(2, Math.floor(width / 128))
                cellWidth: Math.floor(width / cols)
                cellHeight: Math.round(cellWidth * 4 / 3) + 10
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    readonly property bool isSel: Games.selected && Games.selected.appid === modelData.appid

                    Item {
                        id: tile
                        x: 2; y: 2
                        width: parent.width - 10; height: parent.height - 10
                        clip: true
                        Rectangle { anchors.fill: parent; color: Theme.panel2 }
                        Item {
                            id: art
                            anchors.fill: parent
                            scale: tileMouse.containsMouse ? 1.04 : 1
                            Behavior on scale { NumberAnimation { duration: 300 } }
                            GradArt { anchors.fill: parent; stops: Games.palette(cell.modelData.appid); visible: img.status !== Image.Ready }
                            Image {
                                id: img
                                anchors.fill: parent
                                source: cell.modelData.portrait ? "file://" + cell.modelData.portrait : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 300
                            }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: nm.implicitHeight + 30
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
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
                        Rectangle { anchors.fill: parent; color: "transparent"; border.color: Theme.line; border.width: 1 }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Games.selectedId = cell.modelData.appid
                        }
                    }
                    // selection outline (offset 2px)
                    Rectangle {
                        visible: cell.isSel
                        x: tile.x - 2; y: tile.y - 2
                        width: tile.width + 4; height: tile.height + 4
                        color: "transparent"; border.color: Theme.accent; border.width: 2
                    }
                }
            }

            // detail pane
            Flickable {
                id: detail
                x: body.leftW + 16
                width: parent.width - x
                height: parent.height - 46
                clip: true
                contentWidth: width
                contentHeight: col.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: col
                    width: detail.width - 8
                    spacing: 12
                    visible: win.sel !== null

                    // hero
                    Rectangle {
                        width: parent.width; height: 110
                        color: "transparent"
                        border.color: Theme.line; border.width: 1
                        clip: true
                        GradArt { anchors.fill: parent; stops: win.sel ? Games.palette(win.sel.appid) : []; visible: hero.status !== Image.Ready }
                        Image {
                            id: hero
                            anchors.fill: parent
                            source: win.sel && win.sel.header ? "file://" + win.sel.header : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 700
                        }
                        Rectangle { anchors.fill: parent; color: "transparent"; border.color: Theme.line; border.width: 1 }
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
                        GChip {
                            text: win.sel && win.sel.compat === "proton" ? "Proton" : "Native"
                            tone: win.sel && win.sel.compat === "proton" ? Theme.dim : Theme.ok
                        }
                        GChip {
                            text: win.sel && win.sel.ready ? "Installed" : "Update pending"
                            tone: win.sel && win.sel.ready ? Theme.ok : Theme.warn
                        }
                    }
                    Grid {
                        columns: 1; rowSpacing: 4
                        Repeater {
                            model: win.sel ? [
                                ["Size", Games.fmtSize(win.sel.size)],
                                ["Last", Games.fmtLast(win.sel.lastPlayed)],
                                ["App ID", win.sel.appid]
                            ] : []
                            delegate: Row {
                                id: kvRow
                                required property var modelData
                                Text {
                                    width: 56
                                    text: kvRow.modelData[0].toUpperCase()
                                    color: Theme.dim
                                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                                    topPadding: 2
                                }
                                Text {
                                    text: kvRow.modelData[1]
                                    color: Theme.fg
                                    font.family: Theme.ui; font.pixelSize: 12
                                }
                            }
                        }
                    }

                    // one-time launch-option hint
                    Rectangle {
                        visible: !Games.settings.hintDismissed
                        width: parent.width
                        implicitHeight: hintCol.implicitHeight + 20
                        height: implicitHeight
                        color: "transparent"
                        border.color: Theme.lineStrong; border.width: 1
                        Column {
                            id: hintCol
                            x: 10; y: 10
                            width: parent.width - 20
                            spacing: 8
                            Text {
                                width: parent.width
                                text: "ONE-TIME SETUP"
                                color: Theme.accent
                                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "For these settings to apply, set this game's Steam launch option (Properties > General) to:"
                                color: Theme.dim
                                font.family: Theme.ui; font.pixelSize: 12
                            }
                            CopyText { width: parent.width; text: Games.launchOption }
                            GButton { text: "Got it"; onClicked: Games.dismissHint() }
                        }
                    }

                    // GPU select
                    Column {
                        id: gpuField
                        width: parent.width
                        spacing: 6
                        property bool expanded: false
                        readonly property var options: [
                            { id: "auto", label: "Auto" },
                            { id: "nvidia", label: "NVIDIA dGPU" },
                            { id: "integrated", label: "Integrated" }
                        ]
                        function labelOf(id) {
                            for (const o of options) if (o.id === id) return o.label;
                            return "Auto";
                        }
                        Text {
                            text: "RENDER ON"
                            color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                        }
                        Rectangle {
                            width: parent.width; height: 32
                            color: Theme.panel2
                            border.color: Theme.line; border.width: 1
                            Text {
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                text: win.cfg ? gpuField.labelOf(win.cfg.gpu) : ""
                                color: Theme.fg
                                font.family: Theme.ui; font.pixelSize: 13
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: gpuField.expanded ? "▴" : "▾"
                                color: Theme.dim
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gpuField.expanded = !gpuField.expanded
                            }
                        }
                        Column {
                            visible: gpuField.expanded
                            width: parent.width
                            Repeater {
                                model: gpuField.options
                                delegate: Rectangle {
                                    id: opt
                                    required property var modelData
                                    readonly property bool ok: modelData.id !== "nvidia" || Games.tools.nvidia
                                    width: col.width; height: 30
                                    color: optMouse.containsMouse && ok ? Theme.panel2 : "transparent"
                                    border.color: Theme.line; border.width: 1
                                    opacity: ok ? 1 : 0.55
                                    Rectangle {
                                        visible: win.cfg && win.cfg.gpu === opt.modelData.id
                                        width: 2; height: parent.height; color: Theme.accent
                                    }
                                    Text {
                                        x: 10; anchors.verticalCenter: parent.verticalCenter
                                        text: opt.modelData.label
                                        color: Theme.fg
                                        font.family: Theme.ui; font.pixelSize: 13
                                    }
                                    GChip {
                                        visible: !opt.ok
                                        anchors.right: parent.right; anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "no driver"; tone: Theme.warn
                                    }
                                    MouseArea {
                                        id: optMouse
                                        anchors.fill: parent
                                        enabled: opt.ok
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Games.setSetting(win.sel.appid, "gpu", opt.modelData.id);
                                            gpuField.expanded = false;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // toggles
                    GToggle {
                        width: parent.width
                        label: "GameMode"
                        available: Games.tools.gamemode
                        checked: win.cfg ? win.cfg.gamemode : false
                        onToggled: v => Games.setSetting(win.sel.appid, "gamemode", v)
                    }
                    GToggle {
                        width: parent.width
                        label: "Performance overlay"
                        available: Games.tools.mangohud
                        checked: win.cfg ? win.cfg.overlay : false
                        onToggled: v => Games.setSetting(win.sel.appid, "overlay", v)
                    }
                    GToggle {
                        width: parent.width
                        label: "Run in Gamescope"
                        available: Games.tools.gamescope
                        checked: win.cfg ? win.cfg.gamescope : false
                        onToggled: v => Games.setSetting(win.sel.appid, "gamescope", v)
                    }
                }
            }

            // Launch stays pinned under the scrolling detail pane
            GButton {
                x: detail.x
                width: detail.width - 8
                anchors.bottom: parent.bottom
                visible: win.sel !== null
                primary: true
                text: "Launch"
                onClicked: Games.launch(win.sel.appid)
            }
        }
    }
}
