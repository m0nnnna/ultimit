// SectionLabel.qml - ".lbl" from the mockup: accent square + dim mono caps (`decode` scrambles it in, for headers).
import QtQuick
import "../.."
import "../../components"

Row {
    id: root
    property string text: ""
    property bool decode: false   // panel titles/headers: scramble in once (DecodeText)
    spacing: 8
    Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
    DecodeText {
        text: root.text.toUpperCase()
        decode: root.decode
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: Theme.size.sm
        font.letterSpacing: 2.2   // .22em
    }
}
