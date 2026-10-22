// BlockedRow.qml - one port the firewall recently turned away: port/protocol, the app it probably belongs to,
// who knocked and when, and a one-click "allow from home network".
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    required property var item

    implicitHeight: Config.mobile ? port.implicitHeight + col.implicitHeight + btns.implicitHeight + 36 : Math.max(col.implicitHeight, btns.implicitHeight) + 24
    color: Theme.panel2
    border.color: Theme.line
    border.width: 1
    opacity: item.allowed ? 0.6 : 1

    Rectangle { width: 2; height: parent.height; color: root.item.allowed ? Theme.ok : root.item.lan ? Theme.warn : Theme.bad }

    Text {
        id: port
        anchors { left: parent.left; leftMargin: 16; verticalCenter: Config.mobile ? undefined : parent.verticalCenter; top: Config.mobile ? parent.top : undefined; topMargin: 12 }
        width: Config.mobile ? implicitWidth : 128
        text: root.item.port + "/" + root.item.proto.toUpperCase()
        color: Theme.fg
        font.family: Theme.mono; font.pixelSize: 17
    }

    Column {
        id: col
        anchors { left: Config.mobile ? parent.left : port.right; right: Config.mobile ? parent.right : btns.left; verticalCenter: Config.mobile ? undefined : parent.verticalCenter
                  top: Config.mobile ? port.bottom : undefined; topMargin: 6; leftMargin: Config.mobile ? 16 : 8; rightMargin: Config.mobile ? 14 : 12 }
        spacing: 5
        Flow {   // phone: chips wrap under the name
            visible: Config.mobile
            width: parent.width
            spacing: 6
            Text {
                text: root.item.label !== "" ? root.item.label : "Unknown app"
                color: root.item.label !== "" ? Theme.fg : Theme.dim
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 14
            }
            GChip { visible: root.item.allowed; text: "Allowed now"; tone: Theme.ok }
            GChip { visible: root.item.broadcast; text: "Broadcast"; tone: Theme.dim }
            GChip { visible: !root.item.lan; text: "From outside your network"; tone: Theme.bad }
        }
        Row {
            visible: !Config.mobile
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.item.label !== "" ? root.item.label : "Unknown app"
                color: root.item.label !== "" ? Theme.fg : Theme.dim
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 14
            }
            GChip { visible: root.item.allowed; anchors.verticalCenter: parent.verticalCenter; text: "Allowed now"; tone: Theme.ok }
            GChip { visible: root.item.broadcast; anchors.verticalCenter: parent.verticalCenter; text: "Broadcast"; tone: Theme.dim }
            GChip { visible: !root.item.lan; anchors.verticalCenter: parent.verticalCenter; text: "From outside your network"; tone: Theme.bad }
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: (root.item.count === 1 ? "Once" : root.item.count + " times") + " · last " + Firewall.agoText(root.item.ago)
                  + " · from " + root.item.sources.join(", ")
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
        }
    }

    Column {
        id: btns
        anchors { right: parent.right; rightMargin: 14; verticalCenter: Config.mobile ? undefined : parent.verticalCenter
                  left: Config.mobile ? parent.left : undefined; leftMargin: 16; top: Config.mobile ? col.bottom : undefined; topMargin: 8 }
        spacing: 6
        GButton {
            visible: !root.item.allowed
            width: Config.mobile ? btns.width : 196
            primary: root.item.lan
            text: root.item.preset !== "" ? "Allow this app" : "Allow from home"
            enabled: Firewall.busy === "" && Firewall.subnet !== ""
            onClicked: Firewall.allowBlocked(root.item)
        }
        GLabel {
            visible: !root.item.allowed
            anchors.right: parent.right
            height: Config.mobile ? 32 : implicitHeight
            verticalAlignment: Text.AlignVCenter
            text: "Custom rule…"
            color: customMouse.containsMouse ? Theme.accent : Theme.dim
            MouseArea {
                id: customMouse
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { Firewall.addPrefill = { port: String(root.item.port), proto: root.item.proto }; Firewall.overlay = "add"; }
            }
        }
    }
}
