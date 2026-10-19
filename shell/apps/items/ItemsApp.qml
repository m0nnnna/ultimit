// ItemsApp.qml - ITEMS, device settings (mice and other peripherals). Instantiated once from items-shell.qml.
//   qs -p <shell>/items-shell.qml ipc call items open | state | dump | closeWindow
// (shell/bin/ultimit-items wraps these; `select`, `profile`, `apply` are for tests.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "items"
        function open(): void { Items.show(); }
        function state(): string { return Items.open ? "open" : "closed"; }
        function dump(): string { return Items.dump(); }
        function select(id: string): void { Items.select(id); }
        function profile(n: int): void { Items.profile = n - 1; }
        function apply(): void { Items.apply(); }
        function closeWindow(): void { Items.open = false; }
    }
    ItemsWindow {}
}
