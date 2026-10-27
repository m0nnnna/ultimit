// PolkitDialog.qml - modal "AUTHENTICATION REQUIRED" dialog for the polkit agent.
// Overlay layer, full-screen dim backdrop, exclusive keyboard focus. Driven by an AuthFlow
// (or the demo stand-in): message, actionId, identities/selectedIdentity, isResponseRequired,
// inputPrompt, supplementaryMessage/IsError, failed, submit(), cancelAuthenticationRequest().
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.."
import "../../components"
import "../accessory"

PanelWindow {
    id: win

    property string screenName: ""
    property var flow: null

    readonly property bool shown: flow !== null && Config.isUiScreen(screenName)
    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-polkit"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string errorText: {
        if (!flow) return "";
        if (flow.supplementaryMessage !== "" && flow.supplementaryIsError) return flow.supplementaryMessage;
        if (flow.failed) return "Authentication failed. Try again.";
        return "";
    }
    readonly property string infoText: (flow && flow.supplementaryMessage !== "" && !flow.supplementaryIsError) ? flow.supplementaryMessage : ""
    // Quickshell's AuthFlow exposes no polkit details (no program/command_line), only message + actionId.
    // pkexec puts the program path in the message, so spot a shell there: approving one is root access.
    readonly property bool runsShell: flow !== null && flow.actionId === "org.freedesktop.policykit.exec"
        && /(^|[\s"'`\u201c\u2018])(\/usr)?\/bin\/(ba)?sh(["'`\u201d\u2019]|\s|$)/.test(flow.message)
    readonly property bool busy: flow !== null && !flow.isResponseRequired

    function submit() {
        if (!flow || !flow.isResponseRequired) return;
        const v = pw.text;
        pw.text = "";
        flow.submit(v);
    }
    function cancel() { if (flow) flow.cancelAuthenticationRequest(); }

    onShownChanged: if (shown) { pw.text = ""; pw.forceActiveFocus(); }
    Connections {
        target: win.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() { pw.text = ""; }
        function onIsResponseRequiredChanged() { if (win.flow && win.flow.isResponseRequired) pw.forceActiveFocus(); }
    }

    // dim backdrop; swallows clicks (no click-outside dismiss: auth is explicit)
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: win.shown ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 440
        height: col.implicitHeight + 40
        color: Theme.panel
        border.width: 1
        border.color: Theme.lineStrong
        opacity: win.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
        MouseArea { anchors.fill: parent }
        Brackets {}

        Keys.onPressed: event => { if (event.key === Qt.Key_Escape) { win.cancel(); event.accepted = true; } }

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            Text {
                text: "AUTHENTICATION REQUIRED"
                color: Theme.accent
                font.family: Theme.display; font.pixelSize: Theme.ds(13); font.letterSpacing: Theme.dt(2)
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }

            Text {
                Layout.fillWidth: true
                text: win.flow ? win.flow.message : ""
                wrapMode: Text.Wrap
                color: Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 14
            }
            Text {
                Layout.fillWidth: true
                text: win.flow ? win.flow.actionId : ""
                wrapMode: Text.WrapAnywhere  // ids can be long with no break points; elide would hide what is asking
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Text {
                Layout.fillWidth: true
                visible: win.runsShell
                text: "Runs a shell as administrator \u2014 only approve if you just asked for this"
                wrapMode: Text.Wrap
                color: Theme.bad
                font.family: Theme.mono; font.pixelSize: 11
            }

            // identity picker (only when more than one)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: win.flow !== null && win.flow.identities.length > 1
                Text {
                    text: "AUTHENTICATE AS"
                    color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4
                }
                Repeater {
                    model: win.flow ? win.flow.identities : []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: win.flow !== null && win.flow.selectedIdentity !== undefined && win.flow.selectedIdentity !== null && win.flow.selectedIdentity.string === modelData.string
                        Layout.fillWidth: true
                        height: 30
                        color: (sel || idMouse.containsMouse) ? Theme.panel2 : "transparent"
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        border.width: 1
                        border.color: sel ? Theme.accent : Theme.line
                        Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        Rectangle { x: 0; width: 2; height: parent.height; color: Theme.accent; visible: sel }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12; width: parent.width - 24; elide: Text.ElideRight
                            text: modelData.displayName && modelData.displayName !== modelData.string
                                  ? modelData.displayName + "  (" + modelData.string + ")" : modelData.string
                            color: Theme.fg
                            font.family: Theme.ui; font.pixelSize: 13
                        }
                        MouseArea {
                            id: idMouse
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.flow.selectedIdentity = modelData
                        }
                    }
                }
            }

            // password prompt
            Text {
                text: win.flow && win.flow.inputPrompt !== "" ? win.flow.inputPrompt.replace(/:\s*$/, "").toUpperCase() : "PASSWORD"
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4
            }
            Rectangle {
                Layout.fillWidth: true
                height: 34
                color: Theme.panel2
                border.width: 1
                border.color: win.errorText !== "" ? Theme.bad : (pw.activeFocus ? Theme.accent : Theme.line)
                Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                opacity: win.busy ? 0.5 : 1
                Text {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    text: "›"; color: Theme.accent
                    font.family: Theme.mono; font.pixelSize: 16
                }
                TextInput {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: 28; anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: (win.flow && win.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    enabled: !win.busy
                    color: Theme.fg
                    selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                    font.family: Theme.ui; font.pixelSize: 14
                    clip: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) { win.cancel(); event.accepted = true; }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { win.submit(); event.accepted = true; }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: win.errorText !== ""
                text: win.errorText
                wrapMode: Text.Wrap
                color: Theme.bad
                font.family: Theme.mono; font.pixelSize: 11
            }
            Text {
                Layout.fillWidth: true
                visible: win.infoText !== ""
                text: win.infoText
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 11
            }
            Text {
                visible: win.busy
                text: "WORKING..."
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Item { Layout.fillWidth: true }
                ChamferButton { text: "Cancel"; onClicked: win.cancel() }
                ChamferButton { text: "Authenticate"; primary: true; opacity: win.busy ? 0.5 : 1; onClicked: win.submit() }
            }
        }
    }
}
