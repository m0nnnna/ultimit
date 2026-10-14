// Wallpaper.qml - the desktop background (layer: background, no exclusive zone): a picture
// (Config.wallpaper, fitted per Config.wallpaperFit) or the generative shards.
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

    // A picture when one is set and it loads; otherwise (or if the file is gone) the shards.
    readonly property bool picture: Config.wallpaper !== "" && pic.status !== Image.Error
    WallpaperArt { id: cv; anchors.fill: parent; visible: !win.picture; active: win.visible && !win.picture
                   animate: Config.motion && Config.wallpaperMotion }
    Image {
        id: pic
        anchors.fill: parent
        visible: win.picture && status === Image.Ready
        source: Config.wallpaper !== "" ? "file://" + Config.wallpaper : ""
        fillMode: ({ fill: Image.PreserveAspectCrop, fit: Image.PreserveAspectFit, stretch: Image.Stretch,
                     center: Image.Pad })[Config.wallpaperFit] ?? Image.PreserveAspectCrop
        sourceSize: Config.wallpaperFit === "center" ? Qt.size(0, 0) : Qt.size(win.width, win.height)   // 0x0: natural size
        asynchronous: true
        smooth: true
        cache: false
    }

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
