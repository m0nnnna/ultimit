// GSeg.qml - segmented choice: options [{id, label, disabled?}], `current` id, picked(id).
import QtQuick
import "../.."

Item {
    id: root
    property var options: []
    property string current: ""
    signal picked(string id)

    implicitHeight: 28
    implicitWidth: row.implicitWidth

    Row {
        id: row
        height: parent.height
        spacing: -1
        Repeater {
            model: root.options
            delegate: Rectangle {
                id: seg
                required property var modelData
                readonly property bool on: root.current === modelData.id
                readonly property bool off: modelData.disabled === true
                width: lbl.implicitWidth + 24
                height: root.height
                color: on ? Theme.selection : (m.containsMouse && !off ? Theme.hover : Theme.field)
                opacity: off ? 0.45 : 1
                z: on ? 1 : 0
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
                Text {
                    id: lbl
                    anchors.centerIn: parent
                    text: seg.modelData.label
                    color: seg.on ? Theme.accent : Theme.fg
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    font.family: Theme.mono
                    font.pixelSize: Theme.type.label
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }
                MouseArea {
                    id: m
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !seg.off
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(seg.modelData.id)
                }
            }
        }
    }
}
