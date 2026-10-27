// Choice.qml - one selectable card (a drive, what to do with it, a Wi-Fi network): a title, a
// line under it, an optional tag on the right. `danger` marks a choice that erases something.
import QtQuick
import ".."

Rectangle {
    id: root
    property string title: ""
    property string sub: ""
    property string tag: ""
    property bool selected: false
    property bool danger: false
    signal picked()

    implicitHeight: col.implicitHeight + 24
    color: selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, .10) : (mouse.containsMouse && enabled ? Theme.panel2 : "transparent")
    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    border.width: selected ? 2 : 1
    border.color: !enabled ? Theme.line : selected ? (danger ? Theme.bad : Theme.accent) : Theme.lineStrong
    Behavior on border.color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
    opacity: enabled ? 1 : .5
    activeFocusOnTab: enabled
    Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.picked(); e.accepted = true; } }

    Rectangle {   // the accent bar of the selected card
        visible: root.selected
        width: 3; height: parent.height
        color: root.danger ? Theme.bad : Theme.accent
    }
    Column {
        id: col
        x: 16; y: 12
        width: parent.width - 32 - (tagText.visible ? tagText.width + 12 : 0)
        spacing: 4
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.title
            color: root.danger && root.selected ? Theme.bad : Theme.fg
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            font.family: Theme.ui; font.pixelSize: 16; font.weight: Font.DemiBold
        }
        Text {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.sub
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: 13
        }
    }
    Text {
        id: tagText
        visible: root.tag !== ""
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: root.tag
        color: root.danger ? Theme.bad : Theme.dim
        font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 2
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(); root.picked(); }
    }
}
