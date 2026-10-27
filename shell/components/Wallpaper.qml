// Wallpaper.qml - the desktop background (layer: background, no exclusive zone): a picture
// (Config.wallpaper, fitted per Config.wallpaperFit) or the generative shards.
// Port of genShards / genHex / drawWall from docs/design/mockup.html, including the
// seeded PRNG, so the picture matches the mockup. Also hosts the Wordmark and the photo frames.
//
// Cost control: WallpaperArt draws the moving parts on the GPU and the still parts once.
// Nothing runs when motion is off, or while a fullscreen window covers this screen (that includes the
// pointer / audio / window-change reactions of the shards, see WallpaperArt.qml).
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
    // A fullscreen window on any screen stops the animation until it goes (Config.desktopPaused).
    readonly property bool covered: Config.isCovered(win.screen ? win.screen.name : "")
    readonly property bool picture: Config.wallpaper !== "" && pic.status !== Image.Error
    WallpaperArt { id: cv; anchors.fill: parent; visible: !win.picture; active: win.visible && !win.picture && !win.covered && !Config.desktopPaused
                   animate: Config.motion && Config.wallpaperMotion
                   reactPointer: Config.reactPointer; reactAudio: Config.reactAudio }
    // Reactive shards (settings: Appearance > Effects). The position is only stored; the art reads it
    // on its own step. A picture wallpaper has nothing to react.
    HoverHandler {
        enabled: cv.running && Config.reactPointer
        onPointChanged: { cv.rawX = point.position.x; cv.rawY = point.position.y; }
        onHoveredChanged: if (!hovered) { cv.rawX = -1; cv.rawY = -1; }
    }
    Connections {   // Ultimit has no workspaces: the active window changing stands in for a switch
        target: ToplevelManager
        enabled: Config.reactWorkspace
        function onActiveToplevelChanged() { cv.kick(); }
    }
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

    // The shell has no cheap window geometry (the foreign-toplevel protocol carries none), so the
    // wordmark fades whenever a non-minimized window is on this output.
    readonly property bool windowsHere: {
        const name = win.screen ? win.screen.name : "";
        for (const t of ToplevelManager.toplevels.values) {
            if (t.minimized) continue;
            for (const s of t.screens) if (s && s.name === name) return true;
        }
        return false;
    }
    Wordmark {
        dimmed: win.windowsHere
        anchors.right: parent.right
        anchors.rightMargin: 30
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
    }

    Item {   // photo frames on this screen (Frames.qml), over the picture, under every window
        anchors.fill: parent
        Repeater {
            model: Frames.ids
            PhotoFrame {
                required property string modelData
                frameId: modelData
                screenName: win.screen ? win.screen.name : ""
                visible: f !== null && f.screen === screenName
            }
        }
    }
}
