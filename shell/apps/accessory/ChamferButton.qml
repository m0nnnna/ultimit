// ChamferButton.qml - ".btn": 1px strong outline, 8px chamfer on top-left / bottom-right,
// caps label, hover wash. `primary` fills with the accent.
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
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked(); event.accepted = true;
        }
    }

    readonly property real c: 8
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        scale: mouse.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Config.dur(100); easing.type: Easing.OutCubic } }
        ShapePath {
            strokeColor: root.primary ? Theme.accent : (root.activeFocus ? Theme.accent : Theme.lineStrong)
            strokeWidth: 1
            fillColor: root.primary ? Theme.accent : (mouse.containsMouse ? Theme.panel2 : "transparent")
            Behavior on fillColor { ColorAnimation { duration: Config.dur(150) } }
            startX: root.c + .5; startY: .5
            PathLine { x: root.width - .5; y: .5 }
            PathLine { x: root.width - .5; y: root.height - root.c - .5 }
            PathLine { x: root.width - root.c - .5; y: root.height - .5 }
            PathLine { x: .5; y: root.height - .5 }
            PathLine { x: .5; y: root.c + .5 }
            PathLine { x: root.c + .5; y: .5 }
        }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text.toUpperCase()
        color: root.primary ? Theme.onAccent : Theme.fg
        font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 11
        font.letterSpacing: 1.76
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.clicked(); }
    }
}
