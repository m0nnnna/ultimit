pragma Singleton

// Config.qml - greeter settings (trimmed copy of the shell's Config).
import QtQuick
import Quickshell

Singleton {
    // ULTIMIT_MOTION=0 turns the wallpaper animation and UI animations off.
    property bool motion: Quickshell.env("ULTIMIT_MOTION") !== "0"
    property int wallpaperFps: 15
    property int shardDensity: 34
    readonly property real motionScale: motion ? 1 : 0
    function dur(ms) { return Math.round(ms * motionScale); }
}
