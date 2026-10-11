// Sound: output / input devices, volume, mute, per-app streams (PipeWire).
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../.."
import "../accessory"
import "../../components"

Page {
    id: pg
    title: "Sound"

    readonly property var nodes: Pipewire.nodes.values
    readonly property var outputs: nodes.filter(n => n.isSink && !n.isStream && n.audio !== null)
    readonly property var inputs: SysState.sources
    readonly property var streams: SysState.streams
    // bind node properties/audio for everything shown here
    PwObjectTracker { objects: pg.nodes.filter(n => n.audio !== null || n.isStream) }

    function streamName(n) { return SysState.streamName(n); }
    function isDefault(n, d) { return d && n && d.id === n.id; }

    SectionLabel { text: "Output" }
    ColumnLayout {
        Layout.fillWidth: true; spacing: 0
        Repeater {
            model: pg.outputs
            delegate: ItemRow {
                required property var modelData
                title: SysState.nodeLabel(modelData)
                selected: pg.isDefault(modelData, SysState.sink)
                badge: selected ? "default" : ""
                onClicked: SysState.setDefaultSink(modelData)
            }
        }
        Text {
            visible: pg.outputs.length === 0
            text: "No output devices."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }
    }
    SliderField {
        Layout.fillWidth: true
        visible: SysState.sinkReady
        label: "Output volume"
        from: 0; to: 100
        value: SysState.sinkVol
        onMoved: v => SysState.setSinkVol(v)
    }
    ToggleRow {
        Layout.fillWidth: true
        visible: SysState.sinkReady
        text: "Mute output"
        checked: SysState.sinkMuted
        onToggled: SysState.toggleSinkMute()
    }

    SectionLabel { text: "Input" }
    ColumnLayout {
        Layout.fillWidth: true; spacing: 0
        Repeater {
            model: pg.inputs
            delegate: ItemRow {
                required property var modelData
                title: SysState.nodeLabel(modelData)
                selected: pg.isDefault(modelData, SysState.source)
                badge: selected ? "default" : ""
                onClicked: SysState.setDefaultSource(modelData)
            }
        }
        Text {
            visible: pg.inputs.length === 0
            text: "No input devices."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }
    }
    SliderField {
        Layout.fillWidth: true
        visible: SysState.srcReady
        label: "Input volume"
        from: 0; to: 100
        value: SysState.srcVol
        onMoved: v => SysState.setSrcVol(v)
    }
    ToggleRow {
        Layout.fillWidth: true
        visible: SysState.srcReady
        text: "Mute microphone"
        checked: SysState.srcMuted
        onToggled: SysState.toggleSrcMute()
    }

    SectionLabel { text: "Applications" }
    Repeater {
        model: pg.streams
        delegate: ColumnLayout {
            id: sr
            required property var modelData
            Layout.fillWidth: true
            spacing: 0
            SliderField {
                Layout.fillWidth: true
                label: pg.streamName(sr.modelData)
                from: 0; to: 100
                value: sr.modelData.audio ? Math.round(sr.modelData.audio.volume * 100) : 0
                onMoved: v => SysState.setNodeVol(sr.modelData, v)
            }
        }
    }
    Text {
        visible: pg.streams.length === 0
        text: "No applications are playing audio."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
    }
}
