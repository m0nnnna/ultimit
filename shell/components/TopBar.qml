// TopBar.qml - the one bar along the top of the main display (layer: top, exclusive zone = bar height),
// L0 chrome like the rail. Left to right:
//   [ app menu button | news ticker (fills the middle) | plugin slot | status icons, tray, time ]
// The right-hand items come from Config.barItems, each a component file components/bar/<Name>Item.qml.
// The plugin slot (pluginSlot below) is an empty Row between the ticker and those items: put an item
// in it by adding a child there. Nothing else is pluggable.
//
// Fullscreen: while a fullscreen window covers this output the bar is not shown at all. Pushing the
// pointer into the top edge slides it over the window (the compositor reports the edge as an
// {"event":"edge"} line, AltTabState.edge; no polling, no input strip over the game). In Game Mode the
// pointer must rest there Config.revealDwellGame ms. It slides away again once the pointer is off
// the bar and no bar popup (flyout, quick settings, app menu, tray menu) is open.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "bar"

PanelWindow {
    id: win

    readonly property string screenName: screen ? screen.name : ""
    readonly property bool covered: Config.isCovered(screenName)

    // ---- fullscreen reveal ----
    property bool revealed: false        // the user pushed the pointer to the top edge
    property bool edgeOn: false          // the pointer is on the top edge right now
    readonly property bool holdOpen: edgeOn || hov.hovered || BarUi.popupOpen
    readonly property bool wantShown: !covered || (revealed && holdOpen) || (revealed && hideTimer.running)
    // 0 = fully away, 1 = in place; slides with Theme.motion.base
    property real slide: wantShown ? 1 : 0
    Behavior on slide { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: wantShown ? Theme.easeBase : Theme.easeIn } }

    onCoveredChanged: { revealed = false; edgeOn = false; dwell.stop(); hideTimer.stop(); }
    onHoldOpenChanged: {
        if (!revealed) return;
        if (holdOpen) hideTimer.stop(); else hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 250; onTriggered: win.revealed = false }
    Timer { id: dwell; interval: Config.revealDwellGame; onTriggered: if (win.edgeOn && win.covered) win.revealed = true }
    Connections {
        target: AltTabState
        function onEdge(output, on) {
            if (output !== win.screenName) return;
            win.edgeOn = on;
            if (!win.covered) return;
            if (!on) { dwell.stop(); return; }
            if (Config.gameModeActive) dwell.restart(); else win.revealed = true;
        }
    }

    Binding { target: BarUi; property: "revealed"; value: win.revealed }
    Binding { target: BarUi; property: "slide"; value: win.slide }

    anchors { left: true; right: true; top: true }
    implicitHeight: Config.barHeight
    // No zone while covered: nothing on this output is laid out around a hidden bar.
    exclusiveZone: covered ? 0 : Config.barHeight
    color: "transparent"
    // Fullscreen windows sit between the top and overlay layers: the revealed bar rides the overlay.
    WlrLayershell.layer: covered ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "ultimit-topbar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand   // Tab / Enter on bar buttons
    // Main display only. Mapped while sliding; away entirely (and input-transparent) while hidden over a fullscreen window.
    visible: Config.isMainScreen(screenName) && (!covered || slide > 0.001)

    Item {
        id: content
        width: parent.width; height: Config.barHeight
        y: Math.round((win.slide - 1) * Config.barHeight)

        Rectangle {
            anchors.fill: parent
            color: Theme.rail
            GlowFrame { anchors.fill: parent; edges: "bottom"; travel: false }
        }
        HoverHandler { id: hov }

        AppMenuButton {
            id: menuBtn
            anchors { left: parent.left; top: parent.top }
            screenName: win.screenName
        }

        Row {   // right-hand items: plugin slot, then Config.barItems
            id: right
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            spacing: 0

            // Plugin slot: empty on purpose. Children added here appear between the ticker and the status items.
            Row { id: pluginSlot; height: Config.barHeight }

            Repeater {
                model: Config.barItems
                delegate: Loader {
                    id: ld
                    required property string modelData
                    height: Config.barHeight
                    source: Qt.resolvedUrl("bar/" + modelData + "Item.qml")
                    onLoaded: if (item && "screenName" in item) item.screenName = win.screenName
                }
            }
        }

        Ticker {
            id: ticker
            visible: Config.tickerOn
            anchors { left: menuBtn.right; leftMargin: Theme.space(2); right: right.left; rightMargin: Theme.space(2); top: parent.top; bottom: parent.bottom }
            screenName: win.screenName
        }
    }
}
