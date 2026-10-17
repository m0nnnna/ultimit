// EmberApp.qml - EMBER, the Ultimit desktop assistant. Instantiated once by ember-shell.qml.
//   qs -p <shell>/ember-shell.qml ipc call ember open | ask <text> | state
// (shell/bin/ultimit-ember [TEXT] wraps these.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "ember"
        function open(): void { Ember.open(); }
        function ask(text: string): void { Ember.ask(text); }
        function state(): string { return Ember.stateJson(); }
    }
    Variants {
        model: Ember.ids
        EmberWindow { required property var modelData }
    }
}
