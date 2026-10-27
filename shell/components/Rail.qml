// Rail.qml - left icon rail (layer: top, exclusive zone = rail width).
// Pinned buttons own their windows (RailWindows.qml): launch when none, else minimize / restore /
// cycle, with open / focused / minimized / count shown on the button.
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
    // While the launcher is open on this screen the rail rises to the overlay layer with it, so a
    // fullscreen window doesn't hide the rail (like the taskbar coming up with the Start menu).
    readonly property bool withLauncher: Config.launcherOpen && Config.isUiScreen(screen ? screen.name : "")
    WlrLayershell.layer: win.withLauncher ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "ultimit-rail"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand   // Tab / Enter on rail buttons

    // Room for the pin area: everything but the emblem block and a floor kept for WINDOWS + version.
    readonly property real pinsMaxH: Math.max(3 * 68, height - 14 - 40 - 14 - 150)

    // Click: windows decide (RailWindows: minimize / restore / cycle); no window launches the app.
    function activatePin(pin) {
        RailWindows.activate(pin);
    }
    function newWindow(pin) {
        Config.closeLauncher();
        if (RailWindows.canOpenNew(pin)) RailWindows.launch(pin);
        else if (!RailWindows.click(pin.id)) RailWindows.launch(pin);
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
                    scale: embMouse.pressed ? Theme.pressScale : (embMouse.containsMouse ? 1.06 : 1)
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
                            readonly property var st: { RailWindows.tick; return RailWindows.stateFor(modelData.id); }
                            on: st.open
                            focused: st.focused
                            minimized: st.minimized
                            count: st.count
                            onFocusedChanged: if (focused) win.focusBtn = pb
                            Component.onCompleted: if (focused) win.focusBtn = pb
                            onClicked: win.activatePin(modelData)
                            onMiddleClicked: win.newWindow(modelData)
                            onHoveredChanged: {
                                if (hovered && count > 1) tipTimer.restart();
                                else { tipTimer.stop(); WindowUi.hideTip(); }
                            }
                            Timer {
                                id: tipTimer; interval: 350
                                onTriggered: {   // window picker tooltip: titles of the open windows
                                    const t = RailWindows.windowsFor(pb.modelData.id).map(w => (w.title || w.appId || "Untitled"));
                                    WindowUi.showTip(t.join("\n"), pb.mapToGlobal(0, pb.height / 2).y, win.screen ? win.screen.name : "");
                                }
                            }
                            // Minimize animation flies into this button: report where it is.
                            Timer { id: rectTimer; interval: 120; onTriggered: RailWindows.pushRects(pb.modelData.id, pb, win) }
                            onYChanged: rectTimer.restart()
                            onCountChanged: rectTimer.restart()
                            Connections { target: pinsView; function onContentYChanged() { rectTimer.restart(); } }
                            Connections { target: RailWindows; function onMapTickChanged() { rectTimer.restart(); } }
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
