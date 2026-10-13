// BroadcastWindow.qml - the BROADCAST window: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Header with the two engine chips, tabs MICROPHONE / SPEAKERS / CAMERA, one page per tab.
import QtQuick
import Quickshell
import "../.."
import "../games"

FloatingWindow {
    id: win
    title: "BROADCAST"
    visible: Broadcast.open
    implicitWidth: 880
    implicitHeight: 640
    minimumSize: Qt.size(700, 480)
    color: Theme.bg1

    onVisibleChanged: if (visible !== Broadcast.open) Broadcast.open = visible
    Component.onCompleted: Broadcast.refresh()

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        // ---------------- header ----------------
        Item {
            id: header
            // The window title itself is in the compositor's titlebar.
            x: 20; y: 10
            width: parent.width - 40
            height: 36
            GLabel {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Mic, speakers and camera"
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                GChip {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (Broadcast.audioRunning ? "✓ " : "✕ ") + "Audio engine " + (Broadcast.audioRunning ? "running" : "stopped")
                    tone: !Broadcast.loaded ? Theme.dim : Broadcast.audioRunning ? Theme.ok : Theme.warn
                }
                GButton {
                    visible: Broadcast.loaded && !Broadcast.audioRunning
                    text: Broadcast.busy === "audio" ? "Starting…" : "Start"
                    enabled: Broadcast.busy === ""
                    onClicked: Broadcast.engineStart()
                }
                GChip {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Broadcast.camStarting ? "… Camera engine starting" : ((Broadcast.camRunning ? "✓ " : "✕ ") + "Camera engine " + (Broadcast.camRunning ? "running" : "stopped"))
                    tone: !Broadcast.loaded ? Theme.dim : Broadcast.camRunning ? Theme.ok : Broadcast.camStarting ? Theme.warn : Theme.dim
                }
            }
        }

        // ---------------- tabs ----------------
        Item {
            id: tabBar
            x: 20; anchors.top: header.bottom; anchors.topMargin: 2
            width: parent.width - 40
            height: 32
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            Row {
                spacing: 4
                Repeater {
                    model: [{ id: "mic", label: "Microphone" }, { id: "speakers", label: "Speakers" }, { id: "camera", label: "Camera" }]
                    delegate: Item {
                        id: tb
                        required property var modelData
                        readonly property bool on: Broadcast.tab === modelData.id
                        width: tl.implicitWidth + 36; height: 32
                        Text {
                            id: tl
                            anchors.centerIn: parent
                            text: tb.modelData.label.toUpperCase()
                            color: tb.on ? Theme.accent : (tm.containsMouse ? Theme.fg : Theme.dim)
                            font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.8
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent; visible: tb.on }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Broadcast.tab = tb.modelData.id }
                    }
                }
            }
        }

        // ---------------- message line ----------------
        Text {
            id: noteLine
            x: 20; anchors.top: tabBar.bottom; anchors.topMargin: 10
            width: parent.width - 40
            height: 16
            elide: Text.ElideRight
            text: Broadcast.busy === "audio" ? "Starting the audio engine…"
                : Broadcast.busy === "mic" || Broadcast.busy === "speakers" ? "Applying…"
                : Broadcast.note
            color: Broadcast.noteKind === "error" && Broadcast.busy === "" ? Theme.bad : Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
        }

        // ---------------- pages ----------------
        Item {
            id: pages
            x: 20; anchors.top: noteLine.bottom; anchors.topMargin: 8
            anchors.bottom: footer.top; anchors.bottomMargin: 6
            width: parent.width - 40
            MicPage { anchors.fill: parent; visible: Broadcast.tab === "mic" }
            SpeakersPage { anchors.fill: parent; visible: Broadcast.tab === "speakers" }
            CameraPage { anchors.fill: parent; visible: Broadcast.tab === "camera" }
        }

        Text {
            id: footer
            x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            width: parent.width - 40
            elide: Text.ElideRight
            text: "Effects run in hidden helpers (EasyEffects and OBS Studio). Do not open their windows: closing the EasyEffects window stops the audio engine."
            color: Theme.dim; opacity: 0.8
            font.family: Theme.ui; font.pixelSize: 11
        }

        GLabel {
            anchors.centerIn: parent
            visible: !Broadcast.loaded
            text: "Checking…"
        }
    }
}
