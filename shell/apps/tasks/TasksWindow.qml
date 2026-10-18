// TasksWindow.qml - the TASKS window: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Two tabs: PROCESSES (what is running, with End / Kill / Pause) and PERFORMANCE (the last minute of CPU, memory, GPU, disk, network).
import QtQuick
import Quickshell
import "../.."
import "../games"
import "../shares"

FloatingWindow {
    id: win
    title: "TASKS"
    visible: Tasks.open
    implicitWidth: 1000
    implicitHeight: 700
    minimumSize: Qt.size(760, 520)
    color: "transparent"

    onVisibleChanged: if (visible !== Tasks.open) Tasks.open = visible

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
                options: [{ id: "processes", label: "Processes" }, { id: "performance", label: "Performance" }]
                current: Tasks.tab
                onPicked: id => Tasks.tab = id
            }
            GChip {
                visible: Tasks.fake
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Pretend computer"
                tone: Theme.warn
            }
            Text {
                visible: !Tasks.fake && Tasks.loaded && Tasks.tab === "processes"
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: Tasks.shown + (Tasks.shown === 1 ? " process" : " processes")
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
            }
        }

        // ---------------- message line ----------------
        Text {
            id: noteLine
            x: 20; anchors.top: header.bottom; anchors.topMargin: 6
            width: parent.width - 40
            height: Tasks.note !== "" ? 18 : 0
            elide: Text.ElideRight
            text: Tasks.note
            color: Tasks.noteKind === "error" ? Theme.bad : Theme.dim
            font.family: Theme.ui; font.pixelSize: 12
            visible: Tasks.note !== ""
        }

        ProcessesView {
            visible: Tasks.tab === "processes" && Tasks.loaded
            x: 20
            anchors.top: noteLine.bottom; anchors.topMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 40
        }
        PerformanceView {
            visible: Tasks.tab === "performance" && Tasks.loaded
            x: 20
            anchors.top: noteLine.bottom; anchors.topMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: parent.width - 40
        }
        GLabel {
            anchors.centerIn: parent
            visible: !Tasks.loaded
            text: "Checking…"
        }
    }

    // ---------------- confirmations ----------------
    SharesPrompt {
        id: dlg
        visible: Tasks.overlay !== ""
        readonly property var t: Tasks.pending
        readonly property bool crit: Tasks.overlay === "critical"
        title: crit ? "This one keeps the system running" : "Kill " + (t ? t.name : "") + "?"
        message: !t ? "" : crit
            ? t.name + " (PID " + t.pid + ") is part of the system or of this desktop. " + ({ TERM: "Ending", KILL: "Killing", STOP: "Pausing", CONT: "Resuming" }[t.sig])
                + " it can log you out, freeze the screen or lose what you have not saved."
            : t.name + " (PID " + t.pid + ") is stopped at once, without a chance to save. Unsaved work in it is lost."
        buttons: [{ id: "cancel", text: "Keep it" }, { id: "go", text: crit ? "Do it anyway" : "Kill", primary: true }]
        onChosen: id => {
            if (id === "go") Tasks.confirm();
            else { Tasks.overlay = ""; Tasks.pending = null; }
        }
        Connections {
            target: Tasks
            function onSubmitRequested() { if (dlg.visible) dlg.chosen("go"); }
        }
    }
}
