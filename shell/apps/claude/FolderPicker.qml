// FolderPicker.qml - choose a project folder inside CLAUDE (no GTK dialog or portal, which can hand
// the request to DATA instead of showing a picker). Folders only: click one to go in, ".." to go up;
// the path field takes a typed path (~ works). "Use this folder" accepts the folder being shown.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../accessory"

Item {
    id: root
    property string startDir: ""
    signal accepted(string dir)
    signal cancelled()

    property string dir: ""
    property string parentDir: ""
    property var dirs: []
    property string err: ""
    property bool showHidden: false
    readonly property var shown: {
        const out = parentDir !== "" ? [{ n: "..", up: true }] : [];
        for (const d of dirs) if (showHidden || !d.h) out.push(d);
        return out;
    }

    function load(d) {
        Claude.run(["dirs", d], o => {
            if (!o.ok) { root.err = o.err || "Cannot open that folder"; return; }
            root.err = ""; root.dir = o.dir; root.parentDir = o.parent; root.dirs = o.dirs;
            pathE.text = o.dir;
            list.positionViewAtBeginning();
        });
    }
    function open(e) { load(e.up ? parentDir : (dir === "/" ? "" : dir) + "/" + e.n); }

    Component.onCompleted: load(startDir || "~")
    Keys.onEscapePressed: cancelled()

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        SectionLabel { text: "Project folder" }
        RowLayout {
            Layout.fillWidth: true
            Entry { id: pathE; Layout.fillWidth: true; mono: true; onAccepted: root.load(text.trim()) }
            ChamferButton { implicitHeight: 32; text: "Home"; onClicked: root.load("~") }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true
            color: Theme.field
            clip: true
            ListView {
                id: list
                anchors.fill: parent; anchors.margins: 1
                model: root.shown
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                delegate: Rectangle {
                    required property var modelData
                    width: list.width; height: 32
                    color: m.containsMouse ? Theme.hover : Theme.clear(Theme.hover)
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    Text {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.up ? "↑" : "▸"
                        color: Theme.accent; font.family: Theme.mono; font.pixelSize: Theme.type.body
                    }
                    Text {
                        x: 32; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.up ? ".." : modelData.n + "/"
                        color: modelData.h ? Theme.dim : Theme.fg; elide: Text.ElideRight
                        font.family: Theme.mono; font.pixelSize: Theme.type.body
                    }
                    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.open(modelData) }
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.err !== "" || root.shown.length === (root.parentDir !== "" ? 1 : 0)
                    text: root.err !== "" ? root.err : "No folders in here"
                    color: root.err !== "" ? Theme.bad : Theme.dim
                    font.family: Theme.mono; font.pixelSize: Theme.type.label
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            SmallLink {
                text: root.showHidden ? "HIDE HIDDEN FOLDERS" : "SHOW HIDDEN FOLDERS"
                onClicked: root.showHidden = !root.showHidden
            }
            Item { Layout.fillWidth: true }
            ChamferButton { implicitHeight: 32; text: "Cancel"; onClicked: root.cancelled() }
            ChamferButton { implicitHeight: 32; text: "Use this folder"; primary: true; enabled: root.dir !== ""; onClicked: root.accepted(root.dir) }
        }
    }
}
