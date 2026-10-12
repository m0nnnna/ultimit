pragma Singleton

// Games.qml - state for the Ultimit Games app: the library (Steam + desktop entries + manually
// added games), tool detection, per-game options and launching.
//
// Settings live in ~/.config/ultimit/games.json (see scan.py); launching non-Steam games goes
// through bin/ultimit-game-run so GAMES, the launcher and the rail behave the same.
// With ULTIMIT_DRY_RUN=1 every launch is logged (never executed): see _run().
//
// Entry points:   Games.toggle() / Games.show() / Games.hide()   (QML)
//                 qs -p <shell> ipc call games toggle            (shell, see GamesWindow)
import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

Singleton {
    id: root

    property bool open: false
    function toggle() { open = !open; }
    function show() { open = true; }
    function hide() { open = false; }

    readonly property bool dryRun: Quickshell.env("ULTIMIT_DRY_RUN") === "1"

    // ---- scan results ----
    property bool loaded: false
    property string steamRoot: ""
    property string steamState: "ready"        // missing | setup | ready
    property bool steamBinary: false
    property string winePrefix: ""
    property var allGames: []
    property var protons: []                   // installed Proton builds [{name, path}] for the umu runner
    property var tools: ({ gamemode: false, mangohud: false, gamescope: false, nvidia: false, wine: false, umu: false, dxvk: false })
    property var settings: ({ hintDismissed: false, games: {}, manual: [], sort: "recent" })

    // ---- library view state ----
    property string query: ""
    property string sortMode: settings.sort === "name" ? "name" : "recent"
    property string selectedId: ""

    function byId(id) {
        for (const g of allGames) if (g.id === id) return g;
        return null;
    }
    function lastTs(g) {
        const l = (settings.games[g.id] || {}).lastLaunched || 0;
        return Math.max(g.lastPlayed || 0, l);
    }
    // filtered + sorted list shown in the grid
    readonly property var games: {
        const q = query.trim().toLowerCase();
        const out = allGames.filter(g => q === "" || g.name.toLowerCase().indexOf(q) >= 0);
        const nm = (a, b) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0);
        if (sortMode === "name") out.sort(nm);
        else out.sort((a, b) => (lastTs(b) - lastTs(a)) || nm(a, b));
        return out;
    }
    readonly property var selected: {
        const g = byId(selectedId);
        if (g && games.indexOf(g) >= 0) return g;
        return games.length ? games[0] : null;
    }
    readonly property string selectedKey: selected ? selected.id : ""
    function indexOfSelected() { return selected ? games.indexOf(selected) : -1; }

    readonly property string installCommand: "sudo apt install steam-installer"
    readonly property string scriptPath: Quickshell.shellPath("apps/games/scan.py")
    readonly property string runPath: Quickshell.shellPath("bin/ultimit-game-run")

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
                    root.steamState = d.steamState;
                    root.winePrefix = d.winePrefix;
                    root.tools = d.tools;
                    root.protons = d.protons || [];
                    root.allGames = d.games;
                    root.settings = d.settings;
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

    // ---- per-game options (same defaults as scan.py effective()) ----
    // gpu: "auto" | "discrete" | "integrated"
    function setting(id) {
        const s = settings.games[id] || {};
        let gpu = s.gpu !== undefined ? s.gpu : (tools.nvidia ? "discrete" : "auto");
        if (gpu === "nvidia") gpu = "discrete";
        return {
            gpu: gpu,
            gamemode: s.gamemode !== undefined ? s.gamemode : true,
            overlay: s.overlay === true,
            gamescope: s.gamescope === true,
            scopeRes: s.scopeRes || "",
            scopeFps: s.scopeFps || 0,
            dxvk: s.dxvk !== undefined ? s.dxvk : true,
            args: s.args || "",
            env: s.env || "",
            prefix: s.prefix || "default",
            runner: s.runner === "proton" ? "proton" : "wine",
            proton: s.proton || ""
        };
    }

    function _py(args) { Quickshell.execDetached(["python3", root.scriptPath].concat(args)); }
    function _clone() { return JSON.parse(JSON.stringify(settings)); }

    function setSetting(id, key, value) {
        const next = _clone();
        const cur = next.games[id] || {};
        cur[key] = value;
        next.games[id] = cur;
        settings = next;
        const patch = {};
        patch[key] = value;
        _py(["set", id, JSON.stringify(patch)]);
    }
    function setSort(mode) {
        const next = _clone();
        next.sort = mode;
        settings = next;
        _py(["top", "sort", JSON.stringify(mode)]);
    }

    // ---- manual games ----
    function newManualId() { return "manual:" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36); }
    function addManual(name, kind, target, prefix, runner, proton) {
        const id = newManualId();
        const rec = { id: id, name: name, kind: kind, target: target };
        if (prefix) rec.prefix = prefix;
        if (runner === "proton") rec.runner = "proton";
        if (proton) rec.proton = proton;
        _py(["add-manual", JSON.stringify(rec)]);
        selectedId = id;
        query = "";
        addTimer.start();      // rescan once the helper has written the file
    }
    function removeManual(id) {
        _py(["remove-manual", id]);
        addTimer.start();
    }
    Timer { id: addTimer; interval: 400; onTriggered: root.rescan() }

    // ---- launching ----
    // Every launch goes through here: dry-run logs the argv instead of executing it.
    function _run(argv) {
        if (dryRun) { console.log("Games [dry-run] would exec:", JSON.stringify(argv)); _py(["dry-log", JSON.stringify(argv)]); }
        else Quickshell.execDetached(argv);
    }
    function _stamp(id) {
        const next = _clone();
        const cur = next.games[id] || {};
        cur.lastLaunched = Math.floor(Date.now() / 1000);
        next.games[id] = cur;
        settings = next;
    }

    function launch(id) {
        const g = byId(id);
        if (!g) return;
        _stamp(id);
        if (g.source === "steam") {
            // Steam owns the launch; options reach it through the Steam launch-options string.
            _py(["touch", id]);
            _run(["steam", "steam://rungameid/" + id]);
        } else {
            // The wrapper applies GPU/GameMode/overlay/Gamescope/Wine/DXVK/env/args and records last-launched.
            Quickshell.execDetached([root.runPath, "--id", id].concat(dryRun ? ["--dry-run"] : []));
        }
    }
    function setupSteam() { _run(["steam"]); }

    // ---- Steam launch options (Steam controls the launch; we only build the string) ----
    function _quote(s) { return /^[A-Za-z0-9_@%+=:,.\/-]+$/.test(s) ? s : "'" + s.replace(/'/g, "'\\''") + "'"; }
    function envTokens(text) {
        const toks = (text || "").match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) || [];
        return toks.filter(t => /^[A-Za-z_][A-Za-z0-9_]*=/.test(t));
    }
    function steamLaunchOptions(id) {
        const o = setting(id), parts = [];
        if (o.gpu === "discrete" && tools.nvidia)
            parts.push("__NV_PRIME_RENDER_OFFLOAD=1", "__GLX_VENDOR_LIBRARY_NAME=nvidia", "__VK_LAYER_NV_optimus=NVIDIA_only", "DXVK_FILTER_DEVICE_NAME=NVIDIA");
        else if (o.gpu === "integrated")
            parts.push("__GLX_VENDOR_LIBRARY_NAME=mesa", "DXVK_FILTER_DEVICE_NAME=Intel");
        for (const t of envTokens(o.env)) parts.push(t);
        if (o.gamescope && tools.gamescope) {
            parts.push("gamescope", "-f");
            if (/^\d{3,5}x\d{3,5}$/.test(o.scopeRes)) {
                const wh = o.scopeRes.split("x");
                parts.push("-w", wh[0], "-h", wh[1], "-W", wh[0], "-H", wh[1]);
            }
            if (o.scopeFps > 0) parts.push("-r", String(o.scopeFps));
            parts.push("--");
        }
        if (o.gamemode && tools.gamemode) parts.push("gamemoderun");
        if (o.overlay && tools.mangohud) parts.push("mangohud");
        parts.push("%command%");
        if (o.args.trim() !== "") parts.push(o.args.trim());
        return parts.join(" ");
    }
    // The hint under the options, depending on what the string leaves out.
    function steamOptionsNote(id) {
        const o = setting(id), miss = [];
        if (o.gamemode && !tools.gamemode) miss.push("GameMode");
        if (o.overlay && !tools.mangohud) miss.push("MangoHud");
        if (o.gamescope && !tools.gamescope) miss.push("Gamescope");
        return miss.length ? "Left out (not installed): " + miss.join(", ") + "." : "";
    }

    // ---- generated art palette ----
    readonly property var presets: ({
        "525480":  ["#e9edf2", "#4b5563", "#111111"],
        "1245620": ["#d6b25e", "#3b2f1a", "#0d0a05"],
        "427520":  ["#f0b04a", "#5b3b12", "#1a1004"],
        "413150":  ["#9be36a", "#2f6b2a", "#0b1d09"]
    })
    function palette(id) {
        if (presets[id]) return presets[id];
        let h = 0;
        for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) % 360;
        return [Qt.hsla(h / 360, 0.6, 0.65, 1), Qt.hsla(h / 360, 0.5, 0.25, 1), Qt.hsla(h / 360, 0.5, 0.05, 1)];
    }

    function kindLabel(g) {
        if (!g) return "";
        if (g.source === "steam") return g.compat === "proton" ? "Proton" : "Native";
        if (g.kind === "wine") return (settings.games[g.id] || {}).runner === "proton" ? "Proton" : "Wine";
        return g.kind === "wine" ? "Wine" : (g.flatpak ? "Flatpak" : (g.manual ? "Command" : "Desktop entry"));
    }
    function isWine(g) { return !!g && g.kind === "wine"; }

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
