// Chips.qml - segmented single-choice chips (".chip" in the mockup).
//   Chips { options: [{ id: "a", label: "A" }]; current: "a"; onPicked: id => ... }
import QtQuick
import "../.."

Flow {
    id: root
    property var options: []
    property string current: ""
    signal picked(string id)
    spacing: 8
    // Caps tracked labels only while every option is one short word (ON / OFF, LETTERS); a row with
    // any phrase reads in sentence case.
    readonly property bool caps: options.every(o => !/\s/.test(String(o.label).trim()))

    Repeater {
        model: root.options
        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool sel: root.current === String(modelData.id)
            width: t.implicitWidth + 24; height: 28
            color: sel ? Theme.accent : (m.containsMouse ? Theme.press : Theme.field)
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            activeFocusOnTab: true
            Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Space) { root.picked(String(modelData.id)); e.accepted = true; } }
            Text {
                id: t
                anchors.centerIn: parent
                text: root.caps ? String(chip.modelData.label).toUpperCase() : String(chip.modelData.label)
                color: chip.sel ? Theme.onAccent : Theme.fg
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                font.family: Theme.ui; font.weight: Font.DemiBold
                font.pixelSize: root.caps ? Theme.type.label : Theme.type.body
                font.letterSpacing: root.caps ? 1.4 : 0
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
