// PopIn.qml - open animation for popups and menus that are shown by toggling `visible` (the
// shared panel recipe at menu speed): fade 0 -> 1 and scale Theme.showScale -> 1 on `target`.
//   Rectangle { id: box; ... PopIn { target: box; shown: win.visible } }
// Leaving is instant (the popup is already hidden). Durations follow Config.dur.
import QtQuick

ParallelAnimation {
    id: a
    property Item target: null
    property bool shown: false
    property int ms: Theme.motion.fast
    onShownChanged: {
        if (shown) restart();
        else { stop(); if (target) { target.opacity = 1; target.scale = 1; } }
    }
    NumberAnimation { target: a.target; property: "opacity"; from: 0; to: 1; duration: Config.dur(a.ms); easing.type: Theme.easeFast }
    NumberAnimation { target: a.target; property: "scale"; from: Theme.showScale; to: 1; duration: Config.dur(a.ms); easing.type: Theme.easeFast }
}
