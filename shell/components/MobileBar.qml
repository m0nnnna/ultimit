// MobileBar.qml - phone status bar (ULTIMIT_MOBILE=1): clock on the left, network and battery on
// the right. Tap it or pull it down for quick settings. Top layer, exclusive zone.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { left: true; right: true; top: true }
    implicitHeight: Config.mobileBarH
    exclusiveZone: Config.mobileBarH
    color: Theme.rail
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ultimit-mobilebar"

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property int wifiLevel: SysState.netStrength <= 0 ? 1 : Math.max(1, Math.min(3, Math.ceil(SysState.netStrength * 3 - 0.1)))
    readonly property bool airplane: SysState.netKind === "off" && SysState.wifiDev !== null && !SysState.wifiEnabled

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }

    Text {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: Qt.formatTime(clock.date, "HH:mm")
        color: Theme.fg
        font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold }
    }

    Row {
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 10
        StatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            kind: SysState.netKind === "eth" ? "eth" : (win.airplane ? "airplane" : "wifi")
            on: SysState.netKind !== "off"
            level: win.wifiLevel
            size: 16
            tone: SysState.netKind === "off" ? Theme.dim : Theme.fg
        }
        Row {
            visible: SysState.hasBattery
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            StatusIcon {
                anchors.verticalCenter: parent.verticalCenter
                kind: "battery"; pct: SysState.battPct; size: 16
                tone: SysState.battPct <= 10 && !SysState.charging ? Theme.bad : Theme.fg
            }
            StatusIcon {
                visible: SysState.charging
                anchors.verticalCenter: parent.verticalCenter
                kind: "bolt"; size: 12; tone: Theme.ok
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: SysState.battPct + "%"
                color: Theme.fg
                font { family: Theme.ui; pixelSize: 13 }
            }
        }
    }

    // Tap, or pull down: quick settings as a shade under the bar.
    MouseArea {
        anchors.fill: parent
        property real y0: 0
        onPressed: mouse => y0 = mouse.y
        onReleased: mouse => {
            if (mouse.y - y0 > 12 || Math.abs(mouse.y - y0) < 8) SysState.toggleQs(win.screen ? win.screen.name : "", "top");
        }
    }
}
