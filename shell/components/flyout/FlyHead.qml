// FlyHead.qml - flyout section header: accent square + dim mono caps label on the left, optional
// detail on the right. The detail takes only the room the label leaves and elides, so a long
// device name never runs into the label.
import QtQuick
import "../.."
import ".."
import "../../apps/accessory"

Item {
    id: root
    property string text: ""
    property string detail: ""
    property color detailColor: Theme.dim
    width: parent ? parent.width : 300
    height: Theme.space(7)
    SectionLabel { id: lbl; text: root.text; decode: true; anchors.verticalCenter: parent.verticalCenter }
    Text {
        anchors { left: lbl.right; leftMargin: Theme.space(3); right: parent.right; verticalCenter: parent.verticalCenter }
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: root.detail.toUpperCase(); color: root.detailColor
        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
        font.features: Theme.tnum
    }
}
