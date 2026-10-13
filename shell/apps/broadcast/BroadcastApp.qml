// BroadcastApp.qml - BROADCAST, Ultimit's mic / speaker / camera effects app. Instantiated once from broadcast-shell.qml.
//   qs -p <shell>/broadcast-shell.qml ipc call broadcast open | showTab <mic|speakers|camera> | state | dump | closeWindow
// (shell/bin/ultimit-broadcast [--tab NAME] wraps these.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "broadcast"
        function open(): void { Broadcast.show(); }
        function showTab(tab: string): void { Broadcast.show(); Broadcast.tab = tab; }
        function state(): string { return Broadcast.open ? "open" : "closed"; }
        function dump(): string { return Broadcast.dump(); }
        function closeWindow(): void { Broadcast.open = false; }
    }
    BroadcastWindow {}
}
