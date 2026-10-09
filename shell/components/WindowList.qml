// WindowList.qml - "WINDOWS" section of the rail: one 44px entry per open toplevel
// (wlr-foreign-toplevel via ToplevelManager). Left click toggles minimize/activate,
// middle click closes, right click opens the window menu (WindowPopups), hover shows a tooltip.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Item {
    id: root
    property string screenName: ""
    visible: list.count > 0

    Rectangle { id: divider; x: 12; width: parent.width - 24; height: 1; color: Theme.line }
    Text {
        id: head
        anchors.top: divider.bottom; anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        text: "WINDOWS"
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 8; font.letterSpacing: 1.4
    }

    ListView {
        id: list
        anchors.top: head.bottom; anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: ToplevelManager.toplevels
        onContentYChanged: WindowUi.hideTip()

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Config.dur(200); easing.type: Easing.OutCubic }
                NumberAnimation { property: "x"; from: -24; to: 0; duration: Config.dur(200); easing.type: Easing.OutCubic }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: Config.dur(150); easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; to: -24; duration: Config.dur(150); easing.type: Easing.InCubic }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Config.dur(180); easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: ent
            required property var modelData
            width: list.width; height: 44

            property string appId: modelData.appId || ""
            property string title: modelData.title || ""
            readonly property var de: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
            readonly property string iconName: de && de.icon ? de.icon : appId
            readonly property string iconSrc: iconName !== "" ? Quickshell.iconPath(iconName, true) : ""
            readonly property bool active: modelData.activated
            readonly property bool mini: modelData.minimized

            Connections {
                target: ent.modelData
                function onAppIdChanged() { ent.appId = ent.modelData.appId || ""; }
                function onTitleChanged() {
                    ent.title = ent.modelData.title || "";
                    if (mouse.containsMouse) root.tip();
                }
            }
            function tip() {
                const p = ent.mapToGlobal(0, ent.height / 2);
                WindowUi.showTip(ent.title || ent.appId || "Untitled", p.y, root.screenName);
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.panel2
                opacity: mouse.pressed ? 1 : (mouse.containsMouse ? 0.7 : 0)
                Behavior on opacity { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
            }
            Rectangle {   // accent bar, flush to rail edge like RailButton
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: ent.active ? parent.height - 16 : 0
                color: Theme.accent
                visible: height > 0
                Behavior on height { NumberAnimation { duration: Config.dur(220); easing.type: Easing.OutCubic } }
            }
            Item {
                id: ico
                anchors.centerIn: parent
                width: 26; height: 26
                opacity: ent.mini ? 0.35 : 1
                scale: mouse.pressed ? 0.92 : 1
                Behavior on opacity { NumberAnimation { duration: Config.dur(150) } }
                Behavior on scale { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }
                Image {
                    id: img
                    anchors.fill: parent
                    visible: ent.iconSrc !== "" && status === Image.Ready
                    source: ent.iconSrc
                    sourceSize: Qt.size(52, 52)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !img.visible
                    color: "transparent"; border.width: 1
                    border.color: ent.active ? Theme.accent : Theme.lineStrong
                    Text {
                        anchors.centerIn: parent
                        text: ((ent.de && ent.de.name) || ent.title || ent.appId || "?").charAt(0).toUpperCase()
                        color: Theme.fg; font.family: Theme.display; font.pixelSize: 12
                    }
                }
            }
            Rectangle {   // minimized marker
                visible: ent.mini
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                width: 8; height: 2; color: Theme.dim
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onEntered: tipTimer.restart()
                onExited: { tipTimer.stop(); WindowUi.hideTip(); }
                onClicked: mouseEvent => {
                    tipTimer.stop();
                    const tl = ent.modelData;
                    if (mouseEvent.button === Qt.MiddleButton) { WindowUi.hideTip(); tl.close(); }
                    else if (mouseEvent.button === Qt.RightButton) {
                        const p = ent.mapToGlobal(0, ent.height / 2);
                        WindowUi.openMenu(tl, p.y, root.screenName);
                    } else if (tl.activated && !tl.minimized) tl.minimized = true;
                    else { tl.minimized = false; tl.activate(); }
                }
            }
            Timer { id: tipTimer; interval: 180; onTriggered: ent.tip() }
        }
    }
}
