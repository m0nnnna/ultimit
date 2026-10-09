// Tray.qml - StatusNotifierItem tray for the rail (bottom, above the version text).
// Left click = activate, middle = secondary activate, right click = the item's DBusMenu
// (TrayMenu overlay). Hover tooltip reuses the WindowUi tooltip. Hidden when empty.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import ".."

Item {
    id: root
    property string screenName: ""

    readonly property int shown: {
        let n = 0;
        const v = SystemTray.items.values;
        for (let i = 0; i < v.length; i++) if (v[i].status !== Status.Passive) n++;
        return n;
    }
    visible: shown > 0
    implicitHeight: visible ? 8 + head.implicitHeight + 6 + grid.implicitHeight + 4 : 0

    Rectangle { id: divider; x: 12; width: parent.width - 24; height: 1; color: Theme.line }
    Text {
        id: head
        anchors.top: divider.bottom; anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        text: "TRAY"
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 8; font.letterSpacing: 1.4
    }

    Grid {
        id: grid
        anchors.top: head.bottom; anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 2
        spacing: 2

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: ent
                required property var modelData
                readonly property bool vis: modelData.status !== Status.Passive
                visible: vis
                width: vis ? 34 : 0; height: vis ? 32 : 0
                readonly property string tip: modelData.tooltipTitle || modelData.title || modelData.id

                Rectangle {
                    anchors.fill: parent
                    color: Theme.panel2
                    opacity: mouse.pressed ? 1 : (mouse.containsMouse ? 0.7 : 0)
                    Behavior on opacity { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
                }
                Image {
                    id: img
                    anchors.centerIn: parent
                    width: 20; height: 20
                    source: ent.modelData.icon
                    sourceSize: Qt.size(40, 40)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    scale: mouse.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
                    visible: status === Image.Ready
                }
                Rectangle {   // fallback when the icon cannot be resolved
                    anchors.centerIn: parent
                    width: 18; height: 18
                    visible: !img.visible
                    color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                    Text {
                        anchors.centerIn: parent
                        text: (ent.tip || "?").charAt(0).toUpperCase()
                        color: Theme.fg; font.family: Theme.display; font.pixelSize: 9
                    }
                }
                Rectangle {   // needs-attention marker
                    visible: ent.modelData.status === Status.NeedsAttention
                    anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 4
                    width: 5; height: 5; color: Theme.warn
                }

                function menuY() { return ent.mapToGlobal(0, ent.height / 2).y; }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onEntered: tipTimer.restart()
                    onExited: { tipTimer.stop(); WindowUi.hideTip(); }
                    onWheel: wheel => ent.modelData.scroll(wheel.angleDelta.y, false)
                    onClicked: mouseEvent => {
                        tipTimer.stop(); WindowUi.hideTip();
                        const it = ent.modelData;
                        if (mouseEvent.button === Qt.RightButton) {
                            if (it.hasMenu) TrayUi.openMenu(it, ent.menuY(), root.screenName);
                            else it.secondaryActivate();
                        } else if (mouseEvent.button === Qt.MiddleButton) {
                            it.secondaryActivate();
                        } else if (it.onlyMenu && it.hasMenu) {
                            TrayUi.openMenu(it, ent.menuY(), root.screenName);
                        } else {
                            it.activate();
                        }
                    }
                }
                Timer {
                    id: tipTimer; interval: 180
                    onTriggered: WindowUi.showTip(ent.tip, ent.menuY(), root.screenName)
                }
            }
        }
    }
}
