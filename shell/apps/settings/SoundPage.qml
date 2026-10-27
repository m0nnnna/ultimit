// Sound: output / input devices, which screen a graphics card plays to, volume, mute, per-app
// streams (PipeWire).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
            text: "No output devices."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
        }
    }
    // Display audio: which HDMI/DisplayPort connector a graphics card plays to (its profile; one at a
    // time). Through audio.py (pw-dump + wpctl set-profile).
    readonly property string audioScript: Quickshell.shellPath("apps/settings/audio.py")
    property var displayCards: []
    property bool displayBusy: false
    function reloadDisplays() { if (!displayBusy) { displayList.running = false; displayList.running = true; } }
    Component.onCompleted: reloadDisplays()
    Timer { interval: 5000; running: true; repeat: true; onTriggered: pg.reloadDisplays() }
    Process {
        id: displayList
        command: ["python3", "-I", pg.audioScript, "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { const o = JSON.parse(text); if (o.ok) pg.displayCards = o.cards || []; } catch (e) {} }
        }
    }
    function useDisplay(card, out) {
        if (displayBusy || out.active) return;
        if (SetSys.dryRun) { SetSys.note("audio.py set " + card.id + " " + out.index + " (" + out.label + ")"); return; }
        displayBusy = true;
        displaySet.command = ["python3", "-I", audioScript, "set", String(card.id), String(out.index)];
        displaySet.running = true;
    }
    Process {
        id: displaySet
        onExited: { pg.displayBusy = false; pg.reloadDisplays(); }
    }
    Repeater {
        model: pg.displayCards
        delegate: ColumnLayout {
            id: dc
            required property var modelData
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.topMargin: 8; Layout.bottomMargin: 4
                text: "Screen speakers: " + dc.modelData.name + " plays to one screen at a time."
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
            }
            Repeater {
                model: dc.modelData.outputs
                delegate: ItemRow {
                    required property var modelData
                    title: modelData.label
                    subtitle: (modelData.label !== modelData.port ? modelData.port + " · " : "") + modelData.kind
                              + (modelData.connected === false ? " · no screen" : "")
                    titleColor: selected ? Theme.accent : (modelData.connected === false ? Theme.dim : Theme.fg)
                    selected: modelData.active
                    badge: selected ? "playing here" : ""
                    onClicked: pg.useDisplay(dc.modelData, modelData)
                }
            }
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
            text: "No input devices."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
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
        text: "No applications are playing audio."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
    }
}
