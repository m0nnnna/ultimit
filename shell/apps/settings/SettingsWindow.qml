// SettingsWindow.qml - Ultimit Settings (grows out of Accessory and replaces it).
// A plain xdg toplevel (FloatingWindow): the Ultimit compositor draws the titlebar/frame.
// Visibility is driven by Config.accessoryOpen (the rail ACCESSORY button and the desktop menu set
// it; closing via the frame writes it back). IPC:
//   qs ipc call settings open <page> | toggle | close
// Pages: appearance rail news display sound network bluetooth power input defaults datetime users updates about
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"

Scope {
    id: root

    property string page: "appearance"
    readonly property var pages: [
        { id: "appearance", n: "Appearance",   file: "AppearancePage.qml" },
        { id: "rail",       n: "Rail",         file: "RailPage.qml" },
        { id: "news",       n: "News",         file: "NewsPage.qml" },
        { id: "display",    n: "Display",      file: "DisplayPage.qml" },
        { id: "sound",      n: "Sound",        file: "SoundPage.qml" },
        { id: "network",    n: "Network",      file: "NetworkPage.qml" },
        { id: "bluetooth",  n: "Bluetooth",    file: "BluetoothPage.qml" },
        { id: "power",      n: "Power",        file: "PowerPage.qml" },
        { id: "input",      n: "Input",        file: "InputPage.qml" },
        { id: "defaults",   n: "Default apps", file: "DefaultAppsPage.qml" },
        { id: "datetime",   n: "Date & time",  file: "DateTimePage.qml" },
        { id: "users",      n: "Users",        file: "UsersPage.qml" },
        { id: "updates",    n: "Updates",      file: "UpdatesPage.qml" },
        { id: "about",      n: "About",        file: "AboutPage.qml" }
    ]
    function fileFor(id) { for (const p of pages) if (p.id === id) return p.file; return "AppearancePage.qml"; }
    function isPage(id) { for (const p of pages) if (p.id === id) return true; return false; }

    Connections {   // Config.openSettings("rail") from the rail menu etc.
        target: Config
        function onSettingsRequestChanged() { if (root.isPage(Config.settingsPage)) root.page = Config.settingsPage; }
    }

    FloatingWindow {
        id: win
        title: Config.accessoryTitle
        implicitWidth: 900
        implicitHeight: 620
        minimumSize: Qt.size(640, 440)
        color: "transparent"
        visible: false

        onVisibleChanged: if (Config.accessoryOpen !== visible) Config.accessoryOpen = visible

        Connections {
            target: Config
            function onAccessoryOpenChanged() { if (win.visible !== Config.accessoryOpen) win.visible = Config.accessoryOpen; }
        }
        Component.onCompleted: win.visible = Config.accessoryOpen

        Rectangle {
            anchors.fill: parent
            color: Theme.panel

            // ---- sidebar ----
            Rectangle {
                id: side
                width: 190; height: parent.height
                color: Theme.panel2
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

                Column {
                    x: 0; y: 14; width: parent.width - 1
                    spacing: 0
                    Repeater {
                        model: root.pages
                        delegate: Item {
                            id: nav
                            required property var modelData
                            readonly property bool sel: root.page === modelData.id
                            width: parent.width; height: 38
                            activeFocusOnTab: true
                            Keys.onPressed: e => {
                                if (e.key === Qt.Key_Return || e.key === Qt.Key_Space) { root.page = nav.modelData.id; e.accepted = true; }
                            }
                            Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: nm.containsMouse && !nav.sel ? 1 : 0 }
                            Rectangle { anchors.fill: parent; color: Theme.accent; opacity: nav.sel ? 0.12 : 0 }
                            Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: nav.sel }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 2; color: "transparent"
                                border.width: 1; border.color: Theme.fg; visible: nav.activeFocus && !nav.sel
                            }
                            Text {
                                x: 18; anchors.verticalCenter: parent.verticalCenter
                                text: nav.modelData.n.toUpperCase()
                                color: nav.sel ? Theme.accent : Theme.fg
                                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 12
                                font.letterSpacing: 1.6
                            }
                            MouseArea {
                                id: nm
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { nav.forceActiveFocus(Qt.MouseFocusReason); root.page = nav.modelData.id; }
                            }
                        }
                    }
                }
            }

            // ---- page ----
            Loader {
                id: pageLoader
                anchors.left: side.right; anchors.right: parent.right
                anchors.top: parent.top; anchors.bottom: parent.bottom
                active: win.visible
                source: root.fileFor(root.page)
            }
        }
    }

    IpcHandler {
        target: "settings"
        function open(page: string): void {
            if (page !== "" && root.isPage(page)) root.page = page;
            Config.accessoryOpen = true;
        }
        function toggle(): void { Config.accessoryOpen = !Config.accessoryOpen; }
        function close(): void { Config.accessoryOpen = false; }
    }
}
