// StatusTray.qml - the always-visible system tray at the right end of the bottom bar (Ticker.qml):
//   [ app tray icons (SNI) | network  bluetooth  volume  battery  bell | clock ]
// A thin left divider and a slightly darker panel set it apart from the ticker. Every status
// element opens its own flyout (Flyout.qml / FlyoutState.qml: network, sound, Bluetooth, battery,
// clock + bell = notification centre); each has Accessible.name, keyboard focus (Tab / Enter) and a
// 500 ms hover tooltip drawn by WindowPopups.qml (WindowUi.showBarTip). Quick Settings is now
// opened from the big desktop clock (StatusBlock) and `qs ipc call quicksettings ...`.
// State comes from SysState (ULTIMIT_FAKE_STATUS can override it for screenshots / tests).
import QtQuick
import Quickshell
import ".."

Item {
    id: root
    property string screenName: ""

    implicitWidth: panel.width
    width: implicitWidth
    height: Config.tickerHeight

    readonly property var days: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    function p2(n) { return String(n).padStart(2, "0"); }
    function openFly(kind) { root.publish(); FlyoutState.toggle(kind, root.screenName); }
    // Tell FlyoutState where the icons are (screen-global x; the bar window starts at the rail's edge).
    property var flyButtons: []
    function publish() {
        FlyoutState.trayX = Config.railWidth + panel.mapToItem(null, 0, 0).x;
        FlyoutState.trayW = panel.width;
        for (const b of flyButtons) if (b.visible && b.fly !== "") FlyoutState.setAnchor(b.fly, b.centerX());
    }
    Connections { target: FlyoutState; function onOpenChanged() { root.publish(); } }
    Component.onCompleted: publish()
    onWidthChanged: publish()

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date now: clock.date
    readonly property string timeText: ((now.getHours() % 12) || 12) + ":" + p2(now.getMinutes()) + " " + (now.getHours() < 12 ? "AM" : "PM")
    readonly property string dateText: now.getFullYear() + "." + p2(now.getMonth() + 1) + "." + p2(now.getDate()) + " " + days[now.getDay()]

    // ---- derived display state ----
    readonly property int wifiLevel: SysState.netStrength <= 0 ? 1 : Math.max(1, Math.min(3, Math.ceil(SysState.netStrength * 3 - 0.1)))
    readonly property int volLevel: SysState.sinkVol <= 0 ? 0 : (SysState.sinkVol < 34 ? 1 : (SysState.sinkVol < 67 ? 2 : 3))
    readonly property color battTone: SysState.full ? Theme.ok
        : (SysState.battPct < 10 ? Theme.bad : (SysState.battPct < 20 && !SysState.charging ? Theme.warn : Theme.fg))
    readonly property int unread: Notifs.count + (SysState.fake.unread !== undefined && Notifs.count === 0 ? SysState.fake.unread : 0)
    readonly property bool airplane: SysState.netKind === "off" && SysState.wifiDev !== null && !SysState.wifiEnabled

    readonly property string netTip: {
        const ip = SysState.netIp !== "" ? SysState.netIp : "NO ADDRESS";
        if (SysState.netKind === "wifi") return "WI-FI  " + SysState.netName + "\nIP " + ip + "  SIGNAL " + Math.round(SysState.netStrength * 100) + "%";
        if (SysState.netKind === "eth") return "ETHERNET  " + (SysState.ethName || "WIRED") + "\nIP " + ip;
        return root.airplane ? "AIRPLANE MODE\nWI-FI RADIO OFF" : "OFFLINE\nNO NETWORK";
    }
    readonly property string btTip: !SysState.btOn ? "BLUETOOTH OFF"
        : (SysState.btConnectedCount > 0 ? "BLUETOOTH\n" + SysState.btConnectedNames.join("\n") : "BLUETOOTH ON\nNO DEVICES CONNECTED")
    readonly property string volTip: (SysState.sinkMuted ? "VOLUME MUTED  " : "VOLUME  ") + SysState.sinkVol + "%"
        + (SysState.sinkName !== "" ? "\n" + SysState.sinkName : "") + "\nSCROLL: +/- 5%  MIDDLE: MUTE"
    readonly property string battTip: {
        let t = "BATTERY " + SysState.battPct + "%  " + SysState.battState;
        if (SysState.battTime !== "") t += "\n" + SysState.battTime + (SysState.charging ? " UNTIL FULL" : " REMAINING");
        if (SysState.profile !== "") t += "\nPOWER PROFILE  " + SysState.profile.toUpperCase();
        return t;
    }
    readonly property string bellTip: (Notifs.dnd ? "DO NOT DISTURB ON" : "NOTIFICATIONS") + "\n" + root.unread + " IN HISTORY  RIGHT-CLICK: " + (Notifs.dnd ? "ALLOW" : "MUTE")

    // ---- one tray button: hover plate, focus ring, tooltip, click / wheel signals ----
    component StatusButton: Item {
        id: sb
        property string name: ""
        property string tip: ""
        property string fly: ""           // flyout this button opens ("" = none)
        property bool lit: FlyoutState.open && FlyoutState.kind === sb.fly && sb.fly !== ""   // accent plate (flyout open)
        Component.onCompleted: { if (sb.fly !== "") root.flyButtons = root.flyButtons.concat([sb]); }
        onWidthChanged: root.publish()
        onVisibleChanged: root.publish()
        default property alias content: slot.data
        signal clicked(int button)
        signal wheeled(int delta)
        signal hovered()
        height: root.height
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: sb.name
        Accessible.description: sb.tip
        Accessible.onPressAction: sb.clicked(Qt.LeftButton)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { sb.clicked(Qt.LeftButton); event.accepted = true; }
        }
        function centerX() { return Config.railWidth + sb.mapToItem(null, sb.width / 2, 0).x; }
        Rectangle {
            anchors.fill: parent
            color: Theme.panel2
            opacity: m.pressed ? 1 : ((m.containsMouse || sb.lit) ? 0.8 : 0)
            Behavior on opacity { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: 1
            color: "transparent"; border.width: 1; border.color: Theme.accent
            visible: sb.activeFocus
        }
        Item { id: slot; anchors.fill: parent }
        MouseArea {
            id: m
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onEntered: { tipTimer.restart(); sb.hovered(); }
            onExited: { tipTimer.stop(); WindowUi.hideTip(); }
            onClicked: mouse => { tipTimer.stop(); WindowUi.hideTip(); sb.clicked(mouse.button); }
            onWheel: wheel => { WindowUi.hideTip(); sb.wheeled(wheel.angleDelta.y); }
        }
        Timer {
            id: tipTimer; interval: 500
            onTriggered: if (sb.tip !== "") WindowUi.showBarTip(sb.tip, sb.centerX(), root.screenName)
        }
        // keep a visible tip current while hovered (e.g. volume after a scroll)
        onTipChanged: if (m.containsMouse && WindowUi.tipText !== "") WindowUi.showBarTip(sb.tip, sb.centerX(), root.screenName)
    }

    Rectangle {   // slightly darker panel + left divider
        id: panel
        height: parent.height
        width: row.width
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0, 0, 0, 0.28)
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: Theme.lineStrong }

        Row {
            id: row
            height: parent.height
            leftPadding: 1
            spacing: 0

            Tray {
                id: appTray
                screenName: root.screenName
            }
            Item {   // separator between app icons and status icons
                visible: appTray.visible
                width: 9; height: root.height
                Rectangle { anchors.centerIn: parent; width: 1; height: 14; color: Theme.line }
            }

            // ---- privacy: what is using the mic, camera or screen; a running recording ----
            Repeater {
                model: [
                    { id: "rec", label: "REC " + Privacy.recTime, apps: Privacy.rec ? ["Screen recording (click to stop)"] : [], tone: Theme.bad },
                    { id: "screen", label: "SCREEN", apps: Privacy.screenApps, tone: Theme.warn },
                    { id: "cam", label: "CAM", apps: Privacy.cameraApps, tone: Theme.warn },
                    { id: "mic", label: "MIC", apps: Privacy.micApps, tone: Theme.warn }
                ].filter(m => m.apps.length > 0)
                delegate: StatusButton {
                    id: pb
                    required property var modelData
                    name: modelData.id === "rec" ? "Screen recording, " + Privacy.recTime + ", click to stop"
                        : ({ screen: "Screen shared by: ", cam: "Camera in use by: ", mic: "Microphone in use by: " })[modelData.id] + modelData.apps.join(", ")
                    tip: modelData.id === "rec" ? "RECORDING " + Privacy.recTime + "\nCLICK TO STOP AND SAVE"
                        : ({ screen: "SCREEN SHARED", cam: "CAMERA IN USE", mic: "MICROPHONE IN USE" })[modelData.id] + "\n" + modelData.apps.join("\n").toUpperCase()
                    width: chip.width + 10
                    onClicked: if (modelData.id === "rec") Privacy.stopRecording()
                    Rectangle {
                        id: chip
                        anchors.centerIn: parent
                        width: lbl.implicitWidth + 16; height: 18
                        color: "transparent"; border.color: pb.modelData.tone
                        Rectangle {   // the dot blinks while recording
                            id: dot
                            x: 5; anchors.verticalCenter: parent.verticalCenter
                            width: 5; height: 5; radius: 2.5; color: pb.modelData.tone
                            SequentialAnimation on opacity {
                                running: pb.modelData.id === "rec" && Config.motion
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1; duration: 600 }
                            }
                        }
                        Text {
                            id: lbl
                            anchors { left: dot.right; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            text: pb.modelData.label; color: pb.modelData.tone
                            font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.2
                        }
                    }
                }
            }

            // ---- network ----
            StatusButton {
                id: net
                name: "Network: " + (SysState.netKind === "wifi" ? "Wi-Fi " + SysState.netName : (SysState.netKind === "eth" ? "Ethernet" : (root.airplane ? "Airplane mode" : "Offline")))
                tip: root.netTip
                fly: "network"
                width: 28
                onClicked: root.openFly("network")
                StatusIcon {
                    anchors.centerIn: parent
                    kind: SysState.netKind === "eth" ? "eth" : (root.airplane ? "airplane" : "wifi")
                    on: SysState.netKind !== "off"
                    level: root.wifiLevel
                    tone: SysState.netKind === "off" ? Theme.dim : Theme.fg
                }
            }

            // ---- Bluetooth (only with an adapter) ----
            StatusButton {
                visible: SysState.btAvailable
                name: "Bluetooth: " + (!SysState.btOn ? "off" : (SysState.btConnectedCount > 0 ? SysState.btConnectedCount + " connected" : "on"))
                tip: root.btTip
                fly: "bluetooth"
                width: visible ? 28 : 0
                onClicked: root.openFly("bluetooth")
                StatusIcon {
                    anchors.centerIn: parent
                    kind: "bt"
                    state: !SysState.btOn ? "off" : (SysState.btConnectedCount > 0 ? "connected" : "on")
                }
            }

            // ---- volume ----
            StatusButton {
                visible: SysState.sinkReady
                name: "Volume: " + (SysState.sinkMuted ? "muted" : SysState.sinkVol + " percent")
                tip: root.volTip
                fly: "sound"
                width: visible ? 28 : 0
                property real acc: 0
                onClicked: button => {
                    if (button === Qt.MiddleButton) {
                        SysState.toggleSinkMute();
                        Osd.flash("volume", SysState.sinkVol, !SysState.sinkMuted);
                    } else root.openFly("sound");
                }
                onWheeled: delta => {
                    // 5 % per wheel notch (120 units); touchpads accumulate
                    acc += delta;
                    const notches = Math.trunc(acc / 120);
                    if (notches === 0) return;
                    acc -= notches * 120;
                    const v = Math.max(0, Math.min(100, SysState.sinkVol + notches * 5));
                    SysState.setSinkVol(v);
                    Osd.flash("volume", v, SysState.sinkMuted);
                }
                StatusIcon {
                    anchors.centerIn: parent
                    kind: "volume"
                    level: root.volLevel
                    muted: SysState.sinkMuted
                }
            }

            // ---- battery (only with a battery) ----
            StatusButton {
                visible: SysState.hasBattery
                name: "Battery: " + SysState.battPct + " percent" + (SysState.charging ? ", charging" : "")
                tip: root.battTip
                width: visible ? batt.width + 14 : 0
                fly: "battery"
                onHovered: SysState.refreshProfiles()
                onClicked: root.openFly("battery")
                Row {
                    id: batt
                    anchors.centerIn: parent
                    spacing: 3
                    StatusIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "battery"
                        pct: SysState.battPct
                        tone: root.battTone
                    }
                    StatusIcon {
                        visible: SysState.charging
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "bolt"
                        size: 14
                        tone: Theme.ok
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: SysState.battPct + "%"
                        color: root.battTone
                        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 0.6
                    }
                }
            }

            // ---- do-not-disturb / unread ----
            StatusButton {
                visible: Notifs.dnd || root.unread > 0
                name: (Notifs.dnd ? "Do not disturb on, " : "Notifications, ") + root.unread + " in history"
                tip: root.bellTip
                fly: "clock"
                width: visible ? 28 : 0
                onClicked: button => { if (button === Qt.LeftButton) root.openFly("clock"); else if (button === Qt.RightButton) Notifs.toggleDnd(); }
                StatusIcon {
                    anchors.centerIn: parent
                    kind: "bell"
                    muted: Notifs.dnd
                    size: 16
                }
                Rectangle {   // unread count badge
                    visible: root.unread > 0
                    x: parent.width / 2 + 2; y: 4
                    width: Math.max(10, bt.implicitWidth + 4); height: 10
                    color: Theme.accent
                    Text {
                        id: bt
                        anchors.centerIn: parent
                        text: root.unread > 9 ? "9+" : String(root.unread)
                        color: Theme.onAccent
                        font.family: Theme.mono; font.pixelSize: 8
                    }
                }
            }

            Item {   // separator before the clock
                width: 9; height: root.height
                Rectangle { anchors.centerIn: parent; width: 1; height: 14; color: Theme.line }
            }

            // ---- clock ----
            StatusButton {
                name: "Clock: " + root.timeText + ", " + root.dateText
                tip: root.dateText
                fly: "clock"
                width: clockText.implicitWidth + 20
                onClicked: root.openFly("clock")
                Text {
                    id: clockText
                    anchors.centerIn: parent
                    text: root.timeText
                    color: Theme.fg
                    font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 0.8
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
