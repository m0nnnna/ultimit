// EffectsSection.qml - Appearance > Effects: edge glow, decode text, wallpaper reactions, status
// block style, UI sounds. A self-contained block of AppearancePage (one line there).
// Everything animated here also follows "Animations" below and stops under a fullscreen window.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

ColumnLayout {
    id: sec
    spacing: 12

    SectionLabel { text: "Effects" }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Glow along panel edges, text that decodes in, and the wallpaper reacting. Paused while a fullscreen window is up or Animations is off."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
    Chips {
        Layout.fillWidth: true
        options: [{ id: "off", label: "No glow" }, { id: "still", label: "Edge glow" }, { id: "travel", label: "Glow + travelling light" }]
        current: Config.edgeGlow
        onPicked: id => Config.edgeGlow = id
    }
    ToggleRow {
        Layout.fillWidth: true
        text: "Decode text on panel titles"
        checked: Config.decodeText
        onToggled: value => Config.decodeText = value
    }

    SectionLabel { text: "Reactive wallpaper (shards)" }
    ToggleRow {
        Layout.fillWidth: true
        text: "Ripple under the pointer"
        checked: Config.reactPointer
        onToggled: value => Config.reactPointer = value
    }
    ToggleRow {   // PipeWire peak of the default output; nothing is read while this is off
        Layout.fillWidth: true
        text: "Pulse with audio output"
        checked: Config.reactAudio
        onToggled: value => Config.reactAudio = value
    }
    ToggleRow {   // Ultimit has no workspaces; this fires when the active window changes
        Layout.fillWidth: true
        text: "Shift when the active window changes"
        checked: Config.reactWorkspace
        onToggled: value => Config.reactWorkspace = value
    }

    SectionLabel { text: "Status block" }
    Chips {
        Layout.fillWidth: true
        options: [{ id: "classic", label: "Classic (clock and date)" }, { id: "graph", label: "Graph (CPU, GPU, RAM, NET)" }]
        current: Config.statusStyle
        onPicked: id => Config.statusStyle = id
    }
    ToggleRow {
        Layout.fillWidth: true
        text: "Seconds ring around the clock"
        checked: Config.clockRing
        onToggled: value => Config.clockRing = value
    }

    SectionLabel { text: "Interface sounds" }
    ToggleRow {   // short synthesized blips; never while a fullscreen window is focused
        Layout.fillWidth: true
        text: "Play HUD sounds (flyouts, launcher, notifications, lock)"
        checked: Config.uiSounds
        onToggled: value => Config.uiSounds = value
    }
    SliderField {
        visible: Config.uiSounds
        Layout.fillWidth: true
        label: "Volume"
        from: 0; to: 100
        value: Config.uiSoundVolume
        valueText: Config.uiSoundVolume + "%"
        onMoved: v => Config.uiSoundVolume = v
    }
    Flow {
        visible: Config.uiSounds
        Layout.fillWidth: true
        ChamferButton { text: "Test sound"; onClicked: UiSounds.test() }
    }
}
