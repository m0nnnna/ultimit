pragma Singleton

// WindowUi.qml - shared state between the rail window list and its overlay popups
// (hover tooltip + per-window context menu). Y values are screen-global pixels.
import QtQuick
import Quickshell

Singleton {
    property string tipText: ""
    property real tipY: 0          // vertical center of the hovered entry
    property string tipScreen: ""

    property bool menuOpen: false
    property var menuTl: null
    property real menuY: 0
    property string menuScreen: ""

    function showTip(text, y, screen) { tipText = text; tipY = y; tipScreen = screen; }
    function hideTip() { tipText = ""; }
    function openMenu(tl, y, screen) { hideTip(); menuTl = tl; menuY = y; menuScreen = screen; menuOpen = true; }
    function closeMenu() { menuOpen = false; menuTl = null; }
}
