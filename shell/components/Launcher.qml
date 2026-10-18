// Launcher.qml - app launcher opened from the rail emblem (or `qs ipc call launcher toggle`).
// Overlay-layer, full-screen transparent window (so clicks outside close it) with exclusive
// keyboard focus; the glass panel sits beside the rail, top-left, with mockup corner brackets.
// Apps come from Quickshell's DesktopEntries (NoDisplay entries skipped).
import QtQuick
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
    function refilter() {
        results = AppSearch.filter(query);
        list.currentIndex = results.length ? 0 : -1;
    }
    onQueryChanged: refilter()
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { win.refilter(); }
    }
    onShownChanged: {
        if (shown) {
            query = ""; search.text = ""; refilter();
            list.positionViewAtBeginning();
            search.forceActiveFocus();
            powerRow.disarmAll();
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
    function power(cmd) {
        Config.closeLauncher();
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    // click outside the panel closes
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: Config.closeLauncher()
    }

    Rectangle {
        id: panel
        x: Config.railWidth + 10
        y: 10
        width: 420
        height: Math.min(win.height - 20, 600)
        color: Theme.panel
        border.width: 1
        border.color: Theme.lineStrong
        // swallow clicks
        MouseArea { anchors.fill: parent }
        Brackets {}

        opacity: win.shown ? 1 : 0
        ShowBehavior on opacity { ms: 180 }
        // Slides out of / back into the rail.
        transform: Translate {
            x: win.shown ? 0 : -14
            ShowBehavior on x { ms: 180; hidden: -14 }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Text {
                text: "APPLICATIONS"
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4
            }

            // search field
            Rectangle {
                width: parent.width; height: 34
                color: Theme.panel2
                border.width: 1
                border.color: search.activeFocus ? Theme.accent : Theme.line
                Text {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    text: "›"; color: Theme.accent
                    font.family: Theme.mono; font.pixelSize: 16
                }
                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 28; anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                    font.family: Theme.ui; font.pixelSize: 14
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
                height: parent.height - y - powerRow.height - 10 - 4
                clip: true
                model: win.results
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationEnabled: false
                spacing: 0

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool cur: ListView.isCurrentItem
                    width: list.width
                    height: 44
                    color: (cur || rowMouse.containsMouse) ? Theme.panel2 : "transparent"
                    Rectangle { x: 0; width: 2; height: parent.height; color: Theme.accent; visible: row.cur }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; opacity: .5 }

                    readonly property string iconSrc: modelData.icon ? Icons.app(modelData.icon) : ""
                    Item {
                        id: ico
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28
                        Image {
                            anchors.fill: parent
                            visible: row.iconSrc !== "" && status === Image.Ready
                            source: row.iconSrc
                            sourceSize: Qt.size(56, 56)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Item {   // letter tile (other apps' icons, Config.appIcons): the WINDOWS list's chamfer frame
                            anchors.fill: parent
                            visible: row.iconSrc === ""
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeWidth: 1
                                    strokeColor: Theme.lineStrong
                                    fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                                    joinStyle: ShapePath.MiterJoin
                                    startX: 0.5; startY: 0.5
                                    PathLine { x: 22.5; y: 0.5 }
                                    PathLine { x: 27.5; y: 5.5 }
                                    PathLine { x: 27.5; y: 27.5 }
                                    PathLine { x: 5.5; y: 27.5 }
                                    PathLine { x: 0.5; y: 22.5 }
                                    PathLine { x: 0.5; y: 0.5 }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: (row.modelData.name || "?").charAt(0).toUpperCase()
                                color: Theme.fg; font.family: Theme.display; font.pixelSize: 12
                            }
                        }
                    }
                    Column {
                        anchors.left: ico.right; anchors.leftMargin: 12
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: row.modelData.name
                            color: Theme.fg
                            font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 13
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            visible: text !== ""
                            text: row.modelData.genericName || row.modelData.comment || ""
                            color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10
                        }
                    }
                    Rectangle {   // pinned marker
                        visible: { Pins.specs; return Pins.hasDesktop(row.modelData.id); }
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5; height: 5; color: Theme.accent
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
                    text: "NO MATCHES"
                    color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2
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

        // bottom row: power actions
        Item {
            id: powerRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 14
            height: pflow.height
            function disarmAll() { lockB.disarm(); outB.disarm(); hibB.disarm(); rebB.disarm(); offB.disarm(); }
            Rectangle { x: 0; y: -8; width: parent.width; height: 1; color: Theme.line }
            Flow {
                id: pflow
                width: parent.width
                spacing: 8
                PowerButton { id: lockB; text: "Lock"; onActivated: { Config.closeLauncher(); Config.lock(); } }
                PowerButton {
                    id: outB; text: "Log out"; confirm: true
                    onActivated: win.power("loginctl terminate-session \"$XDG_SESSION_ID\"")
                    onArmedChanged: if (armed) { hibB.disarm(); rebB.disarm(); offB.disarm(); }
                }
                PowerButton { id: susB; text: "Sleep"; onActivated: win.power("systemctl suspend") }
                PowerButton {
                    id: hibB; text: "Hibernate"; confirm: true
                    visible: SysState.canHibernate
                    onActivated: win.power("systemctl hibernate")
                    onArmedChanged: if (armed) { outB.disarm(); rebB.disarm(); offB.disarm(); }
                }
                PowerButton {
                    id: rebB; text: "Restart"; confirm: true
                    onActivated: win.power("systemctl reboot")
                    onArmedChanged: if (armed) { outB.disarm(); hibB.disarm(); offB.disarm(); }
                }
                PowerButton {
                    id: offB; text: "Shut down"; confirm: true
                    onActivated: win.power("systemctl poweroff")
                    onArmedChanged: if (armed) { outB.disarm(); hibB.disarm(); rebB.disarm(); }
                }
            }
        }
    }
}
