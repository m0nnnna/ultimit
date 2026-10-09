// QuickSettings.qml - status-block popover: Wi-Fi, Bluetooth, sound, brightness, battery /
// power profile, now playing and the power row. Overlay-layer, full-screen transparent window
// (click outside / Escape closes) with the glass panel anchored under the status block.
// Open with a click on the status block or `qs ipc call quicksettings toggle|open|close`.
// State and side effects live in SysState.qml (ULTIMIT_DRY_RUN=1 logs instead of acting).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Networking
import ".."
import "../apps/accessory"

PanelWindow {
    id: win

    property string screenName: ""

    // Keep the window mapped while the close animation plays.
    property real reveal: SysState.qsOpen ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: Config.dur(180); easing.type: Easing.OutCubic } }

    visible: (SysState.qsOpen || reveal > 0) && SysState.isQsScreen(screenName)
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
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
            if (SysState.qsOpen) { win.pwFor = ""; win.wifiOpen = false; win.btOpen = false; win.outOpen = false; powerRow.disarmAll(); keys.forceActiveFocus(); }
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

    // ---------- small shared pieces ----------
    component Expander: Item {
        id: ex
        property string text: ""
        property string detail: ""
        property bool open: false
        signal clicked()
        width: parent.width; height: 28
        Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: exm.containsMouse ? 1 : 0 }
        Text {
            x: 0; anchors.verticalCenter: parent.verticalCenter
            text: ex.text.toUpperCase(); color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
        }
        Text {
            anchors.right: chev.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 190); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
            text: ex.detail; color: Theme.fg
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
        }
        Text {
            id: chev
            anchors.right: parent.right; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter
            text: ex.open ? "−" : "+"; color: Theme.accent
            font.family: Theme.mono; font.pixelSize: 14
        }
        MouseArea { id: exm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ex.clicked() }
    }
    component LockGlyph: Item {
        property color color: Theme.dim
        width: 10; height: 12
        Rectangle { x: 2; y: 0; width: 6; height: 7; radius: 3; color: "transparent"; border.width: 1; border.color: parent.color }
        Rectangle { x: 0; y: 5; width: 10; height: 7; color: parent.color }
    }
    component Seg: Item {
        id: sg
        property string text: ""
        property bool on: false
        signal clicked()
        implicitWidth: sl.implicitWidth + 20; implicitHeight: 26
        Rectangle {
            anchors.fill: parent
            color: sg.on ? Theme.accent : (sm.containsMouse ? Theme.panel2 : "transparent")
            border.width: 1; border.color: sg.on ? Theme.accent : Theme.lineStrong
        }
        Text {
            id: sl; anchors.centerIn: parent
            text: sg.text.toUpperCase(); color: sg.on ? Theme.onAccent : Theme.fg
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
        }
        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sg.clicked() }
    }
    component Rule: Rectangle { width: parent.width; height: 1; color: Theme.line }

    // click outside closes
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: SysState.closeQs()
    }

    Rectangle {
        id: panel
        readonly property real topY: 100
        width: 360
        x: win.width - 24 - width
        y: topY - (1 - win.reveal) * 10
        height: Math.min(flick.contentHeight + 28, win.height - topY - Config.tickerHeight - 6)
        opacity: win.reveal
        color: Theme.panel
        border.width: 1
        border.color: Theme.lineStrong
        MouseArea { anchors.fill: parent }   // swallow clicks
        Brackets {}

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: SysState.closeQs()
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 14
            contentWidth: width
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: flick.width
                spacing: 8

                Text {
                    text: "QUICK SETTINGS"
                    color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4
                }

                // ================= Wi-Fi =================
                Column {
                    width: parent.width
                    visible: SysState.wifiDev !== null
                    ToggleRow {
                        width: parent.width
                        text: "Wi-Fi"
                        checked: Networking.wifiEnabled
                        onToggled: v => SysState.setWifiEnabled(v)
                    }
                    Expander {
                        visible: Networking.wifiEnabled
                        text: SysState.netKind === "eth" ? "Ethernet" : "Networks"
                        detail: SysState.netKind === "wifi" ? SysState.netName : (SysState.netKind === "eth" ? "CONNECTED" : "NOT CONNECTED")
                        open: win.wifiOpen
                        onClicked: win.wifiOpen = !win.wifiOpen
                    }
                    Column {
                        width: parent.width
                        visible: win.wifiOpen && Networking.wifiEnabled
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
                                    width: parent.width; height: 30
                                    Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: nm.containsMouse ? 1 : 0 }
                                    Rectangle { x: -14; width: 2; height: parent.height; color: Theme.accent; visible: nrow.connected }
                                    SignalBars {
                                        x: 2; anchors.verticalCenter: parent.verticalCenter
                                        level: nrow.modelData.signalStrength
                                        color: nrow.connected ? Theme.ok : Theme.fg
                                    }
                                    Text {
                                        x: 28; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 28 - rightSide.width - 8
                                        elide: Text.ElideRight
                                        text: nrow.modelData.name
                                        color: nrow.connected ? Theme.accent : Theme.fg
                                        font.family: Theme.ui; font.pixelSize: 13
                                    }
                                    Row {
                                        id: rightSide
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        Text {
                                            visible: nrow.busy || nrow.connected || nrow.modelData.known
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: nrow.busy ? "CONNECTING" : (nrow.connected ? "CONNECTED" : "SAVED")
                                            color: nrow.busy ? Theme.warn : (nrow.connected ? Theme.ok : Theme.dim)
                                            font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.2
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
                                    height: visible ? 40 : 0
                                    Rectangle {
                                        x: 28; y: 3; width: parent.width - 28; height: 32
                                        color: Theme.panel2
                                        border.width: 1; border.color: pw.activeFocus ? Theme.accent : Theme.line
                                        TextInput {
                                            id: pw
                                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 56
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            passwordCharacter: "•"
                                            color: Theme.fg
                                            selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                                            font.family: Theme.ui; font.pixelSize: 13
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
                                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                                            text: "JOIN ›"; color: pw.text.length >= 8 ? Theme.accent : Theme.dim
                                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
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
                            visible: win.wifiOpen && SysState.netList.length === 0
                            text: "SCANNING…"; color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                            height: 28; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // ================= Bluetooth =================
                Column {
                    width: parent.width
                    visible: SysState.btAvailable
                    ToggleRow {
                        width: parent.width
                        text: "Bluetooth"
                        checked: SysState.btOn
                        onToggled: v => SysState.setBtEnabled(v)
                    }
                    Expander {
                        visible: SysState.btOn
                        text: "Paired devices"
                        detail: SysState.btConnectedCount + " / " + SysState.btPaired.length + " CONNECTED"
                        open: win.btOpen
                        onClicked: win.btOpen = !win.btOpen
                    }
                    Column {
                        width: parent.width
                        visible: win.btOpen && SysState.btOn
                        Repeater {
                            model: win.btOpen ? SysState.btPaired : []
                            delegate: Item {
                                id: brow
                                required property var modelData
                                width: parent.width; height: 34
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - btBtn.width - 10
                                    elide: Text.ElideRight
                                    text: brow.modelData.name || brow.modelData.address
                                    color: brow.modelData.connected ? Theme.accent : Theme.fg
                                    font.family: Theme.ui; font.pixelSize: 13
                                }
                                Text {
                                    visible: brow.modelData.batteryAvailable
                                    anchors.right: btBtn.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(brow.modelData.battery * (brow.modelData.battery <= 1 ? 100 : 1)) + "%"
                                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                                }
                                PowerButton {
                                    id: btBtn
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: brow.modelData.connected ? "Disconnect" : "Connect"
                                    onActivated: SysState.btToggleDevice(brow.modelData)
                                }
                            }
                        }
                        Text {
                            visible: win.btOpen && SysState.btPaired.length === 0
                            text: "NO PAIRED DEVICES"; color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                            height: 28; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // ================= Sound =================
                SectionLabel { text: "Sound"; visible: SysState.sinkReady || SysState.srcReady }
                Column {
                    width: parent.width
                    spacing: 4
                    visible: SysState.sinkReady || SysState.srcReady
                    Row {
                        width: parent.width; spacing: 10
                        visible: SysState.sinkReady
                        SliderField {
                            width: parent.width - outMute.width - 10
                            label: SysState.sinkMuted ? "Output · muted" : "Output"
                            from: 0; to: 100
                            value: Math.min(100, SysState.sinkVol)
                            onMoved: v => SysState.setSinkVol(v)
                        }
                        PowerButton {
                            id: outMute
                            y: 14
                            text: SysState.sinkMuted ? "Unmute" : "Mute"
                            onActivated: SysState.toggleSinkMute()
                        }
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
                        visible: win.outOpen
                        Repeater {
                            model: win.outOpen ? SysState.sinks : []
                            delegate: Item {
                                id: drow
                                required property var modelData
                                readonly property bool cur: SysState.sink !== null && modelData.id === SysState.sink.id
                                width: parent.width; height: 28
                                Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: dm.containsMouse ? 1 : 0 }
                                Rectangle { x: -14; width: 2; height: parent.height; color: Theme.accent; visible: drow.cur }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; elide: Text.ElideRight
                                    text: SysState.nodeLabel(drow.modelData)
                                    color: drow.cur ? Theme.accent : Theme.fg
                                    font.family: Theme.ui; font.pixelSize: 13
                                }
                                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: SysState.setDefaultSink(drow.modelData) }
                            }
                        }
                    }
                    Row {
                        width: parent.width; spacing: 10
                        visible: SysState.srcReady
                        SliderField {
                            width: parent.width - micMute.width - 10
                            label: SysState.srcMuted ? "Microphone · muted" : "Microphone"
                            from: 0; to: 100
                            value: Math.min(100, SysState.srcVol)
                            onMoved: v => SysState.setSrcVol(v)
                        }
                        PowerButton {
                            id: micMute
                            y: 14
                            text: SysState.srcMuted ? "Unmute" : "Mute"
                            onActivated: SysState.toggleSrcMute()
                        }
                    }
                }

                // ================= Display =================
                SectionLabel { text: "Display"; visible: SysState.hasBacklight }
                SliderField {
                    width: parent.width
                    visible: SysState.hasBacklight
                    label: "Brightness"
                    from: 1; to: 100
                    value: SysState.blPct
                    onMoved: v => SysState.setBrightness(v)
                }

                // ================= Battery / power profile =================
                SectionLabel { text: "Power"; visible: SysState.hasBattery || SysState.profilesAvailable }
                Column {
                    width: parent.width
                    spacing: 8
                    visible: SysState.hasBattery || SysState.profilesAvailable
                    Item {
                        width: parent.width; height: 38
                        visible: SysState.hasBattery
                        Text {
                            id: bigPct
                            text: SysState.battPct + "%"
                            color: SysState.charging ? Theme.ok : (SysState.battPct <= 15 ? Theme.bad : (SysState.battPct <= 30 ? Theme.warn : Theme.fg))
                            font.family: Theme.mono; font.pixelSize: 24; font.letterSpacing: 1
                        }
                        Column {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.right: parent.right
                                text: SysState.battState; color: Theme.fg
                                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                            }
                            Text {
                                anchors.right: parent.right
                                visible: text !== ""
                                text: SysState.battTime !== "" ? SysState.battTime + (SysState.charging ? " TO FULL" : " REMAINING") : ""
                                color: Theme.dim
                                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                            }
                        }
                    }
                    Rectangle {   // charge bar
                        width: parent.width; height: 4
                        visible: SysState.hasBattery
                        color: Theme.panel2; border.width: 1; border.color: Theme.line
                        Rectangle { height: parent.height; width: parent.width * SysState.battPct / 100; color: Theme.accent }
                    }
                    Row {
                        spacing: 6
                        visible: SysState.profilesAvailable
                        Repeater {
                            model: SysState.profileList
                            delegate: Seg {
                                required property string modelData
                                text: modelData === "power-saver" ? "Saver" : modelData
                                on: SysState.profile === modelData
                                onClicked: SysState.setProfile(modelData)
                            }
                        }
                    }
                }

                // ================= Now playing =================
                SectionLabel { text: "Now playing"; visible: SysState.player !== null }
                Item {
                    width: parent.width; height: 44
                    visible: SysState.player !== null
                    Column {
                        anchors.left: parent.left; anchors.right: mediaBtns.left; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: SysState.player ? (SysState.player.trackTitle || "Unknown title") : ""
                            color: Theme.fg; font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 13
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: SysState.player ? (SysState.player.trackArtist || SysState.player.identity) : ""
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                        }
                    }
                    Row {
                        id: mediaBtns
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        PowerButton {
                            text: "Prev"; enabled: SysState.player !== null && SysState.player.canGoPrevious
                            onActivated: SysState.player.previous()
                        }
                        PowerButton {
                            text: SysState.player && SysState.player.isPlaying ? "Pause" : "Play"
                            enabled: SysState.player !== null && SysState.player.canTogglePlaying
                            onActivated: SysState.player.togglePlaying()
                        }
                        PowerButton {
                            text: "Next"; enabled: SysState.player !== null && SysState.player.canGoNext
                            onActivated: SysState.player.next()
                        }
                    }
                }

                // ================= Session =================
                Rule {}
                Item {
                    id: powerRow
                    width: parent.width
                    height: pflow.height
                    function disarmAll() { outB.disarm(); susB.disarm(); rebB.disarm(); offB.disarm(); }
                    Flow {
                        id: pflow
                        width: parent.width
                        spacing: 8
                        Item {
                            id: lockWrap
                            width: lockB.width; height: lockB.height
                            HoverHandler { id: lockHover }
                            PowerButton {
                                id: lockB; text: "Lock"; enabled: SysState.lockAvailable
                                onActivated: { SysState.closeQs(); SysState.lock(); }
                            }
                        }
                        PowerButton {
                            id: outB; text: "Log out"; confirm: true
                            onActivated: { SysState.closeQs(); SysState.exec(["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""]); }
                            onArmedChanged: if (armed) { susB.disarm(); rebB.disarm(); offB.disarm(); }
                        }
                        PowerButton {
                            id: susB; text: "Suspend"
                            onActivated: { SysState.closeQs(); SysState.exec(["systemctl", "suspend"]); }
                        }
                        PowerButton {
                            id: rebB; text: "Restart"; confirm: true
                            onActivated: { SysState.closeQs(); SysState.exec(["systemctl", "reboot"]); }
                            onArmedChanged: if (armed) { outB.disarm(); offB.disarm(); }
                        }
                        PowerButton {
                            id: offB; text: "Shut down"; confirm: true
                            onActivated: { SysState.closeQs(); SysState.exec(["systemctl", "poweroff"]); }
                            onArmedChanged: if (armed) { outB.disarm(); rebB.disarm(); }
                        }
                    }
                    // tooltip for the disabled lock button
                    Rectangle {
                        visible: lockHover.hovered && !SysState.lockAvailable
                        x: 0; y: -30; width: tipText.implicitWidth + 16; height: 22
                        color: Theme.panel; border.width: 1; border.color: Theme.lineStrong
                        Text {
                            id: tipText; anchors.centerIn: parent
                            text: "Lock screen coming soon"; color: Theme.fg
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                        }
                    }
                }
            }
        }
    }
}
