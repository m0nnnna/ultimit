// GButton.qml - .btn: uppercase, letter-spaced, chamfered corners (8px).
import QtQuick
import QtQuick.Shapes
import "../.."

Item {
    id: root
    property string text: ""
    property bool primary: false
    signal clicked()

    implicitWidth: label.implicitWidth + 32
    implicitHeight: Config.mobile ? 40 : 34
    opacity: enabled ? 1 : 0.5

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1
            strokeColor: root.primary ? Theme.accent : Theme.lineStrong
            fillColor: root.primary ? Theme.accent : (mouse.containsMouse ? Theme.panel2 : "transparent")
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
        color: root.primary ? Theme.onAccent : Theme.fg
        font.family: Theme.ui
        font.weight: Font.DemiBold
        font.pixelSize: 11
        font.letterSpacing: 1.76
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
