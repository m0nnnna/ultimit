// PrivacyItem.qml - top bar: chips for what is using the mic, camera or screen, a running recording
// (REC, click to stop), an active VPN and Game Mode (GAME). Collapses to nothing when none applies.
import QtQuick
import "../.."
import ".."

Row {
    id: root
    property string screenName: ""
    height: Config.barHeight
    Repeater {
        model: [
            { id: "rec", label: "REC " + Privacy.recTime, apps: Privacy.rec ? ["Screen recording (click to stop)"] : [], tone: Theme.bad },
            { id: "screen", label: "SCREEN", apps: Privacy.screenApps, tone: Theme.warn },
            { id: "cam", label: "CAM", apps: Privacy.cameraApps, tone: Theme.warn },
            { id: "mic", label: "MIC", apps: Privacy.micApps, tone: Theme.warn },
            { id: "vpn", label: "VPN", apps: SysState.vpnActive, tone: Theme.accent },
            { id: "game", label: "GAME", apps: GameMode.active ? ["Desktop paused"] : [], tone: Theme.ok }
        ].filter(m => m.apps.length > 0)
        delegate: BarButton {
            id: pb
            required property var modelData
            screenName: root.screenName
            name: modelData.id === "rec" ? "Screen recording, " + Privacy.recTime + ", click to stop"
                : ({ screen: "Screen shared by: ", cam: "Camera in use by: ", mic: "Microphone in use by: ", vpn: "VPN connected: ", game: "Game Mode on, " })[modelData.id] + modelData.apps.join(", ")
            tip: modelData.id === "rec" ? "RECORDING " + Privacy.recTime + "\nCLICK TO STOP AND SAVE"
                : ({ screen: "SCREEN SHARED", cam: "CAMERA IN USE", mic: "MICROPHONE IN USE", vpn: "VPN CONNECTED", game: "GAME MODE ON" })[modelData.id] + "\n" + modelData.apps.join("\n").toUpperCase()
            width: chip.width + 10
            onClicked: if (modelData.id === "rec") Privacy.stopRecording(); else if (modelData.id === "vpn") openFly("network")
            Rectangle {
                id: chip
                anchors.centerIn: parent
                width: lbl.implicitWidth + 20; height: 20
                color: "transparent"; border.color: pb.modelData.tone
                Rectangle {   // the dot blinks while recording
                    id: dot
                    x: 5; anchors.verticalCenter: parent.verticalCenter
                    width: 5; height: 5; radius: 2.5; color: pb.modelData.tone
                    SequentialAnimation on opacity {
                        running: pb.modelData.id === "rec" && Config.motion
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: Config.dur(Theme.motion.ambient) }
                        NumberAnimation { to: 1; duration: Config.dur(Theme.motion.ambient) }
                    }
                }
                Text {
                    id: lbl
                    anchors { left: dot.right; leftMargin: 4; verticalCenter: parent.verticalCenter }
                    text: pb.modelData.label; color: pb.modelData.tone
                    font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.2
                }
            }
        }
    }
}
