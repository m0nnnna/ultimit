// MemoApp.qml - MEMO, the Ultimit text editor. Instantiate once from shell.qml:  MemoApp {}
// One MemoWindow (a normal xdg toplevel) per open document.
//   qs -p <shell> ipc call memo open <path> | create | state | closeall
// (shell/bin/ultimit-memo [FILE...] wraps these.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "memo"
        function open(path: string): void { Memo.openFile(path); }
        function create(): void { Memo.newDoc(); }
        function state(): string { return Memo.stateJson(); }
    }
    Variants {
        model: Memo.ids
        MemoWindow { required property var modelData; docId: modelData }
    }
}
