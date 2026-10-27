// SoundFlyout.qml - tray sound flyout: big output slider + mute, output device list, input slider +
// mute + device list, per-app PipeWire mixer. Logic is SysState's (shared with Settings > Sound).
import QtQuick
import Quickshell.Services.Pipewire
import "../.."
import ".."
import "../../apps/accessory"

Column {
    id: root
    spacing: Theme.space(3)

    readonly property var nodes: Pipewire.nodes.values
    PwObjectTracker { objects: root.nodes }
    function isDefault(n, d) { return d && n && d.id === n.id; }

    FlyHead { text: "Output"; detail: SysState.sinkName }
    FlySlider {
        width: parent.width
        big: true
        visible: SysState.sinkReady
        icon: "volume"
        value: SysState.sinkVol
        muted: SysState.sinkMuted
        onMoved: v => SysState.setSinkVol(v)
        onMuteClicked: SysState.toggleSinkMute()
    }
    Column {
        width: parent.width
        Repeater {
            model: SysState.sinks
            delegate: FlyRow {
                required property var modelData
                title: SysState.nodeLabel(modelData)
                subtitle: SysState.nodeKind(modelData)
                radio: true
                selected: root.isDefault(modelData, SysState.sink)
                onClicked: SysState.setDefaultSink(modelData)
            }
        }
        Text {
            visible: SysState.sinks.length === 0
            height: visible ? 36 : 0; verticalAlignment: Text.AlignVCenter
            text: "No output devices."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
        }
    }

    FlyHead { text: "Input"; detail: SysState.nodeLabel(SysState.source) }
    FlySlider {
        width: parent.width
        visible: SysState.srcReady
        icon: "mic"
        value: SysState.srcVol
        muted: SysState.srcMuted
        onMoved: v => SysState.setSrcVol(v)
        onMuteClicked: SysState.toggleSrcMute()
    }
    Column {
        width: parent.width
        Repeater {
            model: SysState.sources
            delegate: FlyRow {
                required property var modelData
                title: SysState.nodeLabel(modelData)
                subtitle: SysState.nodeKind(modelData)
                radio: true
                selected: root.isDefault(modelData, SysState.source)
                onClicked: SysState.setDefaultSource(modelData)
            }
        }
        Text {
            visible: SysState.sources.length === 0
            height: visible ? 36 : 0; verticalAlignment: Text.AlignVCenter
            text: "No input devices."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
        }
    }

    FlyHead { text: "Applications"; detail: SysState.streams.length > 0 ? SysState.streams.length + " playing" : "" }
    Column {
        width: parent.width
        spacing: Theme.space(1)
        Repeater {
            model: SysState.streams
            delegate: Item {
                id: sr
                required property var modelData
                readonly property string icon: SysState.streamIcon(modelData)
                width: parent.width; height: 60
                Item {   // app icon
                    id: ic
                    x: 2; y: 26; width: Theme.icon.lg; height: Theme.icon.lg
                    Image {
                        id: img
                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: sr.icon; sourceSize: Qt.size(48, 48)
                        fillMode: Image.PreserveAspectFit; asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent; visible: !img.visible
                        color: Theme.field
                        Text {
                            anchors.centerIn: parent
                            text: SysState.streamApp(sr.modelData).charAt(0).toUpperCase()
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label
                        }
                    }
                }
                Text {
                    x: 2; y: 4; width: parent.width - 2
                    text: SysState.streamName(sr.modelData); elide: Text.ElideRight
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: Theme.type.label
                }
                FlySlider {
                    x: 36; y: 22; width: parent.width - 36; height: 36
                    icon: "volume"
                    value: sr.modelData.audio ? Math.round(sr.modelData.audio.volume * 100) : 0
                    muted: sr.modelData.audio ? sr.modelData.audio.muted : false
                    onMoved: v => SysState.setNodeVol(sr.modelData, v)
                    onMuteClicked: SysState.toggleNodeMute(sr.modelData)
                }
            }
        }
        Text {
            visible: SysState.streams.length === 0
            height: visible ? 36 : 0; verticalAlignment: Text.AlignVCenter
            text: "No applications are playing audio."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
        }
    }

    ChamferButton {
        width: parent.width
        text: "Sound settings…"
        onClicked: { FlyoutState.close(); Config.openSettings("sound"); }
    }
}
