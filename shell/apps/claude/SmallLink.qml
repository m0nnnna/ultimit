// SmallLink.qml - a small mono caps text button (sidebar "+ NEW", "DETAILS").
import QtQuick
import "../.."

Text {
    id: root
    signal clicked()
    color: lm.containsMouse ? Theme.fg : Theme.accent
    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
    MouseArea {
        id: lm
        anchors.fill: parent; anchors.margins: -4
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
