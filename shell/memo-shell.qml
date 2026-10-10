// memo-shell.qml - MEMO as its own Quickshell process (qs -p <shell>/memo-shell.qml), separate from the desktop
// shell so shell reloads/crashes never lose open documents. Started on demand by bin/ultimit-memo;
// exits shortly after the last window closes. File watching is off (no hot reload of this process).
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/memo"

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
    MemoApp {}
}
