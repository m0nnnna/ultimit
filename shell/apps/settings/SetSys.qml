pragma Singleton

// SetSys.qml - helpers shared by the Settings pages: dry-run gating, config file paths and writes.
// With ULTIMIT_DRY_RUN=1 every state change is logged ("[dry-run] ...") instead of executed and
// config files are written under /tmp/claude-1000/settings-dry/ instead of ~/.config/ultimit/.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("ULTIMIT_DRY_RUN") === "1"
    readonly property string home: Quickshell.env("HOME")
    readonly property string dryDir: "/tmp/claude-1000/settings-dry"
    readonly property string repoDir: Quickshell.shellDir + "/.."
    readonly property string ctl: Quickshell.shellDir + "/bin/ultimitctl"

    // Where a config file named `name` (e.g. "compositor.ini") is read and written.
    function cfgPath(name) { return (dryRun ? dryDir : home + "/.config/ultimit") + "/" + name; }

    // Fire-and-forget state change.
    function run(argv, shown) {
        if (dryRun) { console.log("[dry-run] " + (shown || argv.join(" "))); return; }
        Quickshell.execDetached(argv);
    }
    function note(text) { if (dryRun) console.log("[dry-run] " + text); }

    // Write `text` to `path` (creating the directory). Logged in dry-run mode (path is already redirected).
    function writeFile(path, text) {
        if (dryRun) console.log("[dry-run] write " + path);
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", path, text]);
    }
    // Ask the compositor to re-read compositor.ini.
    function reloadCompositor() { run([ctl, "reload"]); }
}
