// FlyHead.qml - flyout title: accent square + dim mono caps on the left, optional right-hand detail.
import QtQuick
import "../.."
import ".."
import "../../apps/accessory"

Item {
    property string text: ""
    property string detail: ""
    property color detailColor: Theme.dim
    width: parent ? parent.width : 300
    height: 20
    SectionLabel { text: parent.text; anchors.verticalCenter: parent.verticalCenter }
    Text {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: parent.detail.toUpperCase(); color: parent.detailColor
        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
    }
}
