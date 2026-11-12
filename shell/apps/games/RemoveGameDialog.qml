// RemoveGameDialog.qml - modal confirm for taking a game out of the library.
// Manual games are removed (optionally with their prefix, which is deleted only if it
// lives under Ultimit's data dir); desktop-entry games are hidden (and unhideable from
// the Hidden chip above the library).
import QtQuick
import "../.."

Item {
    id: root
    signal closed()

    property var game: null
    property string prefix: ""

    readonly property bool isManual: !!game && game.manual === true
    readonly property bool hasPrefix: prefix !== ""

    function openFor(g) {
        game = g;
        const cfg = (Games.settings.games[g.id]) || {};
        prefix = (cfg.prefix && cfg.prefix !== "default") ? cfg.prefix : "";
        visible = true;
    }
    function close() { visible = false; closed(); }
    function remove(deleteFiles) {
        if (root.game) Games.removeManual(root.game.id, deleteFiles ? root.prefix : "");
        root.close();
    }

    visible: false
    anchors.fill: parent
    z: 60
    focus: visible
    Keys.onEscapePressed: root.close()

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        anchors.centerIn: parent
        width: Config.mobile ? parent.width - 24 : Math.min(440, parent.width - 32)
        height: col.implicitHeight + 40
        color: Theme.bg1
        border.color: Theme.lineStrong
        border.width: 1
        MouseArea { anchors.fill: parent }          // swallow clicks
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { color: Theme.accent; size: 12 }

        Column {
            id: col
            x: 20; y: 20
            width: parent.width - 40
            spacing: 12

            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                GLabel { text: root.isManual ? "Remove from library?" : "Hide game?"; strong: true }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.game ? root.game.name : ""
                color: Theme.fg
                font.family: Theme.display; font.pixelSize: 15; font.letterSpacing: 0.5
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.family: Theme.ui; font.pixelSize: 12
                text: root.isManual
                    ? "Removes the library entry and its settings."
                        + (root.hasPrefix ? " The installed files stay on disk unless you delete the prefix below." : "")
                    : "Hides this desktop entry from the library. Unhide it any time with the Hidden chip above the library."
            }
            Text {
                visible: root.isManual && root.hasPrefix
                width: parent.width
                wrapMode: Text.WrapAnywhere
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 11
                text: "prefix: " + root.prefix
            }
            Text {
                visible: root.isManual && root.hasPrefix
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.warn
                font.family: Theme.ui; font.pixelSize: 11
                text: "“Remove + delete files” erases the prefix and everything in it. This cannot be undone."
            }
            Row {
                spacing: 10
                anchors.right: parent.right
                GButton { text: "Cancel"; onClicked: root.close() }
                GButton {
                    visible: root.isManual && root.hasPrefix
                    text: "Remove + delete files"
                    onClicked: root.remove(true)
                }
                GButton {
                    primary: true
                    text: root.isManual ? "Remove" : "Hide"
                    onClicked: root.isManual ? root.remove(false) : { Games.hide(root.game.id); root.close(); }
                }
            }
        }
    }
}
