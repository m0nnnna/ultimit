// SkinCard.qml - one skin swatch (".skin" in the mockup): gradient preview with an accent
// stripe, name below, accent outline when selected.
import QtQuick
import "../.."

Item {
    id: root
    property string name: "Mine"
    property color colorA: "black"
    property color colorB: "gray"
    property color stripe: "white"
    property bool selected: false
    signal clicked()

    implicitHeight: 64 + nameText.implicitHeight + 16 + 2
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked(); event.accepted = true;
        }
    }

    // selected / focus outline (2px, offset 2)
    Rectangle {
        anchors.fill: parent; anchors.margins: -4
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
        opacity: root.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(150); easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: -3
        color: "transparent"
        border.width: 1
        border.color: Theme.fg
        visible: root.activeFocus && !root.selected
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: mouse.containsMouse ? Theme.panel2 : "transparent"
        border.width: 1
        border.color: Theme.line
        scale: mouse.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: Config.dur(100); easing.type: Easing.OutCubic } }

        Item {
            id: pv
            x: 1; y: 1
            width: parent.width - 2; height: 64
            clip: true
            // CSS linear-gradient(120deg, a, b): horizontal gradient rotated 30deg.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 1.7; height: parent.height * 2.6
                rotation: 30
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: root.colorA }
                    GradientStop { position: 1; color: root.colorB }
                }
            }
            Rectangle { x: 0; y: 0; width: 10; height: parent.height; color: root.stripe }
        }
        Text {
            id: nameText
            x: 10; y: 64 + 8
            text: root.name.toUpperCase()
            color: Theme.fg
            font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 11
            font.letterSpacing: 1.76   // .16em
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.clicked(); }
    }
}
