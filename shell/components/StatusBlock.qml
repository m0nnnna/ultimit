// StatusBlock.qml - clock, date and live system row, top-right (layer: bottom, no exclusive zone).
// The text block is clickable (toggles the quick settings panel); the rest of the window is
// click-through via the input mask.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { top: true; right: true }
    margins { top: 16; right: 24 }
    implicitWidth: 460
    implicitHeight: 84
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "ultimit-status"
    mask: Region { item: block }   // only the text extent takes clicks

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property var days: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    function p2(n) { return String(n).padStart(2, "0"); }
    readonly property date now: clock.date

    // ---- system row segments: { k: label, v: value, dot: color or "" } ----
    readonly property var segs: {
        const out = [];
        const S = SysState;
        // network
        if (S.netKind === "wifi") out.push({ k: "NET", v: S.netName, dot: Theme.ok, bars: S.netStrength });
        else if (S.netKind === "eth") out.push({ k: "NET", v: "ETH", dot: Theme.ok, bars: -1 });
        else out.push({ k: "NET", v: "OFFLINE", dot: Theme.bad, bars: -1 });
        // bluetooth
        if (S.btAvailable) {
            if (!S.btOn) out.push({ k: "BT", v: "OFF", dot: "", bars: -1 });
            else if (S.btConnectedCount > 0) out.push({ k: "BT", v: String(S.btConnectedCount), dot: Theme.ok, bars: -1 });
            else out.push({ k: "BT", v: "ON", dot: "", bars: -1 });
        }
        // battery
        if (S.hasBattery) {
            const c = S.charging ? Theme.ok : (S.battPct <= 15 ? Theme.bad : (S.battPct <= 30 ? Theme.warn : Theme.ok));
            out.push({ k: "BAT", v: S.battPct + "%" + (S.charging ? "+" : ""), dot: c, bars: -1 });
        }
        // volume
        if (S.sinkReady) out.push({ k: "VOL", v: S.sinkMuted ? "MUTED" : String(S.sinkVol), dot: S.sinkMuted ? Theme.warn : "", bars: -1 });
        return out;
    }

    Column {
        id: block
        anchors.right: parent.right
        spacing: 0

        Text {
            anchors.right: parent.right
            text: ((win.now.getHours() % 12) || 12) + ":" + win.p2(win.now.getMinutes()) + ":" + win.p2(win.now.getSeconds()) + (win.now.getHours() < 12 ? " AM" : " PM")
            color: hit.containsMouse || SysState.qsOpen ? Theme.accent : Theme.fg
            font.family: Theme.mono; font.pixelSize: 26
            font.letterSpacing: 1.56
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.right: parent.right
            text: win.now.getFullYear() + "." + win.p2(win.now.getMonth() + 1) + "." + win.p2(win.now.getDate()) + " " + win.days[win.now.getDay()]
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 11
            font.letterSpacing: 2.42
        }
        Item { width: 1; height: 6 }
        Row {
            anchors.right: parent.right
            spacing: 14
            Repeater {
                model: win.segs
                delegate: Row {
                    required property var modelData
                    spacing: 5
                    Text {
                        text: modelData.k
                        color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                    }
                    Text {
                        text: modelData.v
                        width: Math.min(implicitWidth, 110)
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                    }
                    SignalBars {
                        visible: modelData.bars >= 0
                        anchors.verticalCenter: parent.verticalCenter
                        level: modelData.bars
                        color: Theme.ok
                    }
                    Text {
                        visible: modelData.dot !== ""
                        text: "●"
                        color: modelData.dot !== "" ? modelData.dot : "transparent"
                        font.family: Theme.mono; font.pixelSize: 10
                    }
                }
            }
        }
    }

    MouseArea {
        id: hit
        x: block.x; y: block.y; width: block.width; height: block.height
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: SysState.toggleQs(win.screen ? win.screen.name : "")
    }
}
