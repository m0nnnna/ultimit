// InstallerSurface.qml - one full-screen window per monitor: the greeter's wallpaper art, the
// [ ULTIMIT ] wordmark, and (on the first monitor) the setup panel with the current page.
// Plain words throughout: it's for people who have never installed an operating system.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win
    required property var ctl
    color: Theme.bg1
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-installer"
    WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool primary: screen !== null && Quickshell.screens.length > 0
                                    && screen.name === Quickshell.screens[0].name
    readonly property real pw: Math.min(720, width - 64)

    Connections {
        target: win.ctl
        function onUsernameChanged() { if (userField.text !== win.ctl.username) userField.text = win.ctl.username; }
        function onHostnameChanged() { if (hostField.text !== win.ctl.hostname) hostField.text = win.ctl.hostname; }
    }

    WallpaperArt { anchors.fill: parent; active: win.visible; animate: Config.motion }
    Rectangle { anchors.fill: parent; color: Theme.light ? "#50ffffff" : "#99000000" }

    // top-left: where we are
    Row {
        x: 30; y: 26; spacing: 10
        Rectangle { width: 8; height: 8; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
        Text {
            text: "ULTIMIT SETUP" + (ctl.steps.indexOf(ctl.page) >= 0 ? "  ·  STEP " + ctl.stepNo + " OF " + ctl.steps.length : "")
                  + (ctl.dry ? "  ·  TRY-OUT (NOTHING IS INSTALLED)" : "")
            color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 3.3
        }
    }
    Wordmark {
        anchors.right: parent.right; anchors.rightMargin: 30
        anchors.bottom: parent.bottom; anchors.bottomMargin: 28
    }

    // ================= the panel =================
    Item {
        id: panel
        visible: win.primary
        width: win.pw
        height: Math.min(body.implicitHeight + 48, win.height - 120)
        anchors.centerIn: parent
        Rectangle { anchors.fill: parent; color: Theme.panel; border.width: 1; border.color: Theme.line; Brackets {} }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 24
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: flick.width
                spacing: 16

                // ---------- welcome ----------
                ColumnLayout {
                    visible: ctl.page === "welcome"
                    Layout.fillWidth: true
                    spacing: 14
                    Emblem { Layout.alignment: Qt.AlignHCenter; size: 54; color: Theme.fg }
                    Heading { text: "Welcome to Ultimit"; Layout.alignment: Qt.AlignHCenter }
                    Body { text: "This puts Ultimit on this computer. It takes about 15 minutes, and it needs the internet (a network cable, or Wi-Fi on the next step)." }
                    Note {
                        title: "Keeping Windows?"
                        text: "Ultimit can go next to Windows, in free space on the drive. Make that space in Windows first: Disk Management › right-click the Windows (C:) partition › Shrink Volume, by 50 GB or more. If you haven't, turn the PC off now, do that, and start this again."
                    }
                    Buttons {
                        ChamferButton { text: "Use Ubuntu's text installer"; onClicked: ctl.textInstaller() }
                        Item { Layout.fillWidth: true }
                        ChamferButton { id: startBtn; primary: true; text: ctl.netChecking ? "Checking the internet…" : "Start"; onClicked: ctl.next(); focus: true }
                    }
                }

                // ---------- network ----------
                ColumnLayout {
                    visible: ctl.page === "network"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: ctl.net.online ? "You're online" : "Connect to the internet" }
                    Body {
                        text: ctl.net.online ? "Ready for the next step."
                            : (ctl.net.wifi || []).length > 0 ? "Plug in a network cable, or pick your Wi-Fi network below."
                            : "Plug in a network cable. (No Wi-Fi was found on this computer.)"
                    }
                    ColumnLayout {
                        visible: !ctl.net.online && (ctl.net.wifi || []).length > 0
                        Layout.fillWidth: true
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Wi-Fi networks"; Layout.fillWidth: true }
                            ChamferButton { text: ctl.scanning ? "Looking…" : "Look again"; onClicked: ctl.scan() }
                        }
                        Repeater {
                            model: ctl.networks.slice(0, 8)
                            delegate: Choice {
                                required property var modelData
                                Layout.fillWidth: true
                                title: modelData.ssid
                                tag: "▮".repeat(modelData.bars) + "▯".repeat(4 - modelData.bars) + (modelData.secure ? "  🔒" : "")
                                selected: ctl.ssid === modelData.ssid
                                onPicked: { ctl.ssid = modelData.ssid; wifiPw.text = ""; wifiPw.input.forceActiveFocus(); }
                            }
                        }
                        Body { visible: !ctl.scanning && ctl.networks.length === 0; text: "No networks found yet."; dim: true }
                        Field {
                            id: wifiPw
                            visible: ctl.ssid !== ""
                            Layout.fillWidth: true
                            label: "Password for " + ctl.ssid
                            secret: true
                            onTextChanged: ctl.wifiPassword = text
                            onAccepted: ctl.connect()
                        }
                    }
                    Problem { text: ctl.error }
                    Buttons {
                        ChamferButton { text: "Back"; onClicked: ctl.back() }
                        Item { Layout.fillWidth: true }
                        ChamferButton {
                            visible: !ctl.net.online && ctl.ssid !== ""
                            text: ctl.connecting ? "Connecting…" : "Connect"
                            onClicked: ctl.connect()
                        }
                        ChamferButton { primary: true; text: "Next"; enabled: !!ctl.net.online; opacity: enabled ? 1 : .4; onClicked: ctl.next() }
                    }
                }

                // ---------- disk ----------
                ColumnLayout {
                    visible: ctl.page === "disk"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "Where should Ultimit go?" }
                    Body { visible: !ctl.disksLoaded; text: "Looking at the drives…"; dim: true }
                    Body { visible: ctl.disksLoaded && ctl.disks.length === 0; text: "No drive was found to install on." }
                    Repeater {
                        model: ctl.disks
                        delegate: Choice {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            enabled: !modelData.boot
                            title: modelData.model + "  ·  " + ctl.gb(modelData.size)
                            sub: modelData.boot ? "This is the USB stick Ultimit started from."
                                : modelData.empty ? "Empty."
                                : (modelData.windows ? "Windows is on this drive" : modelData.linux ? "Linux is on this drive"
                                   : modelData.windowsFiles ? "Has files from Windows on it" : "Has files on it")
                                  + (modelData.free > 1e9 ? "  ·  " + ctl.gb(modelData.free) + " free space" : "")
                            tag: modelData.boot ? "USB STICK" : modelData.usb ? "USB" : ""
                            selected: ctl.diskIndex === index
                            onPicked: ctl.pickDisk(index)
                        }
                    }
                    ColumnLayout {
                        visible: ctl.disk !== null
                        Layout.fillWidth: true
                        spacing: 8
                        Label { text: "What to do with it" }
                        Choice {
                            visible: !!ctl.disk && ctl.disk.canAlongside
                            Layout.fillWidth: true
                            title: "Use the free space, keep " + (ctl.disk && ctl.disk.windows ? "Windows" : "what's there")
                            sub: ctl.disk ? "Ultimit goes into the " + ctl.gb(ctl.disk.free) + " of free space. Nothing else on the drive is touched, and you choose Windows or Ultimit each time the PC starts." : ""
                            selected: ctl.mode === "alongside"
                            onPicked: ctl.mode = "alongside"
                        }
                        Choice {
                            Layout.fillWidth: true
                            danger: !!ctl.disk && !ctl.disk.empty
                            title: ctl.disk && ctl.disk.empty ? "Use the whole drive" : "Erase the drive and use all of it"
                            sub: ctl.disk && !ctl.disk.empty ? "Everything on it is deleted" + (ctl.disk.windows ? ", Windows included." : ".") : "Ultimit gets the whole drive."
                            selected: ctl.mode === "erase"
                            onPicked: ctl.mode = "erase"
                        }
                        Note {
                            visible: !!ctl.disk && ctl.disk.windows && !ctl.disk.canAlongside
                            title: "To keep Windows on this drive"
                            text: "There isn't enough free space next to it (Ultimit needs 25 GB, better 50 or more). In Windows: Disk Management › right-click C: › Shrink Volume. Then start this again."
                        }
                        Note {
                            visible: !!ctl.disk && ctl.disk.bitlocker
                            warn: true
                            title: "Windows drive encryption (BitLocker) is on"
                            text: "Windows may ask for your BitLocker recovery key the next time it starts. Make sure you have it (aka.ms/myrecoverykey) before going on."
                        }
                    }
                    Problem { text: ctl.error }
                    Buttons {
                        ChamferButton { text: "Back"; onClicked: ctl.back() }
                        Item { Layout.fillWidth: true }
                        ChamferButton { primary: true; text: "Next"; enabled: ctl.disk !== null && ctl.mode !== ""; opacity: enabled ? 1 : .4; onClicked: ctl.next() }
                    }
                }

                // ---------- account ----------
                ColumnLayout {
                    visible: ctl.page === "account"
                    onVisibleChanged: if (visible) Qt.callLater(() => nameField.input.forceActiveFocus())
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "About you" }
                    Body { text: "This is how you'll log in to Ultimit." ; dim: true }
                    Field {
                        id: nameField
                        Layout.fillWidth: true
                        label: "Your name"
                        onTextChanged: ctl.realname = text
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Field {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            id: userField
                            label: "User name"
                            hint: "Small letters, no spaces"
                            onTextChanged: if (text !== ctl.username) { ctl.userEdited = true; ctl.username = text; }
                        }
                        Field {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            id: hostField
                            label: "Computer name"
                            hint: "How it shows on your network"
                            onTextChanged: if (text !== ctl.hostname) { ctl.hostEdited = true; ctl.hostname = text; }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Field {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            label: "Password"
                            secret: true
                            onTextChanged: ctl.password = text
                        }
                        Field {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            label: "Password again"
                            secret: true
                            onTextChanged: ctl.password2 = text
                            onAccepted: ctl.next()
                        }
                    }
                    Body {
                        visible: ctl.realname !== "" && ctl.accountProblem !== ""
                        text: ctl.accountProblem; bad: true
                    }
                    Buttons {
                        ChamferButton { text: "Back"; onClicked: ctl.back() }
                        Item { Layout.fillWidth: true }
                        ChamferButton { primary: true; text: "Next"; enabled: ctl.accountProblem === ""; opacity: enabled ? 1 : .4; onClicked: ctl.next() }
                    }
                }

                // ---------- confirm ----------
                ColumnLayout {
                    visible: ctl.page === "confirm"
                    Layout.fillWidth: true
                    spacing: 12
                    Heading { text: "Ready to install" }
                    Note {
                        warn: ctl.mode === "erase" && !!ctl.disk && !ctl.disk.empty
                        title: ctl.disk ? ctl.disk.model + "  ·  " + ctl.gb(ctl.disk.size) : ""
                        text: !ctl.disk ? ""
                            : ctl.mode === "alongside" ? "Ultimit goes into the " + ctl.gb(ctl.disk.free) + " of free space. " + (ctl.disk.windows ? "Windows" : "What's on the drive") + " stays as it is."
                            : ctl.disk.empty ? "Ultimit gets the whole drive."
                            : "EVERYTHING on this drive will be erased" + (ctl.disk.windows ? ", Windows included" : "") + ". This can't be undone."
                    }
                    Choice {
                        visible: ctl.mode === "erase" && !!ctl.disk && !ctl.disk.empty
                        Layout.fillWidth: true
                        danger: true
                        title: (ctl.understood ? "☑" : "☐") + "  I understand: everything on this drive will be erased"
                        selected: ctl.understood
                        onPicked: ctl.understood = !ctl.understood
                    }
                    Body { text: "You'll log in as " + ctl.realname.trim() + " (" + ctl.username + ") on " + ctl.hostname + "." + (ctl.wifi ? " Wi-Fi: " + ctl.wifi.ssid + "." : ""); dim: true }
                    Body { text: "Keep the computer plugged in. It restarts once at the end."; dim: true }
                    Problem { text: ctl.error }
                    Buttons {
                        ChamferButton { text: "Back"; onClicked: ctl.back() }
                        Item { Layout.fillWidth: true }
                        ChamferButton {
                            primary: true; text: "Install Ultimit"
                            enabled: ctl.mode !== "erase" || !ctl.disk || ctl.disk.empty || ctl.understood
                            opacity: enabled ? 1 : .4
                            onClicked: ctl.next()
                        }
                    }
                }

                // ---------- installing ----------
                ColumnLayout {
                    visible: ctl.page === "installing"
                    Layout.fillWidth: true
                    spacing: 14
                    Heading { text: "Installing Ultimit" }
                    Body { text: (ctl.stepText || "Working") + "…" }
                    Item {
                        Layout.fillWidth: true; height: 3
                        Rectangle { anchors.fill: parent; color: Theme.line }
                        Rectangle {
                            id: sweep
                            height: parent.height; width: parent.width * .28; color: Theme.accent
                            property real t: 0
                            x: (parent.width - width) * (.5 + .5 * Math.sin(t))
                            NumberAnimation on t { from: 0; to: Math.PI * 2; duration: Config.dur(Theme.motion.ambient * 3); loops: Animation.Infinite; running: ctl.page === "installing" && Config.motion }
                        }
                    }
                    Body { text: "This takes 10 to 20 minutes, longer on a slow connection. Keep the computer plugged in and on."; dim: true }
                }

                // ---------- done ----------
                ColumnLayout {
                    visible: ctl.page === "done"
                    Layout.fillWidth: true
                    spacing: 14
                    Emblem { Layout.alignment: Qt.AlignHCenter; size: 54; color: Theme.ok }
                    Heading { text: "Ultimit is installed"; Layout.alignment: Qt.AlignHCenter }
                    Body { text: "Take out the USB stick, then press Restart. Log in with the password you chose; for a few minutes after that, Ultimit finishes adding its apps in the background. (Steam installs from GAMES, where it asks you to accept Valve's licence.)" }
                    Buttons {
                        Item { Layout.fillWidth: true }
                        ChamferButton { primary: true; text: "Restart"; onClicked: ctl.restart() }
                    }
                }

                // ---------- failed ----------
                ColumnLayout {
                    visible: ctl.page === "failed"
                    Layout.fillWidth: true
                    spacing: 14
                    Heading { text: "The install stopped" }
                    Body { text: (ctl.error || "Something went wrong.") + " Nothing was changed on drives you didn't choose. Show the details to see what happened (a photo of that screen helps whoever helps you)."; bad: true }
                    Buttons {
                        Item { Layout.fillWidth: true }
                        ChamferButton { text: "Show the details"; onClicked: ctl.details() }
                    }
                }
            }
        }
    }

    // ---- small pieces ----
    component Heading: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.fg
        font.family: Theme.display; font.pixelSize: 24; font.letterSpacing: 1.5
    }
    component Body: Text {
        property bool dim: false
        property bool bad: false
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: bad ? Theme.bad : dim ? Theme.dim : Theme.fg
        font.family: Theme.ui; font.pixelSize: 15
        lineHeight: 1.15
    }
    component Label: Text {
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2.4
        text: ""
        Component.onCompleted: text = text.toUpperCase()
    }
    component Note: Rectangle {
        property string title: ""
        property string text: ""
        property bool warn: false
        Layout.fillWidth: true
        implicitHeight: noteCol.implicitHeight + 24
        color: Theme.panel2
        border.width: 1; border.color: warn ? Theme.bad : Theme.lineStrong
        Rectangle { width: 3; height: parent.height; color: parent.warn ? Theme.bad : Theme.warn }
        Column {
            id: noteCol
            x: 16; y: 12; width: parent.width - 32
            spacing: 6
            Text { width: parent.width; wrapMode: Text.WordWrap; text: parent.parent.title; color: parent.parent.warn ? Theme.bad : Theme.warn
                   font.family: Theme.ui; font.pixelSize: 15; font.weight: Font.DemiBold; visible: text !== "" }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: parent.parent.text; color: Theme.fg
                   font.family: Theme.ui; font.pixelSize: 14; lineHeight: 1.15 }
        }
    }
    component Problem: Text {
        visible: text !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.bad
        font.family: Theme.ui; font.pixelSize: 14
    }
    component Buttons: RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 12
    }
}
