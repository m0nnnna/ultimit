// MobileSwitcher.qml - phone app switcher (ULTIMIT_MOBILE=1): open apps as cards, most recent
// first. Tap a card to go to it, flick it up to close it; tap outside to go back. Overlay layer,
// opened from the gesture bar (swipe up and hold).
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    readonly property bool shown: Config.switcherOpen
    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Normal
    color: Qt.rgba(0, 0, 0, .78)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-switcher"

    onShownChanged: if (shown) { cards.positionViewAtBeginning(); SysState.closeQs(); }

    MouseArea { anchors.fill: parent; onClicked: Config.switcherOpen = false }

    Text {
        anchors.centerIn: parent
        visible: cards.count === 0
        text: "NO OPEN APPS"
        color: Theme.dim
        font { family: Theme.ui; pixelSize: 15; letterSpacing: 2 }
    }

    ListView {
        id: cards
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -20 }
        height: parent.height * .66
        orientation: ListView.Horizontal
        spacing: 16
        leftMargin: (width - parent.width * .68) / 2
        rightMargin: leftMargin
        snapMode: ListView.SnapToItem
        model: win.shown ? MobileState.mru : []
        delegate: Item {
            id: card
            required property var modelData
            required property int index
            width: win.width * .68
            height: cards.height
            readonly property string appId: modelData.appId || ""
            readonly property var de: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
            readonly property string own: Icons.windowIcon(appId, modelData.title || "")
            readonly property string iconName: own !== "" ? own : (de && de.icon ? de.icon : appId)
            readonly property string iconSrc: iconName !== "" ? Icons.app(iconName) : ""

            Item {
                id: body
                width: parent.width; height: parent.height
                opacity: 1 - Math.min(1, Math.max(0, -y) / 260)

                Row {   // icon + title above the card
                    id: head
                    spacing: 8
                    height: 28
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22
                        source: card.iconSrc
                        sourceSize: Qt.size(44, 44)
                        visible: card.iconSrc !== ""
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: card.width - 30
                        text: card.modelData.title || (card.de && card.de.name) || card.appId || "Untitled"
                        color: Theme.fg
                        elide: Text.ElideRight
                        font { family: Theme.ui; pixelSize: 14 }
                    }
                }
                Rectangle {
                    anchors { top: head.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom }
                    color: Theme.panel
                    border.width: 1; border.color: Theme.lineStrong
                    clip: true
                    Image {   // shown until (or instead of) a snapshot of the window
                        anchors.centerIn: parent
                        width: 72; height: 72
                        source: card.iconSrc
                        sourceSize: Qt.size(144, 144)
                        visible: card.iconSrc !== "" && !shot.hasContent
                    }
                    ScreencopyView {
                        id: shot
                        anchors.fill: parent
                        anchors.margins: 1
                        captureSource: win.shown ? card.modelData : null
                        live: false
                    }
                    Brackets {}
                }

                MouseArea {
                    anchors.fill: parent
                    drag.target: body
                    drag.axis: Drag.YAxis
                    drag.maximumY: 0
                    drag.filterChildren: true
                    onClicked: MobileState.show(card.modelData)
                    onReleased: {
                        if (body.y < -140) MobileState.close(card.modelData);
                        else body.y = 0;
                    }
                }
            }
        }
    }

    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 26 }
        visible: cards.count > 1
        width: 150; height: 40
        color: Theme.panel
        border.width: 1; border.color: Theme.lineStrong
        Text {
            anchors.centerIn: parent
            text: "CLOSE ALL"
            color: Theme.fg
            font { family: Theme.ui; pixelSize: 13; letterSpacing: 2 }
        }
        MouseArea { anchors.fill: parent; onClicked: MobileState.closeAll() }
    }
}
