// claude-shell.qml - CLAUDE (the Claude app) as its own Quickshell process (qs -p <shell>/claude-shell.qml),
// separate from the desktop shell like MEMO and IMAGE, so a long chat never weighs on the desktop and
// a desktop reload never cuts one off. Started on demand by bin/ultimit-claude; exits shortly after its
// window closes.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/claude"

ShellRoot {
    settings.watchFiles: false

    // Follow the desktop skin (read-only; the desktop shell's Persist owns shell.json).
    FileView {
        id: skinFile
        path: Quickshell.env("HOME") + "/.config/ultimit/shell.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (Quickshell.env("ULTIMIT_SKIN")) return;
            try { const s = JSON.parse(text()).skin; if (s in Theme.skins) Theme.skin = s; } catch (e) {}
        }
    }
    ClaudeApp {}
}
