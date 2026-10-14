pragma Singleton

// Icons.qml - icon lookup that follows the skin live.
//
// Quickshell.iconPath() resolves through the Qt icon theme named by QS_ICON_THEME, which Quickshell
// reads once at startup (there is no runtime setter), so a skin switch in Settings -> Appearance
// could never re-skin icons that way. Instead the Ultimit-<Skin> themes carry a names.json
// (name -> relative svg path, written by theme/icons/build-icons.py) and this singleton turns a
// name into a file:// URL inside the *current* skin's theme directory. QML bindings that call
// Icons.path() re-evaluate when Theme.skin changes (and when names.json finishes loading).
// Anything the Ultimit theme does not draw falls back to Quickshell.iconPath(), i.e. to
// QS_ICON_THEME and its Inherits chain (Yaru / Adwaita / hicolor), so third-party app icons are
// unchanged. If the theme is not installed, everything degrades to iconPath() as before.
//
// User-installed icons ($XDG_DATA_HOME/icons/hicolor) are looked up here before iconPath(), because
// Qt picks /usr/share's hicolor copy when both have the name. That is how Steam ended up as a pile
// of cardboard boxes: Ubuntu's steam-installer ships a stand-in "steam" icon (Valve's logo is not
// free), and the real one is what Steam links into ~/.local/share/icons/hicolor on its first start.
// The same directory holds the steam_icon_<appid> icons of Steam games, which name the windows of
// running games (X11 class steam_app_<appid>).
//
// Theme directory: $ULTIMIT_ICON_HOME/icons (tests) else $XDG_DATA_HOME/icons else ~/.local/share/icons.
import QtQuick
import Quickshell
import Quickshell.Io
import "."

Singleton {
    id: root

    readonly property string skinTheme: "Ultimit-" + Theme.skin.charAt(0).toUpperCase() + Theme.skin.slice(1)
    readonly property string dataHome: Quickshell.env("ULTIMIT_ICON_HOME")
        || Quickshell.env("XDG_DATA_HOME")
        || ((Quickshell.env("HOME") || "") + "/.local/share")
    readonly property string base: dataHome + "/icons/" + skinTheme

    // name -> relative path of the current skin's svg ({} until names.json is read)
    property var table: ({})
    // name -> absolute path of the largest icon in the user's hicolor theme ({} until scanned)
    property var userTable: ({})

    // file:// URL of an icon in the current skin's theme, or "" when it does not draw `name`.
    function own(name) {
        const rel = name ? root.table[name] : undefined;
        return rel ? "file://" + root.base + "/" + rel : "";
    }
    // file:// URL of an icon an app installed for this user (hicolor under XDG_DATA_HOME), or "".
    function user(name) {
        const p = name ? root.userTable[name] : undefined;
        return p ? "file://" + p : "";
    }
    // Ultimit's own windows all report appId "org.quickshell"; tell them apart by title.
    // Returns the icon name, or "" for any other window.
    function windowIcon(appId, title) {
        if (appId !== "org.quickshell") return "";
        if (title === Config.accessoryTitle) return "ultimit-settings";
        if (title === Config.gamesTitle) return "ultimit-games";
        if (title.endsWith("\u2014 MEMO")) return "ultimit-memo";   // "<name> - MEMO" (em dash)
        if (title === "IMAGE" || title.endsWith("\u2014 IMAGE")) return "ultimit-image";   // "<name> - IMAGE"
        const own = { DATA: "ultimit-data", CALC: "ultimit-calc", SHARES: "ultimit-shares", FIREWALL: "ultimit-firewall",
                      BROADCAST: "ultimit-broadcast", STORE: "ultimit-store" };
        return own[title] || "";
    }

    // Skin-aware lookup with fallback to the startup icon theme. "" when nothing resolves.
    function path(name) {
        if (!name) return "";
        if (name.startsWith("/")) return "file://" + name;
        if (name.startsWith("file:") || name.startsWith("image:")) return name;
        const o = root.own(name) || root.user(name) || Quickshell.iconPath(name, true) || "";
        if (o !== "") return o;
        // A running Steam game: its window class is steam_app_<appid>; Steam names the game's icon
        // steam_icon_<appid> (installed with a desktop shortcut). Otherwise Steam's own icon.
        const m = /^steam_app_(\d+)$/.exec(name);
        return m ? (root.path("steam_icon_" + m[1]) || root.path("steam")) : "";
    }
    // An app's icon (launcher, windows, Alt-Tab, pins). With Config.appIcons "letters" only the icons
    // the Ultimit theme draws resolve; "" for anything else, so the caller draws its letter tile.
    function app(name) {
        return Config.appIcons === "letters" ? root.own(name) : root.path(name);
    }
    // Same, with a final fallback icon name.
    function pathOr(name, fallback) {
        const p = root.path(name);
        return p !== "" ? p : root.path(fallback);
    }

    FileView {
        path: root.base + "/names.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.table = JSON.parse(text()).icons || ({}); }
            catch (e) { root.table = ({}); }
        }
        onLoadFailed: root.table = ({})
    }

    // ---- user hicolor icons ----
    // One `find` per (re)scan: at start and whenever the desktop entries change, which is when an
    // app (Steam's first start, a new game shortcut) has just installed its icons alongside.
    function parseUser(text) {
        const best = {}, rank = {};
        for (const line of text.split("\n")) {
            // .../hicolor/<48x48|scalable|...>/apps/<name>.<png|svg>
            const m = /\/hicolor\/([^\/]+)\/apps\/([^\/]+)\.(png|svg)$/.exec(line);
            if (!m) continue;
            const r = m[1] === "scalable" ? 100000 : (parseInt(m[1]) || 0);
            if (best[m[2]] === undefined || r > rank[m[2]]) { best[m[2]] = line; rank[m[2]] = r; }
        }
        return best;
    }
    function rescanUser() {
        if (userScan.running) userScanAgain = true;
        else userScan.running = true;
    }
    property bool userScanAgain: false
    Process {
        id: userScan
        running: true
        command: ["sh", "-c", 'd="$1/icons/hicolor"; [ -d "$d" ] && find -L "$d" -path "*/apps/*" -type f \\( -name "*.png" -o -name "*.svg" \\) 2>/dev/null; true',
                  "sh", root.dataHome]
        stdout: StdioCollector { onStreamFinished: root.userTable = root.parseUser(text) }
        onExited: if (root.userScanAgain) { root.userScanAgain = false; running = true; }
    }
    Timer { id: userRescan; interval: 1500; onTriggered: root.rescanUser() }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { userRescan.restart(); }
    }
}
