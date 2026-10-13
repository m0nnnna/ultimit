// PresetRow.qml - one ready-made rule (VTube Studio, Steam Remote Play, ...): name, state chip, what it is for,
// its ports, and a switch that opens it to the home network or closes it again.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    required property var preset
    readonly property bool on: preset.state === "on"
    readonly property bool working: Firewall.busy === "preset:" + preset.id

    implicitHeight: col.implicitHeight + 24
    color: Theme.panel2
    border.color: Theme.line
    border.width: 1

    Rectangle { width: 2; height: parent.height; color: root.on ? Theme.accent : root.preset.state === "partial" ? Theme.warn : Theme.line }

    Column {
        id: col
        anchors { left: parent.left; right: sw.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 16 }
        spacing: 5
        Row {
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.preset.name
                color: Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 15
            }
            GChip {
                anchors.verticalCenter: parent.verticalCenter
                text: root.working ? "Working…" : root.on ? "Allowed" : root.preset.state === "partial" ? "Partly open" : "Blocked"
                tone: root.on ? Theme.ok : root.preset.state === "partial" ? Theme.warn : Theme.dim
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.preset.desc
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.preset.portsText
            color: root.on ? Theme.fg : Theme.dim
            font.family: Theme.mono; font.pixelSize: 11
        }
    }

    // switch (same look as GToggle's box)
    Rectangle {
        id: sw
        anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
        width: 40; height: 20
        color: "transparent"
        border.color: swMouse.containsMouse ? Theme.accent : Theme.lineStrong
        border.width: 1
        opacity: enabled ? 1 : 0.5
        enabled: Firewall.busy === "" && Firewall.ready
        Rectangle {
            y: 3; width: 14; height: 14
            x: root.on ? 23 : 3
            color: root.on ? Theme.accent : root.preset.state === "partial" ? Theme.warn : Theme.dim
            Behavior on x { NumberAnimation { duration: Config.dur(150) } }
        }
        MouseArea {
            id: swMouse
            anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Firewall.setPreset(root.preset.id, !root.on)
        }
    }
}
