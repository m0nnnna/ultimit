// UsageRow.qml - one folder or file of the USAGE list: name, bar relative to the biggest sibling, size, % of the
// parent, item count, and the Open / Trash actions. Folders drill in on click.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    required property var entry          // {name, path, kind, size, items, errors, pct}
    property real maxSize: 1
    property bool showPct: true
    signal drill()
    signal openIt()
    signal trashIt()

    readonly property bool folder: entry.kind === "dir"
    readonly property bool rolled: entry.kind === "other" && !entry.path
    implicitHeight: 38
    color: m.containsMouse ? Theme.panel2 : "transparent"
    border.color: Theme.line
    border.width: 1

    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.folder ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.folder) root.drill()
    }
    Text {
        id: icon
        x: 12; anchors.verticalCenter: parent.verticalCenter
        width: 14
        text: root.folder ? "▸" : root.rolled ? "…" : "·"
        color: root.folder ? Theme.accent : Theme.dim
        font.family: Theme.mono; font.pixelSize: 13
    }
    Text {
        id: nm
        anchors { left: icon.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
        width: Math.max(120, root.width * 0.28)
        elide: Text.ElideMiddle
        text: root.entry.name + (root.entry.errors > 0 ? "  ⚠" : "")
        color: root.rolled ? Theme.dim : Theme.fg
        font.family: Theme.ui; font.pixelSize: 13
    }
    Rectangle {
        id: track
        anchors { left: nm.right; leftMargin: 12; right: sz.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        height: 8
        color: Theme.panel2
        Rectangle {
            width: parent.width * Math.min(1, root.entry.size / Math.max(1, root.maxSize))
            height: parent.height
            color: root.folder ? Theme.accent : Theme.dim
        }
    }
    Text {
        id: sz
        anchors { right: pct.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: 72; horizontalAlignment: Text.AlignRight
        text: Disks.fmt(root.entry.size)
        color: Theme.fg; font.family: Theme.mono; font.pixelSize: 12
    }
    Text {
        id: pct
        anchors { right: cnt.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
        width: 48; horizontalAlignment: Text.AlignRight
        text: root.showPct ? (root.entry.pct < 0.1 ? "<0.1" : root.entry.pct.toFixed(1)) + "%" : ""
        color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
    }
    Text {
        id: cnt
        anchors { right: acts.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
        width: 76; horizontalAlignment: Text.AlignRight
        text: root.folder || root.rolled ? Disks.count(root.entry.items) + (root.entry.items === 1 ? " item" : " items") : ""
        color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
    }
    Row {
        id: acts
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 2
        width: 84
        layoutDirection: Qt.RightToLeft
        visible: !root.rolled
        Repeater {
            model: [{ t: "Trash", a: "trash", c: Theme.bad }, { t: "Open", a: "open", c: Theme.accent }]
            delegate: Item {
                required property var modelData
                width: tl.implicitWidth + 12; height: 24
                Text {
                    id: tl; anchors.centerIn: parent
                    text: modelData.t.toUpperCase()
                    color: bm.containsMouse ? modelData.c : Theme.dim
                    font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.2
                }
                MouseArea {
                    id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.a === "open" ? root.openIt() : root.trashIt()
                }
            }
        }
    }
}
