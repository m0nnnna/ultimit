// TrayMenu.qml - overlay that renders a tray item's DBusMenu (QsMenuOpener) in the
// ContextMenu style: panel fill, 1px line, mono caps rows, accent hover. Submenus replace the
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

    readonly property int rowH: 28
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

    Rectangle {
        id: menu
        readonly property bool fromBar: TrayUi.x >= 0
        x: fromBar ? Math.max(8, Math.min(TrayUi.x - width / 2, win.width - width - 8)) : Config.railWidth + 4
        y: fromBar ? win.height - Config.tickerHeight - 6 - height
            : Math.max(8, Math.min(TrayUi.y - 20, win.height - height - 8))
        width: win.menuW
        height: col.implicitHeight + 12
        color: Theme.panel
        border.width: 1; border.color: Theme.lineStrong
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
        Brackets { size: 8 }

        Column {
            id: col
            y: 6
            width: parent.width

            Item {   // back header for submenus
                visible: win.inSub
                width: parent.width; height: visible ? win.rowH : 0
                Rectangle { anchors.fill: parent; anchors.margins: 1; color: backM.containsMouse ? Theme.panel2 : "transparent" }
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    text: "◂ BACK"
                    color: backM.containsMouse ? Theme.accent : Theme.dim
                    font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.6
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
                    width: col.width; height: sep ? 9 : win.rowH

                    Rectangle {
                        visible: row.sep
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20; height: 1; color: Theme.line
                    }
                    Rectangle {
                        visible: !row.sep
                        anchors.fill: parent; anchors.leftMargin: 1; anchors.rightMargin: 1
                        color: row.hot ? Theme.panel2 : "transparent"
                        Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: row.hot }
                    }
                    Text {   // check / radio mark
                        visible: !row.sep && row.modelData.buttonType !== 0
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.checkState === Qt.Checked ? "■" : "□"
                        color: row.modelData.checkState === Qt.Checked ? Theme.accent : Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10
                    }
                    Text {
                        visible: !row.sep
                        x: row.modelData.buttonType !== 0 ? 30 : 14
                        width: parent.width - x - 30
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.modelData.text.replace(/_(.)/g, "$1").toUpperCase()
                        opacity: row.modelData.enabled ? 1 : 0.4
                        color: row.hot ? Theme.accent : Theme.fg
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.2
                    }
                    Text {
                        visible: !row.sep && row.modelData.hasChildren
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "▸"; color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 11
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
