// ClaudeApp.qml - CLAUDE, the Ultimit Claude app. Instantiated once by claude-shell.qml.
//   qs -p <shell>/claude-shell.qml ipc call claude open | project <id> | folder <path> | troubleshoot | state
//   | mini <screen> (toggle the corner panel) | miniShow <screen> | miniHide
// (shell/bin/ultimit-claude [--troubleshoot | FOLDER] wraps these.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "claude"
        function open(): void { Claude.open(); }
        function project(id: string): void { Claude.openProject(id); }
        function folder(path: string): void { Claude.openDir(path); }
        function troubleshoot(): void { Claude.openProject("system"); }
        function state(): string { return Claude.stateJson(); }
        function mini(screen: string): void { Claude.toggleMini(screen); }
        function miniShow(screen: string): void { Claude.showMini(screen); }
        function miniHide(): void { Claude.hideMini(); }
    }
    Variants {
        model: Claude.ids
        ClaudeWindow { required property var modelData }
    }
    LazyLoader {
        active: Claude.miniMade
        MiniPanel {}
    }
}
