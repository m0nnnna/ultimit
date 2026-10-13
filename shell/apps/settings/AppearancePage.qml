// Appearance: skins, wallpaper, boot sequence (migrated from the old Accessory window).
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Page {
    title: "Appearance"

    SectionLabel { text: "Skin" }
    GridLayout {
        Layout.fillWidth: true
        columnSpacing: 10; rowSpacing: 10
        columns: Math.max(1, Math.floor((width + 10) / 130))
        Repeater {
            model: [
                { id: "mine",    n: "Mine",    a: "#050607", b: "#2a2f37", c: "#d4ebff" },
                { id: "amber",   n: "Amber",   a: "#b84d05", b: "#f8cf96", c: "#ffb04a" },
                { id: "silver",  n: "Silver",  a: "#aeb5bf", b: "#f6f7f9", c: "#2c5b88" },
                { id: "verdant", n: "Verdant", a: "#062a0c", b: "#79d24f", c: "#b9ff8c" }
            ]
            delegate: SkinCard {
                required property var modelData
                Layout.fillWidth: true
                name: modelData.n
                colorA: modelData.a; colorB: modelData.b; stripe: modelData.c
                selected: Theme.skin === modelData.id
                onClicked: Theme.skin = modelData.id
            }
        }
    }

    SectionLabel { text: "Wallpaper" }
    SliderField {
        Layout.fillWidth: true
        label: "Shard count"
        from: 16; to: 60
        value: Config.shardDensity
        onMoved: v => Config.shardDensity = v
    }

    SectionLabel { text: "Rail icons" }
    Chips {
        Layout.fillWidth: true
        options: [{ id: "always", label: "Always turn" }, { id: "hover", label: "Turn on hover" }, { id: "off", label: "Still" }]
        current: Config.railSpin
        onPicked: id => Config.railSpin = id
    }

    SectionLabel { text: "System" }
    // Reduced motion when off: window open/close/minimize, the focus sweep, panel transitions,
    // shard and rail-icon motion, the boot and lock animations.
    ToggleRow {
        Layout.fillWidth: true
        text: "Animations (windows, panels, wallpaper)"
        checked: Config.motion
        onToggled: value => Config.motion = value
    }
    ToggleRow {
        Layout.fillWidth: true
        text: "Play boot sequence at startup"
        checked: Config.bootOnStart
        onToggled: value => Config.bootOnStart = value
    }
    Flow {
        Layout.fillWidth: true
        ChamferButton { text: "Replay boot sequence"; onClicked: Config.playBoot() }
    }

    Text {
        Layout.fillWidth: true
        Layout.maximumWidth: 62 * 7
        text: "Ultimit design mockup. The look is a tribute to Altimit OS from the .hack games by CyberConnect2. The name is a fan homage; the emblem and art are original."
        color: Theme.dim
        font.family: Theme.ui; font.pixelSize: 12
        lineHeight: 1.6
        wrapMode: Text.WordWrap
    }
}
