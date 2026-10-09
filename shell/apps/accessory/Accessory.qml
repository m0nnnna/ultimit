// Accessory.qml - look & system settings window (mockup "Accessory").
// A plain xdg toplevel (FloatingWindow): the Ultimit compositor draws the titlebar/frame.
// Visibility is driven by Config.accessoryOpen; the rail ACCESSORY button sets it, and
// closing via the frame writes it back. Also controllable over IPC:
//   qs ipc call accessory toggle | open | close
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."

Scope {
    id: root

    FloatingWindow {
        id: win
        title: Config.accessoryTitle
        implicitWidth: 560
        implicitHeight: 520
        minimumSize: Qt.size(420, 440)
        color: "transparent"
        visible: false

        onVisibleChanged: if (Config.accessoryOpen !== visible) Config.accessoryOpen = visible

        Connections {
            target: Config
            function onAccessoryOpenChanged() { if (win.visible !== Config.accessoryOpen) win.visible = Config.accessoryOpen; }
        }
        Component.onCompleted: win.visible = Config.accessoryOpen

        Rectangle {
            id: bgr
            anchors.fill: parent
            color: Theme.panel

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: col.implicitHeight + 24
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: col
                    x: 16; y: 12
                    width: parent.width - 32
                    spacing: 14

                    SectionLabel { text: "Skin" }
                    GridLayout {
                        id: skinGrid
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
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        ToggleRow {
                            Layout.fillWidth: true
                            text: "Animate shards"
                            checked: Config.motion
                            onToggled: value => Config.motion = value
                        }
                        SliderField {
                            Layout.fillWidth: true
                            label: "Shard count"
                            from: 16; to: 60
                            value: Config.shardDensity
                            onMoved: v => Config.shardDensity = v
                        }
                    }

                    SectionLabel { text: "System" }
                    ToggleRow {
                        Layout.fillWidth: true
                        text: "Play boot sequence at startup"
                        checked: Config.bootOnStart
                        onToggled: value => Config.bootOnStart = value
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        ChamferButton { text: "Play boot sequence"; onClicked: Config.playBoot() }
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
            }
        }
    }

    IpcHandler {
        target: "accessory"
        function toggle(): void { Config.accessoryOpen = !Config.accessoryOpen; }
        function open(): void { Config.accessoryOpen = true; }
        function close(): void { Config.accessoryOpen = false; }
    }
}
