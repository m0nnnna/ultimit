// Brackets.qml - mockup .win::before/::after: 14px L-shaped accent corners at top-left
// and bottom-right (2px, sitting 1px outside the frame). Drop inside a bordered Rectangle.
import QtQuick
import ".."

Item {
    anchors.fill: parent
    property color color: Theme.accent
    property int size: 14
    property int thickness: 2
    // top-left
    Rectangle { x: -1; y: -1; width: parent.size; height: parent.thickness; color: parent.color }
    Rectangle { x: -1; y: -1; width: parent.thickness; height: parent.size; color: parent.color }
    // bottom-right
    Rectangle { x: parent.width + 1 - parent.size; y: parent.height + 1 - parent.thickness; width: parent.size; height: parent.thickness; color: parent.color }
    Rectangle { x: parent.width + 1 - parent.thickness; y: parent.height + 1 - parent.size; width: parent.thickness; height: parent.size; color: parent.color }
}
