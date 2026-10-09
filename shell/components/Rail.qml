// Rail.qml - left icon rail (layer: top, exclusive zone = rail width).
// Launches Config.apps commands; shows "on" and focuses the window when a toplevel
// whose app_id matches is already open (wlr-foreign-toplevel via ToplevelManager).
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { left: true; top: true; bottom: true }
    implicitWidth: Config.railWidth
    exclusiveZone: Config.railWidth
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ultimit-rail"

    // Returns the first open toplevel whose appId is in `ids`, or null.
    // Depends on toplevels.values so bindings re-evaluate as windows come and go.
    function findToplevel(ids) {
        const list = ToplevelManager.toplevels.values;
        for (let i = 0; i < list.length; i++) {
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
            }
        }
    }

    function launch(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }

    function activate(app) {
        const tl = findToplevel(app.appIds);
        if (tl) {
            tl.minimized = false;
            tl.activate();
        } else {
            launch(app.command);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rail
        // right border
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

        Column {
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Emblem {
                anchors.horizontalCenter: parent.horizontalCenter
                size: 40
                color: Theme.fg
            }
            Item { width: 1; height: 10 }   // emblem margin-bottom 14 = 4 spacing + 10

            Repeater {
                model: Config.apps
                delegate: RailButton {
                    required property var modelData
                    appId: modelData.id
                    label: modelData.label
                    on: { win.tick; return win.findToplevel(modelData.appIds) !== null; }
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
