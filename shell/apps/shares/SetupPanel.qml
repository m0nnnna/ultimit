// SetupPanel.qml - the one-time setup steps (privileged ones run through pkexec when the user clicks).
// Shown as a banner while something is missing; each step shows done / needed and its own button.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: root
    property bool allDone: !Shares.setupNeeded
    signal passwordRequested()

    implicitHeight: col.implicitHeight + 28
    color: Theme.panel2
    border.color: allDone ? Theme.line : Theme.warn
    border.width: 1

    function stateText(s) {
        return s === "done" ? "Done" : s === "relogin" ? "Log out and in" : s === "unknown" ? "Not verified" : s === "blocked" ? "Waiting" : "Needed";
    }
    function stateTone(s) {
        return s === "done" ? Theme.ok : s === "needed" ? Theme.warn : s === "relogin" || s === "unknown" ? Theme.warn : Theme.dim;
    }

    Column {
        id: col
        x: 16; y: 14
        width: parent.width - 32
        spacing: 0

        Item {
            width: parent.width
            height: 26
            Rectangle { id: dot; width: 6; height: 6; y: 5; color: root.allDone ? Theme.ok : Theme.warn }
            GLabel { x: 14; y: 0; text: root.allDone ? "Setup complete" : "Setup needed before you can share"; strong: true }
        }

        Repeater {
            model: Shares.steps
            delegate: Item {
                id: stepRow
                required property var modelData
                required property int index
                readonly property bool busy: Shares.busy === modelData.id || (modelData.id.startsWith("firewall") && Shares.busy.startsWith("firewall"))
                width: col.width
                height: Config.mobile ? textCol.implicitHeight + actions.height + 28 : Math.max(54, textCol.implicitHeight + 16)

                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }

                Text {
                    id: num
                    x: 0; anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    text: stepRow.index + 1
                    color: stepRow.modelData.state === "done" ? Theme.ok : Theme.dim
                    font.family: Theme.mono; font.pixelSize: 14
                }
                Column {
                    id: textCol
                    anchors { left: num.right; right: Config.mobile ? parent.right : actions.left; rightMargin: Config.mobile ? 0 : 12
                              top: Config.mobile ? parent.top : undefined; topMargin: Config.mobile ? 10 : 0
                              verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
                    spacing: 3
                    Flow {
                        width: parent.width
                        spacing: 10
                        Text {
                            anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter
                            text: stepRow.modelData.label
                            color: stepRow.modelData.state === "blocked" ? Theme.dim : Theme.fg
                            font.family: Theme.ui; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        GChip { anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter; text: root.stateText(stepRow.modelData.state); tone: root.stateTone(stepRow.modelData.state) }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: stepRow.modelData.desc
                        color: Theme.dim
                        font.family: Theme.ui; font.pixelSize: 12
                    }
                }
                Row {
                    id: actions
                    anchors { right: Config.mobile ? undefined : parent.right; left: Config.mobile ? textCol.left : undefined
                              bottom: Config.mobile ? parent.bottom : undefined; bottomMargin: Config.mobile ? 10 : 0
                              verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
                    spacing: 8
                    GLabel {
                        visible: stepRow.modelData.state === "unknown"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Already done"
                        color: markMouse.containsMouse ? Theme.accent : Theme.dim
                        MouseArea {
                            id: markMouse
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Shares.mark(stepRow.modelData.id)
                        }
                    }
                    GButton {
                        visible: stepRow.modelData.extra !== undefined && stepRow.modelData.extra !== ""
                        text: stepRow.modelData.extra || ""
                        enabled: Shares.busy === ""
                        onClicked: Shares.setup("firewall-block")
                    }
                    GButton {
                        primary: stepRow.modelData.state === "needed" || stepRow.modelData.state === "unknown"
                        text: stepRow.busy ? "Working…" : stepRow.modelData.button
                        enabled: Shares.busy === "" && stepRow.modelData.state !== "blocked"
                                 && (stepRow.modelData.id !== "firewall" || Shares.subnet !== "")
                        visible: stepRow.modelData.state !== "relogin"
                                 && (stepRow.modelData.state !== "done" || stepRow.modelData.id === "password")
                        onClicked: {
                            const id = stepRow.modelData.id;
                            if (id === "password") root.passwordRequested();
                            else if (id === "firewall") Shares.setup("firewall-allow");
                            else Shares.setup(id);
                        }
                    }
                }
            }
        }
    }
}
