// FirewallApp.qml - FIREWALL, the Ultimit firewall manager. Instantiated once from firewall-shell.qml.
//   qs -p <shell>/firewall-shell.qml ipc call firewall open | blocked | state | dump
// (shell/bin/ultimit-firewall [--blocked] wraps these; `addRule`, `preset`, `closeDialogs` are for tests.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "firewall"
        function open(): void { Firewall.show(); }
        function blocked(): void { Firewall.show(); Firewall.tab = "blocked"; }
        function showTab(tab: string): void { Firewall.show(); Firewall.tab = tab; }
        function state(): string { return Firewall.open ? "open" : "closed"; }
        function dump(): string { return Firewall.dump(); }
        function addRule(): void { Firewall.show(); Firewall.tab = "rules"; Firewall.addPrefill = null; Firewall.overlay = "add"; }
        function preset(id: string, on: bool): void { Firewall.setPreset(id, on); }
        function closeDialogs(): void { Firewall.overlay = ""; }
        function closeWindow(): void { Firewall.open = false; }
    }
    FirewallWindow {}
}
