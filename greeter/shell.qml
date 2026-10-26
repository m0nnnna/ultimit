// shell.qml - Ultimit greeter (greetd). Self-contained Quickshell config:
//   ultimit -s "qs -p /opt/ultimit/greeter"
// Env: ULTIMIT_GREETER_SKIN (mine|amber|silver|verdant|sakura|paper|void, default mine), ULTIMIT_GREETER_DEMO=1,
//      ULTIMIT_MOTION=0, XDG_STATE_HOME (remembered user/session; else /var/lib/ultimit-greeter).
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    Greeter { id: greeter }

    // The main display, as the compositor has it (from the last user's Settings > Display, see
    // ultimit-greeter-session): the login panel goes there. "" until known: the first screen.
    property string mainScreen: ""
    Process {
        id: outputs
        command: ["python3", Quickshell.shellPath("../shell/bin/ultimitctl"), "state"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text).outputs.find(x => x.primary && x.enabled);
                    root.mainScreen = o ? o.name : "";
                } catch (e) {}
            }
        }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { outputs.running = true; }
    }

    Variants {
        model: Quickshell.screens
        GreeterSurface {
            required property var modelData
            screen: modelData
            ctl: greeter
            mainScreen: root.mainScreen
        }
    }
}
