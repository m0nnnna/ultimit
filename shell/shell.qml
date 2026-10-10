// shell.qml - entry point for the Ultimit desktop shell.
// Run with:  qs -p /path/to/ultimit/shell
// One set of panels is created per screen.
import QtQuick
import Quickshell
import Quickshell.Io
import "components"
import "apps/settings"
import "apps/games"
import "apps/data"
import "apps/calc"
import "apps/polkit"

ShellRoot {
    Persist { id: persist }                              // ~/.config/ultimit/shell.json
    Boot { settingsReady: persist.ready }                // boot overlay (startup + on demand)
    SettingsWindow {}                                    // Settings window (replaces Accessory; rail ACCESSORY button)
    LockScreen {}                                        // session lock, idle dim/lock/suspend, lock on sleep
    Polkit {}                                            // polkit authentication agent + dialog
    DataWindow {}    // DATA file manager (ultimit-data, qs ipc call data open <path>)
    CalcWindow {}    // CALC calculator (ultimit-calc, qs ipc call calc toggle|open|close)
    GamesWindow {}   // Ultimit Games app (toggle: qs ipc call games toggle)

    IpcHandler {
        target: "launcher"
        function toggle(): void { Config.toggleLauncher(""); }
        function open(): void { Config.openLauncher(""); }
        function close(): void { Config.closeLauncher(); }
    }

    IpcHandler {
        target: "toasts"
        function show(title: string, message: string): void { Toasts.show(title, message); }
        function notify(title: string, message: string): void { Toasts.show(title, message); }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: scope
            required property var modelData

            Wallpaper   { screen: scope.modelData }   // background layer (+ wordmark)
            StatusBlock { screen: scope.modelData }   // bottom layer, top-right
            Rail        { screen: scope.modelData }   // top layer, left, exclusive zone
            Ticker      { screen: scope.modelData }   // top layer, bottom, exclusive zone
            Launcher    { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, app launcher (rail emblem)
            ContextMenu { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, desktop right-click menu
            WindowPopups { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, rail window tooltip + menu
            OsdOverlay  { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, volume/brightness OSD
            TrayMenu    { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, tray item menu
            ToastOverlay { screen: scope.modelData; screenName: scope.modelData.name }  // overlay, top-right toasts
            QuickSettings { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, status-block popover
        }
    }
}
