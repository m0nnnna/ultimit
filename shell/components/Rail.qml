// Rail.qml - left icon rail (layer: top, exclusive zone = rail width).
// Launches Config.apps commands; shows "on" and focuses the window when a toplevel
// whose app_id matches is already open (wlr-foreign-toplevel via ToplevelManager).
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../apps/games"

PanelWindow {
    id: win

    anchors { left: true; top: true; bottom: true }
    implicitWidth: Config.railWidth
    exclusiveZone: Config.railWidth
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ultimit-rail"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand   // Tab / Enter on rail buttons

    // Returns the first open toplevel whose appId is in `ids`, or null.
    // Depends on toplevels.values so bindings re-evaluate as windows come and go.
    // Accessory and Games are our own FloatingWindows (app_id org.quickshell),
    // matched by title. GAMES also lights up for running launchers like Steam.
    function findToplevel(ids, app) {
        const list = ToplevelManager.toplevels.values;
        for (let i = 0; i < list.length; i++) {
            const own = list[i].appId === "org.quickshell";
            if (app && app.id === "accessory") {
                if (own && list[i].title === Config.accessoryTitle) return list[i];
                continue;
            }
            if (app && app.id === "games" && own && list[i].title === "Games") return list[i];
            const id = (list[i].appId || "").toLowerCase();
            if (ids.indexOf(id) >= 0) return list[i];
        }
        return null;
    }
    // Bumped when any toplevel changes, to refresh "on" state (appId can arrive late).
    property int tick: 0
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { win.tick++; }
    }
    Instantiator {
        model: ToplevelManager.toplevels
        delegate: QtObject {
            id: watcher
            required property var modelData
            property var c: Connections {
                target: watcher.modelData
                function onAppIdChanged() { win.tick++; }
                function onTitleChanged() { win.tick++; }
            }
        }
    }

    function activate(app) {
        if (app.id === "accessory") {
            // Own window: open it, or raise it if already mapped.
            const w = findToplevel(app.appIds, app);
            if (w) { w.minimized = false; w.activate(); }
            else Config.accessoryOpen = true;
            return;
        }
        if (app.id === "games") {
            // Ultimit's own library window; Steam is launched from inside it.
            if (Games.open) {
                for (const t of ToplevelManager.toplevels.values) {
                    if (t.appId === "org.quickshell" && t.title === "Games") {
                        t.minimized = false; t.activate(); return;
                    }
                }
            }
            Games.show();
            return;
        }
        const tl = findToplevel(app.appIds, app);
        if (tl) {
            tl.minimized = false;
            tl.activate();
        } else {
            Config.launchApp(app);
        }
    }

    Rectangle {
        id: railBg
        anchors.fill: parent
        color: Theme.rail
        // right border
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

        Column {
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Item {   // emblem button: opens the app launcher
                id: embBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40; height: 40
                activeFocusOnTab: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        Config.toggleLauncher(win.screen ? win.screen.name : ""); event.accepted = true;
                    }
                }
                Emblem {
                    anchors.fill: parent
                    size: 40
                    color: Theme.fg
                    scale: embMouse.pressed ? 0.92 : (embMouse.containsMouse ? 1.06 : 1)
                    Behavior on scale { NumberAnimation { duration: Config.dur(150); easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: -2
                    color: "transparent"; border.width: 1; border.color: Theme.accent
                    visible: embBtn.activeFocus && !embMouse.pressed
                }
                MouseArea {
                    id: embMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.toggleLauncher(win.screen ? win.screen.name : "")
                }
            }
            Item { width: 1; height: 10 }   // emblem margin-bottom 14 = 4 spacing + 10

            Repeater {
                model: Config.apps
                delegate: RailButton {
                    required property var modelData
                    appId: modelData.id
                    label: modelData.label
                    missing: !Config.available(modelData)
                    on: { win.tick; return win.findToplevel(modelData.appIds, modelData) !== null; }
                    onClicked: win.activate(modelData)
                }
            }
        }

        // Vertical version string, reads bottom-to-top like the mockup.
        Item {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            width: verText.implicitHeight
            height: verText.implicitWidth
            Text {
                id: verText
                anchors.centerIn: parent
                rotation: -90
                text: "Ultimit " + Config.version + " · " + Theme.skinLabel
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 9
                font.letterSpacing: 0.9
            }
        }
    }
}
