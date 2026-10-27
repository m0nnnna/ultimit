// DisksWindow.qml - the DISKS window: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Two tabs: DRIVES (drive list, partition bar, volume details and actions) and USAGE (what takes up space).
import QtQuick
import QtQuick.Controls
import Quickshell
import "../.."
import "../games"
import "../shares"

FloatingWindow {
    id: win
    title: "DISKS"
    visible: Disks.open
    implicitWidth: 1000
    implicitHeight: 700
    minimumSize: Qt.size(760, 520)
    color: "transparent"

    onVisibleChanged: if (visible !== Disks.open) Disks.open = visible
    Connections {
        target: Disks
        function onOverlayChanged() {
            if (Disks.overlay === "format") fmtDlg.open();
            else if (Disks.overlay === "trash") trashDlg.visible = true;
            else if (["create", "resize", "delete", "table", "label"].indexOf(Disks.overlay) >= 0) mgrDlg.open(Disks.overlay);
            else { fmtDlg.visible = false; trashDlg.visible = false; mgrDlg.visible = false; }
        }
    }
    Component.onCompleted: Disks.refresh()

    property bool showSerial: false
    readonly property var d: Disks.drive
    readonly property var v: Disks.volume
    readonly property var health: d ? Disks.healthBy[d.id] : null

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        // ---------------- header ----------------
        Item {
            id: header
            x: 20; y: 10
            width: parent.width - 40
            height: 36
            GSeg {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                options: [{ id: "drives", label: "Drives" }, { id: "usage", label: "Usage" }]
                current: Disks.tab
                onPicked: id => {
                    Disks.tab = id;
                    if (id === "usage" && Disks.usageRoot === "" && !Disks.scanning) Disks.choose(Disks.home);
                }
            }
            GChip {
                visible: Disks.fake
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Pretend drives"
                tone: Theme.warn
            }
        }

        // ---------------- message line ----------------
        Text {
            id: noteLine
            x: 20; anchors.top: header.bottom; anchors.topMargin: 6
            width: parent.width - 40
            height: Disks.note !== "" ? 18 : 0
            elide: Text.ElideRight
            text: Disks.note
            color: Disks.noteKind === "error" ? Theme.bad : Theme.dim
            font.family: Theme.ui; font.pixelSize: Theme.type.label
            visible: Disks.note !== ""
        }
        // progress of an action started outside a dialog (mount, eject, ...); dialogs show their own
        BusyBar {
            id: busyLine
            x: 20; anchors.top: noteLine.bottom; anchors.topMargin: visible ? 6 : 0
            width: parent.width - 40
            visible: Disks.busy !== "" && Disks.overlay === ""
            height: visible ? implicitHeight : 0
        }

        // ---------------- DRIVES ----------------
        Item {
            id: drivesTab
            visible: Disks.tab === "drives" && Disks.loaded
            x: 20
            anchors.top: busyLine.bottom; anchors.topMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 40

            Flickable {
                id: listFlick
                width: 250
                height: parent.height
                contentHeight: listCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: listCol
                    width: listFlick.width
                    spacing: 6
                    Repeater {
                        model: Disks.drives
                        delegate: DriveRow {
                            required property var modelData
                            width: listCol.width
                            drive: modelData
                            onPicked: { Disks.select(modelData.id, ""); win.showSerial = false; }
                        }
                    }
                }
            }

            Flickable {
                id: pane
                anchors { left: listFlick.right; leftMargin: 16; right: parent.right; top: parent.top; bottom: parent.bottom }
                contentHeight: paneCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: !!(win.d !== null)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: paneCol
                    width: pane.width - 10
                    spacing: 12

                    // ---- drive header ----
                    Item {
                        width: parent.width
                        height: 54
                        Column {
                            anchors { left: parent.left; right: btns.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: win.d ? win.d.name : ""
                                color: Theme.fg; font.family: Theme.display; font.pixelSize: Theme.ds(18)
                            }
                            Row {
                                spacing: 8
                                Text {
                                    id: sub
                                    text: win.d ? Disks.fmt(win.d.size) + " (" + Disks.fmtIec(win.d.size) + ") · " + Disks.busText(win.d) + " · " + win.d.device : ""
                                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label
                                }
                                Text {
                                    visible: !!(win.d && win.d.serial !== "")
                                    text: win.showSerial ? "serial " + (win.d ? win.d.serial : "") : "show serial"
                                    color: sm.containsMouse ? Theme.accent : Theme.dim
                                    font.family: Theme.mono; font.pixelSize: Theme.type.label; font.underline: !win.showSerial
                                    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: win.showSerial = !win.showSerial }
                                }
                            }
                        }
                        Row {
                            id: btns
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            // health chip: click to check
                            Rectangle {
                                id: hchip
                                readonly property string verdict: win.health ? win.health.verdict : "unknown"
                                readonly property color tone: verdict === "good" ? Theme.ok : verdict === "warn" ? Theme.warn : verdict === "bad" ? Theme.bad : Theme.dim
                                width: hl.implicitWidth + 18; height: 26
                                anchors.verticalCenter: parent.verticalCenter
                                color: hm.containsMouse ? Theme.panel2 : "transparent"
                                border.color: tone
                                Text {
                                    id: hl; anchors.centerIn: parent
                                    text: (Disks.healthBusy !== "" && win.d && Disks.healthBusy === win.d.id ? "Checking…" : win.health ? win.health.title : "Check health").toUpperCase()
                                    color: hchip.tone
                                    font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.2
                                }
                                MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (win.d) Disks.toggleHealth(win.d) }
                            }
                            GButton {
                                visible: !!(win.d && win.d.ejectable)
                                text: win.d && win.d.loop ? "Detach" : "Eject"
                                enabled: Disks.busy === ""
                                onClicked: Disks.eject(win.d)
                            }
                            GButton {
                                visible: !!(win.d && win.d.can_power_off)
                                text: "Power off"
                                enabled: Disks.busy === ""
                                onClicked: Disks.powerOff(win.d)
                            }
                        }
                    }

                    // ---- health panel ----
                    Rectangle {
                        visible: !!(win.d && Disks.healthShown === win.d.id && win.health !== null && win.health !== undefined)
                        width: parent.width
                        implicitHeight: hcol.implicitHeight + 24
                        color: Theme.panel2
                        border.color: hchip.tone
                        Column {
                            id: hcol
                            x: 14; y: 12; width: parent.width - 28
                            spacing: 6
                            Repeater {
                                model: win.health ? win.health.lines : []
                                delegate: Text {
                                    required property var modelData
                                    width: hcol.width; wrapMode: Text.WordWrap
                                    text: modelData.text
                                    color: modelData.tone === "ok" ? Theme.ok : modelData.tone === "warn" ? Theme.warn : modelData.tone === "bad" ? Theme.bad : Theme.dim
                                    font.family: Theme.ui; font.pixelSize: Theme.type.body
                                }
                            }
                            Text {
                                visible: !!(win.health && win.health.attributes && win.health.attributes.length > 0)
                                width: hcol.width; wrapMode: Text.WordWrap
                                text: win.health && win.health.attributes ? win.health.attributes.map(a => a.name + " " + a.raw).join(" · ") : ""
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label
                            }
                        }
                    }

                    // ---- partition bar ----
                    Item {
                        width: parent.width; height: 26
                        GLabel {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: "Layout" + (win.d && win.d.table ? " · " + win.d.table.toUpperCase() : "")
                        }
                        Text {
                            id: ntBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            visible: !!(win.d && win.d.table_why === "")
                            text: "NEW PARTITION TABLE…"
                            color: nm.containsMouse ? Disks.danger : Theme.dim
                            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.4
                            MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: Disks.busy === ""; onClicked: Disks.overlay = "table" }
                        }
                    }
                    PartBar {
                        width: parent.width
                        drive: win.d || ({ partitions: [], size: 1 })
                        visible: !!(win.d && win.d.partitions.length > 0)
                        current: Disks.selDev
                        currentFree: Disks.selFree
                        onPicked: dev => Disks.select(Disks.drive.id, dev)
                        onPickedFree: off => Disks.selectFree(off)
                    }
                    Text {
                        visible: !!(win.d && win.d.partitions.length === 0)
                        text: "No partitions on this drive."
                        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
                    }
                    Text {
                        visible: !!(win.d && win.d.partitions.length > 0 && !win.v && !Disks.freeSeg)
                        text: "Click a partition to see what is on it."
                        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                    }

                    // ---- free space ----
                    Rectangle {
                        visible: Disks.freeSeg !== null
                        width: parent.width
                        implicitHeight: fcol.implicitHeight + 28
                        color: Theme.panel2
                        border.color: Theme.line
                        Column {
                            id: fcol
                            x: 16; y: 14; width: parent.width - 32
                            spacing: 10
                            Text {
                                text: "Unallocated space"
                                color: Theme.fg; font.family: Theme.display; font.pixelSize: Theme.ds(16)
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: Disks.freeSeg ? Disks.fmt(Disks.freeSeg.size) + " that no partition uses." + (Disks.freeSeg.create && !Disks.freeSeg.create.ok ? " " + Disks.freeSeg.create.why : "") : ""
                                color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
                            }
                            GButton {
                                visible: !!(Disks.freeSeg && Disks.freeSeg.create && Disks.freeSeg.create.ok)
                                primary: true
                                text: "Create partition…"
                                enabled: Disks.busy === ""
                                onClicked: Disks.overlay = "create"
                            }
                        }
                    }

                    // ---- volume details ----
                    Rectangle {
                        visible: !!(win.v !== null)
                        width: parent.width
                        implicitHeight: vcol.implicitHeight + 28
                        color: Theme.panel2
                        border.color: Theme.line
                        Column {
                            id: vcol
                            x: 16; y: 14; width: parent.width - 32
                            spacing: 10

                            Row {
                                spacing: 10
                                Text {
                                    text: win.v ? Disks.volName(win.v) : ""
                                    color: Theme.fg; font.family: Theme.display; font.pixelSize: Theme.ds(16)
                                }
                                GChip { visible: !!(win.v && win.v.fs_name !== ""); text: win.v ? win.v.fs_name : ""; anchors.verticalCenter: parent.verticalCenter }
                                GChip { visible: !!(win.v && win.v.mounted); text: "Mounted"; tone: Theme.ok; anchors.verticalCenter: parent.verticalCenter }
                                GChip { visible: !!(win.v && win.v.read_only); text: "Read only"; tone: Theme.warn; anchors.verticalCenter: parent.verticalCenter }
                            }

                            // used / free
                            Column {
                                width: parent.width
                                spacing: 5
                                visible: !!(win.v && win.v.used !== null && win.v.used !== undefined)
                                Rectangle {
                                    width: parent.width; height: 10; color: Theme.bg1; border.color: Theme.line
                                    Rectangle {
                                        width: win.v && win.v.used !== null ? parent.width * Math.min(1, win.v.used / Math.max(1, win.v.fs_size || win.v.size)) : 0
                                        height: parent.height
                                        color: win.v && win.v.used / Math.max(1, win.v.fs_size || win.v.size) > 0.9 ? Theme.warn : Theme.accent
                                    }
                                }
                                Text {
                                    text: win.v && win.v.used !== null ? Disks.fmt(win.v.used) + " used · " + Disks.fmt(win.v.free) + " free · " + Disks.fmt(win.v.size) + " total" : ""
                                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label
                                }
                            }

                            Repeater {
                                model: win.v ? [
                                    ["Device", win.v.device],
                                    ["Type", win.v.type || ""],
                                    ["Mounted at", win.v.mounted ? win.v.mounts.join(", ") : "not mounted"],
                                    ["UUID", win.v.uuid || ""]
                                ].filter(r => r[1] !== "") : []
                                delegate: Row {
                                    required property var modelData
                                    spacing: 12
                                    GLabel { width: 90; text: modelData[0] }
                                    Text {
                                        width: vcol.width - 102; elide: Text.ElideMiddle
                                        text: modelData[1]
                                        color: Theme.fg; font.family: Theme.mono; font.pixelSize: Theme.type.label
                                    }
                                }
                            }

                            // system note
                            Rectangle {
                                visible: !!(win.v && win.v.is_system)
                                width: parent.width
                                implicitHeight: sysTxt.implicitHeight + 20
                                color: "transparent"
                                border.color: Theme.line
                                Text {
                                    id: sysTxt
                                    x: 12; y: 10; width: parent.width - 24; wrapMode: Text.WordWrap
                                    text: "In use by the system. " + (win.v ? win.v.system_reason : "") + ". It is protected, so it cannot be unmounted or formatted here."
                                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                                }
                            }
                            Text {
                                visible: !!(win.v && !win.v.is_system && win.v.manage && !win.v.manage.resize.ok && win.v.manage.resize.why !== "")
                                width: parent.width; wrapMode: Text.WordWrap
                                text: win.v ? "Resize: " + win.v.manage.resize.why : ""
                                color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                            }
                            Text {
                                visible: !!(win.v && !win.v.is_system && !win.v.can_format && !win.v.mountable)
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "This volume has no filesystem DISKS can mount."
                                color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                            }

                            // actions
                            Flow {
                                width: parent.width
                                spacing: 8
                                GButton {
                                    visible: !!(win.v && !win.v.is_system && win.v.mountable && !win.v.mounted)
                                    text: "Mount"; primary: true
                                    enabled: Disks.busy === ""
                                    onClicked: Disks.mount(win.v)
                                }
                                GButton {
                                    visible: !!(win.v && !win.v.is_system && win.v.mounted)
                                    text: "Unmount"
                                    enabled: Disks.busy === ""
                                    onClicked: Disks.unmount(win.v)
                                }
                                GButton {
                                    visible: !!(win.v && win.v.mounted)
                                    text: "Open in DATA"
                                    onClicked: Disks.openInData(win.v.mounts[0])
                                }
                                GButton {
                                    visible: !!(win.v && win.v.mounted)
                                    text: "Check usage"
                                    onClicked: Disks.checkUsage(win.v.mounts[0])
                                }
                                GButton {
                                    visible: !!(win.v && win.v.manage && win.v.manage.label === "")
                                    text: "Edit name…"
                                    enabled: Disks.busy === ""
                                    onClicked: Disks.overlay = "label"
                                }
                                GButton {
                                    visible: !!(win.v && win.v.manage && win.v.manage.resize.ok)
                                    text: "Resize…"
                                    enabled: Disks.busy === ""
                                    onClicked: Disks.overlay = "resize"
                                }
                                DButton {
                                    visible: !!(win.v && win.v.manage && win.v.manage.delete === "")
                                    text: "Delete…"
                                    enabled: Disks.busy === ""
                                    onClicked: Disks.overlay = "delete"
                                }
                                DButton {
                                    visible: !!(win.v && !win.v.is_system && win.v.can_format)
                                    text: "Format…"
                                    enabled: Disks.busy === ""
                                    onClicked: Disks.overlay = "format"
                                }
                            }
                        }
                    }
                }
            }
            Text {
                anchors.centerIn: pane
                visible: Disks.drives.length === 0
                text: "No drives found."
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.body
            }
        }

        // ---------------- USAGE ----------------
        UsageView {
            visible: Disks.tab === "usage"
            x: 20
            anchors.top: busyLine.bottom; anchors.topMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 40
        }

        GLabel {
            anchors.centerIn: parent
            visible: !Disks.loaded && Disks.tab === "drives"
            text: "Checking…"
        }
    }

    // ---------------- dialogs ----------------
    ManageDialog { id: mgrDlg; onClosed: if (Disks.overlay !== "" && Disks.overlay !== "format" && Disks.overlay !== "trash") Disks.overlay = "" }
    FormatDialog { id: fmtDlg; onClosed: if (Disks.overlay === "format") Disks.overlay = "" }
    SharesPrompt {
        id: trashDlg
        visible: false
        title: "Move to the trash?"
        message: Disks.trashTarget ? Disks.trashTarget.name + " (" + Disks.fmt(Disks.trashTarget.size) + ") will be moved to the trash. You can restore it from there."
                                    + "\n\n" + Disks.trashTarget.path : ""
        buttons: [{ id: "cancel", text: "Keep it" }, { id: "trash", text: "Move to trash", primary: true }]
        onChosen: id => {
            visible = false;
            Disks.overlay = "";
            if (id === "trash") Disks.doTrash();
        }
    }
}
