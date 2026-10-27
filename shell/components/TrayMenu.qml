// TrayMenu.qml - overlay that renders a tray item's DBusMenu (QsMenuOpener) in the
// ContextMenu style: an L1 Surface, mono caps rows, accent hover. Submenus replace the
// content in place with a "back" header. Click outside / Escape closes.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    property string screenName: ""

    visible: TrayUi.open && TrayUi.screen === screenName
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-traymenu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int rowH: Theme.space(8)
    readonly property int menuW: 248
    readonly property var handle: TrayUi.path.length > 0 ? TrayUi.path[TrayUi.path.length - 1]
        : (TrayUi.item ? TrayUi.item.menu : null)
    readonly property bool inSub: TrayUi.path.length > 0

    QsMenuOpener { id: opener; menu: win.handle }

    function close() { TrayUi.close(); }
    onVisibleChanged: if (visible) keys.forceActiveFocus()

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
            if (event.key === Qt.Key_Escape) { if (win.inSub) TrayUi.pop(); else win.close(); event.accepted = true; }
            else if (event.key === Qt.Key_Left && win.inSub) { TrayUi.pop(); event.accepted = true; }
        }
    }

    Surface {
        id: menu
        brackets: true; bracketSize: 8
        elevation: 2; shadowNs: "ultimit-traymenu"; shadowWanted: win.visible
        readonly property bool fromBar: TrayUi.x >= 0
        x: fromBar ? Math.max(8, Math.min(TrayUi.x - width / 2, win.width - width - 8)) : Config.railWidth + 4
        y: fromBar ? win.height - Config.tickerHeight - 6 - height
            : Math.max(8, Math.min(TrayUi.y - 20, win.height - height - 8))
        width: win.menuW
        height: col.implicitHeight + Theme.space(4)
        PopIn { id: pop; target: menu; shown: win.visible }
        Connections { target: TrayUi; function onPathChanged() { if (win.visible) pop.restart(); } }   // submenu swap
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Column {
            id: col
            y: Theme.space(2)
            width: parent.width

            Item {   // back header for submenus
                visible: win.inSub
                width: parent.width; height: visible ? win.rowH : 0
                Rectangle {
                    anchors.fill: parent; anchors.margins: Theme.space(1)
                    color: backM.containsMouse ? Theme.hover : Theme.clear(Theme.hover)
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                }
                Text {
                    x: Theme.space(4); anchors.verticalCenter: parent.verticalCenter
                    text: "◂ BACK"
                    color: backM.containsMouse ? Theme.accent : Theme.dim
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
                }
                MouseArea { id: backM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: TrayUi.pop() }
            }

            Repeater {
                model: opener.children
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool sep: modelData.isSeparator
                    readonly property bool hot: m.containsMouse && modelData.enabled
                    width: col.width; height: sep ? 8 : win.rowH

                    Rectangle {
                        visible: row.sep
                        x: Theme.space(3); anchors.verticalCenter: parent.verticalCenter
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
                    Text {   // check / radio mark
                        visible: !row.sep && row.modelData.buttonType !== 0
                        x: Theme.space(3); anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.checkState === Qt.Checked ? "■" : "□"
                        color: row.modelData.checkState === Qt.Checked ? Theme.accent : Theme.dim
                        font.family: Theme.mono; font.pixelSize: Theme.type.label
                    }
                    Text {
                        visible: !row.sep
                        x: row.modelData.buttonType !== 0 ? Theme.space(8) : Theme.space(4)
                        width: parent.width - x - Theme.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.modelData.text.replace(/_(.)/g, "$1").toUpperCase()
                        opacity: row.modelData.enabled ? 1 : 0.4
                        color: row.hot ? Theme.accent : Theme.fg
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.2
                    }
                    Text {
                        visible: !row.sep && row.modelData.hasChildren
                        anchors.right: parent.right; anchors.rightMargin: Theme.space(4)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "▸"; color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: Theme.type.label
                    }
                    MouseArea {
                        id: m
                        enabled: !row.sep && row.modelData.enabled
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.modelData.hasChildren) TrayUi.push(row.modelData);
                            else { row.modelData.triggered(); win.close(); }
                        }
                    }
                }
            }
        }
    }
}
