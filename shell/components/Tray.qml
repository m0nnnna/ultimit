// Tray.qml - StatusNotifierItem tray for the bottom bar (the app-icon half of StatusTray.qml).
// Left click = activate, middle = secondary activate, right click = the item's DBusMenu
// (TrayMenu overlay, opened above the bar). Hover tooltip (500 ms) reuses the WindowUi tip.
// Collapses to zero width when empty. Icons are shown as provided by the app (not tinted:
// full-colour app icons turn into blobs when forced monochrome).
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import ".."

Row {
    id: root
    property string screenName: ""
    property real barX: 0       // x of this item inside the bar window; the bar sits at Config.railWidth
    readonly property int shown: {
        let n = 0;
        const v = SystemTray.items.values;
        for (let i = 0; i < v.length; i++) if (v[i].status !== Status.Passive) n++;
        return n;
    }
    visible: shown > 0
    height: parent ? parent.height : Config.tickerHeight
    spacing: 0

    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: ent
            required property var modelData
            readonly property bool vis: modelData.status !== Status.Passive
            visible: vis
            width: vis ? 26 : 0; height: root.height
            readonly property string tip: modelData.tooltipTitle || modelData.title || modelData.id
            function centerX() { return Config.railWidth + ent.mapToItem(null, ent.width / 2, 0).x; }

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: ent.tip || "Tray item"
            Accessible.onPressAction: ent.trigger(Qt.LeftButton)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { ent.trigger(Qt.LeftButton); event.accepted = true; }
                else if (event.key === Qt.Key_Menu) { ent.trigger(Qt.RightButton); event.accepted = true; }
            }
            function trigger(button) {
                tipTimer.stop(); WindowUi.hideTip();
                const it = ent.modelData;
                if (button === Qt.RightButton) {
                    if (it.hasMenu) TrayUi.openMenu(it, 0, root.screenName, ent.centerX());
                    else it.secondaryActivate();
                } else if (button === Qt.MiddleButton) {
                    it.secondaryActivate();
                } else if (it.onlyMenu && it.hasMenu) {
                    TrayUi.openMenu(it, 0, root.screenName, ent.centerX());
                } else {
                    it.activate();
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.panel2
                opacity: mouse.pressed ? 1 : (mouse.containsMouse ? 0.7 : 0)
                Behavior on opacity { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
            }
            Rectangle {   // keyboard focus ring
                anchors.fill: parent; anchors.margins: 1
                color: "transparent"; border.width: 1; border.color: Theme.accent
                visible: ent.activeFocus
            }
            Image {
                id: img
                anchors.centerIn: parent
                width: 18; height: 18
                source: ent.modelData.icon
                sourceSize: Qt.size(36, 36)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                scale: mouse.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
                visible: status === Image.Ready
            }
            Rectangle {   // fallback when the icon cannot be resolved
                anchors.centerIn: parent
                width: 16; height: 16
                visible: !img.visible
                color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                Text {
                    anchors.centerIn: parent
                    text: (ent.tip || "?").charAt(0).toUpperCase()
                    color: Theme.fg; font.family: Theme.display; font.pixelSize: 8
                }
            }
            Rectangle {   // needs-attention marker
                visible: ent.modelData.status === Status.NeedsAttention
                anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 4
                width: 5; height: 5; color: Theme.warn
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onEntered: tipTimer.restart()
                onExited: { tipTimer.stop(); WindowUi.hideTip(); }
                onWheel: wheel => ent.modelData.scroll(wheel.angleDelta.y, false)
                onClicked: mouseEvent => ent.trigger(mouseEvent.button)
            }
            Timer {
                id: tipTimer; interval: 500
                onTriggered: WindowUi.showBarTip(ent.tip, ent.centerX(), root.screenName)
            }
        }
    }
}
