// QuickSettings.qml - the clock + quick settings panel: a big clock (time with seconds, date) on
// top, then Wi-Fi, Bluetooth, sound, brightness, battery / power profile, now playing and the power
// row. Overlay-layer, full-screen transparent window (click outside / Escape closes) with the glass
// panel at the top right, under the top bar's time. The window's input mask leaves the bar band
// free, so a click on the time (or any bar item) still reaches the bar.
// Open with a click on the time in the top bar or `qs ipc call quicksettings toggle|open|close`.
// State and side effects live in SysState.qml (ULTIMIT_DRY_RUN=1 logs instead of acting).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Networking
import QtQuick.Shapes
import ".."
import "../apps/accessory"
import "flyout"

PanelWindow {
    id: win

    property string screenName: ""

    // Keep the window mapped while the close animation plays.
    property real reveal: SysState.qsOpen ? 1 : 0
    ShowBehavior on reveal {}

    visible: (SysState.qsOpen || reveal > 0) && SysState.isQsScreen(screenName)
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { x: 0; y: Config.barHeight; width: win.width; height: Math.max(0, win.height - Config.barHeight) }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-quicksettings"
    WlrLayershell.keyboardFocus: (visible && SysState.qsOpen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // section expansion + inline password state
    property bool wifiOpen: false
    property bool btOpen: false
    property bool outOpen: false
    property string pwFor: ""
    Binding { target: SysState; property: "netFreeze"; value: win.pwFor !== "" }

    onVisibleChanged: if (visible && SysState.qsOpen) { keys.forceActiveFocus(); }
    Connections {
        target: SysState
        function onQsOpenChanged() {
            if (SysState.qsOpen) { win.pwFor = ""; win.wifiOpen = false; win.btOpen = false; win.outOpen = false; win.tipText = ""; powerRow.disarmAll(); keys.forceActiveFocus(); }
        }
    }
    Connections {
        target: Config
        function onLauncherOpenChanged() { if (Config.launcherOpen) SysState.closeQs(); }
    }
    // Scan only while the list is on screen.
    Binding {
        target: SysState.wifiDev
        property: "scannerEnabled"
        value: SysState.qsOpen && win.wifiOpen && Networking.wifiEnabled
        when: SysState.wifiDev !== null
    }

    // ---------- private pieces ----------
    readonly property int pad: Theme.space(4)
    readonly property int gap: Theme.space(4)        // between sections
    property string tipText: ""
    property real tipCx: 0
    property real tipTy: 0

    function showTip(text, item) {
        const p = item.mapToItem(panel, item.width / 2, 0);
        win.tipText = text; win.tipCx = p.x; win.tipTy = p.y;
    }

    // thin-line glyph on a 24 grid (paths in Icon.qml's style)
    component Glyph: Item {
        id: gl
        property string path: ""
        property color color: Theme.fg
        property real size: Theme.icon.md
        width: size; height: size
        Shape {
            width: 24; height: 24
            scale: gl.size / 24; transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"; strokeColor: gl.color; strokeWidth: 1.5 * 24 / gl.size
                joinStyle: ShapePath.MiterJoin; capStyle: ShapePath.RoundCap
                Behavior on strokeColor { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                PathSvg { path: gl.path }
            }
        }
    }
    readonly property var glyphs: ({
        lock:    "M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3",
        logout:  "M10 4H5v16h5M9 12h11M16 8l4 4-4 4",
        sleep:   "M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z",
        hibernate: "M12 3v18M4.2 7.5l15.6 9M4.2 16.5l15.6-9",
        restart: "M20 12a8 8 0 1 1-2.4-5.7M20 4v5h-5",
        power:   "M12 3v9M6.3 6.6a8 8 0 1 0 11.4 0",
        prev:    "M7 5v14M19 5L9 12l10 7z",
        play:    "M7 4l13 8-13 8z",
        pause:   "M8 4v16M16 4v16",
        next:    "M17 5v14M5 5l10 7-10 7z",
        chevron: "M9 6l6 6-6 6"
    })

    // square icon button; `confirm` arms on first click (warn colour, "Click again" tip)
    component IconBtn: Item {
        id: ib
        property string glyph: ""
        property string tip: ""
        property bool confirm: false
        property bool armed: false
        property int box: Theme.space(10)
        signal activated()
        function disarm() { armed = false; }
        implicitWidth: box; implicitHeight: box
        opacity: enabled ? 1 : 0.4
        Timer { interval: 3000; running: ib.armed; onTriggered: ib.armed = false }
        Rectangle {
            anchors.fill: parent
            color: ib.armed ? Qt.alpha(Theme.warn, 0.22) : (ima.pressed ? Theme.press : (ima.containsMouse && ib.enabled ? Theme.hover : Theme.field))
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        }
        Glyph { anchors.centerIn: parent; path: win.glyphs[ib.glyph] || ""; color: ib.armed ? Theme.warn : Theme.fg }
        MouseArea {
            id: ima
            anchors.fill: parent; hoverEnabled: true
            cursorShape: ib.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: tipTimer.restart()
            onExited: { tipTimer.stop(); if (win.tipText === (ib.armed ? "Click again to confirm" : ib.tip)) win.tipText = ""; }
            onClicked: {
                if (!ib.enabled) return;
                if (ib.confirm && !ib.armed) { ib.armed = true; win.showTip("Click again to confirm", ib); return; }
                ib.armed = false; win.tipText = "";
                ib.activated();
            }
        }
        Timer { id: tipTimer; interval: 350; onTriggered: if (ib.tip !== "") win.showTip(ib.tip, ib) }
    }

    // toggle tile: icon + name + one-line state; selection fill when on. `expandable` adds a chevron zone.
    component Tile: Item {
        id: tl
        property string name: ""
        property string detail: ""
        property bool on: false
        property bool expandable: false
        property bool expanded: false
        default property alias icon: iconSlot.data
        signal toggled()
        signal expandClicked()
        height: Theme.space(14)
        Rectangle {
            anchors.fill: parent
            color: tl.on ? Theme.selection : (tma.pressed ? Theme.press : (tma.containsMouse ? Theme.hover : Theme.field))
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        }
        Item { id: iconSlot; x: Theme.space(3); anchors.verticalCenter: parent.verticalCenter; width: Theme.icon.md; height: Theme.icon.md }
        Column {
            anchors { left: iconSlot.right; leftMargin: Theme.space(3); right: chev.visible ? chev.left : parent.right; rightMargin: Theme.space(2); verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: tl.name; color: tl.on ? Theme.accent : Theme.fg
                font.family: Theme.ui; font.pixelSize: Theme.type.body; font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: tl.detail; color: Theme.dim
                font.family: Theme.ui; font.pixelSize: Theme.type.label
            }
        }
        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tl.toggled() }
        Item {
            id: chev
            visible: tl.expandable
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: Theme.space(9)
            Rectangle { anchors.fill: parent; color: cma.containsMouse ? Theme.hover : Theme.clear(Theme.hover); Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } } }
            Glyph {
                anchors.centerIn: parent; size: Theme.icon.sm
                path: win.glyphs.chevron; color: tl.expanded ? Theme.accent : Theme.dim
                rotation: tl.expanded ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
            }
            MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tl.expandClicked() }
        }
    }

    // sentence-case row that opens a list
    component Expander: Item {
        id: ex
        property string text: ""
        property string detail: ""
        property bool open: false
        signal clicked()
        width: parent.width; height: Theme.space(9)
        Rectangle { anchors.fill: parent; color: exm.containsMouse ? Theme.hover : Theme.clear(Theme.hover); Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } } }
        Text {
            id: exl
            x: Theme.space(2); anchors.verticalCenter: parent.verticalCenter
            text: ex.text; color: Theme.fg
            font.family: Theme.ui; font.pixelSize: Theme.type.body
        }
        Glyph {
            id: chev
            anchors { right: parent.right; rightMargin: Theme.space(2); verticalCenter: parent.verticalCenter }
            size: Theme.icon.sm; path: win.glyphs.chevron; color: ex.open ? Theme.accent : Theme.dim
            rotation: ex.open ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        }
        Text {
            anchors { left: exl.right; leftMargin: Theme.space(3); right: chev.left; rightMargin: Theme.space(2); verticalCenter: parent.verticalCenter }
            horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
            text: ex.detail; color: Theme.dim
            font.family: Theme.ui; font.pixelSize: Theme.type.label
        }
        MouseArea { id: exm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ex.clicked() }
    }
    component LockGlyph: Item {
        property color color: Theme.dim
        width: 10; height: 12
        Rectangle { x: 2; y: 0; width: 6; height: 7; radius: 3; color: "transparent"; border.width: 1; border.color: parent.color }
        Rectangle { x: 0; y: 5; width: 10; height: 7; color: parent.color }
    }
    // segmented control: equal segments in an inset track, the active one filled with the accent
    component Segmented: Item {
        id: sgc
        property var model: []
        property var labels: ({})
        property string current: ""
        signal picked(string value)
        height: Theme.space(8)
        Rectangle { anchors.fill: parent; color: Theme.field }
        Row {
            anchors.fill: parent; anchors.margins: 2
            Repeater {
                model: sgc.model
                delegate: Item {
                    id: seg
                    required property string modelData
                    readonly property bool on: sgc.current === modelData
                    width: parent.width / Math.max(1, sgc.model.length); height: parent.height
                    Rectangle {
                        anchors.fill: parent
                        color: seg.on ? Theme.accent : (sma.containsMouse ? Theme.hover : Theme.clear(Theme.hover))
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    }
                    Text {
                        anchors.centerIn: parent; width: parent.width - Theme.space(2); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: sgc.labels[seg.modelData] || (seg.modelData.charAt(0).toUpperCase() + seg.modelData.slice(1))
                        color: seg.on ? Theme.onAccent : Theme.fg
                        font.family: Theme.ui; font.pixelSize: Theme.type.label + 1; font.weight: Font.DemiBold
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    }
                    MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sgc.picked(seg.modelData) }
                }
            }
        }
    }

    // click outside closes
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: SysState.closeQs()
    }

    Surface {
        id: panel
        glow: true; brackets: true
        elevation: 2; shadowNs: "ultimit-quicksettings"; shadowWanted: SysState.qsOpen
        readonly property real topY: Config.barHeight + 6
        readonly property real maxH: win.height - topY - 12
        width: 360
        x: win.width - 8 - width
        height: Math.min(flick.contentHeight + win.pad * 2, maxH)
        y: topY - (1 - win.reveal) * Theme.showOffset
        opacity: win.reveal
        transform: Scale {
            origin.x: panel.width; origin.y: 0
            xScale: Theme.showScale + (1 - Theme.showScale) * win.reveal
            yScale: xScale
        }
        MouseArea { anchors.fill: parent }   // swallow clicks

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: SysState.closeQs()
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: win.pad
            contentWidth: width
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: flick.width
                spacing: win.gap

                // ================= clock header =================
                Item {
                    id: clockHead
                    width: parent.width; height: bigTime.implicitHeight + dateLine.implicitHeight + Theme.space(2)
                    readonly property var days: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                    readonly property var months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
                    function p2(n) { return String(n).padStart(2, "0"); }
                    // Seconds only while the panel is up and nothing (fullscreen, game, idle) pauses the desktop.
                    SystemClock { id: qsClock; enabled: SysState.qsOpen; precision: Config.desktopPaused ? SystemClock.Minutes : SystemClock.Seconds }
                    readonly property date now: qsClock.date
                    Text {
                        id: bigTime
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: Theme.type.head
                        text: clockHead.p2(clockHead.now.getHours()) + ":" + clockHead.p2(clockHead.now.getMinutes())
                            + (Config.desktopPaused ? "" : ":" + clockHead.p2(clockHead.now.getSeconds()))
                        color: Theme.fg
                        font.family: Theme.display; font.pixelSize: Theme.type.hero; font.features: Theme.tnum
                    }
                    Text {
                        id: dateLine
                        anchors { left: parent.left; top: bigTime.bottom; topMargin: Theme.space(1) }
                        text: clockHead.days[clockHead.now.getDay()] + ", " + clockHead.months[clockHead.now.getMonth()] + " " + clockHead.now.getDate() + ", " + clockHead.now.getFullYear()
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: Theme.type.body
                    }
                }

                // ================= toggle tiles =================
                Grid {
                    id: tiles
                    width: parent.width
                    columns: 2; spacing: Theme.space(2)
                    readonly property real tw: (width - spacing) / 2
                    Tile {
                        width: tiles.tw
                        visible: SysState.wifiDev !== null
                        name: "Wi-Fi"
                        detail: !Networking.wifiEnabled ? "Off" : (SysState.netKind === "wifi" ? SysState.netName : (SysState.netKind === "eth" ? "Ethernet" : "Not connected"))
                        on: Networking.wifiEnabled
                        expandable: Networking.wifiEnabled; expanded: win.wifiOpen
                        onToggled: SysState.setWifiEnabled(!Networking.wifiEnabled)
                        onExpandClicked: { win.wifiOpen = !win.wifiOpen; if (win.wifiOpen) win.btOpen = false; }
                        StatusIcon { anchors.fill: parent; size: Theme.icon.md; kind: "wifi"; level: 3; on: Networking.wifiEnabled; tone: Networking.wifiEnabled ? Theme.accent : Theme.dim }
                    }
                    Tile {
                        width: tiles.tw
                        visible: SysState.btAvailable
                        name: "Bluetooth"
                        detail: !SysState.btOn ? "Off" : (SysState.btConnectedCount > 0 ? SysState.btConnectedCount + " connected" : "On")
                        on: SysState.btOn
                        expandable: SysState.btOn; expanded: win.btOpen
                        onToggled: SysState.setBtEnabled(!SysState.btOn)
                        onExpandClicked: { win.btOpen = !win.btOpen; if (win.btOpen) win.wifiOpen = false; }
                        StatusIcon { anchors.fill: parent; size: Theme.icon.md; kind: "bt"; state: SysState.btOn ? (SysState.btConnectedCount > 0 ? "connected" : "on") : "off" }
                    }
                    Tile {
                        width: tiles.tw
                        name: "Do not disturb"
                        detail: Notifs.dnd ? "On" : "Off"
                        on: Notifs.dnd
                        onToggled: Notifs.dnd = !Notifs.dnd
                        StatusIcon { anchors.fill: parent; size: Theme.icon.md; kind: "bell"; muted: Notifs.dnd; tone: Notifs.dnd ? Theme.accent : Theme.fg }
                    }
                    Tile {
                        width: tiles.tw
                        name: "Game mode"
                        detail: Config.gameModeActive ? "Active" : (Config.gameModeEnabled ? "Automatic" : "Off")
                        on: Config.gameModeEnabled
                        onToggled: Config.gameModeEnabled = !Config.gameModeEnabled
                        Icon { anchors.centerIn: parent; name: "games"; size: Theme.icon.md; color: Config.gameModeEnabled ? Theme.accent : Theme.fg }
                    }
                }

                // ================= Wi-Fi list =================
                Rectangle {
                    width: parent.width
                    visible: win.wifiOpen && Networking.wifiEnabled && SysState.wifiDev !== null
                    height: visible ? wifiCol.height + Theme.space(4) : 0
                    color: Theme.field
                    Column {
                        id: wifiCol
                        x: Theme.space(2); y: Theme.space(2)
                        width: parent.width - Theme.space(4)
                        Repeater {
                            model: win.wifiOpen ? SysState.netList.slice(0, 8) : []
                            delegate: Column {
                                id: nrow
                                required property var modelData
                                readonly property bool connected: modelData.connected
                                readonly property bool secured: SysState.isSecured(modelData)
                                readonly property bool busy: modelData.stateChanging || SysState.netBusy === modelData.name
                                width: parent.width
                                Item {
                                    width: parent.width; height: Theme.space(9)
                                    Rectangle {
                                        anchors.fill: parent
                                        color: nrow.connected ? Theme.selection : (nm.containsMouse ? Theme.hover : Theme.clear(Theme.hover))
                                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                                    }
                                    SignalBars {
                                        x: Theme.space(2); anchors.verticalCenter: parent.verticalCenter
                                        level: nrow.modelData.signalStrength
                                        color: nrow.connected ? Theme.ok : Theme.fg
                                    }
                                    Text {
                                        x: Theme.space(8); anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Theme.space(8) - rightSide.width - Theme.space(4)
                                        elide: Text.ElideRight
                                        text: nrow.modelData.name
                                        color: nrow.connected ? Theme.accent : Theme.fg
                                        font.family: Theme.ui; font.pixelSize: Theme.type.body
                                    }
                                    Row {
                                        id: rightSide
                                        anchors.right: parent.right; anchors.rightMargin: Theme.space(2); anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.space(2)
                                        Text {
                                            visible: nrow.busy || nrow.connected || nrow.modelData.known
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: nrow.busy ? "Connecting" : (nrow.connected ? "Connected" : "Saved")
                                            color: nrow.busy ? Theme.warn : (nrow.connected ? Theme.ok : Theme.dim)
                                            font.family: Theme.ui; font.pixelSize: Theme.type.label
                                        }
                                        LockGlyph { visible: nrow.secured; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    MouseArea {
                                        id: nm
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (nrow.connected) { win.pwFor = ""; SysState.disconnectWifi(); }
                                            else if (nrow.secured && !nrow.modelData.known) { win.pwFor = nrow.modelData.name; pw.text = ""; pw.forceActiveFocus(); }
                                            else { win.pwFor = ""; SysState.connectWifi(nrow.modelData.name, ""); }
                                        }
                                    }
                                }
                                Item {   // inline password prompt
                                    id: pwBox
                                    width: parent.width
                                    visible: win.pwFor === nrow.modelData.name
                                    height: visible ? Theme.space(11) : 0
                                    Rectangle {
                                        x: Theme.space(8); y: Theme.space(1); width: parent.width - Theme.space(8); height: Theme.space(9)
                                        color: Theme.field
                                        border.width: 1; border.color: pw.activeFocus ? Theme.accent : Theme.line
                                        TextInput {
                                            id: pw
                                            anchors.fill: parent; anchors.leftMargin: Theme.space(3); anchors.rightMargin: Theme.space(16)
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            passwordCharacter: "•"
                                            color: Theme.fg
                                            selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                                            font.family: Theme.ui; font.pixelSize: Theme.type.body
                                            clip: true
                                            Keys.onEscapePressed: win.pwFor = ""
                                            Keys.onReturnPressed: pwGo.go()
                                            Keys.onEnterPressed: pwGo.go()
                                            Text {
                                                visible: pw.text === ""
                                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                text: "Password"; color: Theme.dim; font: pw.font
                                            }
                                        }
                                        Text {
                                            id: pwGo
                                            anchors.right: parent.right; anchors.rightMargin: Theme.space(3); anchors.verticalCenter: parent.verticalCenter
                                            text: "Join"; color: pw.text.length >= 8 ? Theme.accent : Theme.dim
                                            font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.body
                                            function go() {
                                                if (pw.text === "") return;
                                                const p = pw.text; pw.text = ""; win.pwFor = "";
                                                SysState.connectWifi(nrow.modelData.name, p);
                                            }
                                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: pwGo.go() }
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: SysState.netList.length === 0
                            text: "Scanning for networks…"; color: Theme.dim
                            font.family: Theme.ui; font.pixelSize: Theme.type.label
                            height: Theme.space(9); verticalAlignment: Text.AlignVCenter; leftPadding: Theme.space(2)
                        }
                    }
                }

                // ================= Bluetooth list =================
                Rectangle {
                    width: parent.width
                    visible: win.btOpen && SysState.btOn && SysState.btAvailable
                    height: visible ? btCol.height + Theme.space(4) : 0
                    color: Theme.field
                    Column {
                        id: btCol
                        x: Theme.space(2); y: Theme.space(2)
                        width: parent.width - Theme.space(4)
                        Repeater {
                            model: win.btOpen ? SysState.btPaired : []
                            delegate: Item {
                                id: brow
                                required property var modelData
                                width: parent.width; height: Theme.space(9)
                                Rectangle {
                                    anchors.fill: parent
                                    color: brow.modelData.connected ? Theme.selection : (bm.containsMouse ? Theme.hover : Theme.clear(Theme.hover))
                                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                                }
                                Text {
                                    x: Theme.space(2); anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - stateTxt.implicitWidth - Theme.space(6) - (batTxt.visible ? batTxt.implicitWidth + Theme.space(2) : 0)
                                    elide: Text.ElideRight
                                    text: brow.modelData.name || brow.modelData.address
                                    color: brow.modelData.connected ? Theme.accent : Theme.fg
                                    font.family: Theme.ui; font.pixelSize: Theme.type.body
                                }
                                Text {
                                    id: batTxt
                                    visible: brow.modelData.batteryAvailable
                                    anchors.right: stateTxt.left; anchors.rightMargin: Theme.space(2); anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(brow.modelData.battery * (brow.modelData.battery <= 1 ? 100 : 1)) + "%"
                                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label
                                }
                                Text {
                                    id: stateTxt
                                    anchors.right: parent.right; anchors.rightMargin: Theme.space(2); anchors.verticalCenter: parent.verticalCenter
                                    text: brow.modelData.connected ? "Disconnect" : "Connect"
                                    color: bm.containsMouse ? Theme.accent : Theme.dim
                                    font.family: Theme.ui; font.pixelSize: Theme.type.label
                                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                                }
                                MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: SysState.btToggleDevice(brow.modelData) }
                            }
                        }
                        Text {
                            visible: SysState.btPaired.length === 0
                            text: "No paired devices"; color: Theme.dim
                            font.family: Theme.ui; font.pixelSize: Theme.type.label
                            height: Theme.space(9); verticalAlignment: Text.AlignVCenter; leftPadding: Theme.space(2)
                        }
                    }
                }

                // ================= sound and display =================
                SectionLabel { text: "Levels"; visible: SysState.sinkReady || SysState.srcReady || SysState.hasBacklight }
                Column {
                    width: parent.width
                    spacing: Theme.space(1)
                    visible: SysState.sinkReady || SysState.srcReady || SysState.hasBacklight
                    FlySlider {
                        width: parent.width
                        visible: SysState.sinkReady
                        icon: "volume"; muted: SysState.sinkMuted
                        value: Math.min(100, SysState.sinkVol)
                        onMoved: v => SysState.setSinkVol(v)
                        onMuteClicked: SysState.toggleSinkMute()
                    }
                    Expander {
                        visible: SysState.sinkReady && SysState.sinks.length > 1
                        text: "Output device"
                        detail: SysState.nodeLabel(SysState.sink)
                        open: win.outOpen
                        onClicked: win.outOpen = !win.outOpen
                    }
                    Column {
                        width: parent.width
                        visible: win.outOpen && SysState.sinks.length > 1
                        Repeater {
                            model: win.outOpen ? SysState.sinks : []
                            delegate: Item {
                                id: drow
                                required property var modelData
                                readonly property bool cur: SysState.sink !== null && modelData.id === SysState.sink.id
                                width: parent.width; height: Theme.space(9)
                                Rectangle {
                                    anchors.fill: parent
                                    color: drow.cur ? Theme.selection : (dm.containsMouse ? Theme.hover : Theme.clear(Theme.hover))
                                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                                }
                                Text {
                                    x: Theme.space(2); anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Theme.space(4); elide: Text.ElideRight
                                    text: SysState.nodeLabel(drow.modelData)
                                    color: drow.cur ? Theme.accent : Theme.fg
                                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                                    font.family: Theme.ui; font.pixelSize: Theme.type.body
                                }
                                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: SysState.setDefaultSink(drow.modelData) }
                            }
                        }
                    }
                    FlySlider {
                        width: parent.width
                        visible: SysState.srcReady
                        icon: "mic"; muted: SysState.srcMuted
                        value: Math.min(100, SysState.srcVol)
                        onMoved: v => SysState.setSrcVol(v)
                        onMuteClicked: SysState.toggleSrcMute()
                    }
                    FlySlider {
                        width: parent.width
                        visible: SysState.hasBacklight
                        icon: "sun"; muteable: false; from: 1
                        value: SysState.blPct
                        onMoved: v => SysState.setBrightness(v)
                    }
                }

                // ================= battery / power profile =================
                SectionLabel { text: "Power"; visible: SysState.hasBattery || SysState.profilesAvailable }
                Column {
                    width: parent.width
                    spacing: Theme.space(2)
                    visible: SysState.hasBattery || SysState.profilesAvailable
                    Item {
                        width: parent.width; height: Theme.space(7)
                        visible: SysState.hasBattery
                        Text {
                            id: bigPct
                            anchors.verticalCenter: parent.verticalCenter
                            text: SysState.battPct + "%"
                            color: SysState.charging ? Theme.ok : (SysState.battPct <= 15 ? Theme.bad : (SysState.battPct <= 30 ? Theme.warn : Theme.fg))
                            font.family: Theme.mono; font.pixelSize: Theme.type.title; font.features: Theme.tnum
                        }
                        Text {
                            anchors { left: bigPct.right; leftMargin: Theme.space(3); right: parent.right; verticalCenter: parent.verticalCenter }
                            horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                            text: SysState.battState + (SysState.battTime !== "" ? " · " + SysState.battTime + (SysState.charging ? " to full" : " left") : "")
                            color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                        }
                    }
                    Rectangle {   // charge bar
                        width: parent.width; height: 4
                        visible: SysState.hasBattery
                        color: Theme.field
                        Rectangle { height: parent.height; width: parent.width * SysState.battPct / 100; color: Theme.accent }
                    }
                    Segmented {
                        width: parent.width
                        visible: SysState.profilesAvailable
                        model: SysState.profileList
                        labels: ({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" })
                        current: SysState.profile
                        onPicked: v => SysState.setProfile(v)
                    }
                }

                // ================= now playing =================
                Rectangle {
                    width: parent.width; height: Theme.space(14)
                    visible: SysState.player !== null
                    color: Theme.field
                    Column {
                        anchors { left: parent.left; leftMargin: Theme.space(3); right: mediaBtns.left; rightMargin: Theme.space(3); verticalCenter: parent.verticalCenter }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: SysState.player ? (SysState.player.trackTitle || "Unknown title") : ""
                            color: Theme.fg; font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.body
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: SysState.player ? (SysState.player.trackArtist || SysState.player.identity) : ""
                            color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                        }
                    }
                    Row {
                        id: mediaBtns
                        anchors { right: parent.right; rightMargin: Theme.space(2); verticalCenter: parent.verticalCenter }
                        spacing: Theme.space(1)
                        IconBtn {
                            box: Theme.space(8); glyph: "prev"; tip: "Previous"; enabled: SysState.player !== null && SysState.player.canGoPrevious
                            onActivated: SysState.player.previous()
                        }
                        IconBtn {
                            box: Theme.space(8); glyph: SysState.player && SysState.player.isPlaying ? "pause" : "play"
                            tip: SysState.player && SysState.player.isPlaying ? "Pause" : "Play"
                            enabled: SysState.player !== null && SysState.player.canTogglePlaying
                            onActivated: SysState.player.togglePlaying()
                        }
                        IconBtn {
                            box: Theme.space(8); glyph: "next"; tip: "Next"; enabled: SysState.player !== null && SysState.player.canGoNext
                            onActivated: SysState.player.next()
                        }
                    }
                }

                // ================= session =================
                Item {
                    id: powerRow
                    width: parent.width
                    height: Theme.space(10)
                    function disarmAll() { outB.disarm(); rebB.disarm(); offB.disarm(); hibB.disarm(); }
                    Row {
                        id: pflow
                        width: parent.width
                        spacing: Theme.space(2)
                        readonly property int n: 5 + (SysState.canHibernate ? 1 : 0)
                        readonly property real bw: (width - spacing * (n - 1)) / n
                        IconBtn {
                            id: lockB; width: pflow.bw; glyph: "lock"; tip: "Lock"; enabled: SysState.lockAvailable
                            onActivated: { SysState.closeQs(); SysState.lock(); }
                        }
                        IconBtn {
                            id: outB; width: pflow.bw; glyph: "logout"; tip: "Log out"; confirm: true
                            onActivated: { SysState.closeQs(); SysState.exec(["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""]); }
                            onArmedChanged: if (armed) { hibB.disarm(); rebB.disarm(); offB.disarm(); }
                        }
                        IconBtn {
                            id: susB; width: pflow.bw; glyph: "sleep"; tip: "Sleep"
                            onActivated: { SysState.closeQs(); SysState.exec(["systemctl", "suspend"]); }
                        }
                        IconBtn {
                            id: hibB; width: pflow.bw; glyph: "hibernate"; tip: "Hibernate"; confirm: true
                            visible: SysState.canHibernate
                            onActivated: { SysState.closeQs(); SysState.exec(["systemctl", "hibernate"]); }
                            onArmedChanged: if (armed) { outB.disarm(); rebB.disarm(); offB.disarm(); }
                        }
                        IconBtn {
                            id: rebB; width: pflow.bw; glyph: "restart"; tip: "Restart"; confirm: true
                            onActivated: { SysState.closeQs(); SysState.exec(["systemctl", "reboot"]); }
                            onArmedChanged: if (armed) { outB.disarm(); hibB.disarm(); offB.disarm(); }
                        }
                        IconBtn {
                            id: offB; width: pflow.bw; glyph: "power"; tip: "Shut down"; confirm: true
                            onActivated: { SysState.closeQs(); SysState.exec(["systemctl", "poweroff"]); }
                            onArmedChanged: if (armed) { outB.disarm(); hibB.disarm(); rebB.disarm(); }
                        }
                    }
                }
            }
        }

        // tooltip for the icon buttons
        Rectangle {
            id: tipBox
            z: 20
            visible: win.tipText !== ""
            width: tipLbl.implicitWidth + Theme.space(6); height: tipLbl.implicitHeight + Theme.space(3)
            x: Math.max(Theme.space(2), Math.min(win.tipCx - width / 2, panel.width - width - Theme.space(2)))
            y: win.tipTy - height - Theme.space(1)
            color: Qt.rgba(Theme.bg1.r, Theme.bg1.g, Theme.bg1.b, 0.96)
            Text {
                id: tipLbl
                anchors.centerIn: parent
                text: win.tipText; color: Theme.fg
                font.family: Theme.ui; font.pixelSize: Theme.type.label
            }
        }
    }
}
