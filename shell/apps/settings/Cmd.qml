// Cmd.qml - run a command and collect its output. `mutating` commands are only logged in dry-run mode.
//   Cmd { id: c; argv: ["nmcli", "-t", "device"]; onDone: (out, code) => ... }   c.go()
import QtQuick
import Quickshell.Io

Item {
    id: root
    property var argv: []
    property bool mutating: false
    property bool running: proc.running
    property string shown: ""        // text for the dry-run log (mask secrets)
    signal done(string out, int code)

    function go() {
        if (mutating && SetSys.dryRun) {
            console.log("[dry-run] " + (shown || argv.join(" ")));
            root.done("", 0);
            return;
        }
        proc.running = false;
        proc.command = argv;
        proc.running = true;
    }
    Process {
        id: proc
        stdout: StdioCollector { id: so }
        stderr: StdioCollector { id: se }
        onExited: code => root.done(code === 0 ? so.text : (so.text || se.text), code)
    }
}
