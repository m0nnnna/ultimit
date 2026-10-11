// FlyLock.qml - 10x12 padlock glyph (secured network).
import QtQuick
import "../.."
import ".."

Item {
    property color color: Theme.dim
    width: 10; height: 12
    Rectangle { x: 2; y: 0; width: 6; height: 7; radius: 3; color: "transparent"; border.width: 1; border.color: parent.color }
    Rectangle { x: 0; y: 5; width: 10; height: 7; color: parent.color }
}
