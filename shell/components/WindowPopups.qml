// WindowPopups.qml - overlay popups for the rail window list: a hover tooltip (click-through)
// and the per-window right-click menu (full-screen overlay, click-outside / Escape closes).
// Styled like the mockup popups / ContextMenu: panel fill, 1px line, mono caps, accent hover row.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Scope {
    id: root
    property var screen: null
    property string screenName: ""

    // ---- tooltip ----
    PanelWindow {
        screen: root.screen
        visible: WindowUi.tipText !== "" && WindowUi.tipScreen === root.screenName && !WindowUi.menuOpen
        readonly property bool bar: WindowUi.tipX >= 0
        anchors { left: true; top: !bar; bottom: bar }
        margins.left: bar ? Math.max(4, Math.min(WindowUi.tipX - width / 2, (screen ? screen.width : 4000) - width - 4))
            : Config.railWidth + 6
        margins.top: Math.max(4, WindowUi.tipY - height / 2)
        margins.bottom: Config.tickerHeight + 6
        implicitWidth: tipBox.width
        implicitHeight: tipBox.height
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}   // never takes input
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ultimit-wintip"

        Rectangle {
            id: tipBox
            width: Math.min(360, tipTxt.implicitWidth + 28); height: tipTxt.implicitHeight + 16
            color: Theme.panel
            border.width: 1; border.color: Theme.lineStrong
            Brackets { size: 6 }
            PopIn { target: tipBox; shown: WindowUi.tipText !== "" && !WindowUi.menuOpen }
            Text {
                id: tipTxt
                anchors.verticalCenter: parent.verticalCenter
                x: 14; width: parent.width - 28
                text: WindowUi.tipText
                textFormat: Text.PlainText
                elide: Text.ElideRight
                lineHeight: 1.15
                color: Theme.fg
                font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 0.8
            }
        }
    }

    // ---- context menu ----
    PanelWindow {
        id: mwin
        screen: root.screen
        visible: WindowUi.menuOpen && WindowUi.menuScreen === root.screenName
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ultimit-winmenu"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        readonly property var tl: WindowUi.menuTl
        readonly property int rowH: 30
        property int cur: -1
        // re-evaluates on tl property changes through the explicit reads
        readonly property var items: tl ? [
            { id: "min",  label: tl.minimized ? "Restore" : "Minimize" },
            { id: "max",  label: tl.maximized ? "Unmaximize" : "Maximize" },
            { id: "full", label: tl.fullscreen ? "Exit fullscreen" : "Fullscreen" },
            { id: "close", label: "Close" }
        ] : []

        function close() { WindowUi.closeMenu(); }
        function activate(it) {
            const t = tl;
            if (!t || !it) return;
            switch (it.id) {
            case "min":
                if (t.minimized) { t.minimized = false; t.activate(); } else t.minimized = true;
                break;
            case "max": t.maximized = !t.maximized; if (t.minimized) t.minimized = false; break;
            case "full": t.fullscreen = !t.fullscreen; if (t.minimized) t.minimized = false; break;
            case "close": t.close(); break;
            }
            close();
        }
        onVisibleChanged: if (visible) { cur = -1; keys.forceActiveFocus(); }
        // window vanished while its menu was open
        onTlChanged: if (!tl && WindowUi.menuOpen) WindowUi.closeMenu()
        Connections {
            target: ToplevelManager.toplevels
            function onValuesChanged() {
                if (WindowUi.menuTl && ToplevelManager.toplevels.values.indexOf(WindowUi.menuTl) < 0) WindowUi.closeMenu();
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: mwin.close()
        }
        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                event.accepted = true;
                const n = mwin.items.length;
                if (event.key === Qt.Key_Escape) mwin.close();
                else if (event.key === Qt.Key_Down) mwin.cur = (mwin.cur + 1) % n;
                else if (event.key === Qt.Key_Up) mwin.cur = (mwin.cur + n - 1 + (mwin.cur < 0 ? 1 : 0)) % n;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (mwin.cur >= 0) mwin.activate(mwin.items[mwin.cur]);
                } else event.accepted = false;
            }
        }

        Rectangle {
            id: menu
            x: Config.railWidth + 6
            y: Math.max(8, Math.min(WindowUi.menuY - 22, mwin.height - height - 8))
            width: 190; height: mwin.items.length * mwin.rowH + 12
            PopIn { target: menu; shown: mwin.visible }
            color: Theme.panel
            border.width: 1; border.color: Theme.lineStrong
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
            Brackets { size: 8 }

            Repeater {
                model: mwin.items
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool hot: mwin.cur === index
                    y: 6 + index * mwin.rowH
                    width: menu.width; height: mwin.rowH
                    Rectangle {
                        anchors.fill: parent; anchors.leftMargin: 1; anchors.rightMargin: 1
                        color: row.hot ? Theme.panel2 : "transparent"
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: row.hot }
                    }
                    Text {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.label.toUpperCase()
                        color: row.hot ? Theme.accent : Theme.fg
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.6
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: mwin.cur = row.index
                        onClicked: mwin.activate(row.modelData)
                    }
                }
            }
        }
    }
}
