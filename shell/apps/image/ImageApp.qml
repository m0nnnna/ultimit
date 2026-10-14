// ImageApp.qml - IMAGE, the Ultimit image viewer. Instantiated once by image-shell.qml.
// One ImageWindow (a normal xdg toplevel) per open request.
//   qs -p <shell>/image-shell.qml ipc call image open <path> | openset <paths, one per line> | state
// (shell/bin/ultimit-image [FILE...] wraps these.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "image"
        function open(path: string): void { Viewer.openFile(path); }
        function openset(paths: string): void { Viewer.openSet(paths.split("\n").filter(p => p !== "")); }
        function state(): string { return Viewer.stateJson(); }
    }
    Variants {
        model: Viewer.ids
        ImageWindow { required property var modelData; winId: modelData }
    }
}
