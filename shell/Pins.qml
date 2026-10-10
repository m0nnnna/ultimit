pragma Singleton

// Pins.qml - the rail's pinned items (the top section: GAMES, MAILER, ... ACCESSORY).
//
// `specs` is the stored list, in order (Persist.qml keeps it in shell.json as "pins"):
//   { id, label, icon, desktopId? }
//   - built-in rail entry: id is a Config.apps id ("games", "mailer", "news", "audio", "data", "accessory"),
//     label/icon are those of the built-in.
//   - desktop app: id is "app:<desktopId>", desktopId the DesktopEntries id; label is the upper-cased name
//     shortened to fit the rail; icon the entry's themed icon name (resolved live via Icons.qml).
// ACCESSORY (Settings) is locked: it can be moved but never removed, so Settings stays reachable.
// At most `maxPins` entries; the rail scrolls the pin area when it does not fit (WINDOWS and the tray keep their space).
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    readonly property int maxPins: 12
    readonly property string lockedId: "accessory"
    readonly property var defaultIds: ["games", "mailer", "news", "audio", "data", "accessory"]

    function defaults() {
        return defaultIds.map(id => { const a = Config.appById(id); return { id: id, label: a.label, icon: id }; });
    }
    property var specs: defaults()

    // Bumped when DesktopEntries (re)loads so entry lookups re-evaluate.
    property int entriesTick: 0
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.entriesTick++; }
    }

    // ---- helpers ----
    function shortLabel(name) {
        const s = String(name || "").trim().toUpperCase();
        return s.length > 9 ? s.slice(0, 8) + "…" : s;
    }
    function entryById(desktopId) {
        entriesTick;
        if (!desktopId) return null;
        const id = String(desktopId).replace(/\.desktop$/, "");
        return DesktopEntries.byId(id) || DesktopEntries.byId(id + ".desktop") || null;
    }
    function entryFor(pin) { return pin && pin.desktopId ? entryById(pin.desktopId) : null; }
    function isBuiltin(id) { return !!Config.appById(id); }

    // Stored specs -> validated list (drops unknown/duplicate/malformed items, caps, re-adds ACCESSORY).
    function sanitize(arr) {
        const out = [], seen = {};
        for (const p of (arr || [])) {
            if (!p || typeof p.id !== "string" || seen[p.id] || out.length >= maxPins) continue;
            if (Config.appById(p.id)) {
                out.push({ id: p.id, label: Config.appById(p.id).label, icon: p.id });
            } else if (p.id.startsWith("app:") && typeof p.desktopId === "string" && p.desktopId !== "") {
                out.push({ id: "app:" + p.desktopId, label: shortLabel(p.label || p.desktopId),
                           icon: typeof p.icon === "string" ? p.icon : "", desktopId: p.desktopId });
            } else continue;
            seen[out[out.length - 1].id] = true;
        }
        if (!seen[lockedId]) {
            if (out.length >= maxPins) out.pop();
            out.push({ id: lockedId, label: Config.appById(lockedId).label, icon: lockedId });
        }
        return out;
    }
    // ULTIMIT_PINS="games,foot,accessory" (tokens: built-in ids or desktop ids).
    function fromTokens(str) {
        const out = [];
        for (const tok of String(str).split(/[\s,]+/)) {
            if (!tok) continue;
            if (Config.appById(tok)) out.push({ id: tok });
            else { const id = tok.replace(/\.desktop$/, ""); out.push({ id: "app:" + id, desktopId: id, label: id, icon: "" }); }
        }
        return sanitize(out);
    }
    function setSpecs(arr) { specs = sanitize(arr); }

    // ---- resolved view for the rail ----
    // [{ id, label, icon, desktopId, builtin, app }]; desktop pins take label/icon from the live entry.
    readonly property var list: {
        entriesTick;
        return specs.map(p => {
            const app = Config.appById(p.id);
            if (app) return { id: p.id, label: app.label, icon: p.id, desktopId: "", builtin: true, app: app, found: true };
            const e = root.entryById(p.desktopId);
            return { id: p.id, label: e ? root.shortLabel(e.name) : p.label, icon: e && e.icon ? e.icon : p.icon,
                     desktopId: p.desktopId, builtin: false, app: null, found: !!e, name: e ? e.name : p.label };
        });
    }
    function indexOf(id) { for (let i = 0; i < specs.length; i++) if (specs[i].id === id) return i; return -1; }
    function has(id) { return indexOf(id) >= 0; }
    function hasDesktop(desktopId) { return has("app:" + String(desktopId).replace(/\.desktop$/, "")); }
    function isLocked(id) { return id === lockedId; }
    function canAdd() { return specs.length < maxPins; }

    // ---- edits (return true when something changed) ----
    function pinBuiltin(id) {
        if (!Config.appById(id) || has(id)) return false;
        if (!canAdd()) { Toasts.show("Rail", "Pin limit reached (" + maxPins + ")"); return false; }
        specs = specs.concat([{ id: id, label: Config.appById(id).label, icon: id }]);
        return true;
    }
    function pinEntry(e) {
        if (!e || !e.id || hasDesktop(e.id)) return false;
        if (!canAdd()) { Toasts.show("Rail", "Pin limit reached (" + maxPins + ")"); return false; }
        specs = specs.concat([{ id: "app:" + e.id, label: shortLabel(e.name), icon: e.icon || "", desktopId: e.id }]);
        return true;
    }
    // IPC / generic: "<builtin id>" or "<desktop id>" (with or without .desktop). Returns a status string.
    function pinSpec(spec) {
        spec = String(spec).trim();
        if (spec === "") return "error: empty";
        if (Config.appById(spec)) return has(spec) ? "already pinned" : (pinBuiltin(spec) ? "ok" : "error: limit");
        const e = entryById(spec);
        if (!e) return "error: unknown app '" + spec + "'";
        if (hasDesktop(e.id)) return "already pinned";
        return pinEntry(e) ? "ok" : "error: limit";
    }
    function unpin(id) {
        id = String(id);
        if (id === lockedId) return false;
        let i = indexOf(id);
        if (i < 0 && !id.startsWith("app:")) i = indexOf("app:" + id.replace(/\.desktop$/, ""));
        if (i < 0) return false;
        const n = specs.slice(); n.splice(i, 1); specs = n;
        return true;
    }
    function move(id, delta) {
        const i = indexOf(id), j = i + delta;
        if (i < 0 || j < 0 || j >= specs.length) return false;
        const n = specs.slice(); const t = n[i]; n[i] = n[j]; n[j] = t; specs = n;
        return true;
    }
    function reset() { specs = defaults(); }

    // ---- running windows / launching (desktop pins) ----
    function matchToplevel(pin) {
        const e = entryFor(pin);
        if (!e) return null;
        const keys = [e.id, e.startupClass, e.name].filter(x => x).map(x => String(x).toLowerCase());
        const list = ToplevelManager.toplevels.values;
        for (let i = 0; i < list.length; i++) {
            const a = (list[i].appId || "");
            if (a === "" || a === "org.quickshell") continue;
            if (keys.indexOf(a.toLowerCase()) >= 0) return list[i];
            const de = DesktopEntries.heuristicLookup(a);
            if (de && de.id === e.id) return list[i];
        }
        return null;
    }
    function launch(pin) {
        const e = entryFor(pin);
        if (!e) { Toasts.show(pin.label, "Application not installed"); return false; }
        e.execute();
        return true;
    }

    // ---- rail right-click menu state (components/RailMenu.qml) ----
    property bool menuOpen: false
    property string menuPinId: ""
    property real menuY: 0
    property string menuScreen: ""
    function openMenu(id, y, screenName) { menuPinId = id; menuY = y; menuScreen = screenName; menuOpen = true; }
    function closeMenu() { menuOpen = false; }

    // Open Settings on a page (and raise it when it is already mapped).
    function openSettings(page) {
        Config.openSettings(page);
        for (const t of ToplevelManager.toplevels.values) {
            if (t.appId === "org.quickshell" && t.title === Config.accessoryTitle) { t.minimized = false; t.activate(); break; }
        }
    }
}
