pragma Singleton

// MobileState.qml - phone navigation (ULTIMIT_MOBILE=1): most-recently-used window order, home,
// back to the previous app, close. Windows come from wlr-foreign-toplevel (ToplevelManager).
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Toplevels, most recently active first.
    property var mru: []
    function _sync() {
        const all = ToplevelManager.toplevels.values;
        const keep = mru.filter(t => all.indexOf(t) >= 0);
        for (const t of all) if (keep.indexOf(t) < 0) keep.push(t);
        const a = ToplevelManager.activeToplevel;
        if (a && !a.minimized) { keep.splice(keep.indexOf(a), 1); keep.unshift(a); }
        mru = keep;
    }
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { root._sync(); }
    }
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root._sync(); }
    }
    Component.onCompleted: _sync()

    // Something open and on screen (else the home grid shows).
    readonly property bool appShown: ToplevelManager.toplevels.values.some(t => !t.minimized)

    function home() {
        Config.switcherOpen = false;
        for (const t of ToplevelManager.toplevels.values) t.minimized = true;
    }
    function show(t) {
        Config.switcherOpen = false;
        if (!t) return;
        t.minimized = false;
        t.activate();
    }
    // The app used before the current one (swipe sideways on the gesture bar).
    function previous() {
        const cur = ToplevelManager.activeToplevel;
        const list = mru.filter(t => t !== cur || (cur && cur.minimized));
        if (list.length) show(list[0]);
    }
    function close(t) { if (t) t.close(); }
    function closeAll() { for (const t of ToplevelManager.toplevels.values.slice()) t.close(); Config.switcherOpen = false; }
}
