// DDialog.qml - modal dialogs for DATA, driven by Data.dialog:
// confirm (delete / empty trash), conflict (Replace / Keep both / Skip), props, openwith.
import QtQuick
import Quickshell
import "../.."
import "../../components"
import "../games"

FocusScope {
    id: root
    anchors.fill: parent
    z: 100
    readonly property var d: Data.dialog
    visible: d !== null
    property bool applyAll: false
    property int appSel: 0

    onVisibleChanged: if (visible) { applyAll = false; appSel = 0; forceActiveFocus(); }

    Keys.onPressed: event => {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
            if (d && d.kind === "conflict") Data.answerConflict("cancel", false); else Data.closeDialog();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (d && d.kind === "openwith") { if (Data.apps.length) Data.openWith(Data.apps[appSel]); }
            else if (d && d.kind === "conflict") Data.answerConflict("both", applyAll);
            else Data.acceptDialog();
        } else if (d && d.kind === "openwith" && event.key === Qt.Key_Down) appSel = Math.min(Data.apps.length - 1, appSel + 1);
        else if (d && d.kind === "openwith" && event.key === Qt.Key_Up) appSel = Math.max(0, appSel - 1);
        else event.accepted = false;
    }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55) }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Math.min(root.width - 40, d && d.kind === "conflict" ? 480 : 440)
        height: content.implicitHeight + 40
        color: Theme.bg1
        border.width: 1; border.color: Theme.lineStrong
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets {}

        Column {
            id: content
            x: 20; y: 20
            width: box.width - 40
            spacing: 14

            Item {   // .lbl
                width: parent.width; height: 16
                Rectangle { id: sq; width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                Text {
                    anchors.left: sq.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: !d ? "" : d.kind === "confirm" ? d.title.toUpperCase()
                        : d.kind === "conflict" ? "NAME CONFLICT" : d.kind === "props" ? "PROPERTIES" : "OPEN WITH"
                    color: Theme.fg
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.8
                }
            }

            // ---- confirm
            Text {
                visible: d && d.kind === "confirm"
                width: parent.width; wrapMode: Text.WordWrap
                text: d && d.kind === "confirm" ? d.text : ""
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
            }
            // ---- conflict
            Text {
                visible: d && d.kind === "conflict"
                width: parent.width; wrapMode: Text.WordWrap
                text: d && d.kind === "conflict" ? "“" + d.name + "” already exists in " + (Data.basename(d.dstDir) || "/") + ". What should happen?" : ""
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
            }
            Item {
                visible: d && d.kind === "conflict" && d.remaining > 1
                width: parent.width; height: 22
                Rectangle {
                    id: cb; width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter
                    color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; color: Theme.accent; visible: root.applyAll }
                }
                Text {
                    anchors.left: cb.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: "Apply to all " + (d && d.kind === "conflict" ? d.remaining : 0) + " conflicts"
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.applyAll = !root.applyAll }
            }

            // ---- props
            Column {
                visible: d && d.kind === "props"
                width: parent.width; spacing: 0
                Repeater {
                    model: {
                        const s = Data.propsStat, u = Data.propsDu;
                        if (!d || d.kind !== "props") return [];
                        if (!s) return [["", "Reading…"]];
                        if (s.err) return [["", s.err]];
                        const multi = s.count > 1;
                        const rows = [];
                        rows.push(["Name", multi ? s.count + " items" : s.name]);
                        rows.push(["Type", multi ? "Mixed" : s.mime + (s.link ? " → " + s.link : "")]);
                        rows.push(["Location", s.dir]);
                        rows.push(["Size", !u ? "Counting…" : Data.fmtSize(u.size) + (u.size >= 1000 ? " (" + u.size.toLocaleString(Qt.locale("en_US"), "f", 0) + " bytes)" : "") +
                                   (s.isdir || multi ? " · " + u.files + " files, " + u.dirs + " folders" : "")]);
                        if (!multi) {
                            rows.push(["Permissions", s.mode + "  (" + s.octal + ")"]);
                            rows.push(["Owner", s.owner + " : " + s.group]);
                            rows.push(["Modified", Data.fmtFull(s.mtime)]);
                            rows.push(["Accessed", Data.fmtFull(s.atime)]);
                            rows.push(["Changed", Data.fmtFull(s.ctime)]);
                        }
                        return rows;
                    }
                    delegate: Item {
                        required property var modelData
                        width: parent.width; height: 26
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                        Text {
                            x: 0; width: 96; anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0].toUpperCase(); color: Theme.dim
                            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                        }
                        Text {
                            x: 100; width: parent.width - 100; anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]; color: Theme.fg; elide: Text.ElideMiddle
                            font.family: Theme.mono; font.pixelSize: 12
                        }
                    }
                }
            }

            // ---- open with
            Column {
                visible: d && d.kind === "openwith"
                width: parent.width; spacing: 8
                Text {
                    width: parent.width; elide: Text.ElideMiddle
                    text: d && d.kind === "openwith" ? d.entry.n + "  ·  " + d.entry.t : ""
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                }
                Text {
                    visible: Data.apps.length === 0
                    text: "No applications found for this type."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
                }
                Repeater {
                    model: Data.apps
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: parent.width; height: 34
                        readonly property bool hot: root.appSel === index
                        Rectangle {
                            anchors.fill: parent; color: hot ? Theme.panel2 : "transparent"
                            Rectangle { width: 2; height: parent.height; color: Theme.accent; visible: hot }
                        }
                        Image {
                            x: 10; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22
                            sourceSize: Qt.size(44, 44)
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                        }
                        Text {
                            x: 44; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name; color: hot ? Theme.accent : Theme.fg
                            font.family: Theme.ui; font.pixelSize: 13
                        }
                        GChip { visible: modelData.default; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "default"; tone: Theme.ok }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: root.appSel = index
                            onClicked: root.appSel = index
                            onDoubleClicked: Data.openWith(modelData)
                        }
                    }
                }
            }

            // ---- buttons
            Row {
                anchors.right: parent.right
                spacing: 10
                GButton { visible: d && d.kind === "conflict"; text: "Cancel"; onClicked: Data.answerConflict("cancel", false) }
                GButton { visible: d && d.kind === "conflict"; text: "Skip"; onClicked: Data.answerConflict("skip", root.applyAll) }
                GButton { visible: d && d.kind === "conflict"; text: "Keep both"; onClicked: Data.answerConflict("both", root.applyAll) }
                GButton { visible: d && d.kind === "conflict"; primary: true; text: "Replace"; onClicked: Data.answerConflict("replace", root.applyAll) }

                GButton { visible: d && d.kind === "confirm"; text: "Cancel"; onClicked: Data.closeDialog() }
                GButton { visible: d && d.kind === "confirm"; primary: true; text: d && d.kind === "confirm" ? d.ok : ""; onClicked: Data.acceptDialog() }

                GButton { visible: d && d.kind === "props"; primary: true; text: "Close"; onClicked: Data.closeDialog() }

                GButton { visible: d && d.kind === "openwith"; text: "Cancel"; onClicked: Data.closeDialog() }
                GButton { visible: d && d.kind === "openwith"; primary: true; enabled: Data.apps.length > 0; text: "Open"; onClicked: Data.openWith(Data.apps[root.appSel]) }
            }
        }
    }
}
