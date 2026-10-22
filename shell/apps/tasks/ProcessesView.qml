// ProcessesView.qml - the PROCESSES tab: search, Apps / Mine / All, End / Kill / Pause for the selected process,
// and the table (click a column title to sort).
import QtQuick
import QtQuick.Controls
import "../.."
import "../games"
import "../data"

Item {
    id: root
    readonly property var p: Tasks.sel
    readonly property bool paused: !!(p && (p.state === "T" || p.state === "t"))

    // ---- toolbar ----
    Item {
        id: bar
        width: parent.width
        height: Config.mobile ? 132 : 34
        GInput {
            id: find
            anchors { left: parent.left; verticalCenter: Config.mobile ? undefined : parent.verticalCenter; top: Config.mobile ? parent.top : undefined }
            width: Config.mobile ? parent.width : 240
            height: Config.mobile ? 40 : implicitHeight
            placeholder: "Search name, command or PID"
            onEdited: v => Tasks.search = v
            onEscaped: { text = ""; Tasks.search = ""; }
        }
        GSeg {
            id: seg
            anchors { left: Config.mobile ? parent.left : find.right; leftMargin: Config.mobile ? 0 : 12; verticalCenter: Config.mobile ? undefined : parent.verticalCenter
                      top: Config.mobile ? find.bottom : undefined; topMargin: Config.mobile ? 6 : 0 }
            height: Config.mobile ? 40 : implicitHeight
            options: [{ id: "apps", label: "Apps" }, { id: "mine", label: "Mine" }, { id: "all", label: "All" }]
            current: Tasks.filter
            onPicked: id => Tasks.filter = id
        }
        Row {
            anchors { right: parent.right; verticalCenter: Config.mobile ? undefined : parent.verticalCenter; bottom: Config.mobile ? parent.bottom : undefined }
            spacing: Config.mobile ? 4 : 8
            GButton { text: root.paused ? "Resume" : "Pause"; enabled: !!root.p && !Tasks.busy; onClicked: Tasks.ask(root.paused ? "cont" : "stop") }
            GButton { text: "End"; primary: true; enabled: !!root.p && !Tasks.busy; onClicked: Tasks.ask("term") }
            DButton { text: "Kill…"; enabled: !!root.p && !Tasks.busy; onClicked: Tasks.ask("kill") }
        }
    }

    // ---- column titles ----
    Item {
        id: head
        anchors.top: bar.bottom; anchors.topMargin: 10
        width: parent.width - 10
        height: 28
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        Row {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            HeaderCell { width: parent.width - Tasks.colTotal; key: "name"; text: "Name" }
            HeaderCell { width: Tasks.colW.pid; visible: width > 0; key: "pid"; text: "PID"; alignRight: true; rightPadding: 8 }
            HeaderCell { width: Tasks.colW.user; visible: width > 0; key: "user"; text: "User"; leftPadding: 8 }
            HeaderCell { width: Tasks.colW.cpu; key: "cpu"; text: "CPU"; alignRight: true; rightPadding: 8 }
            HeaderCell { width: Tasks.colW.mem; key: "mem"; text: "Memory"; alignRight: true; rightPadding: 8 }
            HeaderCell { width: Tasks.colW.gpu; visible: width > 0; key: "gpu"; text: "GPU mem"; alignRight: true; rightPadding: 8 }
            HeaderCell { width: Tasks.colW.threads; visible: width > 0; key: "threads"; text: "Thr."; alignRight: true; rightPadding: 8 }
            HeaderCell { width: Tasks.colW.state; visible: width > 0; key: "state"; text: "State"; leftPadding: 8 }
        }
    }

    // ---- table ----
    ListView {
        id: list
        anchors { top: head.bottom; left: parent.left; bottom: parent.bottom }
        width: parent.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Tasks.rows
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: ProcRow {
            width: list.width - 10
            onMenu: (x, y) => {
                const pt = mapToItem(root, x, y);
                ctx.popup(pt.x, pt.y);
            }
        }
    }
    Text {
        anchors.centerIn: list
        visible: Tasks.loaded && Tasks.shown === 0
        text: Tasks.filter === "apps" && Tasks.search === "" ? "No windows are open. Pick All to see every process." : "Nothing matches."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 14
    }

    // ---- right-click menu ----
    DMenu {
        id: ctx
        items: [
            { id: "term", label: "End" },
            { id: "kill", label: "Kill…" },
            { id: "pause", label: root.paused ? "Resume" : "Pause" },
            { kind: "sep" },
            { id: "cmd", label: "Copy command line", disabled: !root.p || root.p.cmd === "" },
            { id: "pid", label: "Copy PID" }
        ]
        onPicked: id => {
            if (id === "term" || id === "kill") Tasks.ask(id);
            else if (id === "pause") Tasks.ask(root.paused ? "cont" : "stop");
            else if (id === "cmd" && root.p) Tasks.copy(root.p.cmd);
            else if (id === "pid" && root.p) Tasks.copy(String(root.p.pid));
        }
    }
}
