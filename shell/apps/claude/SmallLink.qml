// SmallLink.qml - a small text button (sidebar "+ NEW", "DETAILS").
import QtQuick
import "../.."

Text {
    id: root
    signal clicked()
    color: lm.containsMouse ? Theme.fg : Theme.accent
    font.family: Theme.ui; font.pixelSize: Theme.type.label; font.weight: Font.DemiBold
    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    MouseArea {
        id: lm
        anchors.fill: parent; anchors.margins: -4
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
