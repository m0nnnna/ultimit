// nekoshot-shell.qml - BACKUP (NekoShot GUI) as its own Quickshell process (qs -p <shell>/nekoshot-shell.qml), separate
// from the desktop shell like FIREWALL. Started on demand by bin/ultimit-nekoshot; exits shortly after its window closes.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/nekoshot"

ShellRoot {
    settings.watchFiles: false

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
    BackupApp {}
}
