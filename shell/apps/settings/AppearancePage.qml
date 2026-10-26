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
    property var accentHover: null   // accent swatch under the pointer, named below the row
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
                { id: "verdant", n: "Verdant", a: "#062a0c", b: "#79d24f", c: "#b9ff8c" },
                { id: "sakura",  n: "Sakura",  a: "#14040d", b: "#8c2a5c", c: "#ff5fa2" },
                { id: "paper",   n: "Paper",   a: "#d6cdb6", b: "#fbf8f1", c: "#0e7c70" },
                { id: "void",    n: "Void",    a: "#000000", b: "#06080e", c: "#4f9dff" }
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

    SkinAutoSection { Layout.fillWidth: true }

    // ---- accent: the one colour that marks state (focused window, selection, toggles, cursor) ----
    SectionLabel { text: "Accent" }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "The colour that marks what's focused, selected or on, on every skin."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [{ n: "Skin's own", c: "" }].concat(Theme.accentPresets)
            delegate: Rectangle {
                required property var modelData
                readonly property bool sel: Theme.accentOverride === modelData.c
                width: 34; height: 34
                color: "transparent"
                border.width: sel ? 2 : 1
                border.color: sel ? Theme.fg : (sw.hovered ? Theme.lineStrong : Theme.line)
                Rectangle {
                    anchors.fill: parent; anchors.margins: 5
                    color: parent.modelData.c === "" ? Theme.cur.accent : parent.modelData.c
                }
                HoverHandler {
                    id: sw; cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: pg.accentHover = hovered ? parent.modelData : null
                }
                TapHandler { onTapped: Theme.accentOverride = parent.modelData.c }
            }
        }
        TextEntry {
            id: hex
            width: 104; height: 34
            placeholder: "#rrggbb"
            text: Theme.accentOverride
            onAccepted: {
                const t = text.trim().toLowerCase(), v = t.startsWith("#") ? t : "#" + t;
                if (Theme.validAccent(v)) Theme.accentOverride = v;
                else text = Theme.accentOverride;
            }
            Connections { target: Theme; function onAccentOverrideChanged() { hex.text = Theme.accentOverride; } }
        }
    }
    Text {
        Layout.fillWidth: true
        // the swatch under the pointer, else the current accent
        readonly property var shown: pg.accentHover
            || Theme.accentPresets.find(p => p.c === Theme.accentOverride) || { n: "", c: Theme.accentOverride }
        text: shown.c === "" ? "SKIN'S OWN" : (shown.n ? shown.n.toUpperCase() + " · " : "") + shown.c
        color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.2
    }
    // the most vivid colour of the current wallpaper picture (off for the generative shards)
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        property string note: ""
        ChamferButton {
            readonly property bool can: Config.wallpaper !== "" && !wpAccent.busy
            text: "From wallpaper"
            enabled: can; opacity: can ? 1 : 0.3
            onClicked: { parent.note = ""; wpAccent.pick(Config.wallpaper); }
        }
        Text {
            Layout.fillWidth: true; elide: Text.ElideRight
            text: parent.note !== "" ? parent.note : (Config.wallpaper === "" ? "NEEDS A PICTURE WALLPAPER" : "")
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.2
        }
        WallpaperAccent {
            id: wpAccent
            onPicked: hex => { Theme.accentOverride = hex; parent.note = "PICKED · " + hex; }
            onFailed: parent.note = "NO VIVID COLOUR IN THIS PICTURE"
        }
    }

    FontSetSection { Layout.fillWidth: true }

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

    SectionLabel { text: "Mouse cursor" }
    Chips {
        Layout.fillWidth: true
        options: [{ id: "izy", label: "Izy" }, { id: "shard", label: "Shard" }]
        current: Config.cursorStyle
        onPicked: id => Config.cursorStyle = id
    }

    EffectsSection { Layout.fillWidth: true }

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
