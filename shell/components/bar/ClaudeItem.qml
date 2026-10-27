// ClaudeItem.qml - top bar: the small Claude chat (left click) / the full window (right, middle).
import QtQuick
import Quickshell
import "../.."
import ".."

BarButton {
    name: "Claude"
    tip: "CLAUDE\nCLICK: CHAT HERE  RIGHT-CLICK: FULL WINDOW"
    width: 32
    onClicked: button => Quickshell.execDetached(button === Qt.LeftButton
        ? [Quickshell.shellPath("bin/ultimit-claude"), "--mini", screenName]
        : [Quickshell.shellPath("bin/ultimit-claude")])
    Image {
        anchors.centerIn: parent
        width: Theme.icon.md; height: Theme.icon.md
        sourceSize: Qt.size(Theme.icon.md * 2, Theme.icon.md * 2)
        source: Icons.app("ultimit-claude")
        smooth: true
    }
}
