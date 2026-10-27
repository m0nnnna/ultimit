// Launcher.qml - app launcher opened from the rail emblem (or `qs ipc call launcher toggle`).
// Overlay-layer, full-screen transparent window (so clicks outside close it) with exclusive
// keyboard focus; the L1 Surface sits beside the rail, top-left, with mockup corner brackets.
// Apps come from Quickshell's DesktopEntries (NoDisplay entries skipped).
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    // Set by shell.qml (avoids a visible <-> screen binding loop).
    property string screenName: ""

    // Open state; the window stays mapped until the panel has faded out so
    // closing animates too, and lets clicks through while it fades.
    readonly property bool shown: Config.launcherOpen && Config.isUiScreen(screenName)
    visible: shown || panel.opacity > 0.01
    mask: shown ? null : noInput
    Region { id: noInput }
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-launcher"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string query: ""
    property var results: []

    // ---- filtering (AppSearch.qml, shared with Settings -> Rail) ----
    // `results` (entries, best first) is what the keys and Enter use; `rows` mirrors its ids in a
    // ListModel so the list can run a displaced transition: rows slide into place while typing
    // instead of the whole list being rebuilt. Only removals and moves animate; adds just appear.
    property var byId: ({})
    ListModel { id: rows }
    function syncRows(reset) {
        const ids = results.map(e => e.id);
        if (reset) {
            rows.clear();
            for (const id of ids) rows.append({ eid: id });
            return;
        }
        const want = {};
        for (const id of ids) want[id] = true;
        for (let i = rows.count - 1; i >= 0; i--) if (!want[rows.get(i).eid]) rows.remove(i);
        for (let i = 0; i < ids.length; i++) {
            if (i < rows.count && rows.get(i).eid === ids[i]) continue;
            let j = -1;
            for (let k = i + 1; k < rows.count; k++) if (rows.get(k).eid === ids[i]) { j = k; break; }
            if (j >= 0) rows.move(j, i, 1);
            else rows.insert(i, { eid: ids[i] });
        }
    }
    function refilter(reset) {
        results = AppSearch.filter(query);
        const m = {};
        for (const e of results) m[e.id] = e;
        byId = m;
        syncRows(reset === true);
        list.currentIndex = results.length ? 0 : -1;
    }
    onQueryChanged: refilter()
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { win.refilter(true); }
    }
    onShownChanged: {
        if (shown) {
            query = ""; search.text = ""; refilter(true);
            list.positionViewAtBeginning();
            search.forceActiveFocus();
        }
        ctxOpen = false;
    }

    // ---- right-click menu: Pin to rail / Unpin from rail ----
    property bool ctxOpen: false
    property var ctxEntry: null
    property real ctxX: 0
    property real ctxY: 0
    readonly property var ctxItems: {
        const e = ctxEntry;
        Pins.specs;   // re-evaluate when the pins change
        if (!e) return [];
        return [{ id: "pin", label: Pins.hasDesktop(e.id) ? "Unpin from rail" : "Pin to rail" }];
    }
    function openCtx(e, x, y) {   // x, y in panel coordinates
        ctxEntry = e; ctxX = x; ctxY = y; ctxPm.cur = 0; ctxOpen = true;
    }
    function ctxActivate(it) {
        const e = ctxEntry;
        ctxOpen = false;
        if (!e || !it) return;
        if (Pins.hasDesktop(e.id)) Pins.unpin("app:" + e.id);
        else Pins.pinEntry(e);
    }

    function runEntry(e) {
        if (!e) return;
        Config.closeLauncher();
        e.execute();
    }

    // click outside the panel closes
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: Config.closeLauncher()
    }

    Surface {
        id: panel
        glow: true; brackets: true
        elevation: 2; shadowNs: "ultimit-launcher"; shadowWanted: win.shown
        x: Config.railWidth + 12
        y: 12
        width: 420
        height: Math.min(win.height - 24, 600)
        // swallow clicks
        MouseArea { anchors.fill: parent }

        opacity: win.shown ? 1 : 0
        ShowBehavior on opacity { ms: Theme.motion.base }
        // Slides out of / back into the rail.
        transform: Translate {
            x: win.shown ? 0 : -14
            ShowBehavior on x { ms: Theme.motion.base; hidden: -14 }
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.space(4)
            spacing: Theme.space(3)

            DecodeText {
                text: "APPLICATIONS"
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2.4
            }

            // search field
            Rectangle {
                width: parent.width; height: Theme.space(9)
                color: Theme.field
                border.width: 1
                border.color: search.activeFocus ? Theme.accent : Theme.line
                Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                Text {
                    x: Theme.space(3); anchors.verticalCenter: parent.verticalCenter
                    text: "›"; color: Theme.accent
                    font.family: Theme.mono; font.pixelSize: Theme.type.title
                }
                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space(8); anchors.rightMargin: Theme.space(3)
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                    font.family: Theme.ui; font.pixelSize: Theme.type.body
                    clip: true
                    focus: true
                    onTextChanged: win.query = text
                    Keys.onPressed: event => {
                        if (win.ctxOpen) {   // the pin menu has the keyboard
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.ctxActivate(win.ctxItems[Math.max(0, ctxPm.cur)]);
                            else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left) win.ctxOpen = false;
                            event.accepted = true; return;
                        }
                        if (event.key === Qt.Key_Menu) {
                            const cur = win.results[list.currentIndex];
                            if (cur && list.currentItem) win.openCtx(cur, 60, list.mapToItem(panel, 0, 0).y + list.currentItem.y - list.contentY + 22);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) { Config.closeLauncher(); event.accepted = true; }
                        else if (event.key === Qt.Key_Down) { list.incrementCurrentIndex(); event.accepted = true; }
                        else if (event.key === Qt.Key_Up) { list.decrementCurrentIndex(); event.accepted = true; }
                        else if (event.key === Qt.Key_PageDown) { list.currentIndex = Math.min(list.count - 1, list.currentIndex + 8); event.accepted = true; }
                        else if (event.key === Qt.Key_PageUp) { list.currentIndex = Math.max(0, list.currentIndex - 8); event.accepted = true; }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            win.runEntry(win.results[list.currentIndex]); event.accepted = true;
                        }
                    }
                    Text {
                        visible: search.text === ""
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Type to search"
                        color: Theme.dim
                        font: search.font
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - y
                clip: true
                model: rows
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationEnabled: false
                spacing: 0
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase }
                }

                delegate: Rectangle {
                    id: row
                    required property string eid
                    required property int index
                    readonly property var modelData: win.byId[eid] || ({ id: eid, name: "", icon: "" })
                    readonly property bool cur: ListView.isCurrentItem
                    width: list.width
                    height: Theme.space(11)
                    color: cur ? Theme.selection : (rowMouse.containsMouse ? Theme.hover : Theme.clear(Theme.selection))
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    Rectangle {
                        x: 0; width: 2; height: parent.height; color: Theme.accent
                        opacity: row.cur ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    }

                    // A real icon wins over the letter badge in every icon mode (Icons.path: skin theme, user hicolor,
                    // then the system and Flatpak icon themes); the badge is the last resort.
                    readonly property string iconSrc: modelData.icon ? Icons.path(modelData.icon) : ""
                    Item {
                        id: ico
                        x: Theme.space(3); anchors.verticalCenter: parent.verticalCenter
                        width: Theme.icon.lg; height: Theme.icon.lg
                        Image {
                            id: iconImg
                            anchors.fill: parent
                            visible: row.iconSrc !== "" && status === Image.Ready
                            source: row.iconSrc
                            sourceSize: Qt.size(Theme.icon.lg * 2, Theme.icon.lg * 2)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        IconBadge {   // letter badge (other apps' icons, Config.appIcons)
                            anchors.fill: parent
                            visible: row.iconSrc === "" || iconImg.status !== Image.Ready
                            opacity: 0.7
                            size: Theme.icon.lg
                            letter: (row.modelData.name || "?").charAt(0).toUpperCase()
                        }
                    }
                    Column {
                        anchors.left: ico.right; anchors.leftMargin: Theme.space(3)
                        anchors.right: parent.right; anchors.rightMargin: Theme.space(3)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: AppSearch.label(row.modelData)
                            color: Theme.fg
                            font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.body
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            visible: text !== ""
                            text: {
                                const t = row.modelData.genericName || row.modelData.comment || "";
                                const h = AppSearch.hint(row.modelData);
                                return h === "" ? t : (t === "" ? h : t + " · " + h);
                            }
                            color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: Theme.type.label
                        }
                    }
                    Rectangle {   // pinned marker
                        visible: { Pins.specs; return Pins.hasDesktop(row.modelData.id); }
                        anchors.right: parent.right; anchors.rightMargin: Theme.space(3)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; color: Theme.accent
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPositionChanged: list.currentIndex = row.index
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                const p = rowMouse.mapToItem(panel, mouse.x, mouse.y);
                                win.openCtx(row.modelData, p.x, p.y);
                            } else win.runEntry(row.modelData);
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "No matches"
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: Theme.type.body
                }
            }
        }

        // right-click menu (inside the panel; a click anywhere else closes it)
        Item {
            id: ctxLayer
            anchors.fill: parent
            visible: win.ctxOpen
            z: 50
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: win.ctxOpen = false
            }
            PopupMenu {
                id: ctxPm
                x: Math.max(4, Math.min(win.ctxX, panel.width - width - 4))
                y: Math.max(4, Math.min(win.ctxY, panel.height - height - 4))
                items: win.ctxItems
                onActivated: item => win.ctxActivate(item)
            }
        }
    }
}
