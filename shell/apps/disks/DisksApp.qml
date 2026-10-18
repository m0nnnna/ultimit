// DisksApp.qml - DISKS, the Ultimit disks manager and disk-usage checker. Instantiated once from disks-shell.qml.
//   qs -p <shell>/disks-shell.qml ipc call disks open | usage <path> | state | dump | closeWindow
// (shell/bin/ultimit-disks [--usage [PATH]] wraps these; `closeDialogs`, `select` are for tests.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "disks"
        function open(): void { Disks.show(); Disks.tab = "drives"; }
        function usage(path: string): void {
            Disks.show();
            Disks.tab = "usage";
            if (path !== "") Disks.scan(path);
            else if (Disks.usageRoot === "") Disks.choose(Disks.home);
        }
        function state(): string { return Disks.open ? "open" : "closed"; }
        function dump(): string { return Disks.dump(); }
        function select(driveId: string, dev: string): void { Disks.select(driveId, dev); }
        function formatDialog(): void { Disks.overlay = "format"; }
        function dialog(mode: string): void { Disks.overlay = mode; }     // create | resize | delete | table | label | format
        function selectFree(driveId: string, offset: string): void { Disks.select(driveId, ""); Disks.selectFree(Number(offset)); }
        function closeDialogs(): void { Disks.overlay = ""; }
        function closeWindow(): void { Disks.open = false; }
    }
    DisksWindow {}
}
