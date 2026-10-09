pragma Singleton

// TrayUi.qml - shared state between the rail tray (components/Tray.qml) and the tray menu
// overlay (components/TrayMenu.qml). y is a screen-global pixel position.
import QtQuick
import Quickshell

Singleton {
    property bool open: false
    property var item: null          // SystemTray item
    property var path: []            // submenu entries pushed on top of item.menu
    property real y: 0
    property string screen: ""

    function openMenu(it, y, screen) { item = it; path = []; this.y = y; this.screen = screen; open = true; }
    function close() { open = false; item = null; path = []; }
    function push(entry) { path = path.concat([entry]); }
    function pop() { path = path.slice(0, -1); }
}
