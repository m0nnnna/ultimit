// SectionLabel.qml - ".lbl" from the mockup: accent square + dim mono caps.
import QtQuick
import "../.."

Row {
    id: root
    property string text: ""
    spacing: 8
    Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
    Text {
        text: root.text.toUpperCase()
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 10
        font.letterSpacing: 2.2   // .22em
    }
}
