// rescue-shell.qml - what session/ultimit-shell runs when the desktop shell, and its last good copy,
// keep crashing: a plain full-screen message with a way out instead of a black screen. It shares
// nothing with shell/ (no Theme, no components), so whatever broke the shell can't break this.
//   qs -p rescue-shell.qml        exits when "Try again" is clicked
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property string log: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ultimit/session.log"

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "ultimit-rescue"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "#050607"

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 64, 640)
                spacing: 18
                Text {
                    text: "[ ULTIMIT ]"
                    color: "#d4ebff"; font.family: "Michroma"; font.pixelSize: 26; font.letterSpacing: 4
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "The desktop shell keeps crashing, so the taskbar and panels can't start. "
                        + "Your apps and files are fine. Try again, or open a terminal to look into it."
                    color: "#eef1f4"; font.family: "Chakra Petch"; font.pixelSize: 16; lineHeight: 1.3
                }
                Text {
                    width: parent.width; wrapMode: Text.WrapAnywhere
                    text: "Log: " + root.log
                    color: "#8d949e"; font.family: "Share Tech Mono"; font.pixelSize: 12
                }
                Row {
                    spacing: 12
                    Repeater {
                        model: [
                            { label: "Try again", run: () => Qt.quit() },
                            { label: "Open terminal", run: () => Quickshell.execDetached(["foot"]) },
                            { label: "Show log", run: () => Quickshell.execDetached(["foot", "-e", "less", "+G", root.log]) },
                            { label: "Log out", run: () => Quickshell.execDetached(["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""]) }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: lbl.implicitWidth + 32; height: 38
                            color: index === 0 ? "#d4ebff" : (ma.containsMouse ? "#1c2026" : "transparent")
                            border.color: index === 0 ? "#d4ebff" : "#7a8088"
                            Text {
                                id: lbl; anchors.centerIn: parent
                                text: parent.modelData.label.toUpperCase()
                                color: parent.index === 0 ? "#07090b" : "#eef1f4"
                                font.family: "Chakra Petch"; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 2
                            }
                            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: parent.modelData.run() }
                        }
                    }
                }
            }
        }
    }
}
