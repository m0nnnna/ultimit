// GameModeSection.qml - Power > Game Mode: the desktop gets out of the way while a game runs.
// A self-contained block of PowerPage (one line there). Logic: ../../GameMode.qml.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

ColumnLayout {
    id: sec
    spacing: 12

    SectionLabel { text: "Game Mode" }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "While a game is fullscreen (or a Steam / Wine game is focused) the wallpaper, glow and other shell animations stop, "
            + "UI sounds go quiet and notifications wait until you are done. Browsers and video players do not count."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
    }
    ToggleRow {
        Layout.fillWidth: true
        text: "Switch on Game Mode automatically"
        checked: Config.gameModeEnabled
        onToggled: v => Config.gameModeEnabled = v
    }
    ToggleRow {
        Layout.fillWidth: true
        visible: Config.gameModeEnabled
        text: "Use the performance power profile while playing"
        checked: Config.gameModePower
        onToggled: v => Config.gameModePower = v
    }
    ToggleRow {
        Layout.fillWidth: true
        visible: Config.gameModeEnabled
        text: "Hold notifications (critical ones still show)"
        checked: Config.gameModeHold
        onToggled: v => Config.gameModeHold = v
    }
    InfoRow { Layout.fillWidth: true; label: "Status"; value: GameMode.active ? "ON (" + GameMode.reason + ")" : "off" }
}
