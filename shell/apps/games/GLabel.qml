// GLabel.qml - small-caps section label (.lbl without the square): mono, tracked, dim.
import QtQuick
import "../.."

Text {
    property bool strong: false
    color: strong ? Theme.fg : Theme.dim
    font.family: Theme.mono
    font.pixelSize: Theme.type.label
    font.letterSpacing: 1.8
    font.capitalization: Font.AllUppercase
}
