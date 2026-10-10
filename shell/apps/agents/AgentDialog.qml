// AgentDialog.qml - modal prompt for the BlueZ pairing agent / NetworkManager secret agent.
// Same look and focus handling as apps/polkit/PolkitDialog.qml: overlay layer, dim backdrop,
// exclusive keyboard focus, Enter submits, Escape cancels. Shows AgentPrompt.current.
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

    // The prompt being shown, only replaced when its content really changes (a newly queued
    // prompt behind it must not reset what the user is typing).
    property var cur: null
    property string curKey: ""
    function sync() {
        const p = AgentPrompt.current;
        const k = p ? p.id + "|" + p.kind + "|" + JSON.stringify(p.data) : "";
        if (k !== curKey) { curKey = k; cur = p; }
    }
    Connections { target: AgentPrompt; function onSerialChanged() { win.sync(); } }
    Component.onCompleted: sync()

    readonly property string kind: cur ? cur.kind : ""
    readonly property var pd: cur ? cur.data : ({})
    readonly property var fields: pd.fields || []
    readonly property bool hasFields: fields.length > 0
    readonly property bool anySecret: fields.some(f => f.secret)
    property bool reveal: false

    readonly property bool shown: cur !== null && Config.isUiScreen(screenName)
    visible: shown
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-agents"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var titles: ({
        confirm: "CONFIRM PAIRING", pin: "PAIRING PIN", passkey: "PAIRING PASSKEY",
        display: "PAIRING CODE", authorize: "ALLOW CONNECTION",
        wifi: "WI-FI PASSWORD", "8021x": "NETWORK LOGIN", vpn: "VPN LOGIN"
    })
    readonly property string title: pd.title || titles[kind] || "REQUEST"
    readonly property string primaryText: ({ confirm: "Confirm", authorize: "Allow", display: "Done",
                                              wifi: "Connect", "8021x": "Connect", vpn: "Connect" })[kind] || "OK"
    readonly property string cancelText: ({ confirm: "Reject", authorize: "Deny" })[kind] || "Cancel"

    // ---- validity ----
    property int fieldsRev: 0     // bumped on every keystroke so `valid` re-evaluates
    readonly property bool valid: {
        fieldsRev;
        if (!hasFields) return true;
        for (let i = 0; i < fields.length; ++i) {
            const it = rep.itemAt(i);
            if (!it) return false;
            const v = it.val;
            const f = fields[i];
            if (v.length < (f.minLen !== undefined ? f.minLen : 1)) return false;
            if (f.digits && (!/^[0-9]+$/.test(v) || parseInt(v, 10) > 999999)) return false;
        }
        return true;
    }

    // Guard so a key typed for something else just before the prompt appears can't answer it.
    property bool armed: false
    Timer { id: armTimer; interval: 450; onTriggered: win.armed = true }
    onCurKeyChanged: {
        armed = false; reveal = false;
        if (shown) { armTimer.restart(); focusTimer.restart(); }
    }
    onShownChanged: if (shown) { armed = false; armTimer.restart(); focusTimer.restart(); }
    Timer { id: focusTimer; interval: 30; onTriggered: win.focusFirst() }
    function focusFirst() {
        const it = rep.itemAt(0);
        if (it) it.focusInput(); else panel.forceActiveFocus();
    }

    function submit() {
        if (!cur || !armed || !valid) return;
        const vals = {};
        for (let i = 0; i < fields.length; ++i) vals[fields[i].key] = rep.itemAt(i).val;
        AgentPrompt.answer(true, vals);
    }
    function cancel() {
        if (!cur || !armed) return;
        if (kind === "display") AgentPrompt.answer(true, {});
        else AgentPrompt.answer(false, {});
    }
    // Escape is honoured immediately (never trap the user), only accepting is delayed.
    function dismiss() { if (cur) { armed = true; cancel(); } }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: win.shown ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Config.dur(180); easing.type: Easing.OutCubic } }
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
        Behavior on opacity { NumberAnimation { duration: Config.dur(180); easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }
        Brackets {}

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { win.dismiss(); event.accepted = true; }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { win.submit(); event.accepted = true; }
        }

        ColumnLayout {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            Text {
                text: win.title
                color: Theme.accent
                font.family: Theme.display; font.pixelSize: 13; font.letterSpacing: 2
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: win.pd.message || ""
                wrapMode: Text.Wrap
                color: Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 14
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: win.pd.detail || ""
                elide: Text.ElideMiddle
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
            }

            // the code to compare / type on the other device
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: win.pd.code || ""
                horizontalAlignment: Text.AlignHCenter
                color: Theme.accent
                font.family: Theme.mono; font.pixelSize: 38; font.letterSpacing: 8
            }
            Text {
                Layout.fillWidth: true
                visible: win.kind === "display" && win.pd.entered !== undefined && win.pd.entered !== null
                text: "ENTERED " + (win.pd.entered || 0)
                horizontalAlignment: Text.AlignHCenter
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4
            }

            Repeater {
                id: rep
                model: win.fields
                onItemAdded: win.fieldsRev++
                delegate: ColumnLayout {
                    id: fd
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 4
                    readonly property string val: inp.text
                    function focusInput() { inp.forceActiveFocus(); }
                    Text {
                        text: (fd.modelData.label || fd.modelData.key).toUpperCase()
                        color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        color: Theme.panel2
                        border.width: 1
                        border.color: (win.pd.retry && fd.index === 0) ? Theme.bad : (inp.activeFocus ? Theme.accent : Theme.line)
                        Text {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            text: "›"; color: Theme.accent
                            font.family: Theme.mono; font.pixelSize: 16
                        }
                        TextInput {
                            id: inp
                            anchors.fill: parent
                            anchors.leftMargin: 28; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: (fd.modelData.secret && !win.reveal) ? TextInput.Password : TextInput.Normal
                            passwordCharacter: "•"
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                                | (fd.modelData.digits ? Qt.ImhDigitsOnly : 0)
                            maximumLength: fd.modelData.max || 256
                            text: fd.modelData.value || ""
                            color: Theme.fg
                            selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                            font.family: Theme.ui; font.pixelSize: 14
                            clip: true
                            onTextChanged: win.fieldsRev++
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) { win.dismiss(); event.accepted = true; }
                                else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                                    const back = event.key === Qt.Key_Backtab || event.key === Qt.Key_Up;
                                    const n = win.fields.length;
                                    rep.itemAt((fd.index + (back ? n - 1 : 1)) % n).focusInput();
                                    event.accepted = true;
                                }
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (fd.index < win.fields.length - 1) rep.itemAt(fd.index + 1).focusInput();
                                    else win.submit();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }
            }

            // show-password toggle
            Item {
                Layout.fillWidth: true
                height: 20
                visible: win.anySecret
                Rectangle {
                    id: box
                    width: 14; height: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: "transparent"
                    border.width: 1; border.color: Theme.lineStrong
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; color: Theme.accent; visible: win.reveal }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 24
                    text: "SHOW PASSWORD"
                    color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.reveal = !win.reveal
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !!win.pd.retry
                text: "The previous password was not accepted."
                wrapMode: Text.Wrap
                color: Theme.bad
                font.family: Theme.mono; font.pixelSize: 11
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Item { Layout.fillWidth: true }
                ChamferButton {
                    visible: win.kind !== "display"
                    text: win.cancelText
                    onClicked: win.dismiss()
                }
                ChamferButton {
                    text: win.primaryText
                    primary: true
                    opacity: win.valid ? 1 : 0.5
                    onClicked: { win.armed = true; win.submit(); }
                }
            }
        }
    }
}
