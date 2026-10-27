// node apps/gamemode/detect_test.js  (also run by test_gamemode.py): detect.js decisions.
const fs = require("fs"), vm = require("vm"), assert = require("assert");
const src = fs.readFileSync(__dirname + "/detect.js", "utf8").replace(/^\.pragma library/m, "");
const mod = { exports: {} };
vm.runInNewContext(src, { module: mod });
const D = mod.exports;
const w = (appId, o) => Object.assign({ appId, fullscreen: false, minimized: false, focused: false, screens: ["HDMI-A-1"] }, o || {});
const NORUN = { alive: false, apps: [] };
let n = 0;
function t(name, fn) { fn(); n++; }

t("fullscreen game", () => {
    const r = D.classify([w("rail"), w("hl2_linux", { fullscreen: true, focused: true })], NORUN);
    assert.deepStrictEqual([r.active, r.reason, r.screens], [true, "fullscreen", ["HDMI-A-1"]]);
});
t("fullscreen on a screen that is not focused still counts", () => {
    assert.ok(D.classify([w("godot", { fullscreen: true }), w("foo", { focused: true })], NORUN).active);
});
t("minimized fullscreen does not", () => {
    assert.ok(!D.classify([w("godot", { fullscreen: true, minimized: true })], NORUN).active);
});
for (const id of ["firefox", "org.mozilla.firefox", "mpv", "vlc", "io.github.celluloid_player.Celluloid", "chromium", "Chromium-browser", "foot", "org.quickshell", "org.videolan.VLC", "firefox.desktop"])
    t("fullscreen " + id + " is not a game", () => assert.ok(!D.classify([w(id, { fullscreen: true, focused: true })], NORUN).active, id));
t("a browser game launched through ultimit-game-run is", () => {
    const r = D.classify([w("firefox", { fullscreen: true, focused: true })], { alive: true, apps: [] });
    assert.ok(r.active && r.reason === "fullscreen");
});
t("a background browser fullscreen while a game runs elsewhere is not", () => {
    assert.ok(!D.classify([w("firefox", { fullscreen: true }), w("steam_app_1", { focused: false })], { alive: true, apps: [] }).active);
});
t("steam / gamescope / wine focused, windowed", () => {
    for (const id of ["steam_app_730", "gamescope", "wine", "Proton", "game.exe", "steam_proton"]) {
        const r = D.classify([w(id, { focused: true })], NORUN);
        assert.ok(r.active && r.reason === "game-id", id);
    }
});
t("steam client itself is not a game", () => {
    assert.ok(!D.classify([w("steam", { focused: true })], NORUN).active);
    assert.ok(!D.classify([w("steam_app_730", { minimized: true, focused: true })], NORUN).active);
});
t("game-run: only the learned app, only while alive", () => {
    const run = { alive: true, apps: ["supertux2"] };
    assert.ok(D.classify([w("supertux2", { focused: true })], run).active);
    assert.ok(!D.classify([w("supertux2", { focused: true })], { alive: false, apps: ["supertux2"] }).active);
    assert.ok(!D.classify([w("supertux2"), w("gedit", { focused: true })], run).active);
});
t("learn: new focused ordinary app, not the old ones, not blocked", () => {
    assert.deepStrictEqual(D.learn([w("foot", { focused: true })], [], []), []);
    assert.deepStrictEqual(D.learn([w("gedit", { focused: true })], ["gedit"], []), []);
    assert.deepStrictEqual(D.learn([w("supertux2", { focused: true })], ["gedit"], []), ["supertux2"]);
    assert.deepStrictEqual(D.learn([w("supertux2", { focused: true })], [], ["supertux2"]), ["supertux2"]);
});
t("nothing open", () => assert.ok(!D.classify([], NORUN).active));
console.log("detect_test: " + n + " ok");
