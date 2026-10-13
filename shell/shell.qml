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
import "apps/agents"

ShellRoot {
    Persist { id: persist }                              // ~/.config/ultimit/shell.json
    Boot { settingsReady: persist.ready }                // boot overlay (startup + on demand)
    SettingsWindow {}                                    // Settings window (replaces Accessory; rail ACCESSORY button)
    LockScreen {}                                        // session lock, idle dim/lock/suspend, lock on sleep
    BatteryWatch {}                                      // low-battery warnings (20/10/5%)
    Polkit {}                                            // polkit authentication agent + dialog
    Agents {}        // Bluetooth pairing / Wi-Fi & VPN password prompts (bin/ultimit-agents)
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

    IpcHandler {   // rail pins: qs ipc call rail pin <desktopId|builtin> | unpin <id> | list
        target: "rail"
        function pin(spec: string): string { return Pins.pinSpec(spec); }
        function unpin(id: string): string { return Pins.unpin(id) ? "ok" : (Pins.isLocked(id) ? "error: locked" : "error: not pinned"); }
        function list(): string { return JSON.stringify(Pins.specs.map(p => p.id)); }
    }

    IpcHandler {   // news ticker: qs ipc call feeds refresh | list
        target: "feeds"
        function refresh(): void { Feeds.refresh(); }
        function list(): string { return JSON.stringify(Feeds.shown); }
        function open(url: string): string { return Feeds.open(url) ? "ok" : "refused"; }
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
            RailMenu    { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, rail button right-click menu
            WindowPopups { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, rail window tooltip + menu
            OsdOverlay  { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, volume/brightness OSD
            TrayMenu    { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, tray item menu
            ToastOverlay { screen: scope.modelData; screenName: scope.modelData.name }  // overlay, top-right toasts
            Flyout      { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, tray icon flyouts
            AltTab      { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, Alt+Tab window switcher (compositor-driven)
            QuickSettings { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, status-block popover
        }
    }
}
