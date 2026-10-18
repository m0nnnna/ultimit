// disks-shell.qml - DISKS as its own Quickshell process (qs -p <shell>/disks-shell.qml), separate from the
// desktop shell like FIREWALL. Started on demand by bin/ultimit-disks; exits shortly after its window closes.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/disks"

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
    DisksApp {}
}
