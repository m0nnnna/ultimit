// StoreApp.qml - STORE, the Ultimit app store over Flathub. Instantiated once from store-shell.qml.
//   qs -p <shell>/store-shell.qml ipc call store open | search <words> | app <id> | installed | install <id> | state | dump
// (shell/bin/ultimit-store [--search WORDS | --app ID | --installed] wraps these.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "store"
        function open(): void { Store.show(); }
        function search(words: string): void { Store.showSearch(words); }
        function app(id: string): void { Store.showApp(id); }
        function installed(): void { Store.show(); Store.showInstalled(); }
        function state(): string { return Store.open ? "open" : "closed"; }
        function dump(): string { return Store.dump(); }
        function closeWindow(): void { Store.open = false; }
        function install(id: string): void { Store.show(); Store.install(id, id); }
    }
    StoreWindow {}
}
