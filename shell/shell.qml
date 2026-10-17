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
import "apps/clipboard"

ShellRoot {
    Persist { id: persist }                              // ~/.config/ultimit/shell.json
    Boot { settingsReady: persist.ready }                // boot overlay (startup + on demand)
    SettingsWindow {}                                    // Settings window (replaces Accessory; rail ACCESSORY button)
    LockScreen {}                                        // session lock, idle dim/lock/suspend, lock on sleep
    BatteryWatch {}                                      // low-battery warnings (20/10/5%)
    CrashNotice {}                                       // "Ultimit crashed" once after a compositor crash
    UpdateWatch {}                                       // "Ultimit 0.x is out" once per new release
    Polkit {}                                            // polkit authentication agent + dialog
    Agents {}        // Bluetooth pairing / Wi-Fi & VPN password prompts (bin/ultimit-agents)
    DataWindow {}    // DATA file manager (ultimit-data, qs ipc call data open <path>)
    CalcWindow {}    // CALC calculator (ultimit-calc, qs ipc call calc toggle|open|close)
    GamesWindow {}   // Ultimit Games app (toggle: qs ipc call games toggle)

    // Menus and flyouts cover only their own screen and keep the keyboard, so the compositor says
    // when a shortcut ran or a click landed on another screen; close them all. "keep" is the panel
    // that shortcut toggles itself (Super tap, Super+V, Super+/).
    Connections {
        target: AltTabState
        function onDismiss(keep) {
            FlyoutState.close(); SysState.closeQs(); TrayUi.close();
            Config.closeMenu(); Pins.closeMenu(); WindowUi.closeMenu();
            if (keep !== "launcher") Config.closeLauncher();
            if (keep !== "clipboard") Clipboard.open = false;
            if (keep !== "shortcuts") Config.shortcutsOpen = false;
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { Config.toggleLauncher(""); }
        function open(): void { Config.openLauncher(""); }
        function close(): void { Config.closeLauncher(); }
    }

    IpcHandler {   // desktop picture: qs ipc call wallpaper set <file> [fill|fit|stretch|center] | shards | get
        target: "wallpaper"
        function set(path: string, fit: string): string {
            if (!path.startsWith("/")) return "error: give an absolute path";
            Config.wallpaper = path;
            if (Config.wallpaperFits.indexOf(fit) >= 0) Config.wallpaperFit = fit;
            return "ok";
        }
        function shards(): void { Config.wallpaper = ""; }
        function get(): string { return JSON.stringify({ wallpaper: Config.wallpaper, fit: Config.wallpaperFit }); }
    }

    IpcHandler {   // your own accent on every skin: qs ipc call accent set <#rrggbb> | reset | get
        target: "accent"
        function set(hex: string): string {
            const v = hex.startsWith("#") ? hex : "#" + hex;
            if (!Theme.validAccent(v)) return "error: give a colour as #rrggbb";
            Theme.accentOverride = v.toLowerCase();
            return "ok";
        }
        function reset(): void { Theme.accentOverride = ""; }
        function get(): string { return Theme.accentOverride === "" ? "skin" : Theme.accentOverride; }
    }

    IpcHandler {   // keyboard shortcut sheet: qs ipc call shortcuts toggle | open | close
        target: "shortcuts"
        function toggle(): void { Config.shortcutsOpen = !Config.shortcutsOpen; }
        function open(): void { Config.shortcutsOpen = true; }
        function close(): void { Config.shortcutsOpen = false; }
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
            // rail: every display, or the main one only (Config.barsOn)
            Rail        { screen: scope.modelData; visible: Config.showsBars(scope.modelData.name) }   // top layer, left, exclusive zone
            // news ticker: the main display only, so its scroll animation runs once, not per screen
            Ticker      { screen: scope.modelData; visible: Config.isMainScreen(scope.modelData.name) }   // top layer, bottom, exclusive zone
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
            ClipboardPanel { screen: scope.modelData; screenName: scope.modelData.name }  // overlay, Super+V clipboard history
            ShortcutSheet { screen: scope.modelData; screenName: scope.modelData.name }   // overlay, Super+/ keyboard shortcuts
        }
    }
}
