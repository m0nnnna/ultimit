// AppCard.qml - one app in a STORE grid: icon, name, developer, summary, and Install / Open.
import QtQuick
import "../.."
import "../games"

Rectangle {
    id: card
    property var app: ({})
    readonly property string jobKind: Store.jobFor(app.id)
    readonly property bool installed: Store.isInstalled(app.id)

    color: hov.hovered ? Theme.panel2 : "transparent"
    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    border.color: hov.hovered ? Theme.lineStrong : Theme.line
    Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    border.width: 1

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: Store.openApp(card.app.id) }

    AppIcon { id: ic; x: 14; y: 14; size: 48; app: card.app }
    Column {
        anchors { left: ic.right; leftMargin: 12; right: parent.right; rightMargin: 12; top: ic.top }
        spacing: 2
        Text {
            width: parent.width; elide: Text.ElideRight
            text: card.app.name || ""; color: Theme.fg
            font.family: Theme.ui; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width; elide: Text.ElideRight
            text: (card.app.verified ? "✓ " : "") + (card.app.developer || "")
            color: card.app.verified ? Theme.accent : Theme.dim
            font.family: Theme.mono; font.pixelSize: 10
        }
    }
    Text {
        anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14; top: ic.bottom; topMargin: 10; bottom: btn.top; bottomMargin: 8 }
        text: card.app.summary || ""; color: Theme.dim
        font.family: Theme.ui; font.pixelSize: 12
        wrapMode: Text.WordWrap; elide: Text.ElideRight; maximumLineCount: 2
    }
    GButton {
        id: btn
        anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
        primary: !card.installed && card.jobKind === ""
        enabled: card.jobKind === ""
        text: card.jobKind === "install" ? "Installing…" : card.jobKind === "install-queued" ? "Waiting…"
            : card.jobKind.indexOf("remove") === 0 ? "Removing…"
            : card.installed ? "Open" : "Install"
        onClicked: card.installed ? Store.launch(card.app.id) : Store.install(card.app.id, card.app.name)
    }
}
