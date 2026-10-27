pragma Singleton

// RailWindows.qml - dock-style window ownership for the rail. Every toplevel belongs to at most one
// pinned button (components/railmatch.js decides by app_id / desktop file / launch command); a
// pinned app's windows are shown on its button (open, focused, minimized, count) and are left out of
// the WINDOWS list. Clicking a button launches, minimizes, restores or cycles its windows.
// One tracker for all screens' rails: they all read `owners`.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components/railmatch.js" as RM
import "apps/games"
import "apps/data"

Singleton {
    id: root

    // Bumped whenever a toplevel appears, goes, or changes app_id / title / focus / minimized state.
    property int tick: 0
    // Only when the set of windows or an owner may have changed (not on title/focus): rects are re-sent then.
    property int mapTick: 0
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.tick++; root.mapTick++; }
    }
    Instantiator {
        model: ToplevelManager.toplevels
        delegate: QtObject {
            id: watcher
            required property var modelData
            property var c: Connections {
                target: watcher.modelData
                function onAppIdChanged() { root.tick++; root.mapTick++; }
                function onTitleChanged() { root.tick++; }
                function onActivatedChanged() { root.tick++; }
                function onMinimizedChanged() { root.tick++; }
            }
        }
    }

    // The default browser's desktop id (Settings > Default apps): WWW also owns its windows, whatever
    // it is (a Flatpak, a browser the app_id list has never heard of).
    property string browserId: ""
    Process {
        id: browserProbe
        running: true
        command: ["sh", "-c", "xdg-settings get default-web-browser 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.browserId = text.trim() }
    }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: { browserProbe.running = false; browserProbe.running = true; } }

    function lookup(appId) {
        const e = DesktopEntries.heuristicLookup(appId);
        return e ? e.id : "";
    }
    // Pins as the matcher wants them, in rail order.
    readonly property var pinDefs: {
        const out = [];
        for (const p of Pins.list) {
            if (p.builtin) {
                const keys = RM.keysFromCommand(Config.resolved[p.id] || "");
                let desktopId = "";
                if (p.id === "www" && root.browserId !== "") {
                    desktopId = root.browserId;
                    const e = Pins.entryById(desktopId);
                    if (e && e.startupClass) keys.push(e.startupClass);
                }
                out.push({ id: p.id, appIds: p.app.appIds || [], own: p.app.ownTitles || [], keys: keys, desktopId: desktopId });
            } else {
                const e = Pins.entryFor(p);
                const keys = e ? [e.startupClass, e.name].filter(x => x) : [];
                out.push({ id: p.id, appIds: [], own: [], keys: keys, desktopId: p.desktopId });
            }
        }
        return out;
    }
    // Owner pin id for each ToplevelManager toplevel (same order; "" = none).
    readonly property var owners: {
        tick;
        const list = ToplevelManager.toplevels.values, wins = [];
        for (let i = 0; i < list.length; i++) wins.push({ appId: list[i].appId || "", title: list[i].title || "" });
        return RM.assign(wins, root.pinDefs, root.lookup);
    }
    readonly property int unownedCount: { let n = 0; for (const o of owners) if (o === "") n++; return n; }
    function ownerOf(tl) {
        const i = ToplevelManager.toplevels.values.indexOf(tl);
        return i >= 0 && i < owners.length ? owners[i] : "";
    }
    // Windows of a pin, in map order.
    function windowsFor(pinId) {
        const list = ToplevelManager.toplevels.values, out = [];
        for (let i = 0; i < list.length; i++) if (owners[i] === pinId) out.push(list[i]);
        return out;
    }
    function stateFor(pinId) {
        return RM.state(windowsFor(pinId));
    }

    function focusWindow(tl) { tl.minimized = false; tl.activate(); }

    // A pinned button was clicked. Returns false when it has no window (the caller launches).
    function click(pinId) {
        const wins = windowsFor(pinId);
        const r = RM.click(wins);
        if (r.action === "launch") return false;
        if (r.action === "minimize") wins[r.index].minimized = true;
        else focusWindow(wins[r.index]);
        return true;
    }

    // Open the app (first window, or another one). Own-window apps have a single window.
    function launch(pin) {
        if (!pin.builtin) { Pins.launch(pin); return; }
        const app = pin.app;
        if (app.id === "news" && Feeds.homeUrl !== "") { Feeds.open(Feeds.homeUrl); return; }
        if (app.id === "accessory") { Config.openSettings(""); return; }
        if (app.id === "data") { Data.show(""); return; }
        if (app.id === "games") { Games.show(); return; }
        Config.launchApp(app);
    }
    function canOpenNew(pin) { return !pin.builtin || !pin.app.own; }

    // Where the minimize animation should fly: every window owned by `pinId` reports this item.
    function pushRects(pinId, item, panel) {
        if (!item || !panel) return;
        const wins = windowsFor(pinId);
        if (wins.length === 0) return;
        const p = item.mapToItem(null, 0, 0);
        const r = Qt.rect(Math.round(p.x), Math.round(p.y), item.width, item.height);
        for (const w of wins) w.setRectangle(panel, r);
    }

    function pinById(id) { for (const p of Pins.list) if (p.id === id) return p; return null; }
    // Click on a pin: its windows decide, no window launches it.
    function activate(pin) {
        Config.closeLauncher();   // the rail sits above the launcher while it is open
        if (!click(pin.id)) launch(pin);
    }

    // qs ipc call railwin click <pin id> | newwindow <pin id> | state <pin id> | unowned   (tests, scripting)
    IpcHandler {
        target: "railwin"
        function click(id: string): string {
            const p = root.pinById(id);
            if (!p) return "error: no such pin";
            root.activate(p);
            return "ok";
        }
        function newwindow(id: string): string {
            const p = root.pinById(id);
            if (!p) return "error: no such pin";
            if (root.canOpenNew(p)) root.launch(p); else root.activate(p);
            return "ok";
        }
        function state(id: string): string {
            const s = root.stateFor(id);
            return "count=" + s.count + " open=" + s.open + " focused=" + s.focused + " minimized=" + s.minimized;
        }
        function unowned(): string {
            const list = ToplevelManager.toplevels.values, out = [];
            for (let i = 0; i < list.length; i++) if (root.owners[i] === "") out.push(list[i].appId || "?");
            return out.join(",");
        }
    }
}
