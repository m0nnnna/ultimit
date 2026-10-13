// PasswordDialog.qml - modal "network password" card: password + confirm (masked). The text goes to the helper's
// stdin only (never argv, never logged) and both fields are cleared right after submitting.
import QtQuick
import "../.."
import "../games"

Item {
    id: root
    signal closed()

    readonly property bool match: pw1.text === pw2.text
    readonly property bool valid: pw1.text.length > 0 && match
    property string hint: pw2.text.length > 0 && !match ? "The two passwords are different." : ""

    function open() {
        pw1.text = ""; pw2.text = "";
        visible = true;
        pw1.input.forceActiveFocus();
    }
    function clear() { pw1.text = ""; pw2.text = ""; }
    function close() { clear(); visible = false; closed(); }
    function submit() {
        if (!visible || !valid) return;
        const pw = pw1.text;
        close();                    // fields are empty before the helper even starts
        Shares.setPassword(pw);
    }

    visible: false
    anchors.fill: parent
    z: 50
    focus: visible
    Keys.onEscapePressed: root.close()

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(460, parent.width - 32)
        height: col.implicitHeight + 40
        color: Theme.bg1
        border.color: Theme.lineStrong
        border.width: 1
        MouseArea { anchors.fill: parent }
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: Theme.accent; size: 12 }

        Column {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12
            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                GLabel { text: "Network password"; strong: true }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.family: Theme.ui; font.pixelSize: 12
                text: "This is the password other computers use to open your shares. It can differ from your login password. It is stored by Samba, not by SHARES."
            }
            Column {
                width: parent.width
                spacing: 6
                GLabel { text: "Password" }
                GInput {
                    id: pw1
                    width: parent.width
                    Component.onCompleted: { input.echoMode = TextInput.Password; input.passwordCharacter = "•"; }
                    onAccepted: pw2.input.forceActiveFocus()
                    onEscaped: root.close()
                }
            }
            Column {
                width: parent.width
                spacing: 6
                GLabel { text: "Confirm password" }
                GInput {
                    id: pw2
                    width: parent.width
                    Component.onCompleted: { input.echoMode = TextInput.Password; input.passwordCharacter = "•"; }
                    onAccepted: root.submit()
                    onEscaped: root.close()
                }
            }
            Text {
                visible: root.hint !== ""
                width: parent.width
                color: Theme.warn
                font.family: Theme.ui; font.pixelSize: 11
                text: root.hint
            }
            Row {
                spacing: 10
                anchors.right: parent.right
                GButton { text: "Cancel"; onClicked: root.close() }
                GButton { primary: true; text: "Set password"; enabled: root.valid; onClicked: root.submit() }
            }
        }
    }
}
