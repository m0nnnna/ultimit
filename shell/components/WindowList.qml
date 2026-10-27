// WindowList.qml - "WINDOWS" section of the rail: one 44px entry per open toplevel
// (wlr-foreign-toplevel via ToplevelManager). Left click toggles minimize/activate,
// middle click closes, right click opens the window menu (WindowPopups), hover shows a tooltip.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import ".."

Item {
    id: root
    property string screenName: ""
    // The rail window: entries report their place in it so the compositor's
    // minimize/restore animation flies to and from them.
    property var panel: null
    visible: list.count > 0

    Rectangle { id: divider; x: 12; width: parent.width - 24; height: 1; color: Theme.divider }   // between the pins and the windows
    Text {
        id: head
        anchors.top: divider.bottom; anchors.topMargin: Theme.space(2)
        anchors.horizontalCenter: parent.horizontalCenter
        text: "WINDOWS"
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
    }

    ListView {
        id: list
        anchors.top: head.bottom; anchors.topMargin: Theme.space(2)
        anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: ToplevelManager.toplevels
        onContentYChanged: WindowUi.hideTip()

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase }
                NumberAnimation { property: "x"; from: -24; to: 0; duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: Config.dur(Theme.motion.base); easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; to: -24; duration: Config.dur(Theme.motion.base); easing.type: Easing.InCubic }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase }
        }

        delegate: Item {
            id: ent
            required property var modelData
            width: list.width; height: 40

            function pushRect() {
                if (!root.panel || !modelData) return;
                const p = ent.mapToItem(null, 0, 0);
                modelData.setRectangle(root.panel, Qt.rect(Math.round(p.x), Math.round(p.y), ent.width, ent.height));
            }
            Timer { id: rectTimer; interval: 250; onTriggered: ent.pushRect() }   // after add/displace transitions
            Component.onCompleted: rectTimer.restart()
            onYChanged: rectTimer.restart()
            Connections { target: list; function onContentYChanged() { rectTimer.restart(); } }

            property string appId: modelData.appId || ""
            property string title: modelData.title || ""
            readonly property var de: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
            readonly property string ownIcon: Icons.windowIcon(appId, title)
            readonly property string iconName: ownIcon !== "" ? ownIcon : (de && de.icon ? de.icon : appId)
            // Real icon, not a letter: the desktop entry's Icon through the icon theme (Icons.path: the
            // skin's own drawn glyph, the user's hicolor, then the system theme; follows the skin live).
            readonly property string iconSrc: iconName !== "" ? Icons.path(iconName) : ""
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
                color: mouse.pressed ? Theme.press : (ent.active ? Theme.selection : (mouse.containsMouse ? Theme.hover : Theme.clear(Theme.hover)))
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            }
            Rectangle {   // accent bar, flush to rail edge like RailButton
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: ent.active ? parent.height - 16 : 0
                color: Theme.accent
                visible: height > 0
                Behavior on height { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
            }
            Item {
                id: ico
                anchors.centerIn: parent
                width: Theme.icon.xl; height: Theme.icon.xl
                opacity: ent.mini ? 0.35 : 1
                scale: mouse.pressed ? 0.92 : 1
                Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                Behavior on scale { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }

                Image {
                    id: img
                    anchors.centerIn: parent
                    width: Theme.icon.lg; height: Theme.icon.lg
                    visible: ent.iconSrc !== "" && status === Image.Ready
                    source: ent.iconSrc
                    sourceSize: Qt.size(Theme.icon.lg * 2, Theme.icon.lg * 2)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                IconBadge {   // last resort, dimmed: no icon resolved (letter in the badge)
                    anchors.centerIn: parent
                    visible: !img.visible
                    opacity: 0.6
                    size: Theme.icon.lg
                    letter: ((ent.de && ent.de.name) || ent.title || ent.appId || "?").charAt(0).toUpperCase()
                    active: ent.active
                }
            }
            Rectangle {   // minimized marker
                visible: ent.mini
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 4
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
                    Config.closeLauncher();   // the rail sits above the launcher while it is open
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
