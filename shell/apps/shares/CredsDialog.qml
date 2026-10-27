// CredsDialog.qml - modal sign-in card for a computer or share that needs a password: user, domain (under
// "Advanced"), password (masked), "Remember password". The password goes to the helper's stdin only and every
// field is cleared the moment the dialog closes.
import QtQuick
import "../.."
import "../games"

Item {
    id: root
    signal closed()

    property bool advanced: false
    property bool remember: true
    readonly property var req: Shares.credReq
    readonly property bool valid: user.text.trim() !== "" && pw.text.length > 0

    function open() {
        pw.text = ""; domain.text = req && req.domain ? req.domain : "";
        user.text = req && req.user ? req.user : "";
        remember = true; advanced = domain.text !== "" && domain.text.toUpperCase() !== "WORKGROUP";
        visible = true;
        (user.text === "" ? user : pw).input.forceActiveFocus();
    }
    function clear() { pw.text = ""; user.text = ""; domain.text = ""; }
    function close() { clear(); visible = false; Shares.credReq = null; closed(); }
    function submit() {
        if (!visible || !valid) return;
        const u = user.text.trim(), d = domain.text.trim(), p = pw.text, r = remember;
        clear(); visible = false;                 // fields are empty before the helper starts
        closed();
        Shares.submitCreds(u, d, p, r);
    }

    visible: false
    anchors.fill: parent
    z: 55
    focus: visible
    Keys.onEscapePressed: root.close()

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(460, parent.width - 32)
        height: col.implicitHeight + 40
        color: Theme.bg1
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
                GLabel { text: "Sign in"; strong: true }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.family: Theme.ui; font.pixelSize: Theme.type.body
                text: root.req ? (root.req.kind === "browse" ? "“" + root.req.name + "” needs a user name and password to show its shares."
                                                              : "“" + root.req.name + "” needs a user name and password.") : ""
            }
            Text {
                visible: root.req !== null && root.req.wrong === true
                width: parent.width
                color: Theme.bad
                font.family: Theme.ui; font.pixelSize: Theme.type.label
                text: "That user name or password was not accepted. Try again."
            }
            Column {
                width: parent.width
                spacing: 6
                GLabel { text: "User name" }
                GInput { id: user; width: parent.width; onAccepted: pw.input.forceActiveFocus(); onEscaped: root.close() }
            }
            Column {
                width: parent.width
                spacing: 6
                GLabel { text: "Password" }
                GInput {
                    id: pw
                    width: parent.width
                    Component.onCompleted: { input.echoMode = TextInput.Password; input.passwordCharacter = "•"; }
                    onAccepted: root.submit()
                    onEscaped: root.close()
                }
            }
            GLabel {
                text: (root.advanced ? "▾ " : "▸ ") + "Advanced"
                color: advMouse.containsMouse ? Theme.accent : Theme.dim
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                MouseArea { id: advMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.advanced = !root.advanced }
            }
            Column {
                visible: root.advanced
                width: parent.width
                spacing: 6
                GLabel { text: "Domain or workgroup" }
                GInput { id: domain; width: parent.width; placeholder: "WORKGROUP"; onAccepted: root.submit(); onEscaped: root.close() }
            }
            GToggle {
                width: parent.width
                label: "Remember password"
                checked: root.remember
                onToggled: v => root.remember = v
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                text: root.remember ? "Saved in your keyring, so you are not asked again. If the keyring is locked the password is used once and not saved."
                                    : "Used for this connection only."
            }
            Row {
                spacing: 10
                anchors.right: parent.right
                GButton { text: "Cancel"; onClicked: root.close() }
                GButton { primary: true; text: "Sign in"; enabled: root.valid; onClicked: root.submit() }
            }
        }
    }
}
