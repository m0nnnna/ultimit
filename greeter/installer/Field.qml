// Field.qml - a labelled text box in the greeter's chamfered style. `secret` hides what's typed.
import QtQuick
import QtQuick.Shapes
import ".."

Column {
    id: root
    property string label: ""
    property string hint: ""          // under the box (dim), or the error when `bad`
    property bool bad: false
    property bool secret: false
    property alias text: input.text
    property alias input: input
    signal accepted()
    spacing: 6

    Text {
        text: root.label.toUpperCase()
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.4
    }
    Item {
        id: box
        width: root.width; height: 42
        readonly property real c: 8
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: root.bad ? 2 : 1
                strokeColor: root.bad ? Theme.bad : (input.activeFocus ? Theme.accent : Theme.lineStrong)
                fillColor: Theme.panel2
                startX: box.c + .5; startY: .5
                PathLine { x: box.width - .5; y: .5 }
                PathLine { x: box.width - .5; y: box.height - box.c - .5 }
                PathLine { x: box.width - box.c - .5; y: box.height - .5 }
                PathLine { x: .5; y: box.height - .5 }
                PathLine { x: .5; y: box.c + .5 }
                PathLine { x: box.c + .5; y: .5 }
            }
        }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
            font.family: Theme.ui; font.pixelSize: 16
            echoMode: root.secret ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            clip: true
            activeFocusOnTab: true
            onAccepted: root.accepted()
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: m => { input.forceActiveFocus(); m.accepted = false; } }
    }
    Text {
        visible: text !== ""
        width: root.width
        wrapMode: Text.WordWrap
        text: root.hint
        color: root.bad ? Theme.bad : Theme.dim
        font.family: Theme.ui; font.pixelSize: 12
    }
}
