pragma Singleton

// WindowUi.qml - shared state between the rail window list and its overlay popups
// (hover tooltip + per-window context menu). Y values are screen-global pixels.
import QtQuick
import Quickshell

Singleton {
    property string tipText: ""
    property real tipY: 0          // vertical center of the hovered entry
    property string tipScreen: ""
    // Bottom-bar tooltips (tray cluster): tipX >= 0 puts the tip above the bar, centred on tipX
    // (screen-global px); -1 = the rail's side tooltip.
    property real tipX: -1

    property bool menuOpen: false
    property var menuTl: null
    property real menuY: 0
    property string menuScreen: ""

    function showTip(text, y, screen) { tipX = -1; tipText = text; tipY = y; tipScreen = screen; }
    function showBarTip(text, x, screen) { tipX = x; tipText = text; tipScreen = screen; }
    function hideTip() { tipText = ""; }
    function openMenu(tl, y, screen) { hideTip(); menuTl = tl; menuY = y; menuScreen = screen; menuOpen = true; }
    function closeMenu() { menuOpen = false; menuTl = null; }
}
