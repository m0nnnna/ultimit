// BackupApp.qml - BACKUP, the Ultimit GUI for NekoShot. Instantiated once from nekoshot-shell.qml.
//   qs -p <shell>/nekoshot-shell.qml ipc call backup open | state   (shell/bin/ultimit-nekoshot wraps these)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "backup"
        function open(): void { Backup.show(); }
        function showTab(tab: string): void { Backup.show(); Backup.tab = tab; }
        function state(): string { return Backup.open ? "open" : "closed"; }
        function closeWindow(): void { Backup.open = false; }
    }
    BackupWindow {}
}
