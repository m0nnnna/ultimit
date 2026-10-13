// RuleRow.qml - one ufw rule in plain words, its name (comment), the preset it belongs to, the raw ufw line, Remove.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    required property var rule
    signal removeRequested(var rule)

    readonly property var preset: rule.preset !== "" ? Firewall.presetById(rule.preset) : null
    readonly property bool opens: rule.action === "allow" || rule.action === "limit"

    implicitHeight: col.implicitHeight + 22
    color: Theme.panel2
    border.color: Theme.line
    border.width: 1

    Rectangle { width: 2; height: parent.height; color: root.opens ? (root.rule.from === "any" ? Theme.warn : Theme.accent) : Theme.bad }

    Column {
        id: col
        anchors { left: parent.left; right: rm.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 12 }
        spacing: 4
        Row {
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.rule.text
                color: Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 14
            }
            GChip { visible: root.preset !== null; anchors.verticalCenter: parent.verticalCenter; text: root.preset ? root.preset.name : ""; tone: Theme.accent }
            GChip { visible: root.opens && root.rule.from === "any" && !root.rule.route && root.rule.dir === "in"; anchors.verticalCenter: parent.verticalCenter; text: "Anyone"; tone: Theme.warn }
        }
        Text {
            visible: root.rule.comment !== ""
            width: parent.width
            elide: Text.ElideRight
            text: root.rule.comment
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.rule.line
            color: Theme.dim
            opacity: 0.8
            font.family: Theme.mono; font.pixelSize: 10
        }
    }

    GButton {
        id: rm
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: 104
        text: "Remove"
        enabled: Firewall.busy === "" && Firewall.ready
        onClicked: root.removeRequested(root.rule)
    }
}
