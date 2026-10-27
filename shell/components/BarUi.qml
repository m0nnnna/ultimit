pragma Singleton

// BarUi.qml - shared state of the top bar (components/TopBar.qml) and its app menu
// (components/AppMenu.qml). x is the screen-global centre of the menu button.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Singleton {
    id: root
    property bool appMenuOpen: false
    property real appMenuX: 0
    property string appMenuScreen: ""
    // Fullscreen reveal state of the bar on the main display (TopBar.qml writes it; `qs ipc call bar state`).
    property bool revealed: false
    property real slide: 1
    property var appMenuTl: null          // the window the menu acts on (focused one when it opened)

    // True while any popup that hangs from the bar is up: the bar must not slide away under it.
    readonly property bool popupOpen: appMenuOpen || FlyoutState.open || SysState.qsOpen || TrayUi.open

    function openAppMenu(x, screen) {
        WindowUi.hideTip(); FlyoutState.close(); SysState.closeQs(); TrayUi.close(); Config.closeLauncher(); Config.closeMenu();
        appMenuTl = ToplevelManager.activeToplevel; appMenuX = x; appMenuScreen = screen; appMenuOpen = true;
    }
    function closeAppMenu() { appMenuOpen = false; }
    function toggleAppMenu(x, screen) { if (appMenuOpen) closeAppMenu(); else openAppMenu(x, screen); }

    // Own shell apps (Settings, ...) are quickshell windows told apart by title.
    function isOwn(tl) { return !!tl && (tl.appId === "org.quickshell" || tl.appId === ""); }
    function entryFor(tl) { return tl && !isOwn(tl) ? DesktopEntries.heuristicLookup(tl.appId) : null; }
    // Name shown on the bar button for the focused window.
    function nameFor(tl) {
        if (!tl) return "";
        const e = entryFor(tl);
        if (e && e.name) return e.name;
        return tl.title || tl.appId || "";
    }

    // Menu rows: { id, label } or { sep: true }.
    function itemsFor(tl) {
        const out = [];
        if (!tl) return out;
        const e = entryFor(tl);
        if (e) {
            out.push({ id: "new", label: "New window" });
            const acts = e.actions || [];
            for (let i = 0; i < acts.length; i++) out.push({ id: "act:" + i, label: acts[i].name });
            out.push({ sep: true });
        }
        out.push({ id: "full", label: tl.fullscreen ? "Exit fullscreen" : "Fullscreen" });
        out.push({ id: "min", label: "Minimize" });
        out.push({ id: "close", label: "Close window" });
        if (!isOwn(tl)) out.push({ id: "quit", label: "Quit" });
        return out;
    }
    function run(id) {
        const t = appMenuTl;
        closeAppMenu();
        if (!t) return;
        const e = entryFor(t);
        if (id === "new") { if (e) e.execute(); }
        else if (id.startsWith("act:")) { const a = e && e.actions ? e.actions[parseInt(id.slice(4))] : null; if (a) a.execute(); }
        else if (id === "full") { t.fullscreen = !t.fullscreen; if (t.minimized) t.minimized = false; }
        else if (id === "min") t.minimized = true;
        else if (id === "close") t.close();
        else if (id === "quit") {
            for (const w of ToplevelManager.toplevels.values.slice()) if (w.appId === t.appId) w.close();
        }
    }
    Connections { target: ToplevelManager.toplevels; function onValuesChanged() {
        if (root.appMenuOpen && root.appMenuTl && ToplevelManager.toplevels.values.indexOf(root.appMenuTl) < 0) root.closeAppMenu();
    } }
    Connections { target: SysState; function onQsOpenChanged() { if (SysState.qsOpen) root.closeAppMenu(); } }
    Connections { target: FlyoutState; function onOpenChanged() { if (FlyoutState.open) root.closeAppMenu(); } }
}
