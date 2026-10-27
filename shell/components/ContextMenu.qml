// ContextMenu.qml - desktop right-click menu (opened by Wallpaper via Config.openMenu).
// Overlay-layer full-screen transparent window: click-outside / Escape closes, exclusive
// keyboard focus for arrow-key navigation. The panel opens at the cursor and is clamped
// on screen; "Skin" opens a side panel (flips left when there is no room on the right).
// Opened on a photo frame (Config.menuFrame) it lists that frame's items instead.
// Styled like the mockup popups: an L1 Surface, accent hover row, small mono labels.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../apps/data"

PanelWindow {
    id: win

    // Set by shell.qml (avoids a visible <-> screen binding loop).
    property string screenName: ""

    visible: Config.menuOpen && Config.isUiScreen(screenName)
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-menu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int rowH: Theme.space(8)
    readonly property int menuW: 232
    readonly property int subW: 168

    readonly property var skinList: [
        { id: "mine", n: "Mine" }, { id: "amber", n: "Amber" },
        { id: "silver", n: "Silver" }, { id: "verdant", n: "Verdant" },
        { id: "sakura", n: "Sakura" }, { id: "paper", n: "Paper" }, { id: "void", n: "Void" }
    ]
    // kind: "item" | "sep"
    readonly property var desktopItems: [
        { id: "term",    label: "Open Terminal" },
        { id: "files",   label: "Files" },
        { id: "launch",  label: "App launcher" },
        { id: "acc",     label: "Accessory" },
        { id: "skin",    label: "Skin", sub: true },
        { kind: "sep" },
        { id: "frame",   label: "Add photo frame…" },
        { id: "motion",  label: "Animate shards", check: true },
        { id: "boot",    label: "Play boot sequence" }
    ]
    readonly property var frameItems: [
        { id: "flock",   label: "Lock in place", check: true },
        { id: "fopen",   label: "Open in IMAGE" },
        { id: "fpic",    label: "Change picture…" },
        { kind: "sep" },
        { id: "fremove", label: "Remove frame" }
    ]
    readonly property var items: Config.menuFrame !== "" ? frameItems : desktopItems
    readonly property int skinIndex: items.findIndex(it => it.id === "skin")
    function checked(it) {
        if (it.id === "motion") return Config.motion;
        if (it.id === "flock") { const f = Frames.byId(Config.menuFrame); return !!(f && f.locked); }
        return false;
    }
    readonly property int menuH: {
        let h = Theme.space(4);
        for (const it of items) h += it.kind === "sep" ? 8 : rowH;
        return h;
    }

    property int cur: -1          // highlighted row index in items
    property bool subOpen: false
    property int subCur: 0

    onVisibleChanged: if (visible) { cur = -1; subOpen = false; keys.forceActiveFocus(); }

    function close() { Config.closeMenu(); }
    function activate(it) {
        if (!it || it.kind === "sep") return;
        switch (it.id) {
        case "skin": subOpen = true; subCur = Math.max(0, skinList.findIndex(s => s.id === Theme.skin)); return;
        case "motion": Config.motion = !Config.motion; break;
        case "term": close(); Config.openTerminal(); return;
        case "files": close(); Data.show(""); return;
        case "launch": Config.openLauncher(win.screenName); return;
        case "acc": close(); Config.openSettings(""); return;
        case "boot": close(); Config.playBoot(); return;
        case "frame": close(); Frames.pick(win.screenName, Config.menuX, Config.menuY, ""); return;
        case "flock": { const f = Frames.byId(Config.menuFrame); if (f) Frames.setLocked(f.id, !f.locked); break; }
        case "fopen": Frames.openInImage(Config.menuFrame); break;
        case "fpic": Frames.pick(win.screenName, -1, -1, Config.menuFrame); break;
        case "fremove": Frames.remove(Config.menuFrame); break;
        }
        close();
    }
    function step(d) {
        let i = cur;
        for (let n = 0; n < items.length; n++) {
            i = (i + d + items.length) % items.length;
            if (items[i].kind !== "sep") { cur = i; return; }
        }
    }
    function rowY(idx) {
        let y = Theme.space(2);
        for (let i = 0; i < idx; i++) y += items[i].kind === "sep" ? 8 : rowH;
        return y;
    }

    MouseArea {   // click anywhere outside closes
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: win.close()
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            event.accepted = true;
            if (event.key === Qt.Key_Escape) { if (win.subOpen) win.subOpen = false; else win.close(); }
            else if (win.subOpen) {
                if (event.key === Qt.Key_Down) win.subCur = (win.subCur + 1) % win.skinList.length;
                else if (event.key === Qt.Key_Up) win.subCur = (win.subCur + win.skinList.length - 1) % win.skinList.length;
                else if (event.key === Qt.Key_Left) win.subOpen = false;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    Theme.skin = win.skinList[win.subCur].id; win.close();
                } else event.accepted = false;
            } else {
                if (event.key === Qt.Key_Down) win.step(1);
                else if (event.key === Qt.Key_Up) win.step(-1);
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (win.cur >= 0) win.activate(win.items[win.cur]);
                } else event.accepted = false;
            }
        }
    }

    Surface {
        id: menu
        brackets: true; bracketSize: 8
        x: Math.max(8, Math.min(Config.menuX, win.width - width - 8))
        y: Math.max(8, Math.min(Config.menuY, win.height - height - 8))
        width: win.menuW; height: win.menuH
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Repeater {
            model: win.items
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool sep: modelData.kind === "sep"
                x: 0; y: win.rowY(index)
                width: menu.width; height: sep ? 8 : win.rowH
                readonly property bool hot: win.cur === index

                Rectangle {   // separator
                    visible: row.sep
                    x: Theme.space(3); anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.space(6); height: 1; color: Theme.divider
                }
                Rectangle {   // hover row
                    visible: !row.sep
                    anchors.fill: parent; anchors.leftMargin: Theme.space(1); anchors.rightMargin: Theme.space(1)
                    color: row.hot ? Theme.hover : Theme.clear(Theme.hover)
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    Rectangle {
                        width: 2; height: parent.height; color: Theme.accent
                        opacity: row.hot ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    }
                }
                Text {
                    visible: !row.sep
                    x: Theme.space(4); anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label ? row.modelData.label.toUpperCase() : ""
                    color: row.hot ? Theme.accent : Theme.fg
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
                }
                Text {   // check mark / submenu arrow
                    visible: !row.sep
                    anchors.right: parent.right; anchors.rightMargin: Theme.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool on: !!row.modelData.check && win.checked(row.modelData)
                    text: row.modelData.sub ? "▸" : (on ? "■" : (row.modelData.check ? "□" : ""))
                    color: on ? Theme.accent : Theme.dim
                    font.family: Theme.mono; font.pixelSize: Theme.type.label
                }
                MouseArea {
                    enabled: !row.sep
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        win.cur = row.index;
                        win.subOpen = !!row.modelData.sub;
                        if (win.subOpen) win.subCur = Math.max(0, win.skinList.findIndex(s => s.id === Theme.skin));
                    }
                    onClicked: win.activate(row.modelData)
                }
            }
        }
    }

    // Skin submenu
    Surface {
        id: sub
        brackets: true; bracketSize: 8
        visible: win.subOpen
        readonly property real skinRowY: menu.y + win.rowY(Math.max(0, win.skinIndex))
        readonly property bool flip: menu.x + menu.width + width + 4 > win.width
        x: flip ? menu.x - width - 2 : menu.x + menu.width + 2
        y: Math.max(8, Math.min(skinRowY - Theme.space(2), win.height - height - 8))
        width: win.subW; height: win.skinList.length * win.rowH + Theme.space(4)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Repeater {
            model: win.skinList
            delegate: Item {
                id: srow
                required property var modelData
                required property int index
                x: 0; y: Theme.space(2) + index * win.rowH
                width: sub.width; height: win.rowH
                readonly property bool hot: win.subCur === index
                Rectangle {
                    anchors.fill: parent; anchors.leftMargin: 1; anchors.rightMargin: 1
                    color: srow.hot ? Theme.hover : Theme.clear(Theme.hover)
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    Rectangle {
                        width: 2; height: parent.height; color: Theme.accent
                        opacity: srow.hot ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    }
                }
                Text {
                    x: Theme.space(4); anchors.verticalCenter: parent.verticalCenter
                    text: srow.modelData.n.toUpperCase()
                    color: srow.hot ? Theme.accent : Theme.fg
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: Theme.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Theme.skin === srow.modelData.id
                    text: "■"; color: Theme.accent
                    font.family: Theme.mono; font.pixelSize: Theme.type.label
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: win.subCur = srow.index
                    onClicked: { Theme.skin = srow.modelData.id; win.close(); }
                }
            }
        }
    }
}
