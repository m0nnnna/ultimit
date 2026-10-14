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

    // file:// URL of an icon in the current skin's theme, or "" when it does not draw `name`.
    function own(name) {
        const rel = name ? root.table[name] : undefined;
        return rel ? "file://" + root.base + "/" + rel : "";
    }
    // Ultimit's own windows all report appId "org.quickshell"; tell them apart by title.
    // Returns the icon name, or "" for any other window.
    function windowIcon(appId, title) {
        if (appId !== "org.quickshell") return "";
        if (title === Config.accessoryTitle) return "ultimit-settings";
        if (title === Config.gamesTitle) return "ultimit-games";
        if (title.endsWith("\u2014 MEMO")) return "ultimit-memo";   // "<name> - MEMO" (em dash)
        if (title === "CLAUDE" || title.endsWith("\u2014 CLAUDE")) return "ultimit-claude";   // "<chat> - CLAUDE"
        const own = { DATA: "ultimit-data", CALC: "ultimit-calc", SHARES: "ultimit-shares", FIREWALL: "ultimit-firewall",
                      BROADCAST: "ultimit-broadcast", STORE: "ultimit-store" };
        return own[title] || "";
    }

    // Skin-aware lookup with fallback to the startup icon theme. "" when nothing resolves.
    function path(name) {
        if (!name) return "";
        if (name.startsWith("/")) return "file://" + name;
        if (name.startsWith("file:") || name.startsWith("image:")) return name;
        const o = root.own(name);
        return o !== "" ? o : (Quickshell.iconPath(name, true) || "");
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
}
