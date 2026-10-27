.pragma library

// detect.js - decides whether a game is in front (Game Mode, GameMode.qml). Pure functions, no
// QML types, so scripts/test and test_gamemode.py run it under node.
//
// Confidence, highest first:
//   fullscreen  a fullscreen window (not minimized) whose app is not a browser / video player /
//               terminal / the shell's own window, on any screen
//   game-id     the focused window's app_id is a Steam game (steam_app_*), gamescope, Wine or Proton
//   game-run    a game started through ultimit-game-run is alive (marker files, see gamemode.py
//               "running") and the focused window is that game's (learn())
// A blocked app (browser, player...) only counts when it is fullscreen AND focused AND a
// ultimit-game-run game is alive (a browser game started from the Games app).

var BLOCKED = [
    "firefox", "org.mozilla.firefox", "librewolf", "chromium", "chromium-browser", "google-chrome",
    "brave-browser", "vivaldi", "org.chromium.chromium", "com.brave.browser", "org.gnome.epiphany",
    "mpv", "vlc", "org.videolan.vlc", "celluloid", "io.github.celluloid_player.celluloid", "totem",
    "org.gnome.totem", "haruna", "smplayer", "org.kde.haruna", "dragon", "parole", "kodi", "jellyfin",
    "freetube", "io.freetubeapp.freetube", "stremio", "plex", "plexamp", "spotify", "obs", "com.obsproject.studio",
    "discord", "slack", "zoom", "teams", "evince", "org.pwmt.zathura", "okular", "foot", "footclient", "alacritty",
    "kitty", "wezterm", "org.wezfurlong.wezterm", "xterm", "org.gnome.terminal", "konsole", "ptyxis",
    "org.gnome.ptyxis", "org.quickshell", "quickshell", "ultimit-launcher", "gimp", "org.gimp.gimp",
    "krita", "inkscape", "libreoffice", "soffice", "code", "code-oss", "org.gnome.nautilus"
];

function norm(appId) {
    return String(appId || "").toLowerCase().replace(/\.desktop$/, "");
}

function isBlocked(appId) {
    var a = norm(appId);
    if (a === "") return false;
    for (var i = 0; i < BLOCKED.length; i++) {
        if (a === BLOCKED[i]) return true;
    }
    // reverse-DNS app ids of the same programs ("org.mozilla.firefox.Beta", "...vlc.Vlc")
    return /(^|\.)(firefox|chromium|vlc|mpv|celluloid|libreoffice)(\.|$)/.test(a);
}

// Steam games (steam_app_<id>), gamescope, Wine / Proton windows.
function isGameId(appId) {
    var a = norm(appId);
    if (a === "") return false;
    return /^steam_app_\d+$/.test(a) || a === "gamescope" || /^(wine|proton|steam_proton)/.test(a)
        || /\.exe$/.test(a);
}

// Which app is the ultimit-game-run game? Windows carry no pid, so while a marker is alive the first
// ordinary app that takes focus and was not open when the game was launched (pre) is learned as
// the game's app. Returns the (possibly longer) list of app ids.
function learn(windows, pre, apps) {
    for (var i = 0; i < (windows || []).length; i++) {
        var a = norm(windows[i].appId);
        if (windows[i].focused && a !== "" && !isBlocked(a) && pre.indexOf(a) < 0 && apps.indexOf(a) < 0)
            return apps.concat([a]);
    }
    return apps;
}

// windows: [{appId, fullscreen, minimized, focused, screens: [name]}]
// run: {alive: a game launched through ultimit-game-run is running, apps: its learned app ids}.
// returns {active, reason, appId, screens}; reason is "" when nothing qualifies.
function classify(windows, run) {
    var gameRunAlive = !!(run && run.alive), runApps = (run && run.apps) || [];
    var none = { active: false, reason: "", appId: "", screens: [] };
    var focused = null, i, w;
    windows = windows || [];
    for (i = 0; i < windows.length; i++) if (windows[i].focused) { focused = windows[i]; break; }

    for (i = 0; i < windows.length; i++) {
        w = windows[i];
        if (!w.fullscreen || w.minimized) continue;
        if (isBlocked(w.appId)) {
            if (gameRunAlive && w.focused && norm(w.appId) !== "org.quickshell")
                return { active: true, reason: "fullscreen", appId: norm(w.appId), screens: w.screens || [] };
            continue;
        }
        return { active: true, reason: "fullscreen", appId: norm(w.appId), screens: w.screens || [] };
    }
    if (focused && !focused.minimized) {
        if (isGameId(focused.appId))
            return { active: true, reason: "game-id", appId: norm(focused.appId), screens: focused.screens || [] };
        if (gameRunAlive && runApps.indexOf(norm(focused.appId)) >= 0)
            return { active: true, reason: "game-run", appId: norm(focused.appId), screens: focused.screens || [] };
    }
    return none;
}

if (typeof module !== "undefined") module.exports = { classify: classify, learn: learn, isBlocked: isBlocked, isGameId: isGameId, norm: norm };
