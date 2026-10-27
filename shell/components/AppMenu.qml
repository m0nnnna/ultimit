// AppMenu.qml - the app-name menu of the top bar (macOS style), an overlay that opens under the
// bar's left button: New window, the app's own desktop-entry Actions, then Fullscreen, Minimize,
// Close window, Quit (closes every window of the app). Rows come from BarUi.itemsFor(); our own
// shell apps (Settings, ...) get the generic rows only. Same look as TrayMenu / ContextMenu.
// Click outside / Escape closes; Up / Down / Enter drive it from the keyboard.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    property string screenName: ""

    visible: BarUi.appMenuOpen && BarUi.appMenuScreen === screenName
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-appmenu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int rowH: Theme.space(8)
    readonly property int sepH: Theme.space(3)
    // re-evaluated when the window's fullscreen state changes (label) through the explicit read
    readonly property var items: { const t = BarUi.appMenuTl; if (t) t.fullscreen; return BarUi.itemsFor(t); }
    readonly property var acts: items.filter(i => !i.sep)
    property int cur: -1

    function close() { BarUi.closeAppMenu(); }
    onVisibleChanged: if (visible) { cur = -1; keys.forceActiveFocus(); }

    MouseArea {
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
            const n = win.acts.length;
            if (event.key === Qt.Key_Escape) win.close();
            else if (n === 0) event.accepted = false;
            else if (event.key === Qt.Key_Down) win.cur = (win.cur + 1) % n;
            else if (event.key === Qt.Key_Up) win.cur = (win.cur + n - 1 + (win.cur < 0 ? 1 : 0)) % n;
            else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && win.cur >= 0) BarUi.run(win.acts[win.cur].id);
            else event.accepted = false;
        }
    }

    Surface {
        id: menu
        brackets: true; bracketSize: 8
        elevation: 2; shadowNs: "ultimit-appmenu"; shadowWanted: win.visible
        x: Math.max(8, Math.min(BarUi.appMenuX - Theme.space(8), win.width - width - 8))
        y: Config.barHeight + 6
        width: 232
        height: col.implicitHeight + Theme.space(4)
        PopIn { target: menu; shown: win.visible }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Column {
            id: col
            y: Theme.space(2)
            width: parent.width
            Repeater {
                model: win.items
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool sep: !!modelData.sep
                    readonly property bool hot: !sep && win.cur >= 0 && win.acts[win.cur] && win.acts[win.cur].id === modelData.id
                    width: col.width; height: sep ? win.sepH : win.rowH
                    Rectangle {
                        visible: row.sep
                        anchors.centerIn: parent
                        width: parent.width - Theme.space(6); height: 1; color: Theme.divider
                    }
                    Rectangle {
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
                        x: Theme.space(4); width: parent.width - Theme.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.sep ? "" : row.modelData.label.toUpperCase()
                        color: row.hot ? Theme.accent : Theme.fg
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
                    }
                    MouseArea {
                        visible: !row.sep
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.cur = win.acts.findIndex(a => a.id === row.modelData.id)
                        onClicked: BarUi.run(row.modelData.id)
                    }
                }
            }
        }
    }
}
