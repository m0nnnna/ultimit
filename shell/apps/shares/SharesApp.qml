// SharesApp.qml - SHARES, the Ultimit file share maker. Instantiated once from shares-shell.qml.
//   qs -p <shell>/shares-shell.qml ipc call shares open | newShare <folder> | state | dump
// (shell/bin/ultimit-shares [--new FOLDER] wraps these; `passwordDialog`, `setup`, `select` are for tests.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "shares"
        function open(): void { Shares.show(); }
        function newShare(path: string): void { Shares.showNew(path); }
        function state(): string { return Shares.open ? "open" : "closed"; }
        function dump(): string { return Shares.dump(); }
        function passwordDialog(): void { Shares.show(); Shares.overlay = "password"; }
        function closeDialogs(): void { Shares.overlay = ""; }
        function setup(step: string): void { Shares.setup(step); }
        function closeWindow(): void { Shares.open = false; }
    }
    SharesWindow {}
}
