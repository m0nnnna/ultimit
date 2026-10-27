// DeviceList.qml - pick one device: rows [{id, label, sub?}], `current` id, picked(id).
import QtQuick
import "../.."
import "../games"

Column {
    id: root
    property var devices: []            // [{id, label, tag?}]
    property string current: ""
    property string emptyText: "Nothing found"
    signal picked(string id)
    spacing: 6

    Repeater {
        model: root.devices
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool on: String(modelData.id) === root.current
            width: root.width; height: 40
            color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10) : (m.containsMouse ? Theme.panel2 : "transparent")
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            border.color: on ? Theme.accent : Theme.line
            Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            border.width: 1
            Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: row.on ? Theme.accent : "transparent"; border.color: row.on ? Theme.accent : Theme.dim; border.width: 1; Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } } }
            Text {
                anchors { left: parent.left; leftMargin: 32; right: tag.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: row.modelData.label
                elide: Text.ElideRight
                color: row.on ? Theme.fg : Theme.dim
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                font.family: Theme.ui; font.pixelSize: 13
            }
            GChip {
                id: tag
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                visible: (row.modelData.tag || "") !== ""
                text: row.modelData.tag || ""
                tone: Theme.dim
            }
            MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.picked(String(row.modelData.id)) }
        }
    }
    GLabel { visible: root.devices.length === 0; text: root.emptyText; color: Theme.warn }
}
