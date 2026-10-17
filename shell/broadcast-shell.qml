// broadcast-shell.qml - BROADCAST as its own Quickshell process (qs -p <shell>/broadcast-shell.qml), separate from the
// desktop shell like SHARES and MEMO. Started on demand by bin/ultimit-broadcast; exits shortly after its window closes.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/broadcast"

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
    BroadcastApp {}
}
