// SharesApp.qml - SHARES, the Ultimit file share maker. Instantiated once from shares-shell.qml.
//   qs -p <shell>/shares-shell.qml ipc call shares open | newShare <folder> | connectAddress <addr> <open?> | showConnect | state | dump
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
        function connectAddress(addr: string, openFolder: bool): void { Shares.connectAddress(addr, openFolder); }
        function showConnect(): void { Shares.showConnect(); }
        function showMine(): void { Shares.show(); Shares.tab = "mine"; }
        function browse(host: string): void { Shares.showConnect(); Shares.browseHost({ name: host, host: host }); }
        function credsDialog(): void { Shares.showConnect(); Shares.credReq = { kind: "browse", host: "annas-macbook.local", name: "Anna's MacBook", user: "", domain: "", wrong: false }; Shares.overlay = "creds"; }
        function closeDialogs(): void { Shares.overlay = ""; }
        function setup(step: string): void { Shares.setup(step); }
        function closeWindow(): void { Shares.open = false; }
    }
    SharesWindow {}
}
