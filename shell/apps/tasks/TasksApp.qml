// TasksApp.qml - TASKS, the Ultimit task manager. Instantiated once from tasks-shell.qml.
//   qs -p <shell>/tasks-shell.qml ipc call tasks open | performance | state | dump | closeWindow
// (shell/bin/ultimit-tasks [--performance] wraps these; `select`, `filter`, `search`, `sortBy`, `dialog`, `closeDialogs`,
// `submitDialog` are for tests.)
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    IpcHandler {
        target: "tasks"
        function open(): void { Tasks.show(); Tasks.tab = "processes"; }
        function performance(): void { Tasks.show(); Tasks.tab = "performance"; }
        function state(): string { return Tasks.open ? "open" : "closed"; }
        function dump(): string { return Tasks.dump(); }
        function select(pid: string): void { Tasks.selPid = Number(pid); }
        function filter(mode: string): void { Tasks.filter = mode; }       // apps | mine | all
        function search(text: string): void { Tasks.search = text; }
        function sortBy(key: string): void { Tasks.sortBy(key); }
        function dialog(mode: string): void { Tasks.ask(mode); }          // term | kill | stop | cont (for the selected process)
        function closeDialogs(): void { Tasks.overlay = ""; }
        function submitDialog(): void { Tasks.submitRequested(); }
        function closeWindow(): void { Tasks.open = false; }
    }
    TasksWindow {}
}
