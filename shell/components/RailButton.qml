// RailButton.qml - one launcher button in the left rail.
// Shows the accent bar when `on`, a hover wash, and emits `clicked`.
import QtQuick
import ".."

Item {
    id: root
    property string appId: "games"
    property string label: "GAMES"
    property bool on: false
    signal clicked()

    width: 72
    height: 62

    Rectangle {
        anchors.fill: parent
        color: Theme.panel2
        visible: mouse.containsMouse
    }
    // Accent bar: the mockup draws it 6px outside the button, i.e. flush to the rail edge.
    Rectangle {
        visible: root.on
        x: -6; y: 12
        width: 3; height: parent.height - 24
        color: Theme.accent
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.appId
            color: Theme.fg
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.fg
            font.family: Theme.ui
            font.weight: Font.DemiBold
            font.pixelSize: 9
            font.letterSpacing: 1.62   // .18em
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
