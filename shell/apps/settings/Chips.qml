// Chips.qml - segmented single-choice chips (".chip" in the mockup).
//   Chips { options: [{ id: "a", label: "A" }]; current: "a"; onPicked: id => ... }
import QtQuick
import "../.."

Flow {
    id: root
    property var options: []
    property string current: ""
    signal picked(string id)
    spacing: 6

    Repeater {
        model: root.options
        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool sel: root.current === String(modelData.id)
            width: t.implicitWidth + 24; height: 28
            color: sel ? Theme.accent : (m.containsMouse ? Theme.panel2 : "transparent")
            border.width: 1; border.color: sel ? Theme.accent : Theme.lineStrong
            activeFocusOnTab: true
            Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Space) { root.picked(String(modelData.id)); e.accepted = true; } }
            Text {
                id: t
                anchors.centerIn: parent
                text: String(chip.modelData.label).toUpperCase()
                color: chip.sel ? Theme.onAccent : Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 11
                font.letterSpacing: 1.4
            }
            MouseArea {
                id: m
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { chip.forceActiveFocus(Qt.MouseFocusReason); root.picked(String(chip.modelData.id)); }
            }
        }
    }
}
