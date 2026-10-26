// StatCard.qml - one PERFORMANCE card: small-caps title, a big current value, a line of detail, and the graph (child items) below.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    property string title: ""
    property string value: ""
    property string detail: ""
    property color tone: Theme.fg
    default property alias content: body.data

    color: Theme.panel2
    border.color: Theme.line
    border.width: 1

    Item {
        id: top
        x: 14; y: 12; width: parent.width - 28; height: 22
        GLabel { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: root.title }
        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: root.value
            color: root.tone
            font.family: Theme.display; font.pixelSize: Theme.ds(16)
        }
    }
    Text {
        id: sub
        x: 14; anchors.top: top.bottom; anchors.topMargin: 2
        width: parent.width - 28
        elide: Text.ElideRight
        text: root.detail
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 11
    }
    Item {
        id: body
        x: 14; anchors.top: sub.bottom; anchors.topMargin: 8
        width: parent.width - 28
        height: parent.height - y - 14
    }
}
