// store-shell.qml - STORE as its own Quickshell process (qs -p <shell>/store-shell.qml), separate from the
// desktop shell like MEMO. Started on demand by bin/ultimit-store; exits once its window is closed and no install is running.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/store"

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
    StoreApp {}
}
