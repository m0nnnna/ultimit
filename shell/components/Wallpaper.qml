// Wallpaper.qml - generative wallpaper (layer: background, no exclusive zone).
// Port of genShards / genHex / drawWall from docs/design/mockup.html, including the
// seeded PRNG, so the picture matches the mockup. Also hosts the Wordmark.
//
// Cost control: one Canvas, redrawn at most Config.wallpaperFps while Config.motion
// is on and the timer is running; with motion off it paints once (and on resize /
// skin change). Nothing runs when motion is off.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.bg1
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "ultimit-wallpaper"

    WallpaperArt { id: cv; anchors.fill: parent; active: win.visible }

    MouseArea {   // right-click on the empty desktop opens the context menu
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => Config.openMenu(win.screen ? win.screen.name : "", mouse.x, mouse.y)
    }

    Wordmark {
        anchors.right: parent.right
        anchors.rightMargin: 30
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
    }
}
