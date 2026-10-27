// AltTab.qml - the Alt+Tab window switcher overlay (Windows-style).
// The compositor drives it: AltTabState.qml receives show/move/hide events; releasing Alt
// focuses the highlighted window (compositor side). Overlay layer, no keyboard focus, click-through.
// One tile per window (most recently used first, current window first): app icon, small-caps title,
// minimized marker; the highlighted tile gets the accent frame + corner brackets. Icons and titles
// only - live thumbnails would need a screencopy of every window per keypress.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    property string screenName: ""

    readonly property bool shown: AltTabState.shown && Config.isUiScreen(screenName)
    visible: shown || box.opacity > 0.01
    mask: Region {}
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-alttab"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int tileW: 150
    readonly property int tileH: 128
    readonly property int gap: 8
    readonly property int pad: 18
    readonly property int cols: Math.max(1, Math.min(AltTabState.items.length,
        Math.floor(((screen ? screen.width : 1280) - 120 - 2 * pad + gap) / (tileW + gap))))
    readonly property int rows: Math.max(1, Math.ceil(AltTabState.items.length / cols))

    // Unanchored layer surface: the compositor centres it.
    implicitWidth: cols * tileW + (cols - 1) * gap + 2 * pad
    implicitHeight: 34 + rows * tileH + (rows - 1) * gap + 2 * pad + 30

    Rectangle {
        id: box
        anchors.fill: parent
        color: Theme.panel
        border.width: 1
        border.color: Theme.lineStrong
        opacity: win.shown ? 1 : 0
        ShowBehavior on opacity {}
        scale: win.shown ? 1 : Theme.showScale
        ShowBehavior on scale { hidden: Theme.showScale }
        GlowFrame { anchors.fill: parent; travel: false }
        Brackets {}

        DecodeText {
            x: win.pad; y: 14
            text: "SWITCH WINDOW"
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: Theme.size.sm; font.letterSpacing: 2.4
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: win.pad; y: 14
            text: (AltTabState.index + 1) + " / " + AltTabState.items.length
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: Theme.size.sm; font.letterSpacing: 2
            font.features: Theme.tnum
        }

        Grid {
            x: win.pad; y: 34 + win.pad - 6
            columns: win.cols
            spacing: win.gap

            Repeater {
                model: AltTabState.items

                Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === AltTabState.index
                    readonly property string appId: modelData.app_id || ""
                    readonly property string title: modelData.title || ""
                    readonly property var de: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
                    readonly property string own: Icons.windowIcon(appId, title)
                    readonly property string iconName: own !== "" ? own : (de && de.icon ? de.icon : appId)
                    readonly property string iconSrc: iconName !== "" ? Icons.app(iconName) : ""

                    width: win.tileW; height: win.tileH
                    color: sel ? Theme.panel2 : "transparent"
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    border.width: 1
                    border.color: sel ? Theme.accent : "transparent"
                    Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    Brackets { visible: tile.sel; size: 8 }

                    Item {
                        id: iconBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 14
                        width: 56; height: 56
                        opacity: tile.modelData.minimized ? 0.5 : 1
                        Image {
                            id: img
                            anchors.fill: parent
                            visible: tile.iconSrc !== "" && status !== Image.Error
                            source: tile.iconSrc
                            sourceSize: Qt.size(112, 112)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        IconBadge {   // letter fallback when no icon resolves
                            anchors.centerIn: parent
                            visible: tile.iconSrc === "" || img.status === Image.Error
                            size: 56
                            letter: ((tile.de && tile.de.name) || tile.title || tile.appId || "?").charAt(0).toUpperCase()
                            active: tile.sel
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 80
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.title !== "" ? AppSearch.windowTitle(tile.title, tile.appId) : ((tile.de && tile.de.name) || tile.appId || "Untitled")
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        color: tile.sel ? Theme.fg : Theme.dim
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        font.family: Theme.ui; font.pixelSize: 12; font.capitalization: Font.SmallCaps
                        font.letterSpacing: 0.6
                    }
                    Rectangle {   // minimized marker
                        visible: tile.modelData.minimized
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                        width: 8; height: 2; color: Theme.dim
                    }
                }
            }
        }

        Text {   // the highlighted window's full title
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 12
            width: parent.width - 2 * win.pad
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: AltTabState.current ? (AppSearch.windowTitle(AltTabState.current.title, AltTabState.current.app_id) || AltTabState.current.app_id) : ""
            color: Theme.accent
            font.family: Theme.display; font.pixelSize: Theme.ds(11); font.capitalization: Font.SmallCaps
            font.letterSpacing: 1.2
        }
    }
}
