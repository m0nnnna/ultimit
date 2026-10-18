// DButton.qml - GButton in the danger colour: outlined, or `solid` for the one red button of a confirmation.
import QtQuick
import QtQuick.Shapes
import "../.."

Item {
    id: root
    property string text: ""
    property bool solid: false
    readonly property color red: Disks.danger
    signal clicked()

    implicitWidth: label.implicitWidth + 32
    implicitHeight: 34
    opacity: enabled ? 1 : 0.4

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1
            strokeColor: root.red
            fillColor: root.solid ? root.red : (mouse.containsMouse ? Qt.rgba(root.red.r, root.red.g, root.red.b, 0.16) : "transparent")
            startX: 8; startY: 0.5
            PathLine { x: root.width - 0.5; y: 0.5 }
            PathLine { x: root.width - 0.5; y: root.height - 8 }
            PathLine { x: root.width - 8; y: root.height - 0.5 }
            PathLine { x: 0.5; y: root.height - 0.5 }
            PathLine { x: 0.5; y: 8 }
            PathLine { x: 8; y: 0.5 }
        }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text.toUpperCase()
        color: root.solid ? "#ffffff" : root.red
        font.family: Theme.ui
        font.weight: Font.DemiBold
        font.pixelSize: 11
        font.letterSpacing: 1.76
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
