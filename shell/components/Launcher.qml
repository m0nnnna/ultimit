// Launcher.qml - app launcher opened from the rail emblem (or `qs ipc call launcher toggle`).
// Overlay-layer, full-screen transparent window (so clicks outside close it) with exclusive
// keyboard focus; the glass panel sits beside the rail, top-left, with mockup corner brackets.
// Apps come from Quickshell's DesktopEntries (NoDisplay entries skipped).
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    // Set by shell.qml (avoids a visible <-> screen binding loop).
    property string screenName: ""

    visible: Config.launcherOpen && Config.isUiScreen(screenName)
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property string query: ""
    property var results: []

    // ---- filtering ----
    function subseq(needle, hay) {
        let i = 0;
        for (let j = 0; j < hay.length && i < needle.length; j++) if (hay[j] === needle[i]) i++;
        return i === needle.length;
    }
    function score(e, q) {
        const n = (e.name || "").toLowerCase();
        if (n.startsWith(q)) return 100;
        if (n.indexOf(" " + q) >= 0) return 90;
        if (n.indexOf(q) >= 0) return 80;
        const g = (e.genericName || "").toLowerCase();
        if (g.indexOf(q) >= 0) return 60;
        const kw = (e.keywords || []).join(" ").toLowerCase();
        if (kw.indexOf(q) >= 0) return 50;
        if ((e.comment || "").toLowerCase().indexOf(q) >= 0) return 30;
        if (q.length >= 3 && subseq(q, n)) return 20;
        return 0;
    }
    function refilter() {
        const q = query.trim().toLowerCase();
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay && Config.launcherHidden.indexOf(e.id) < 0);
        let out;
        if (q === "") {
            out = all.slice().sort((a, b) => a.name.localeCompare(b.name));
        } else {
            out = all.map(e => ({ e: e, s: score(e, q) })).filter(x => x.s > 0)
                .sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name)).map(x => x.e);
        }
        results = out;
        list.currentIndex = out.length ? 0 : -1;
    }
    onQueryChanged: refilter()
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { win.refilter(); }
    }
    onVisibleChanged: {
        if (visible) {
            query = ""; search.text = ""; refilter();
            list.positionViewAtBeginning();
            search.forceActiveFocus();
            powerRow.disarmAll();
        }
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

        opacity: win.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(180); easing.type: Easing.OutCubic } }

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
                        if (event.key === Qt.Key_Escape) { Config.closeLauncher(); event.accepted = true; }
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

                    readonly property string iconSrc: modelData.icon ? Icons.path(modelData.icon) : ""
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
                        Rectangle {   // fallback: bordered initial
                            anchors.fill: parent
                            visible: row.iconSrc === ""
                            color: "transparent"; border.width: 1; border.color: Theme.lineStrong
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
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: list.currentIndex = row.index
                        onClicked: win.runEntry(row.modelData)
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

        // bottom row: power actions
        Item {
            id: powerRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 14
            height: 28
            function disarmAll() { lockB.disarm(); outB.disarm(); rebB.disarm(); offB.disarm(); }
            Rectangle { x: 0; y: -8; width: parent.width; height: 1; color: Theme.line }
            Row {
                spacing: 8
                PowerButton { id: lockB; text: "Lock"; onActivated: { Config.closeLauncher(); Config.lock(); } }
                PowerButton {
                    id: outB; text: "Log out"; confirm: true
                    onActivated: win.power("loginctl terminate-session \"$XDG_SESSION_ID\"")
                    onArmedChanged: if (armed) { rebB.disarm(); offB.disarm(); }
                }
                PowerButton {
                    id: rebB; text: "Restart"; confirm: true
                    onActivated: win.power("systemctl reboot")
                    onArmedChanged: if (armed) { outB.disarm(); offB.disarm(); }
                }
                PowerButton {
                    id: offB; text: "Shut down"; confirm: true
                    onActivated: win.power("systemctl poweroff")
                    onArmedChanged: if (armed) { outB.disarm(); rebB.disarm(); }
                }
            }
        }
    }
}
