// RailMenu.qml - right-click menu for a rail button (Pins.openMenu): Unpin, Move up/down, Rail settings...
// Full-screen overlay like WindowPopups' window menu: click-outside / Escape closes, arrows + Enter work.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Scope {
    id: root
    property var screen: null
    property string screenName: ""

    PanelWindow {
        id: mwin
        screen: root.screen
        visible: Pins.menuOpen && Pins.menuScreen === root.screenName
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ultimit-railmenu"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        readonly property int idx: Pins.indexOf(Pins.menuPinId)
        readonly property var items: {
            const out = [];
            if (idx < 0) return out;
            if (!Pins.isLocked(Pins.menuPinId)) out.push({ id: "unpin", label: "Unpin" });
            if (idx > 0) out.push({ id: "up", label: "Move up" });
            if (idx < Pins.specs.length - 1) out.push({ id: "down", label: "Move down" });
            out.push({ id: "settings", label: "Rail settings…" });
            return out;
        }

        function close() { Pins.closeMenu(); }
        function activate(it) {
            if (!it) return;
            const id = Pins.menuPinId;
            close();
            switch (it.id) {
            case "unpin": Pins.unpin(id); break;
            case "up": Pins.move(id, -1); break;
            case "down": Pins.move(id, 1); break;
            case "settings": Pins.openSettings("rail"); break;
            }
        }
        onVisibleChanged: if (visible) { pm.cur = -1; keys.forceActiveFocus(); }
        onItemsChanged: if (visible && items.length === 0) close()

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
                else if (event.key === Qt.Key_Down) pm.cur = (pm.cur + 1) % n;
                else if (event.key === Qt.Key_Up) pm.cur = (pm.cur + n - 1 + (pm.cur < 0 ? 1 : 0)) % n;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (pm.cur >= 0) mwin.activate(mwin.items[pm.cur]);
                } else event.accepted = false;
            }
        }
        PopupMenu {
            id: pm
            x: Config.railWidth + 6
            y: Math.max(8, Math.min(Pins.menuY - 22, mwin.height - height - 8))
            items: mwin.items
            onActivated: item => mwin.activate(item)
        }
    }
}
