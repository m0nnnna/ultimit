// InstalledPage.qml - every installed Flatpak app, with Open and Remove. Updates live in
// Settings > Updates.
import QtQuick
import QtQuick.Controls
import Quickshell
import "../.."
import "../games"

Item {
    id: root
    property string confirmId: ""

    GLabel {
        id: hd
        strong: true
        text: Store.installedApps.length + " installed apps  ·  updates are in Settings › Updates"
    }
    Text {
        anchors { right: parent.right; verticalCenter: hd.verticalCenter }
        text: "OPEN UPDATES"; color: up.hovered ? Theme.fg : Theme.accent
        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
        HoverHandler { id: up; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Quickshell.execDetached(["ultimit-settings", "updates"]) }
    }
    ListView {
        anchors { top: hd.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Store.installedApps
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: row
            required property var modelData
            readonly property string jobKind: Store.jobFor(modelData.id)
            width: ListView.view.width; height: 56
            Rectangle { anchors.fill: parent; color: rh.hovered ? Theme.panel2 : "transparent" }
            HoverHandler { id: rh }
            Column {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - btns.width - 36
                spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.name; color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                    TapHandler { onTapped: Store.openApp(row.modelData.id) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.id + (row.modelData.version ? "  ·  " + row.modelData.version : "") + (row.modelData.size ? "  ·  " + row.modelData.size : "")
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                }
            }
            Row {
                id: btns
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text {
                    visible: root.confirmId === row.modelData.id
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Remove it?"; color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
                }
                GButton {
                    visible: row.jobKind === "" && root.confirmId !== row.modelData.id
                    text: "Open"; onClicked: Store.launch(row.modelData.id)
                }
                GButton {
                    enabled: row.jobKind === ""
                    primary: root.confirmId === row.modelData.id
                    text: row.jobKind !== "" ? "Removing…" : "Remove"
                    onClicked: {
                        if (root.confirmId === row.modelData.id) { root.confirmId = ""; Store.remove(row.modelData.id, row.modelData.name); }
                        else root.confirmId = row.modelData.id;
                    }
                }
                GButton {
                    visible: root.confirmId === row.modelData.id
                    text: "Keep"; onClicked: root.confirmId = ""
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }
    }
}
