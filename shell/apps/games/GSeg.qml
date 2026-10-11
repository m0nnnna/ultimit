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
                color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (m.containsMouse && !off ? Theme.panel2 : "transparent")
                border.color: on ? Theme.accent : Theme.line
                border.width: 1
                opacity: off ? 0.45 : 1
                z: on ? 1 : 0
                Behavior on color { ColorAnimation { duration: Config.dur(120) } }
                Text {
                    id: lbl
                    anchors.centerIn: parent
                    text: seg.modelData.label
                    color: seg.on ? Theme.accent : Theme.fg
                    font.family: Theme.mono
                    font.pixelSize: 10
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
