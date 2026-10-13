// ShareRow.qml - one share: name, folder, access chips, network address (+ copy), Open folder and Remove.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    required property var share
    signal removeRequested(string name)

    readonly property string unc: Shares.uncPath(share.name)

    implicitHeight: 92
    color: Theme.panel2
    border.color: Theme.line
    border.width: 1

    Rectangle { width: 2; height: parent.height; color: root.share.guest ? Theme.warn : Theme.accent }

    Column {
        anchors { left: parent.left; right: buttons.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 12 }
        spacing: 6
        Row {
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.share.name
                color: Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 16
            }
            GChip { anchors.verticalCenter: parent.verticalCenter; text: root.share.writable ? "Writable" : "Read-only"; tone: root.share.writable ? Theme.accent : Theme.dim }
            GChip { anchors.verticalCenter: parent.verticalCenter; text: root.share.guest ? "Guests: yes" : "Guests: no"; tone: root.share.guest ? Theme.warn : Theme.dim }
        }
        Text {
            width: parent.width
            elide: Text.ElideMiddle
            text: root.share.path + (root.share.comment !== "" ? "   ·   " + root.share.comment : "")
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 12
        }
        Row {
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.unc
                color: Theme.fg
                font.family: Theme.mono; font.pixelSize: 13
            }
            GLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: "Copy address"
                color: copyMouse.containsMouse ? Theme.accent : Theme.dim
                MouseArea {
                    id: copyMouse
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Shares.copy(root.unc)
                }
            }
            GLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: "Copy smb link"
                color: copyUrlMouse.containsMouse ? Theme.accent : Theme.dim
                MouseArea {
                    id: copyUrlMouse
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Shares.copy(Shares.smbUrl(root.share.name))
                }
            }
        }
    }

    Column {
        id: buttons
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 8
        GButton { width: 118; text: "Open folder"; onClicked: Shares.openFolder(root.share.path) }
        GButton { width: 118; text: "Remove"; onClicked: root.removeRequested(root.share.name) }
    }
}
