// SignalBars.qml - four ascending bars; `level` 0..1 lights them up (mono, token colored).
import QtQuick
import ".."

Item {
    id: root
    property real level: 0
    property color color: Theme.fg
    property color offColor: Theme.line
    implicitWidth: 15
    implicitHeight: 10
    readonly property int lit: level <= 0 ? 0 : Math.max(1, Math.min(4, Math.ceil(level * 4 - 0.15)))
    Repeater {
        model: 4
        Rectangle {
            required property int index
            x: index * 4; width: 3
            height: 3 + index * 2
            y: root.height - height
            color: index < root.lit ? root.color : root.offColor
        }
    }
}
