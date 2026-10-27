// Page.qml - scrolling page scaffold: header + a column for the page's content.
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root
    property string title: ""
    property string subtitle: ""
    default property alias content: col.data

    Flickable {
        id: fl
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 24; y: 18
            width: fl.width - 48
            spacing: 14

            Text {
                text: root.title.toUpperCase()
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: Theme.ds(15)
                font.letterSpacing: 2.4
            }
            Text {
                visible: root.subtitle !== ""
                Layout.fillWidth: true
                text: root.subtitle
                color: Theme.dim
                font.family: Theme.ui; font.pixelSize: Theme.type.label
                wrapMode: Text.WordWrap
            }
        }
    }
    Rectangle {   // scrollbar
        visible: fl.contentHeight > fl.height
        anchors.right: parent.right
        width: 3; radius: 0
        y: fl.height * fl.visibleArea.yPosition
        height: fl.height * fl.visibleArea.heightRatio
        color: Theme.lineStrong
    }
}
