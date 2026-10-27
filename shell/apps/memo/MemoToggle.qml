// MemoToggle.qml - small toggle chip used in the MEMO bars. Sentence-case body label; on = the
// selection wash with accent text and a 2px accent underline (not a full accent block).
import QtQuick
import "../.."

Rectangle {
    id: root
    property string text: ""
    property bool on: false
    signal clicked()
    implicitWidth: lab.implicitWidth + 24
    implicitHeight: 26
    color: on ? Theme.selection : (ma.containsMouse ? Theme.hover : Theme.field)
    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    Text {
        id: lab
        anchors.centerIn: parent
        text: root.text
        color: root.on ? Theme.accent : Theme.fg
        font.family: Theme.ui; font.pixelSize: Theme.type.body
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    }
    Rectangle {   // on marker
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 2; color: Theme.accent
        opacity: root.on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
