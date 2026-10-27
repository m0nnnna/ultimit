// FontSetSection.qml - Fonts: the display / UI / mono family set (Theme.fontSet, "fontSet" in
// shell.json), each set drawn in its own fonts as a preview card.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

ColumnLayout {
    id: root
    spacing: 14

    SectionLabel { text: "Fonts" }
    GridLayout {
        Layout.fillWidth: true
        columnSpacing: 10; rowSpacing: 10
        columns: Math.max(1, Math.floor((width + 10) / 200))
        Repeater {
            model: Object.keys(Theme.fontSets)
            delegate: Rectangle {
                id: card
                required property string modelData
                readonly property var f: Theme.fontSets[modelData]
                readonly property bool sel: Theme.fontSet === modelData
                Layout.fillWidth: true
                implicitHeight: pv.implicitHeight + 24
                color: ma.containsMouse ? Theme.panel2 : "transparent"
                border.width: sel ? 2 : 1
                border.color: sel ? Theme.accent : (ma.containsMouse ? Theme.lineStrong : Theme.line)
                activeFocusOnTab: true
                Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { Theme.fontSet = modelData; e.accepted = true; } }
                Column {
                    id: pv
                    x: 12; y: 12
                    width: parent.width - 24
                    spacing: 5
                    Text {
                        text: card.f.n.toUpperCase()
                        color: Theme.fg; font.family: card.f.display; font.pixelSize: Theme.type.body; font.letterSpacing: 2.4
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: "The quick brown fox"
                        color: Theme.fg; font.family: card.f.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.body
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: "0123 ULTIMIT [ OK ]"
                        color: Theme.dim; font.family: card.f.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: (card.f.display + " / " + card.f.ui).toUpperCase()
                        color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.4
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { card.forceActiveFocus(Qt.MouseFocusReason); Theme.fontSet = card.modelData; }
                }
            }
        }
    }
}
