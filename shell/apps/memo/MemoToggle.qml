// MemoToggle.qml - small chamfer-less toggle chip (caps label) used in the MEMO bars.
import QtQuick
import "../.."

Rectangle {
    id: root
    property string text: ""
    property bool on: false
    signal clicked()
    implicitWidth: lab.implicitWidth + 18
    implicitHeight: 26
    color: on ? Theme.accent : (ma.containsMouse ? Theme.selection : Theme.field)
    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    Text {
        id: lab
        anchors.centerIn: parent
        text: root.text
        color: root.on ? Theme.onAccent : Theme.fg
        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
