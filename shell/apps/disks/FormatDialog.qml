// FormatDialog.qml - modal "Format" card. Erases everything on one volume; the system's password prompt
// (UDisks2 through polkit) is the confirmation.
import QtQuick
import "../.."
import "../games"

Item {
    id: root
    signal closed()

    readonly property var v: Disks.volume
    property string fs: "ext4"
    property var contents: null              // peek of the mount point, when mounted
    readonly property var fsInfo: {
        for (const f of Disks.formats) if (f.id === fs) return f;
        return null;
    }
    readonly property string devName: v ? v.device.replace("/dev/", "") : ""
    readonly property bool valid: v !== null && fsInfo !== null && Disks.busy === ""

    function open() {
        const first = Disks.formats;
        fs = first.length > 0 ? first[0].id : "ext4";
        labelField.text = ""; contents = null;
        if (v && v.mounted) Disks.peek(v.mounts[0], o => { if (o.ok) root.contents = o; });
        visible = true;
        labelField.input.forceActiveFocus();
    }
    Connections { target: Disks; function onSubmitRequested() { if (root.visible) root.submit(); } }
    function close() { if (Disks.busy !== "") return; visible = false; closed(); }    // not while it runs: the progress is here
    function submit() {
        if (!valid) return;
        const vol = v;
        Disks.format(vol, fs, labelField.text.trim(), o => { if (o.ok || o.cancelled) root.close(); });
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
        width: Math.min(520, parent.width - 32)
        height: Math.min(col.implicitHeight + 40, parent.height - 24)
        color: Theme.bg1
        MouseArea { anchors.fill: parent }
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: Disks.danger; size: 12 }

        Flickable {
            anchors.fill: parent
            anchors.margins: 20
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                width: parent.width
                spacing: 12

                Row {
                    spacing: 8
                    Rectangle { width: 6; height: 6; color: Disks.danger; anchors.verticalCenter: parent.verticalCenter }
                    GLabel { text: "Format " + (root.v ? Disks.volName(root.v) : ""); strong: true }
                }
                Rectangle {
                    width: parent.width
                    implicitHeight: warn.implicitHeight + 20
                    color: Qt.rgba(Disks.danger.r, Disks.danger.g, Disks.danger.b, 0.1)
                    border.color: Disks.danger
                    Text {
                        id: warn
                        x: 12; y: 10; width: parent.width - 24
                        wrapMode: Text.WordWrap
                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: Theme.type.body
                        text: root.v ? "This erases everything on " + root.v.device + " (" + Disks.fmt(root.v.size) + (root.v.fs_name ? ", " + root.v.fs_name : "") + "). It cannot be undone."
                                       + (root.v.used ? "\n\nThere is " + Disks.fmt(root.v.used) + " of data on it." : "")
                                       + (root.contents ? "\n\nIncluding: " + root.contents.names.map(n => n.name).join(", ") + (root.contents.total > root.contents.names.length ? " and " + (root.contents.total - root.contents.names.length) + " more" : "") : "")
                                     : ""
                    }
                }
                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Format as" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: Disks.formats
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: root.fs === modelData.id
                                readonly property bool off: false
                                width: ft.implicitWidth + 20; height: 28
                                opacity: off ? 0.4 : 1
                                color: on ? Theme.selection : Theme.field
                                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                                Text { id: ft; anchors.centerIn: parent; text: modelData.name; color: parent.on ? Theme.accent : Theme.fg
                                    font.family: Theme.ui; font.pixelSize: Theme.type.label }
                                MouseArea { anchors.fill: parent; enabled: !parent.off; cursorShape: Qt.PointingHandCursor; onClicked: root.fs = modelData.id }
                            }
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        visible: root.fsInfo !== null && root.fsInfo.bad !== ""
                        text: root.fsInfo ? "Names cannot contain: " + root.fsInfo.bad : ""
                        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                    }
                }
                Column {
                    width: parent.width
                    spacing: 6
                    GLabel { text: "New name (optional)" }
                    GInput {
                        id: labelField
                        width: parent.width
                        placeholder: root.fsInfo ? "up to " + root.fsInfo.label_max + " characters" : ""
                        onEscaped: root.close()
                    }
                }
                BusyBar { width: parent.width }
                Row {
                    spacing: 10
                    anchors.right: parent.right
                    GButton { text: "Cancel"; enabled: Disks.busy === ""; onClicked: root.close() }
                    DButton {
                        solid: true
                        text: Disks.busy === "format" ? "Formatting…" : "Format"
                        enabled: root.valid
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
