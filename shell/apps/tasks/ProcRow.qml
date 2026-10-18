// ProcRow.qml - one process in the table: icon and name (with the window title when it has a window), PID, user, CPU,
// memory, GPU memory, threads, state. Click selects (by PID, so the selection survives the refresh); right-click opens the menu.
import QtQuick
import "../.."

Rectangle {
    id: root
    required property int pid
    required property string name
    required property string cmd
    required property string user
    required property real cpu
    required property real rss
    required property real gpuMem
    required property int threads
    required property string state
    required property string app
    required property string title
    required property bool critical
    readonly property bool on: Tasks.selPid === pid
    signal menu(real x, real y)

    height: 30
    color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : (m.containsMouse ? Theme.panel2 : "transparent")
    border.color: on ? Theme.accent : "transparent"
    border.width: 1

    readonly property string iconUrl: app === "" ? "" : Icons.app(Icons.windowIcon(app, title.replace(/  \+\d+$/, "")) || app.split(".").pop().replace(/_/g, "-"))
    readonly property color cpuTone: cpu >= 80 ? Theme.bad : cpu >= 40 ? Theme.warn : cpu >= 1 ? Theme.fg : Theme.dim

    Row {
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        spacing: 0
        Item {
            id: nameCell
            width: parent.width - Tasks.colTotal
            height: parent.height
            Image {
                id: icon
                visible: status === Image.Ready
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 18; height: 18
                sourceSize: Qt.size(36, 36)
                source: root.iconUrl
            }
            Row {
                anchors { left: icon.visible ? icon.right : parent.left; leftMargin: icon.visible ? 8 : 0; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text {
                    id: nm
                    width: Math.min(implicitWidth, parent.width)
                    elide: Text.ElideRight
                    text: root.name
                    color: root.critical ? Theme.warn : Theme.fg
                    font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 13
                }
                Text {
                    width: Math.max(0, parent.width - nm.width - parent.spacing)
                    elide: Text.ElideRight
                    visible: width > 20
                    text: root.title
                    color: Theme.dim
                    font.family: Theme.ui; font.pixelSize: 12
                }
            }
        }
        Text { width: Tasks.colW.pid; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; rightPadding: 8
            text: root.pid; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11 }
        Text { width: Tasks.colW.user; height: parent.height; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; leftPadding: 8; rightPadding: 4
            text: root.user; color: root.user === Tasks.me ? Theme.fg : Theme.dim; font.family: Theme.mono; font.pixelSize: 11 }
        Text { width: Tasks.colW.cpu; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; rightPadding: 8
            text: Tasks.pct(root.cpu); color: root.cpuTone; font.family: Theme.mono; font.pixelSize: 11 }
        Text { width: Tasks.colW.mem; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; rightPadding: 8
            text: Tasks.fmt(root.rss); color: Theme.fg; font.family: Theme.mono; font.pixelSize: 11 }
        Text { width: Tasks.colW.gpu; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; rightPadding: 8
            text: root.gpuMem >= 0 ? Tasks.fmt(root.gpuMem) : "–"; color: root.gpuMem >= 0 ? Theme.fg : Theme.dim; font.family: Theme.mono; font.pixelSize: 11 }
        Text { width: Tasks.colW.threads; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; rightPadding: 8
            text: root.threads; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11 }
        Text { width: Tasks.colW.state; height: parent.height; verticalAlignment: Text.AlignVCenter; leftPadding: 8
            text: Tasks.stateText(root.state); color: root.state === "T" || root.state === "t" ? Theme.warn : root.state === "Z" ? Theme.bad : Theme.dim
            font.family: Theme.mono; font.pixelSize: 11 }
    }
    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            Tasks.selPid = root.pid;
            if (mouse.button === Qt.RightButton) root.menu(mouse.x, mouse.y);
        }
    }
}
