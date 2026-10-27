// node components/railmatch_test.js: railmatch.js ownership + click decisions.
const fs = require("fs"), vm = require("vm"), assert = require("assert");
const src = fs.readFileSync(__dirname + "/railmatch.js", "utf8").replace(/^\.pragma library/m, "");
const ctx = vm.createContext({});
vm.runInContext(src + "\nthis.RM = { norm, variants, isPwa, keysFromCommand, matches, assign, state, click };", ctx);
const J = x => JSON.parse(JSON.stringify(x));
const RM = ctx.RM;
let n = 0;
function t(name, fn) { fn(); n++; }

const WWW = { id: "www", appIds: ["firefox", "chromium", "chromium-browser", "google-chrome"], own: [], keys: [], desktopId: "" };
const GAMES = { id: "games", appIds: [], own: ["GAMES"], keys: [], desktopId: "" };
const TERM = { id: "term", appIds: ["foot", "kitty"], own: [], keys: ["foot"], desktopId: "" };
const SET = { id: "accessory", appIds: [], own: ["SETTINGS"], keys: [], desktopId: "" };
const pins = [WWW, GAMES, TERM, SET];
const w = (appId, title) => ({ appId, title: title || "" });
const own = (...ws) => J(RM.assign(ws, pins, () => ""));

t("plain app_ids, case-insensitive", () => {
    assert.deepStrictEqual(own(w("foot"), w("Firefox"), w("Chromium-browser"), w("gedit")), ["term", "www", "www", ""]);
});
t("own windows match by title only", () => {
    assert.deepStrictEqual(own(w("org.quickshell", "GAMES"), w("org.quickshell", "SETTINGS"), w("org.quickshell", "MEMO"), w("org.quickshell", "")),
        ["games", "accessory", "", ""]);
});
t("steam / lutris are not GAMES (the old always-open bug)", () => {
    assert.deepStrictEqual(own(w("steam"), w("lutris"), w("heroic")), ["", "", ""]);
});
t("empty / late app_id belongs to nobody, then to its owner once it arrives", () => {
    assert.deepStrictEqual(own(w("")), [""]);
    assert.deepStrictEqual(own(w("foot")), ["term"]);
});
t("flatpak browser: desktop id / flatpak run command become keys", () => {
    const fp = { id: "www", appIds: [], own: [], keys: RM.keysFromCommand("flatpak run org.mozilla.firefox"), desktopId: "" };
    assert.deepStrictEqual(J(RM.keysFromCommand("flatpak run --branch=stable org.mozilla.firefox https://x")), ["org.mozilla.firefox"]);
    assert.deepStrictEqual(J(RM.assign([w("org.mozilla.firefox"), w("firefox")], [fp], null)), ["www", "www"]);
    const ung = { id: "www", appIds: [], own: [], keys: [], desktopId: "io.github.ungoogled_software.ungoogled_chromium.desktop" };
    assert.deepStrictEqual(J(RM.assign([w("io.github.ungoogled_software.ungoogled_chromium"), w("ungoogled-chromium"), w("Chromium-browser")], [ung], null)), ["www", "www", ""]);
});
t("chromium --app / PWA windows do not count as the browser", () => {
    for (const id of ["chrome-youtube.com__-Default", "chrome-abcdefghijklmnopabcdefghijklmnop-Default", "crx_abcdef", "brave-x.com__-Default"]) {
        assert.ok(RM.isPwa(id), id);
        assert.deepStrictEqual(own(w(id)), [""], id);
    }
    const ung = { id: "www", appIds: ["chromium"], own: [], keys: [], desktopId: "chromium.desktop" };
    // even a heuristic desktop lookup that (wrongly) resolves a PWA to the browser entry is ignored
    assert.deepStrictEqual(J(RM.assign([w("chrome-youtube.com__-Default")], [ung], () => "chromium.desktop")), [""]);
    assert.deepStrictEqual(J(RM.assign([w("SomeApp")], [ung], () => "chromium.desktop")), ["www"]);
});
t("not a prefix match", () => {
    assert.deepStrictEqual(own(w("footage"), w("foot-server"), w("firefox-developer-edition")), ["", "", ""]);
});
t("first pin in rail order wins a shared window", () => {
    const a = { id: "a", appIds: ["x"], own: [], keys: [], desktopId: "" }, b = { id: "b", appIds: ["x"], own: [], keys: [], desktopId: "" };
    assert.deepStrictEqual(J(RM.assign([w("x")], [a, b], null)), ["a"]);
    assert.deepStrictEqual(J(RM.assign([w("x")], [b, a], null)), ["b"]);
});
t("unpinned: windows are unowned", () => {
    assert.deepStrictEqual(J(RM.assign([w("foot")], [WWW], null)), [""]);
});
t("desktop pin: heuristic desktop lookup, StartupWMClass key", () => {
    const d = { id: "app:org.gnome.Gedit", appIds: [], own: [], keys: ["gedit-wm"], desktopId: "org.gnome.Gedit" };
    assert.deepStrictEqual(J(RM.assign([w("gedit-wm"), w("gedit"), w("other")], [d], a => a === "gedit" ? "org.gnome.Gedit.desktop" : "")), ["app:org.gnome.Gedit", "app:org.gnome.Gedit", ""]);
});
t("state", () => {
    assert.deepStrictEqual(JSON.parse(JSON.stringify(RM.state([]))), { count: 0, open: false, focused: false, minimized: false });
    const s = RM.state([{ minimized: true, activated: false }, { minimized: false, activated: true }]);
    assert.deepStrictEqual([s.count, s.open, s.focused, s.minimized], [2, true, true, false]);
    assert.ok(RM.state([{ minimized: true }, { minimized: true }]).minimized);
    assert.ok(!RM.state([{ minimized: true, activated: true }]).focused);   // a minimized window is not "focused"
});
t("click: none launches, one toggles, several cycle", () => {
    const c = ws => { const r = RM.click(ws); return [r.action, r.index]; };
    const W = (m, a) => ({ minimized: m, activated: a });
    assert.deepStrictEqual(c([]), ["launch", -1]);
    assert.deepStrictEqual(c([W(false, true)]), ["minimize", 0]);
    assert.deepStrictEqual(c([W(false, false)]), ["focus", 0]);
    assert.deepStrictEqual(c([W(true, false)]), ["focus", 0]);
    assert.deepStrictEqual(c([W(true, true)]), ["focus", 0]);   // minimized "activated" leftover: restore
    assert.deepStrictEqual(c([W(false, true), W(false, false), W(false, false)]), ["focus", 1]);
    assert.deepStrictEqual(c([W(false, false), W(false, false), W(false, true)]), ["focus", 0]);   // wraps
    assert.deepStrictEqual(c([W(false, false), W(false, false)]), ["focus", 0]);
    assert.deepStrictEqual(c([W(true, false), W(false, false)]), ["focus", 1]);
    assert.deepStrictEqual(c([W(true, false), W(true, false)]), ["focus", 0]);
});
console.log("railmatch_test: " + n + " ok");
