// shares-shell.qml - SHARES as its own Quickshell process (qs -p <shell>/shares-shell.qml), separate from the
// desktop shell like MEMO. Started on demand by bin/ultimit-shares; exits shortly after its window closes.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/shares"

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
    SharesApp {}
}
