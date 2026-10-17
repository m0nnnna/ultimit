// store-shell.qml - STORE as its own Quickshell process (qs -p <shell>/store-shell.qml), separate from the
// desktop shell like MEMO. Started on demand by bin/ultimit-store; exits once its window is closed and no install is running.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/store"

ShellRoot {
    settings.watchFiles: false

    // Follow the desktop skin and accent (read-only; the desktop shell's Persist owns shell.json).
    FileView {
        id: skinFile
        path: Quickshell.env("HOME") + "/.config/ultimit/shell.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { Theme.load(JSON.parse(text())); } catch (e) {}
        }
    }
    StoreApp {}
}
