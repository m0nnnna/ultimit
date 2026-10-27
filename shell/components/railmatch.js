.pragma library
// railmatch.js - which windows belong to which pinned rail button (dock-style ownership), and what a
// click on a button does. Pure functions (no Qt), unit-tested by railmatch_test.js under node.
//
// A pin is { id, appIds: [...], own: [titles], desktopId, keys: [...] }:
//   appIds   Wayland app_ids that are this app's windows (case-insensitive, ".desktop" ignored)
//   own      titles of Ultimit's own FloatingWindows (app_id org.quickshell), e.g. "GAMES"
//   desktopId, keys   desktop entry id plus its StartupWMClass / the flatpak id / the binary the rail
//            launches: extra app_ids for this button (see keysFromCommand)
// Matching is exact on the normalised id (plus underscore/dash and reverse-DNS-last-segment
// variants for Flatpak: "io.github.ungoogled_software.ungoogled_chromium" also matches
// "ungoogled-chromium" / "ungoogled_chromium"), never a prefix: a Chromium --app / PWA window
// ("chrome-<host>__-Default") has its own app_id and belongs to no browser button.

var OWN_APP_ID = "org.quickshell";

function norm(s) {
    return String(s || "").trim().toLowerCase().replace(/\.desktop$/, "");
}

// The ids one app_id can be written as.
function variants(id) {
    id = norm(id);
    if (id === "") return [];
    var out = [id, id.replace(/_/g, "-")];
    var seg = id.split(".");
    if (seg.length >= 3) {   // reverse-DNS (Flatpak): the last segment alone
        var last = seg[seg.length - 1];
        out.push(last, last.replace(/_/g, "-"));
    }
    return out;
}

// Chromium/Chrome/Brave/Edge --app and installed-PWA windows: "chrome-<host>__<path>-Default",
// "chrome-<32 letters>-Default", "crx_<id>", "brave-<..>-Default". Never a browser's own window.
function isPwa(appId) {
    var a = norm(appId);
    return /^(chrome|chromium|brave|msedge|vivaldi|opera)-.+-(default|profile ?\d+)$/.test(a) || /^crx_/.test(a);
}

// The app_id candidates in a launch command: "flatpak run [opts] org.x.Y [args]" -> org.x.Y,
// otherwise the first word's basename ("/usr/bin/foo --x" -> foo; gtk-launch NAME -> NAME).
function keysFromCommand(cmd) {
    var words = String(cmd || "").trim().split(/\s+/).filter(function (w) { return w !== ""; });
    var out = [];
    if (words.length === 0) return out;
    var base = words[0].replace(/^.*\//, "");
    if (base === "flatpak" && words[1] === "run") {
        for (var i = 2; i < words.length; i++) {
            if (words[i].charAt(0) === "-") continue;
            out.push(words[i]);
            break;
        }
    } else if (base === "gtk-launch" || base === "sh" || base === "env" || base.indexOf("$") >= 0) {
        // gtk-launch "$(xdg-settings ...)" is resolved separately (the default browser's desktop id)
    } else if (base !== "xdg-open") {
        out.push(base);
    }
    return out;
}

function pinKeySet(pin) {
    var set = {}, list = [].concat(pin.appIds || [], pin.keys || [], pin.desktopId ? [pin.desktopId] : []);
    for (var i = 0; i < list.length; i++) {
        var v = variants(list[i]);
        for (var j = 0; j < v.length; j++) set[v[j]] = true;
    }
    return set;
}

// Does `win` { appId, title } belong to `pin`? lookup(appId) -> desktop id or "" (heuristic desktop-file
// match, desktop pins only).
function matches(win, pin, lookup, keyset) {
    var appId = norm(win.appId);
    if (appId === "") return false;
    if (appId === OWN_APP_ID) return (pin.own || []).indexOf(win.title) >= 0;
    var set = keyset || pinKeySet(pin);
    var v = variants(appId);
    for (var i = 0; i < v.length; i++) if (set[v[i]]) return true;
    if (pin.desktopId && lookup && !isPwa(appId)) {
        var d = lookup(win.appId);
        if (d && norm(d) === norm(pin.desktopId)) return true;
    }
    return false;
}

// Owner pin id for every window (same order as `wins`; "" = belongs to no pin). First pin in rail
// order wins when two could claim a window.
function assign(wins, pins, lookup) {
    var sets = pins.map(pinKeySet), out = [];
    for (var w = 0; w < wins.length; w++) {
        var owner = "";
        for (var p = 0; p < pins.length && owner === ""; p++)
            if (matches(wins[w], pins[p], lookup, sets[p])) owner = pins[p].id;
        out.push(owner);
    }
    return out;
}

// Button state from its windows ([{ minimized, activated }]).
function state(wins) {
    var n = wins.length, mini = 0, foc = false;
    for (var i = 0; i < n; i++) {
        if (wins[i].minimized) mini++;
        else if (wins[i].activated) foc = true;
    }
    return { count: n, open: n > 0, focused: foc, minimized: n > 0 && mini === n };
}

// What a click does. wins in stable (map) order. -> { action: "launch" | "minimize" | "focus", index }
function click(wins) {
    var n = wins.length;
    if (n === 0) return { action: "launch", index: -1 };
    var cur = -1;
    for (var i = 0; i < n; i++) if (wins[i].activated && !wins[i].minimized) { cur = i; break; }
    if (n === 1) return cur === 0 ? { action: "minimize", index: 0 } : { action: "focus", index: 0 };
    if (cur < 0) {   // none focused: bring back the first visible one, else the first
        for (var j = 0; j < n; j++) if (!wins[j].minimized) return { action: "focus", index: j };
        return { action: "focus", index: 0 };
    }
    return { action: "focus", index: (cur + 1) % n };   // cycle on repeated clicks
}
