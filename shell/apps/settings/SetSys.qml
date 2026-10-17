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
    // An ini file's text with `values` ({key: value}) set in [section]: keys already there are
    // changed in place, new ones go at the end of the section (made if missing); every other
    // line, section and comment is kept, so pages writing the same file don't drop each other's keys.
    function iniSet(text, section, values) {
        const lines = text === "" ? [] : text.replace(/\n$/, "").split("\n");
        const left = Object.assign({}, values);
        let sec = "", end = -1;
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].trim();
            if (t[0] === "[") { sec = t.slice(1, t.indexOf("]")); continue; }
            if (sec !== section || t === "") continue;
            end = i;
            const eq = t.indexOf("=");
            if (eq < 0 || t[0] === "#" || t[0] === ";") continue;
            const k = t.slice(0, eq).trim();
            if (k in left) { lines[i] = k + " = " + left[k]; delete left[k]; }
        }
        const add = Object.keys(left).map(k => k + " = " + left[k]);
        if (add.length) {
            if (end < 0) {
                const hdr = lines.findIndex(l => l.trim() === "[" + section + "]");
                if (hdr >= 0) end = hdr;
                else { if (lines.length && lines[lines.length - 1].trim() !== "") lines.push(""); lines.push("[" + section + "]"); end = lines.length - 1; }
            }
            lines.splice(end + 1, 0, ...add);
        }
        return lines.join("\n") + "\n";
    }
    // Ask the compositor to re-read compositor.ini.
    function reloadCompositor() { run([ctl, "reload"]); }
}
