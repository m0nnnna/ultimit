// GameArt.qml - a game's art: Steam artwork when present, otherwise the generated GradArt tile
// with the game's themed icon on it.
import QtQuick
import "../.."
import "../../components"

Item {
    id: root
    property var game: null
    property bool portrait: true
    property real iconSize: 56
    clip: true

    readonly property string src: game ? (portrait ? game.portrait : game.header) : ""
    readonly property bool plain: game && game.source !== "steam"

    GradArt { anchors.fill: parent; stops: root.game ? Games.palette(root.game.id) : []; visible: img.status !== Image.Ready }
    Image {
        id: img
        anchors.fill: parent
        source: root.src ? "file://" + root.src : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.portrait ? 300 : 700
    }
    Image {
        id: ico
        visible: root.plain && status === Image.Ready
        anchors.centerIn: parent
        width: root.iconSize; height: root.iconSize
        source: root.plain ? Icons.pathOr(root.game.icon, "applications-games") : ""
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
    Icon {
        visible: root.plain && ico.status !== Image.Ready
        anchors.centerIn: parent
        size: root.iconSize * 0.8
        name: "games"
        color: Qt.rgba(1, 1, 1, 0.85)
    }
}
