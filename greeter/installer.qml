// installer.qml - the Ultimit installer screen (the Ultimit ISO; installer/start.sh runs it):
//   ultimit -x -s "qs -p /opt/ultimit/greeter/installer.qml"
// It lives beside the login screen (greeter/) and uses its look; the pieces are in installer/.
// Try it in the devbox:
//   ULTIMIT_INSTALLER_DRY=1 PROBE_FAKE_DIR=$PWD/greeter/installer/fixtures/windows-gap qs -p greeter/installer.qml
import QtQuick
import Quickshell
import "installer"

ShellRoot {
    Installer { id: setup }

    Variants {
        model: Quickshell.screens
        InstallerSurface {
            required property var modelData
            screen: modelData
            ctl: setup
        }
    }
}
