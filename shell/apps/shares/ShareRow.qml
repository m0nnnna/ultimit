// ShareRow.qml - one share: name, folder, access chips, network address (+ copy), Open folder and Remove.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    required property var share
    signal removeRequested(string name)

    readonly property string unc: Shares.uncPath(share.name)

    implicitHeight: Config.mobile ? info.implicitHeight + buttons.height + 36 : 92
    color: Theme.panel2
    border.color: Theme.line
    border.width: 1

    Rectangle { width: 2; height: parent.height; color: root.share.guest ? Theme.warn : Theme.accent }

    Column {
        id: info
        anchors { left: parent.left; right: Config.mobile ? parent.right : buttons.left; leftMargin: 16; rightMargin: Config.mobile ? 12 : 12
                  top: Config.mobile ? parent.top : undefined; topMargin: Config.mobile ? 12 : 0
                  verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
        spacing: 6
        Flow {
            width: parent.width
            spacing: 10
            Text {
                anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter
                text: root.share.name
                color: Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 16
            }
            GChip { anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter; text: root.share.writable ? "Writable" : "Read-only"; tone: root.share.writable ? Theme.accent : Theme.dim }
            GChip { anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter; text: root.share.guest ? "Guests: yes" : "Guests: no"; tone: root.share.guest ? Theme.warn : Theme.dim }
        }
        Text {
            width: parent.width
            elide: Text.ElideMiddle
            text: root.share.path + (root.share.comment !== "" ? "   ·   " + root.share.comment : "")
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 12
        }
        Flow {
            width: parent.width
            spacing: 10
            Text {
                anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter
                text: root.unc
                color: Theme.fg
                font.family: Theme.mono; font.pixelSize: 13
            }
            GLabel {
                anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter
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
                anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter
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

    Grid {
        id: buttons
        columns: Config.mobile ? 2 : 1
        anchors { right: Config.mobile ? undefined : parent.right; left: Config.mobile ? parent.left : undefined; rightMargin: 14; leftMargin: 16
                  bottom: Config.mobile ? parent.bottom : undefined; bottomMargin: Config.mobile ? 12 : 0
                  verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
        spacing: 8
        GButton { width: 118; text: "Open folder"; onClicked: Shares.openFolder(root.share.path) }
        GButton { width: 118; text: "Remove"; onClicked: root.removeRequested(root.share.name) }
    }
}
