// Rail.qml - left icon rail (layer: top, exclusive zone = rail width).
// Launches Config.apps commands; shows "on" and focuses the window when a toplevel
// whose app_id matches is already open (wlr-foreign-toplevel via ToplevelManager).
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../apps/games"
import "../apps/data"

PanelWindow {
    id: win

    anchors { left: true; top: true; bottom: true }
    implicitWidth: Config.railWidth
    exclusiveZone: Config.railWidth
    color: "transparent"
    // While the launcher is open on this screen the rail rises to the overlay layer with it, so a
    // fullscreen window doesn't hide the rail (like the taskbar coming up with the Start menu).
    readonly property bool withLauncher: Config.launcherOpen && Config.isUiScreen(screen ? screen.name : "")
    WlrLayershell.layer: win.withLauncher ? WlrLayer.Overlay : WlrLayer.Top
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
            if (app && app.id === "data" && own && list[i].title === "DATA") return list[i];
            if (app && app.id === "games" && own && list[i].title === Config.gamesTitle) return list[i];
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
                function onActivatedChanged() { win.tick++; }
            }
        }
    }

    // Room for the pin area: everything but the emblem block and a floor kept for WINDOWS + version.
    readonly property real pinsMaxH: Math.max(3 * 68, height - 14 - 40 - 14 - 150)

    function pinToplevel(pin) {
        return pin.builtin ? findToplevel(pin.app.appIds, pin.app) : Pins.matchToplevel(pin);
    }
    function activatePin(pin) {
        Config.closeLauncher();   // the rail sits above the launcher while it is open
        if (pin.builtin) { activate(pin.app); return; }
        const tl = Pins.matchToplevel(pin);
        if (tl) { tl.minimized = false; tl.activate(); }
        else Pins.launch(pin);
    }

    function activate(app) {
        if (app.id === "news" && Feeds.homeUrl !== "") {   // a feed has loaded: open its site
            Feeds.open(Feeds.homeUrl);
            return;
        }
        if (app.id === "accessory") {
            // Own window: open it, or raise it if already mapped.
            const w = findToplevel(app.appIds, app);
            if (w) { w.minimized = false; w.activate(); }
            else Config.openSettings("");
            return;
        }
        if (app.id === "data") {
            const w = findToplevel(app.appIds, app);
            if (w) { w.minimized = false; w.activate(); }
            else Data.show("");
            return;
        }
        if (app.id === "games") {
            // Ultimit's own library window; Steam is launched from inside it.
            if (Games.open) {
                for (const t of ToplevelManager.toplevels.values) {
                    if (t.appId === "org.quickshell" && t.title === Config.gamesTitle) {
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

    // The button whose window is active; the sliding marker follows it (kept after focus leaves the
    // pins so the marker fades where it was instead of jumping).
    property Item focusBtn: null

    Rectangle {
        id: railBg
        anchors.fill: parent
        color: Theme.rail
        GlowFrame { anchors.fill: parent; edges: "right"; travel: false }

        Column {
            id: btnCol
            anchors.top: parent.top
            anchors.topMargin: 16
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
                    Behavior on scale { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
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

            // Pinned items (Pins.qml). Scrolls with the wheel when it would crowd out WINDOWS.
            Flickable {
                id: pinsView
                width: Config.railWidth   // full rail width so the buttons' accent bar (x: -6) is not clipped
                height: Math.min(pinCol.implicitHeight, win.pinsMaxH)
                contentWidth: width
                contentHeight: pinCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentYChanged: WindowUi.hideTip()

                Column {
                    id: pinCol
                    x: (Config.railWidth - 76) / 2
                    spacing: 4
                    Repeater {
                        model: Pins.list
                        delegate: RailButton {
                            id: pb
                            required property var modelData
                            required property int index
                            phase: index * 52   // staggered so the icons don't turn in lockstep
                            covered: !win.withLauncher && Config.isCovered(win.screen ? win.screen.name : "")
                            appId: modelData.builtin ? modelData.id : ""
                            label: modelData.label
                            iconSrc: modelData.builtin ? "" : (modelData.icon ? Icons.app(modelData.icon) : "")
                            letter: modelData.builtin ? "" : ((modelData.name || modelData.label || "?").charAt(0).toUpperCase())
                            missing: modelData.builtin ? !Config.available(modelData.app) : !modelData.found
                            badge: modelData.builtin && modelData.id === "mailer" ? Config.mailUnread : 0
                            on: { win.tick; return win.pinToplevel(modelData) !== null; }
                            focused: { win.tick; const t = win.pinToplevel(modelData); return t !== null && t.activated; }
                            onFocusedChanged: if (focused) win.focusBtn = pb
                            Component.onCompleted: if (focused) win.focusBtn = pb
                            onClicked: win.activatePin(modelData)
                            onRightClicked: gy => { Config.closeLauncher(); Pins.openMenu(modelData.id, gy, win.screen ? win.screen.name : ""); }
                        }
                    }
                }
                Rectangle {   // active-window marker: slides between buttons (Config.dur(); instant with motion off)
                    id: marker
                    x: pinCol.x - 6
                    z: 2
                    width: 3
                    height: 40
                    color: Theme.accent
                    readonly property bool shown: win.focusBtn !== null && win.focusBtn.focused
                    y: win.focusBtn ? win.focusBtn.y + 12 : 0
                    opacity: shown ? 1 : 0
                    Behavior on y { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
                    Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                }
                Rectangle {   // scroll indicator, only when the pins overflow
                    visible: pinsView.contentHeight > pinsView.height
                    anchors.right: parent.right
                    width: 2
                    y: pinsView.height * pinsView.visibleArea.yPosition
                    height: pinsView.height * pinsView.visibleArea.heightRatio
                    color: Theme.lineStrong
                }
            }
        }

        // Open windows; the list scrolls inside the space between the buttons and the version text.
        WindowList {
            anchors.top: btnCol.bottom; anchors.topMargin: 8
            anchors.bottom: bottomEdge.top; anchors.bottomMargin: 12
            anchors.left: parent.left; anchors.right: parent.right
            screenName: win.screen ? win.screen.name : ""
            panel: win
        }

        // What the window list sits on: the version text, or the rail's
        // bottom edge when the screen is too short to spare it (720p).
        Item {
            id: bottomEdge
            anchors.bottom: parent.bottom
            anchors.bottomMargin: verItem.visible ? verItem.height + 14 : 2
            width: 1; height: 0
        }

        // Vertical version string, reads bottom-to-top like the mockup; gives way
        // to open windows when there isn't room for at least two entries.
        Item {
            id: verItem
            visible: parent.height - btnCol.y - btnCol.height - height > 140
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            width: verText.implicitHeight
            height: verText.implicitWidth
            Text {
                id: verText
                anchors.centerIn: parent
                rotation: -90
                text: "Ultimit " + (Config.versionShort !== "" ? Config.versionShort + " · " : "") + Theme.skinLabel
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: Theme.type.label
                font.letterSpacing: 0.9
            }
        }
    }
}
