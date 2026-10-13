// AppIcon.qml - an app's Flathub icon, or a chamfered tile with its initial when it has none.
import QtQuick
import "../.."

Item {
    id: root
    property var app: ({})
    property int size: 48
    width: size; height: size

    Image {
        id: img
        anchors.fill: parent
        source: root.app.icon ? "file://" + root.app.icon : ""
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }
    Rectangle {
        visible: img.status !== Image.Ready
        anchors.fill: parent
        color: Theme.panel2; border.color: Theme.lineStrong
        Text {
            anchors.centerIn: parent
            text: (root.app.name || "?").charAt(0).toUpperCase()
            color: Theme.accent; font.family: Theme.display; font.pixelSize: root.size * 0.45
        }
    }
}
