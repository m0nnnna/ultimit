// ManageDialog.qml - modal card for partition management: create | resize | delete | table | label.
// The destructive ones (resize, delete, table) get a red button and a warning; the system's password prompt
// (UDisks2 through polkit) is the confirmation. The size ones use a slider and a field in GB (base 1000).
import QtQuick
import "../.."
import "../games"

Item {
    id: root
    signal closed()

    property string mode: "create"
    readonly property var d: Disks.drive
    readonly property var v: Disks.volume
    readonly property var gap: Disks.freeSeg
    property var contents: null
    property string fs: "ext4"
    property string kind: "gpt"
    property real bytes: 0

    readonly property bool destructive: mode === "resize" || mode === "delete" || mode === "table"
    readonly property var rz: v && v.manage ? v.manage.resize : null
    readonly property real lo: mode === "create" ? 1048576 : rz ? rz.min : 0
    readonly property real hi: mode === "create" ? (gap && gap.create ? gap.create.max : 0) : rz ? rz.max : 0
    readonly property string devName: v ? v.device.replace("/dev/", "") : ""
    readonly property var fsInfo: { for (const f of Disks.formats) if (f.id === fs) return f; return null; }
    readonly property bool sizeOk: mode === "create" ? hi >= 1048576 && bytes >= 1048576
        : mode === "resize" ? Math.abs(bytes - (v ? v.size : 0)) >= 1048576 && bytes >= lo && bytes <= hi : true
    readonly property string labelErr: {
        if (mode === "create" && fs !== "none" && fsInfo) {
            const l = nameField.text, n = l.length;
            if (n > fsInfo.label_max) return "At most " + fsInfo.label_max + " characters for this file system.";
        }
        if (mode === "label" && v && v.fs) {
            const f = Disks.formats.find(x => x.id === v.fs);
            if (f && nameField.text.length > f.label_max) return "At most " + f.label_max + " characters for " + v.fs_name + ".";
        }
        return "";
    }
    readonly property bool valid: Disks.busy === "" && sizeOk && labelErr === ""
    readonly property string verb: ({ create: "Create", resize: "Resize", delete: "Delete", table: "Erase drive", label: "Save" })[mode]

    function setBytes(b) {
        bytes = Math.max(lo, Math.min(hi, b));
    }
    function open(m) {
        mode = m;
        nameField.text = ""; contents = null; sizeField.text = ""; kind = "gpt";
        const first = Disks.formats;
        fs = first.length > 0 ? first[0].id : "none";
        if (m === "create") { bytes = hi; sizeField.text = (hi / 1e9).toFixed(1); }
        else if (m === "resize" && v) { bytes = v.size; sizeField.text = (v.size / 1e9).toFixed(1); }
        else if (m === "label" && v) nameField.text = v.label;
        if ((m === "delete" || m === "resize") && v && v.mounted) Disks.peek(v.mounts[0], o => { if (o.ok) root.contents = o; });
        visible = true;
        if (m === "resize") sizeField.input.forceActiveFocus();
        else if (!destructive) nameField.input.forceActiveFocus();
        else root.forceActiveFocus();
    }
    function close() { visible = false; closed(); }
    function submit() {
        if (!valid) return;
        const cb = o => { if (o.ok || o.cancelled) root.close(); };
        if (mode === "create") Disks.createPartition(d, gap, bytes, fs, fs === "none" ? "" : nameField.text.trim(), cb);
        else if (mode === "resize") Disks.resizePartition(v, bytes, cb);
        else if (mode === "delete") Disks.deletePartition(v, cb);
        else if (mode === "table") Disks.newTable(d, kind, cb);
        else if (mode === "label") Disks.setLabel(v, nameField.text.trim(), cb);
    }
    function peekText() {
        if (!contents) return "";
        return "\n\nIncluding: " + contents.names.map(n => n.name).join(", ")
            + (contents.total > contents.names.length ? " and " + (contents.total - contents.names.length) + " more" : "");
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
        width: Math.min(540, parent.width - 32)
        height: Math.min(col.implicitHeight + 40, parent.height - 24)
        color: Theme.bg1
        border.color: Theme.lineStrong
        border.width: 1
        MouseArea { anchors.fill: parent }
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: root.destructive ? Disks.danger : Theme.accent; size: 12 }

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
                    Rectangle { width: 6; height: 6; color: root.destructive ? Disks.danger : Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    GLabel {
                        strong: true
                        text: root.mode === "create" ? "New partition" + (root.d ? " on " + root.d.name : "")
                            : root.mode === "resize" ? "Resize " + (root.v ? Disks.volName(root.v) : "")
                            : root.mode === "delete" ? "Delete " + (root.v ? Disks.volName(root.v) : "")
                            : root.mode === "table" ? "New partition table"
                            : "Name of " + (root.v ? Disks.volName(root.v) : "")
                    }
                }

                // ---- warnings ----
                Rectangle {
                    visible: root.destructive
                    width: parent.width
                    implicitHeight: warn.implicitHeight + 20
                    color: Qt.rgba(Disks.danger.r, Disks.danger.g, Disks.danger.b, 0.1)
                    border.color: Disks.danger
                    Text {
                        id: warn
                        x: 12; y: 10; width: parent.width - 24
                        wrapMode: Text.WordWrap
                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                        text: {
                            if (root.mode === "delete" && root.v)
                                return "This deletes " + root.v.device + " (" + Disks.fmt(root.v.size) + (root.v.fs_name ? ", " + root.v.fs_name : "")
                                    + ") and everything on it. It cannot be undone." + (root.v.used ? "\n\nThere is " + Disks.fmt(root.v.used) + " of data on it." : "") + root.peekText();
                            if (root.mode === "resize" && root.v)
                                return (root.bytes < root.v.size ? "Shrinking" : "Growing") + " " + root.v.device + " moves the edges of the partition. "
                                    + "Back up anything important first: if the power goes out half way, the file system can be damaged."
                                    + (root.bytes < root.v.size ? " Everything past the new end is given up, so the data must fit." : "") + root.peekText();
                            if (root.mode === "table" && root.d) {
                                const ps = root.d.partitions.filter(p => p.kind === "partition");
                                return "This erases the whole drive " + root.d.name + " (" + Disks.fmt(root.d.size) + "): every partition and all data on it."
                                    + (ps.length > 0 ? "\n\nLost: " + ps.map(p => Disks.volName(p) + " (" + Disks.fmt(p.size) + (p.fs_name ? ", " + p.fs_name : "") + ")").join(", ") + "." : "")
                                    + "\n\nIt cannot be undone.";
                            }
                            return "";
                        }
                    }
                }

                // ---- size (create, resize) ----
                Column {
                    visible: root.mode === "create" || root.mode === "resize"
                    width: parent.width
                    spacing: 6
                    GLabel { text: root.mode === "create" ? "Size" : "New size" }
                    Row {
                        width: parent.width
                        spacing: 12
                        GSlider {
                            width: parent.width - 120 - 12
                            anchors.verticalCenter: parent.verticalCenter
                            from: root.lo; to: root.hi; value: root.bytes
                            onMoved: v => { root.setBytes(v); sizeField.text = (root.bytes / 1e9).toFixed(1); }
                        }
                        GInput {
                            id: sizeField
                            width: 120
                            placeholder: "GB"
                            onEdited: t => {
                                const g = parseFloat(t.replace(",", "."));
                                if (!isNaN(g)) root.setBytes(g * 1e9);
                            }
                            onEscaped: root.close()
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        color: root.sizeOk ? Theme.dim : Theme.warn
                        font.family: Theme.mono; font.pixelSize: 11
                        text: root.mode === "create"
                            ? (root.hi < 1048576 ? "That free space is too small."
                               : Disks.fmt(root.bytes) + " of " + Disks.fmt(root.hi) + " free" + (root.hi - root.bytes >= 1048576 ? " · " + Disks.fmt(root.hi - root.bytes) + " stays unallocated" : ""))
                            : (root.v ? "now " + Disks.fmt(root.v.size) + " · smallest " + Disks.fmt(root.lo) + " · largest " + Disks.fmt(root.hi)
                                        + (root.rz && !root.rz.shrink && root.rz.why ? "\n" + root.rz.why : "") : "")
                    }
                }

                // ---- file system (create) ----
                Column {
                    visible: root.mode === "create"
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Format as" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [{ id: "none", name: "Leave empty", bad: "" }].concat(Disks.formats)
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: root.fs === modelData.id
                                readonly property bool off: false
                                width: ft.implicitWidth + 20; height: 28
                                opacity: off ? 0.4 : 1
                                color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : "transparent"
                                border.color: on ? Theme.accent : Theme.line
                                Text { id: ft; anchors.centerIn: parent; text: modelData.name; color: parent.on ? Theme.accent : Theme.fg
                                    font.family: Theme.ui; font.pixelSize: 12 }
                                MouseArea { anchors.fill: parent; enabled: !parent.off; cursorShape: Qt.PointingHandCursor; onClicked: root.fs = modelData.id }
                            }
                        }
                    }
                }

                // ---- table kind ----
                Column {
                    visible: root.mode === "table"
                    width: parent.width
                    spacing: 6
                    GLabel { text: "Table type" }
                    GSeg {
                        options: [{ id: "gpt", label: "GPT (modern, default)" }, { id: "dos", label: "DOS / MBR (old PCs, small drives)" }]
                        current: root.kind
                        onPicked: id => root.kind = id
                    }
                }

                // ---- name (create, label) ----
                Column {
                    visible: (root.mode === "create" && root.fs !== "none") || root.mode === "label"
                    width: parent.width
                    spacing: 6
                    GLabel { text: root.mode === "label" ? "Name" : "Name (optional)" }
                    GInput {
                        id: nameField
                        width: parent.width
                        placeholder: "name of the volume"
                        onAccepted: if (root.mode === "label") root.submit()
                        onEscaped: root.close()
                    }
                    Text {
                        visible: root.labelErr !== ""
                        width: parent.width; wrapMode: Text.WordWrap
                        text: root.labelErr; color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
                    }
                }

                Row {
                    spacing: 10
                    anchors.right: parent.right
                    GButton { text: "Cancel"; onClicked: root.close() }
                    GButton {
                        visible: !root.destructive
                        primary: true
                        text: Disks.busy !== "" ? "Working…" : root.verb
                        enabled: root.valid
                        onClicked: root.submit()
                    }
                    DButton {
                        visible: root.destructive
                        solid: true
                        text: Disks.busy !== "" ? "Working…" : root.verb
                        enabled: root.valid
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
