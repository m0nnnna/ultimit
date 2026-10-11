// SteamCard.qml - Steam status / tip card.
//   mode "missing": steam-installer not installed -> install hint
//   mode "setup":   installed, never run          -> "Set up Steam" (runs `steam`)
//   mode "tip":     recommended Steam settings (text only)
import QtQuick
import "../.."

Rectangle {
    id: root
    property string mode: "tip"
    property bool compact: false     // inside the library strip: header RESCAN is already there
    implicitHeight: col.implicitHeight + 24
    color: Theme.panel2
    border.color: mode === "tip" ? Theme.line : Theme.lineStrong
    border.width: 1

    Rectangle { width: 2; height: parent.height; color: root.mode === "tip" ? Theme.dim : Theme.warn }

    Column {
        id: col
        x: 14; y: 12
        width: parent.width - 28
        spacing: 8
        GLabel {
            width: parent.width
            strong: true
            text: root.mode === "missing" ? "Steam  /  not installed"
                : root.mode === "setup" ? "Steam  /  not set up yet" : "Steam settings"
            color: root.mode === "tip" ? Theme.fg : Theme.warn
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
            text: root.mode === "missing"
                ? "Steam isn't installed. Ultimit lists its games here once it is. Install it from a terminal, then rescan."
                : root.mode === "setup"
                ? "Steam is installed but has never been run. The first start downloads its client and asks you to sign in."
                : "Recommended: enable Proton Experimental for all titles. Steam > Settings > Compatibility > Enable Steam Play for all other titles, then pick Proton Experimental."
        }
        CopyText { visible: root.mode === "missing"; width: parent.width; text: Games.installCommand }
        Row {
            visible: root.mode === "setup" || (root.mode === "missing" && !root.compact)
            spacing: 10
            GButton { visible: root.mode === "setup"; primary: true; text: "Set up Steam"; onClicked: Games.setupSteam() }
            GButton { visible: !root.compact; text: "Rescan"; onClicked: Games.rescan() }
        }
    }
}
