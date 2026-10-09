pragma Singleton

// Games.qml - state for the Ultimit Games app: Steam library scan, tool
// detection and per-game settings (persisted in ~/.config/ultimit/games.json).
//
// Entry points:   Games.toggle() / Games.show() / Games.hide()   (QML)
//                 qs -p <shell> ipc call games toggle            (shell, see GamesWindow)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool open: false
    function toggle() { open = !open; }
    function show() { open = true; }
    function hide() { open = false; }

    // ---- scan results ----
    property bool loaded: false
    property string steamRoot: ""
    property bool steamInstalled: steamRoot !== "" || steamBinary
    property bool steamBinary: false
    property var games: []
    property var tools: ({ gamemode: false, mangohud: false, gamescope: false, nvidia: false })
    property var settings: ({ hintDismissed: false, games: {} })
    property string selectedId: ""
    readonly property var selected: {
        for (const g of games) if (g.appid === selectedId) return g;
        return games.length ? games[0] : null;
    }

    readonly property string installCommand: "sudo apt install steam-installer"
    readonly property string launchOption: "ultimit-game-run %command%"
    readonly property string scriptPath: Quickshell.shellPath("apps/games/scan.py")

    function rescan() { if (!scanner.running) scanner.running = true; }

    onOpenChanged: if (open) rescan()

    Process {
        id: scanner
        command: ["python3", root.scriptPath, "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.steamRoot = d.steamRoot;
                    root.steamBinary = d.steamBinary;
                    root.tools = d.tools;
                    root.games = d.games;
                    root.settings = {
                        hintDismissed: d.settings.hintDismissed === true,
                        games: d.settings.games || {}
                    };
                    if (!root.games.some(g => g.appid === root.selectedId))
                        root.selectedId = root.games.length ? root.games[0].appid : "";
                } catch (e) {
                    console.warn("Games: bad scan output:", e, text.slice(0, 200));
                }
                root.loaded = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.length) console.warn("Games scan:", text)
        }
    }

    // ---- per-game settings ----
    // gpu: "auto" | "nvidia" | "integrated". Defaults: NVIDIA when a driver is
    // loaded, GameMode on, everything else off (ultimit-game-run uses the same).
    function setting(appid) {
        const s = settings.games[appid] || {};
        return {
            gpu: s.gpu !== undefined ? s.gpu : (tools.nvidia ? "nvidia" : "auto"),
            gamemode: s.gamemode !== undefined ? s.gamemode : true,
            overlay: s.overlay === true,
            gamescope: s.gamescope === true
        };
    }

    function _save() {
        Quickshell.execDetached(["python3", root.scriptPath, "save", JSON.stringify(settings)]);
    }

    function setSetting(appid, key, value) {
        const next = JSON.parse(JSON.stringify(settings));
        const cur = setting(appid);
        cur[key] = value;
        next.games[appid] = cur;
        settings = next;
        _save();
    }

    function dismissHint() {
        const next = JSON.parse(JSON.stringify(settings));
        next.hintDismissed = true;
        settings = next;
        _save();
    }

    function launch(appid) {
        Quickshell.execDetached(["steam", "steam://rungameid/" + appid]);
    }

    // ---- art fallback palette (mockup colors for known titles) ----
    readonly property var presets: ({
        "525480":  ["#e9edf2", "#4b5563", "#111111"],
        "1245620": ["#d6b25e", "#3b2f1a", "#0d0a05"],
        "427520":  ["#f0b04a", "#5b3b12", "#1a1004"],
        "413150":  ["#9be36a", "#2f6b2a", "#0b1d09"]
    })
    function palette(appid) {
        if (presets[appid]) return presets[appid];
        let h = 0;
        for (let i = 0; i < appid.length; i++) h = (h * 31 + appid.charCodeAt(i)) % 360;
        return [Qt.hsla(h / 360, 0.6, 0.65, 1), Qt.hsla(h / 360, 0.5, 0.25, 1), Qt.hsla(h / 360, 0.5, 0.05, 1)];
    }

    function fmtSize(b) {
        if (b >= 1e9) return (b / 1e9).toFixed(b >= 1e11 ? 0 : 1) + " GB";
        if (b >= 1e6) return Math.round(b / 1e6) + " MB";
        return b > 0 ? Math.round(b / 1e3) + " KB" : "-";
    }
    function fmtLast(ts) {
        if (!ts) return "Never";
        const d = new Date(ts * 1000), now = new Date();
        const days = Math.floor((now - d) / 86400000);
        if (days <= 0) return "Today";
        if (days === 1) return "Yesterday";
        return Qt.formatDate(d, "MMM dd");
    }
}
