pragma Singleton

// FlyoutState.qml - which tray flyout is open (components/Flyout.qml draws it) and where its
// icon is. One flyout at a time: opening one closes the last; Quick Settings, the launcher,
// the desktop menu and the tray-item menu close it, and it closes them.
//   kind    "network" | "sound" | "bluetooth" | "battery" | "clock" (stays set while the panel fades out)
//   open    true while the flyout should be up
//   screen  output the flyout is on (the tray's output)
//   anchors kind -> screen-global x of that icon's centre, published by StatusTray.qml
//   trayX/trayW  screen-global span of the tray cluster; clicks there pass through the click-catcher
//           so another icon switches flyouts and the same icon toggles it closed.
// IPC: qs ipc call flyout open network|sound|bluetooth|battery|clock | close | toggle <kind>
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root

    readonly property var kinds: ["network", "sound", "bluetooth", "battery", "clock"]
    property string kind: ""
    property bool open: false
    property string screen: ""
    property var anchors: ({})
    property real trayX: 0
    property real trayW: 0

    function setAnchor(k, x) {
        if (anchors[k] === x) return;
        const a = Object.assign({}, anchors);
        a[k] = x;
        anchors = a;
    }

    function openFlyout(k, screenName) {
        if (kinds.indexOf(k) < 0) return false;
        SysState.closeQs(); Config.closeLauncher(); Config.closeMenu(); TrayUi.close();
        screen = screenName || primaryScreen();
        kind = k;
        open = true;
        return true;
    }
    function close() { open = false; }
    function toggle(k, screenName) {
        if (open && kind === k) close(); else openFlyout(k, screenName);
    }
    function primaryScreen() {
        const s = Quickshell.screens;
        for (let i = 0; i < s.length; i++) if (Config.isTrayScreen(s[i].name)) return s[i].name;
        return s.length ? s[0].name : "";
    }

    Connections { target: SysState; function onQsOpenChanged() { if (SysState.qsOpen) root.close(); } }
    Connections { target: Config; function onLauncherOpenChanged() { if (Config.launcherOpen) root.close(); }
                                  function onMenuOpenChanged() { if (Config.menuOpen) root.close(); } }
    Connections { target: TrayUi; function onOpenChanged() { if (TrayUi.open) root.close(); } }

    IpcHandler {
        target: "flyout"
        function open(kind: string): string { return root.openFlyout(kind.toLowerCase(), "") ? "ok" : "error: unknown flyout (network|sound|bluetooth|battery|clock)"; }
        function toggle(kind: string): string { root.toggle(kind.toLowerCase(), ""); return root.open ? root.kind : "closed"; }
        function close(): void { root.close(); }
        function current(): string { return root.open ? root.kind : ""; }
    }
}
