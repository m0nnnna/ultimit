// shell.qml - Ultimit greeter (greetd). Self-contained Quickshell config:
//   ultimit -s "qs -p /opt/ultimit/greeter"
// Env: ULTIMIT_GREETER_SKIN (mine|amber|silver|verdant, default mine), ULTIMIT_GREETER_DEMO=1,
//      ULTIMIT_MOTION=0, XDG_STATE_HOME (remembered user/session; else /var/lib/ultimit-greeter).
import QtQuick
import Quickshell

ShellRoot {
    Greeter { id: greeter }

    Variants {
        model: Quickshell.screens
        GreeterSurface {
            required property var modelData
            screen: modelData
            ctl: greeter
        }
    }
}
