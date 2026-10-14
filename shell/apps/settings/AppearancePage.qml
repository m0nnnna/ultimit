// Appearance: skins, wallpaper (shards or a picture), rail icons, animations, boot sequence.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Page {
    id: pg
    title: "Appearance"

    // Picture mode chosen but no picture picked yet (Config.wallpaper still "").
    property bool pictureMode: false
    // Candidate pictures: Pictures/Wallpapers, Pictures (two levels down), the system backgrounds.
    property var pictures: []
    Cmd {
        id: scan
        argv: ["sh", "-c", 'p=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures"); '
            + 'for d in "$p/Wallpapers" "$p" /usr/share/backgrounds; do [ -d "$d" ] && find "$d" -maxdepth 2 -type f '
            + '\\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) -size +40k '
            + '-not -path "*/Screenshots/*" 2>/dev/null | sort; done | awk "!seen[\\$0]++" | head -n 48']
        onDone: out => pg.pictures = out.split("\n").filter(l => l.startsWith("/"))
    }
    Cmd {
        id: browse
        argv: ["zenity", "--file-selection", "--title=Choose a wallpaper",
               "--file-filter=Pictures | *.jpg *.jpeg *.png *.webp *.JPG *.JPEG *.PNG *.WEBP"]
        onDone: (out, code) => { const f = out.trim(); if (code === 0 && f.startsWith("/")) Config.wallpaper = f; }
    }
    Component.onCompleted: scan.go()

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
    Chips {
        Layout.fillWidth: true
        options: [{ id: "shards", label: "Shards" }, { id: "picture", label: "Picture" }]
        current: Config.wallpaper === "" && !pg.pictureMode ? "shards" : "picture"
        onPicked: id => {
            pg.pictureMode = id === "picture";
            if (id === "shards") Config.wallpaper = "";
            else if (Config.wallpaper === "" && pg.pictures.length) Config.wallpaper = pg.pictures[0];
        }
    }
    SliderField {
        visible: Config.wallpaper === "" && !pg.pictureMode
        Layout.fillWidth: true
        label: "Shard count"
        from: 16; to: 60
        value: Config.shardDensity
        onMoved: v => Config.shardDensity = v
    }
    ToggleRow {   // off: the shards stay still; window and panel animations are unaffected
        visible: Config.wallpaper === "" && !pg.pictureMode
        Layout.fillWidth: true
        text: "Moving shards"
        checked: Config.wallpaperMotion
        onToggled: value => Config.wallpaperMotion = value
    }
    // ---- picture: thumbnails from the usual picture folders, Browse…, how it fills the screen ----
    GridLayout {
        visible: Config.wallpaper !== "" || pg.pictureMode
        Layout.fillWidth: true
        columnSpacing: 8; rowSpacing: 8
        columns: Math.max(1, Math.floor((width + 8) / 150))
        Repeater {
            model: pg.pictures
            delegate: Rectangle {
                required property string modelData
                readonly property bool sel: Config.wallpaper === modelData
                Layout.fillWidth: true
                Layout.preferredHeight: width * 9 / 16
                color: Theme.panel2
                border.color: sel ? Theme.accent : (th.hovered ? Theme.lineStrong : Theme.line)
                border.width: sel ? 2 : 1
                Image {
                    anchors.fill: parent; anchors.margins: parent.border.width
                    source: "file://" + parent.modelData
                    sourceSize: Qt.size(300, 170)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Config.wallpaper = parent.modelData }
            }
        }
    }
    Text {
        visible: (Config.wallpaper !== "" || pg.pictureMode) && pg.pictures.length === 0
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "No pictures found in Pictures or Pictures/Wallpapers. Use Browse… or right-click an image in DATA › Set as wallpaper."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
    RowLayout {
        visible: Config.wallpaper !== "" || pg.pictureMode
        Layout.fillWidth: true
        spacing: 12
        ChamferButton { text: "Browse…"; onClicked: browse.go() }
        Chips {
            Layout.fillWidth: true
            options: [{ id: "fill", label: "Fill" }, { id: "fit", label: "Fit" }, { id: "stretch", label: "Stretch" }, { id: "center", label: "Center" }]
            current: Config.wallpaperFit
            onPicked: id => Config.wallpaperFit = id
        }
    }
    Text {
        visible: Config.wallpaper !== "" && pg.pictures.indexOf(Config.wallpaper) < 0
        Layout.fillWidth: true; elide: Text.ElideMiddle
        text: Config.wallpaper; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
    }

    SectionLabel { text: "Rail icons" }
    Chips {
        Layout.fillWidth: true
        options: [{ id: "always", label: "Always turn" }, { id: "hover", label: "Turn on hover" }, { id: "off", label: "Still" }]
        current: Config.railSpin
        onPicked: id => Config.railSpin = id
    }

    SectionLabel { text: "Other apps' icons" }
    Chips {
        Layout.fillWidth: true
        options: [{ id: "letters", label: "Letters" }, { id: "original", label: "Original" }]
        current: Config.appIcons
        onPicked: id => Config.appIcons = id
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
