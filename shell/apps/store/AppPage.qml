// AppPage.qml - one app in full: icon, name, developer, Install / Open / Remove, screenshots,
// description and details. Store.app is null while it loads.
import QtQuick
import QtQuick.Controls
import "../.."
import "../games"

Flickable {
    id: root
    readonly property var a: Store.app
    readonly property string jobKind: Store.jobFor(Store.appId)
    readonly property bool installed: Store.isInstalled(Store.appId)

    contentWidth: width
    contentHeight: col.implicitHeight + 20
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
        id: col
        width: root.width
        spacing: 16

        Text {
            text: "‹  BACK"; color: bk.hovered ? Theme.fg : Theme.accent
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
            HoverHandler { id: bk; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Store.back() }
        }

        Text {
            visible: !root.a
            text: "Loading…"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }

        // ---- head ----
        Item {
            visible: !!root.a
            width: parent.width; height: 96
            AppIcon { id: ic; size: 96; app: root.a || ({}) }
            Column {
                anchors { left: ic.right; leftMargin: 18; right: actions.left; rightMargin: 16; verticalCenter: ic.verticalCenter }
                spacing: 4
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: root.a ? root.a.name : ""; color: Theme.fg
                    font.family: Theme.display; font.pixelSize: Theme.ds(20); font.letterSpacing: Theme.dt(1)
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: root.a ? root.a.summary : ""; color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                }
                Row {
                    spacing: 8
                    Text {
                        text: root.a ? root.a.developer : ""; color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 0.8
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    GChip { visible: !!(root.a && root.a.verified); text: "✓ Verified"; tone: Theme.ok }
                    GChip { visible: root.installed; text: "Installed"; tone: Theme.accent }
                }
            }
            Row {
                id: actions
                anchors { right: parent.right; verticalCenter: ic.verticalCenter }
                spacing: 8
                GButton {
                    visible: root.installed && root.jobKind === ""
                    text: "Remove"
                    onClicked: confirmRemove.visible = true
                }
                GButton {
                    primary: true
                    enabled: root.jobKind === ""
                    text: root.jobKind === "install" ? "Installing…" : root.jobKind === "install-queued" ? "Waiting…"
                        : root.jobKind.indexOf("remove") === 0 ? "Removing…"
                        : root.installed ? "Open" : "Install"
                    onClicked: root.installed ? Store.launch(Store.appId) : Store.install(Store.appId, root.a ? root.a.name : "")
                }
            }
        }
        // remove confirmation
        Rectangle {
            id: confirmRemove
            visible: false
            width: parent.width; height: 48
            color: Theme.panel2; border.color: Theme.warn
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Remove " + (root.a ? root.a.name : "") + "? Its settings stay in your home folder."
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 12
            }
            Row {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 8
                GButton { text: "Keep"; onClicked: confirmRemove.visible = false }
                GButton { primary: true; text: "Remove"; onClicked: { confirmRemove.visible = false; Store.remove(Store.appId, root.a ? root.a.name : ""); } }
            }
            Connections { target: Store; function onAppIdChanged() { confirmRemove.visible = false; } }
        }

        // ---- screenshots ----
        ListView {
            id: shots
            visible: !!(root.a && root.a.screenshots.length)
            width: parent.width; height: 270
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.a ? root.a.screenshots : []
            delegate: Rectangle {
                required property string modelData
                height: shots.height; width: Math.max(160, shot.status === Image.Ready ? shot.paintedWidth : 480)
                color: Theme.panel2; border.color: Theme.line
                Image {
                    id: shot
                    anchors.fill: parent; anchors.margins: 1
                    source: parent.modelData
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.height: 540
                }
                Text {
                    visible: shot.status !== Image.Ready
                    anchors.centerIn: parent
                    text: shot.status === Image.Error ? "No connection" : "Loading…"
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                }
            }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        }

        // ---- description + details ----
        Text {
            visible: !!root.a
            width: parent.width
            text: root.a ? root.a.description : ""
            color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13; lineHeight: 1.25
            wrapMode: Text.WordWrap
        }
        Column {
            visible: !!root.a
            width: parent.width
            spacing: 0
            Repeater {
                model: root.a ? [
                    { k: "Version", v: root.a.version },
                    { k: "License", v: root.a.license },
                    { k: "Website", v: root.a.homepage },
                    { k: "App ID", v: root.a.id }
                ].filter(r => r.v) : []
                delegate: Item {
                    required property var modelData
                    width: parent.width; height: 30
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.k.toUpperCase(); color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4 }
                    Text {
                        x: 120; width: parent.width - 120; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        text: parent.modelData.v; color: parent.modelData.k === "Website" ? Theme.accent : Theme.fg
                        font.family: Theme.ui; font.pixelSize: 12
                        HoverHandler { enabled: parent.parent.modelData.k === "Website"; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: parent.parent.modelData.k === "Website"; onTapped: Qt.openUrlExternally(parent.parent.modelData.v) }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                }
            }
        }
    }
    onVisibleChanged: if (visible) contentY = 0
}
