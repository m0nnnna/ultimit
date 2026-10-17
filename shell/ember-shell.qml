// ember-shell.qml - EMBER (the desktop assistant) as its own Quickshell process (qs -p <shell>/ember-shell.qml),
// separate from the desktop shell like CLAUDE and MEMO, so a long chat never weighs on the desktop and a
// desktop reload never cuts one off. Started on demand by bin/ultimit-ember; exits shortly after its
// window closes.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/ember"

ShellRoot {
    settings.watchFiles: false

    // Follow the desktop skin and accent (read-only; the desktop shell's Persist owns shell.json).
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
    EmberApp {}
}
