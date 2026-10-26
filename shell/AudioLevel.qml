pragma Singleton

// AudioLevel.qml - how loud the PC is playing right now (0..1), for the wallpaper's pulse.
// PipeWire's peak monitor on the default sink (Quickshell.Services.Pipewire). The monitor opens a
// capture stream, so it only exists while someone asks: users is counted by the shards that want
// it, and they only do while they animate (motion on, no fullscreen window). `peak` is read
// imperatively by their timers, not bound, so the audio-rate changes cost nothing on their own.
// Without PipeWire (or no sink) peak stays 0 and nothing pulses.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property int users: 0
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real peak: root.users > 0 && mon.peak > 0 ? Math.min(1, mon.peak) : 0

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    PwNodePeakMonitor {
        id: mon
        node: root.sink
        enabled: root.users > 0 && root.sink !== null
    }
}
