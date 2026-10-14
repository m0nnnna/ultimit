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
            // Skin-aware (Icons.qml): follows the current skin live, falls back to the startup icon theme.
            readonly property string iconSrc: iconName !== "" ? Icons.app(iconName) : ""
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
                width: 36; height: 36
                opacity: ent.mini ? 0.35 : 1
                scale: mouse.pressed ? 0.92 : 1
                Behavior on opacity { NumberAnimation { duration: Config.dur(150) } }
                Behavior on scale { NumberAnimation { duration: Config.dur(120); easing.type: Easing.OutCubic } }

                // Altimit frame: thin chamfered outline (top-right / bottom-left cut), accent when active.
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 1
                        strokeColor: ent.active ? Theme.accent : Theme.line
                        fillColor: ent.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10) : "transparent"
                        joinStyle: ShapePath.MiterJoin
                        Behavior on strokeColor { ColorAnimation { duration: Config.dur(150) } }
                        startX: 0.5; startY: 0.5
                        PathLine { x: 29.5; y: 0.5 }
                        PathLine { x: 35.5; y: 6.5 }
                        PathLine { x: 35.5; y: 35.5 }
                        PathLine { x: 6.5; y: 35.5 }
                        PathLine { x: 0.5; y: 29.5 }
                        PathLine { x: 0.5; y: 0.5 }
                    }
                }
                Image {
                    id: img
                    anchors.centerIn: parent
                    width: 26; height: 26
                    visible: ent.iconSrc !== "" && status !== Image.Error
                    source: ent.iconSrc
                    sourceSize: Qt.size(52, 52)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Text {   // letter fallback, only when no icon resolves
                    anchors.centerIn: parent
                    visible: ent.iconSrc === "" || img.status === Image.Error
                    text: ((ent.de && ent.de.name) || ent.title || ent.appId || "?").charAt(0).toUpperCase()
                    color: ent.active ? Theme.accent : Theme.fg
                    font.family: Theme.display; font.pixelSize: 12
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
