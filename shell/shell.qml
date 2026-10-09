// shell.qml - entry point for the Ultimit desktop shell.
// Run with:  qs -p /path/to/ultimit/shell
// One set of panels is created per screen.
import QtQuick
import Quickshell
import "components"
import "apps/accessory"
import "apps/games"

ShellRoot {
    Persist { id: persist }                              // ~/.config/ultimit/shell.json
    Boot { settingsReady: persist.ready }                // boot overlay (startup + on demand)
    Accessory {}                                         // Accessory settings window
    GamesWindow {}   // Ultimit Games app (toggle: qs ipc call games toggle)

    Variants {
        model: Quickshell.screens

        Scope {
            id: scope
            required property var modelData

            Wallpaper   { screen: scope.modelData }   // background layer (+ wordmark)
            StatusBlock { screen: scope.modelData }   // bottom layer, top-right
            Rail        { screen: scope.modelData }   // top layer, left, exclusive zone
            Ticker      { screen: scope.modelData }   // top layer, bottom, exclusive zone
        }
    }
}
