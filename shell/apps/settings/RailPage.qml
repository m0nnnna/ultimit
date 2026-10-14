// Rail: choose and order the pinned items in the rail's top section (Pins.qml, saved in shell.json "pins").
// ACCESSORY (Settings) always stays pinned. "Add" lists the built-ins that are not pinned plus every
// installed app (same search as the launcher: NoDisplay and Config.launcherHidden entries are left out).
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."
import "../accessory"
import "../../components"

Page {
    id: pg
    title: "Rail"
    subtitle: "Pinned items in the rail's top section, in order. Right-click a rail button for the same actions. Up to " + Pins.maxPins + " items; a longer list scrolls in the rail."

    property string query: ""
    // Add candidates: unpinned built-ins first (when they match), then apps.
    readonly property var candidates: {
        Pins.specs; Pins.entriesTick;
        const q = query.trim().toLowerCase();
        const out = [];
        for (const a of Config.apps) {
            if (Pins.has(a.id)) continue;
            if (q !== "" && a.label.toLowerCase().indexOf(q) < 0) continue;
            out.push({ kind: "builtin", id: a.id, name: a.label, sub: "Built-in" });
        }
        for (const e of AppSearch.filter(query)) {
            if (Pins.hasDesktop(e.id)) continue;
            out.push({ kind: "app", id: e.id, name: e.name, sub: e.genericName || e.comment || e.id, icon: e.icon || "", entry: e });
        }
        return out;
    }

    SectionLabel { text: "Pinned" }
    Repeater {
        model: Pins.list
        delegate: ItemRow {
            id: row
            required property var modelData
            required property int index
            title: modelData.builtin ? modelData.label : (modelData.name || modelData.label)
            subtitle: modelData.builtin ? "Built-in" : (modelData.found ? modelData.desktopId : modelData.desktopId + " (not installed)")
            badge: Pins.isLocked(modelData.id) ? "always pinned" : ""
            ChamferButton {
                text: "↑"; implicitWidth: 44; implicitHeight: 30
                enabled: row.index > 0; opacity: enabled ? 1 : 0.3
                onClicked: Pins.move(row.modelData.id, -1)
            }
            ChamferButton {
                text: "↓"; implicitWidth: 44; implicitHeight: 30
                enabled: row.index < Pins.list.length - 1; opacity: enabled ? 1 : 0.3
                onClicked: Pins.move(row.modelData.id, 1)
            }
            ChamferButton {
                text: "Remove"; implicitHeight: 30
                enabled: !Pins.isLocked(row.modelData.id); opacity: enabled ? 1 : 0.3
                onClicked: Pins.unpin(row.modelData.id)
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        ChamferButton { text: "Reset to default"; onClicked: Pins.reset() }
    }

    SectionLabel { text: "Add" }
    TextEntry {
        Layout.fillWidth: true
        placeholder: "Search apps"
        onTextChanged: pg.query = text
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 264
        color: "transparent"
        border.width: 1; border.color: Theme.line
        ListView {
            id: addList
            anchors.fill: parent; anchors.margins: 1
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: pg.candidates
            delegate: Item {
                id: ar
                required property var modelData
                width: addList.width; height: 44
                readonly property string src: modelData.kind === "app" && modelData.icon ? Icons.app(modelData.icon) : ""
                Rectangle { anchors.fill: parent; color: Theme.panel2; opacity: am.containsMouse ? 1 : 0 }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; opacity: .5 }
                Item {
                    id: ico
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26
                    Image {
                        anchors.fill: parent
                        visible: ar.src !== "" && status !== Image.Error
                        source: ar.src
                        sourceSize: Qt.size(52, 52)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Icon {
                        visible: ar.modelData.kind === "builtin"
                        anchors.centerIn: parent
                        size: 22; name: ar.modelData.id; color: Theme.fg
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: ar.modelData.kind === "app" && ar.src === ""
                        text: ar.modelData.name.charAt(0).toUpperCase()
                        color: Theme.fg; font.family: Theme.display; font.pixelSize: 12
                    }
                }
                Column {
                    anchors.left: ico.right; anchors.leftMargin: 10
                    anchors.right: addBtn.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: ar.modelData.name; color: Theme.fg
                        font.family: Theme.ui; font.pixelSize: 13
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: ar.modelData.sub; color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10
                    }
                }
                ChamferButton {
                    id: addBtn
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: "Add"; implicitHeight: 28
                    enabled: Pins.canAdd(); opacity: enabled ? 1 : 0.3
                    onClicked: ar.modelData.kind === "builtin" ? Pins.pinBuiltin(ar.modelData.id) : Pins.pinEntry(ar.modelData.entry)
                }
                MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
            Text {
                anchors.centerIn: parent
                visible: addList.count === 0
                text: Pins.canAdd() ? "NO MATCHES" : "RAIL IS FULL"
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: Pins.canAdd() ? "" : "The rail is full (" + Pins.maxPins + " pins). Remove one to add another."
        visible: text !== ""
        color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
    }
}
