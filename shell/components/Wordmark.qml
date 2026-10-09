// Wordmark.qml - "[ ULTIMIT ]" with dim brackets and the OS caption (bottom-right).
import QtQuick
import QtQuick.Window
import ".."

Column {
    id: root
    spacing: 2

    // clamp(28px, 4.2vw, 54px) in the mockup
    readonly property real wordSize: Math.max(28, Math.min(54, (Window.width || 1280) * 0.042))

    Row {
        anchors.right: parent.right
        spacing: wordSize * 0.14 * 0.6
        Text {
            text: "["
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: root.wordSize
            font.letterSpacing: root.wordSize * 0.14
        }
        Text {
            text: "ULTIMIT"
            color: Theme.fg
            font.family: Theme.display; font.pixelSize: root.wordSize
            font.letterSpacing: root.wordSize * 0.14
        }
        Text {
            text: "]"
            color: Theme.dim
            font.family: Theme.ui; font.pixelSize: root.wordSize
            font.letterSpacing: root.wordSize * 0.14
        }
    }
    Text {
        anchors.right: parent.right
        text: "OPERATING SYSTEM · " + Theme.skinLabel
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 10
        font.letterSpacing: 5   // .5em
    }
}
