// Dropdown.qml - labelled picker that expands in place (no popup window). Long lists scroll and
// get a filter box.   Dropdown { label: "Timezone"; options: [{id, label}]; current: "x"; onPicked: id => ... }
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root
    property string label: ""
    property var options: []
    property string current: ""
    property string placeholder: "—"
    property bool open: false
    property string query: ""
    signal picked(string id)

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        if (q === "") return options;
        return options.filter(o => String(o.label).toLowerCase().indexOf(q) >= 0 || String(o.id).toLowerCase().indexOf(q) >= 0);
    }
    readonly property string currentLabel: {
        for (const o of options) if (String(o.id) === current) return String(o.label);
        return current !== "" ? current : placeholder;
    }
    readonly property bool filterable: options.length > 12

    implicitHeight: head.height + (open ? list.height + (filterable ? 34 : 0) + 4 : 0)
    Layout.fillWidth: true
    clip: true

    Item {
        id: head
        width: parent.width; height: 48
        Text {
            text: root.label.toUpperCase()
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.8
        }
        Rectangle {
            y: 16; width: parent.width; height: 30
            color: m.containsMouse ? Theme.hover : Theme.field
            border.width: root.open || root.activeFocus ? 1 : 0; border.color: Theme.accent
            Text {
                anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 36
                elide: Text.ElideRight
                text: root.currentLabel
                color: Theme.fg
                font.family: Theme.ui; font.pixelSize: Theme.type.body
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                text: root.open ? "▲" : "▼"
                color: Theme.dim; font.pixelSize: Theme.type.label
            }
            MouseArea {
                id: m
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.open = !root.open; if (root.open) root.query = ""; }
            }
        }
    }
    Rectangle {
        id: filterBox
        visible: root.open && root.filterable
        y: head.height; width: parent.width; height: 30
        color: Theme.field
        TextInput {
            id: fi
            anchors.fill: parent; anchors.margins: 6
            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
            font.family: Theme.ui; font.pixelSize: Theme.type.body
            clip: true
            onTextChanged: root.query = text
            Text { visible: fi.text === ""; text: "Filter…"; color: Theme.dim; font: fi.font }
        }
    }
    ListView {
        id: list
        visible: root.open
        y: head.height + (root.filterable ? 34 : 0)
        width: parent.width
        height: Math.min(220, Math.max(1, count) * 30)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool sel: String(modelData.id) === root.current
            width: list.width; height: 30
            color: rm.containsMouse ? Theme.panel2 : "transparent"
            Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: row.sel }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24; elide: Text.ElideRight
                text: String(row.modelData.label)
                color: row.sel ? Theme.accent : Theme.fg
                font.family: Theme.ui; font.pixelSize: Theme.type.body
            }
            MouseArea {
                id: rm
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.open = false; root.picked(String(row.modelData.id)); }
            }
        }
    }
}
