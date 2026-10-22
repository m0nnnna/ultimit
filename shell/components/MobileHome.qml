// MobileHome.qml - phone home screen (ULTIMIT_MOBILE=1): clock, app search and a grid of every app.
// Bottom layer (and its own plain background: no wallpaper layer on phones), so open apps (always
// full-screen) cover it; the gesture bar's swipe up minimizes them all to come back here.
// Kept lean for a phone GPU: opaque, one surface, recycled grid cells, single-line labels.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    anchors { left: true; right: true; top: true; bottom: true }
    color: Theme.bg1
    WlrLayershell.layer: WlrLayer.Bottom
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "ultimit-home"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand   // the search field

    property string query: ""
    property var apps: AppSearch.filter(query)
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { win.apps = AppSearch.filter(win.query); }
    }
    // Back home: a clean grid, no stale search.
    Connections {
        target: MobileState
        function onAppShownChanged() {
            if (!MobileState.appShown) { search.text = ""; search.focus = false; grid.positionViewAtBeginning(); }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Rectangle {   // the sky behind the grid, between the status and gesture bars
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bg1 }
            GradientStop { position: 1; color: Qt.darker(Theme.bg2, Theme.light ? 1.1 : 2.2) }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: search.focus = false }

    Column {
        id: head
        anchors { top: parent.top; topMargin: Config.mobileBarH + 22; left: parent.left; right: parent.right }
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Theme.fg
            font { family: Theme.display; pixelSize: 54 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, "dddd d MMMM").toUpperCase()
            color: Theme.dim
            font { family: Theme.ui; pixelSize: 13; letterSpacing: 2 }
        }
        Item { width: 1; height: 16 }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32; height: 42
            color: Theme.panel
            border.width: 1; border.color: search.activeFocus ? Theme.accent : Theme.line
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                visible: search.text === ""
                text: "Search apps"
                color: Theme.dim
                font { family: Theme.ui; pixelSize: 15 }
            }
            TextInput {
                id: search
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font { family: Theme.ui; pixelSize: 15 }
                clip: true
                onTextChanged: win.query = text
                onAccepted: if (win.apps.length) win.run(win.apps[0])
                Keys.onEscapePressed: { text = ""; focus = false; }
            }
        }
    }

    function run(e) {
        search.text = ""; search.focus = false;
        e.execute();
    }

    GridView {
        id: grid
        anchors { top: head.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: Config.gestureH; leftMargin: 8; rightMargin: 8 }
        clip: true
        cellWidth: Math.floor(width / 4)
        cellHeight: 88
        reuseItems: true
        cacheBuffer: cellHeight * 4
        maximumFlickVelocity: 6000
        pixelAligned: true
        model: win.apps
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: cell
            required property var modelData
            width: grid.cellWidth; height: grid.cellHeight
            readonly property string iconSrc: modelData.icon ? Icons.app(modelData.icon) : ""
            Rectangle {
                anchors.fill: parent; anchors.margins: 3
                color: tap.pressed ? Theme.panel2 : "transparent"
            }
            Item {
                id: ico
                anchors { top: parent.top; topMargin: 10; horizontalCenter: parent.horizontalCenter }
                width: 46; height: 46
                Image {
                    anchors.fill: parent
                    visible: cell.iconSrc !== "" && status === Image.Ready
                    source: cell.iconSrc
                    sourceSize: Qt.size(92, 92)
                    asynchronous: true
                    smooth: false
                    mipmap: false
                }
                Rectangle {   // letter tile when there is no icon
                    anchors.fill: parent
                    visible: cell.iconSrc === ""
                    color: Theme.panel; border.width: 1; border.color: Theme.lineStrong
                    Text {
                        anchors.centerIn: parent
                        text: (cell.modelData.name || "?").charAt(0).toUpperCase()
                        color: Theme.accent
                        font { family: Theme.display; pixelSize: 20 }
                    }
                }
            }
            Text {
                anchors { top: ico.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
                horizontalAlignment: Text.AlignHCenter
                text: cell.modelData.name
                color: Theme.fg
                elide: Text.ElideRight
                renderType: Text.NativeRendering
                font { family: Theme.ui; pixelSize: 12 }
            }
            MouseArea { id: tap; anchors.fill: parent; onClicked: win.run(cell.modelData) }
        }
    }
}
