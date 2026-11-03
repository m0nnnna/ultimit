// BackupWindow.qml - the BACKUP window. Tabs: OVERVIEW (back up now, progress, last result), SNAPSHOTS (verify),
// SCHEDULE, SETTINGS (folder, encryption, retention) and RECOVERY (how to restore from a rescue USB).
import QtQuick
import QtQuick.Controls
import Quickshell
import "../.."
import "../games"
import "../shares"

FloatingWindow {
    id: win
    title: "BACKUP"
    visible: Backup.open
    implicitWidth: 860
    implicitHeight: 640
    minimumSize: Qt.size(640, 460)
    color: "transparent"

    onVisibleChanged: if (visible !== Backup.open) Backup.open = visible
    Component.onCompleted: { Backup.refresh(); Backup.loadRecovery(); }

    readonly property var presets: [
        { label: "Every night, 2:00", cron: "0 2 * * *" },
        { label: "Every Sunday, 3:00", cron: "0 3 * * 0" },
        { label: "First of the month, 4:00", cron: "0 4 1 * *" }
    ]
    property string passphraseShown: ""

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        Item {
            id: header
            x: 20; y: 10; width: parent.width - 40; height: 36
            GLabel { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: "Back up this whole PC" }
            GButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: Backup.ready
                primary: true
                enabled: !Backup.backingUp && Backup.busy === ""
                text: Backup.backingUp ? "Backing up…" : "Back up now"
                onClicked: Backup.backupNow()
            }
        }

        Column {
            id: banners
            x: 20; anchors.top: header.bottom; anchors.topMargin: 8
            width: parent.width - 40; spacing: 6
            Repeater {
                model: Backup.warnings
                delegate: Rectangle {
                    required property string modelData
                    width: banners.width; implicitHeight: wt.implicitHeight + 16
                    color: Theme.panel2; border.color: Theme.warn; border.width: 1
                    Text { id: wt; x: 12; y: 8; width: parent.width - 24; wrapMode: Text.WordWrap; text: modelData
                           color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12 }
                }
            }
        }

        Item {
            id: tabBar
            x: 20; anchors.top: banners.bottom; anchors.topMargin: 8
            width: parent.width - 40; height: 32
            visible: Backup.ready
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            Row {
                spacing: 4
                Repeater {
                    model: [{ id: "overview", label: "Overview" }, { id: "snapshots", label: "Backups · " + Backup.snapshots.length },
                            { id: "schedule", label: "Schedule" }, { id: "settings", label: "Settings" }, { id: "recovery", label: "Recovery" }]
                    delegate: Item {
                        id: tb
                        required property var modelData
                        readonly property bool on: Backup.tab === modelData.id
                        width: tl.implicitWidth + 32; height: 32
                        Text { id: tl; anchors.centerIn: parent; text: tb.modelData.label.toUpperCase()
                               color: tb.on ? Theme.accent : (tm.containsMouse ? Theme.fg : Theme.dim)
                               font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.8 }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent; visible: tb.on }
                        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Backup.tab = tb.modelData.id }
                    }
                }
            }
        }

        Text {
            id: noteLine
            x: 20; anchors.top: tabBar.bottom; anchors.topMargin: 8
            width: parent.width - 40; height: Backup.note !== "" ? 16 : 0
            elide: Text.ElideRight; text: Backup.note
            color: Backup.noteKind === "error" ? Theme.bad : Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
        }

        Flickable {
            id: scroller
            visible: Backup.ready
            x: 20; anchors.top: noteLine.bottom; anchors.topMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 40
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: body
                width: scroller.width - 8
                spacing: 10

                // ---- OVERVIEW ----
                Column {
                    visible: Backup.tab === "overview"; width: parent.width; spacing: 10
                    Rectangle {
                        visible: Backup.running !== null
                        width: parent.width; height: 70; color: Theme.panel2; border.color: Theme.accent; border.width: 1
                        Column {
                            anchors { fill: parent; margins: 14 } spacing: 8
                            Text { text: Backup.running ? (Backup.running.phase || "Backing up") : ""; color: Theme.fg
                                   font.family: Theme.ui; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Rectangle { width: parent.width; height: 6; color: Theme.field
                                Rectangle { height: parent.height; color: Theme.accent
                                    width: parent.width * Math.max(0.02, Math.min(1, (Backup.running ? (Backup.running.percent || 0) : 0) / 100)) } }
                        }
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
                           text: Backup.snapshots.length === 0
                                 ? "No backups yet. Press Back up now: it copies the whole system (apps, settings, boot files) so it can be restored later."
                                 : "Latest backup: " + Backup.snapshots[0].created + "  ·  " + Backup.snapshots[0].size_human
                                   + (Backup.snapshots[0].encrypted ? "  ·  encrypted" : "") }
                    Text { visible: Backup.last !== null && Backup.running === null; width: parent.width; wrapMode: Text.WordWrap
                           color: Backup.last && Backup.last.state === "failed" ? Theme.bad : Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                           text: Backup.last ? "Last run: " + (Backup.last.state || "") + (Backup.last.error ? " — " + Backup.last.error : "") : "" }
                    Row { spacing: 8
                        GChip { text: Backup.schedule.length > 0 ? "Scheduled" : "Not scheduled"; tone: Backup.schedule.length > 0 ? Theme.ok : Theme.warn }
                        GChip { text: Backup.settings.encrypt ? "Encrypted" : "Not encrypted"; tone: Backup.settings.encrypt ? Theme.ok : Theme.dim }
                    }
                }

                // ---- SNAPSHOTS ----
                Repeater {
                    model: Backup.tab === "snapshots" ? Backup.snapshots : []
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: body.width; implicitHeight: 62; color: Theme.panel2; border.color: Theme.line; border.width: 1
                        Column {
                            anchors { left: parent.left; right: vb.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 12 } spacing: 4
                            Text { text: row.modelData.created + "  ·  " + row.modelData.size_human; color: Theme.fg
                                   font.family: Theme.ui; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.name
                                   + (row.modelData.encrypted ? "  ·  encrypted" : "")
                                   + (Backup.verified[row.modelData.path] === true ? "  ·  ✓ verified" : Backup.verified[row.modelData.path] === false ? "  ·  ✕ DAMAGED" : "")
                                   color: Backup.verified[row.modelData.path] === false ? Theme.bad : Theme.dim; font.family: Theme.mono; font.pixelSize: 10 }
                        }
                        GButton { id: vb; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } width: 104
                                  text: Backup.busy === "verify:" + row.modelData.path ? "Checking…" : "Verify"
                                  enabled: Backup.busy === ""; onClicked: Backup.verify(row.modelData.path) }
                    }
                }
                Text { visible: Backup.tab === "snapshots" && Backup.snapshots.length === 0; color: Theme.dim
                       font.family: Theme.ui; font.pixelSize: 13; text: "Nothing in " + (Backup.settings.output_dir || "") + " yet." }
                GButton { visible: Backup.tab === "snapshots" && Backup.snapshots.length > Math.max(1, Backup.settings.keep || 3)
                          enabled: Backup.busy === ""; text: "Remove old backups (keep " + (Backup.settings.keep || 3) + ")"; onClicked: pruneDlg.visible = true }

                // ---- SCHEDULE ----
                Column {
                    visible: Backup.tab === "schedule"; width: parent.width; spacing: 10
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
                           text: Backup.schedule.length > 0 ? "Scheduled: " + (Backup.schedule[0].description || Backup.schedule[0].schedule)
                                 : "Backups are not scheduled. Pick a time and the PC backs itself up (a missed run happens at next boot)." }
                    Repeater {
                        model: win.presets
                        delegate: GButton { required property var modelData; text: modelData.label; enabled: Backup.busy === ""
                                            onClicked: Backup.addSchedule(modelData.cron) }
                    }
                    GButton { visible: Backup.schedule.length > 0; enabled: Backup.busy === ""; text: "Turn off schedule"; onClicked: Backup.removeSchedule() }
                }

                // ---- SETTINGS ----
                Column {
                    visible: Backup.tab === "settings"; width: parent.width; spacing: 10
                    GLabel { text: "Where backups are kept" }
                    GInput { width: parent.width; value: Backup.settings.output_dir || ""; onCommitted: v => Backup.setSetting("output_dir", v) }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                           text: "Use an external drive for real protection (a mounted path like /media/you/backup). Backups on the system disk are lost if that disk fails." }
                    GToggle { width: parent.width; label: "Encrypt backups"; checked: Backup.settings.encrypt === true
                              onToggled: v => { if (v) Backup.makePassphrase(o => { win.passphraseShown = o.passphrase || ""; Backup.setSetting("encrypt", true); });
                                                 else Backup.setSetting("encrypt", false); } }
                    Rectangle { visible: win.passphraseShown !== ""; width: parent.width; implicitHeight: pt.implicitHeight + 24
                        color: Theme.panel2; border.color: Theme.warn; border.width: 1
                        Text { id: pt; x: 12; y: 12; width: parent.width - 24; wrapMode: Text.WordWrap; color: Theme.fg; font.family: Theme.mono; font.pixelSize: 12
                               text: "Write this passphrase down NOW and keep it off this PC. Without it the backups cannot be opened:\n\n" + win.passphraseShown } }
                    GLabel { text: "Backups to keep" }
                    GInput { width: 120; value: String(Backup.settings.keep || 3); onCommitted: v => Backup.setSetting("keep", v) }
                }

                // ---- RECOVERY ----
                Column {
                    visible: Backup.tab === "recovery"; width: parent.width; spacing: 8
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                           text: "If Ultimit still starts, a normal restore is the NekoShot restore command from a terminal. If the disk or boot is broken, restore from a rescue USB:" }
                    Repeater {
                        model: Backup.recoverySteps
                        delegate: Text { required property int index; required property string modelData
                            width: body.width; wrapMode: Text.WordWrap; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                            text: (index + 1) + ".  " + modelData }
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
                           text: "Test this once before you need it: restore a backup into a virtual machine." }
                }
            }
        }

        GLabel { anchors.centerIn: parent; visible: !Backup.loaded; text: "Checking…" }
        Column {
            anchors.centerIn: parent; visible: Backup.loaded && Backup.st.cli !== true; spacing: 8
            GLabel { text: "NekoShot is not installed" }
            Text { color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12; text: "Run scripts/build-nekoshot.sh, then reopen BACKUP." }
        }
    }

    SharesPrompt {
        id: pruneDlg
        visible: false
        title: "Remove old backups?"
        message: "Only the newest " + (Backup.settings.keep || 3) + " backups are kept. The rest are deleted for good."
        buttons: [{ id: "cancel", text: "Cancel" }, { id: "go", text: "Remove", primary: true }]
        onChosen: id => { visible = false; if (id === "go") Backup.prune(); }
    }
}
