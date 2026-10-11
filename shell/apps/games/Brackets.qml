// Brackets.qml - Altimit corner brackets around the parent's bounds.
import QtQuick

Item {
    id: root
    property color color: "white"
    property real size: 10
    property real thickness: 2
    anchors.fill: parent
    Repeater {
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]
        delegate: Item {
            required property var modelData
            x: modelData[0] ? root.width - root.size : 0
            y: modelData[1] ? root.height - root.size : 0
            width: root.size; height: root.size
            Rectangle { width: parent.width; height: root.thickness; color: root.color; y: modelData[1] ? parent.height - root.thickness : 0 }
            Rectangle { height: parent.height; width: root.thickness; color: root.color; x: modelData[0] ? parent.width - root.thickness : 0 }
        }
    }
}
