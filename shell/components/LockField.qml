// LockField.qml - the lock screen's chamfered, masked password field with its caret
// (desktop panel and the phone's MobileLock). State lives in LockScreen `ctl`.
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: field
    required property var ctl
    implicitHeight: 40
    readonly property real c: 8
    readonly property bool bad: field.ctl.authState === "fail"
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: field.bad ? 2 : 1
            strokeColor: field.bad ? Theme.bad : Theme.accent
            fillColor: Theme.panel2
            startX: field.c + .5; startY: .5
            PathLine { x: field.width - .5; y: .5 }
            PathLine { x: field.width - .5; y: field.height - field.c - .5 }
            PathLine { x: field.width - field.c - .5; y: field.height - .5 }
            PathLine { x: .5; y: field.height - .5 }
            PathLine { x: .5; y: field.c + .5 }
            PathLine { x: field.c + .5; y: .5 }
        }
    }
    Text {   // placeholder
        anchors.verticalCenter: parent.verticalCenter; x: 22
        visible: field.ctl.password.length === 0 && field.ctl.authState !== "auth"
        text: "ENTER PASSWORD"; color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 3
    }
    Text {   // masked input (tail is kept visible when long)
        id: dots
        anchors.verticalCenter: parent.verticalCenter; x: 14
        width: parent.width - 28
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideLeft
        text: "•".repeat(field.ctl.password.length)
        color: Theme.fg
        font.family: Theme.ui; font.pixelSize: 18; font.letterSpacing: 4
    }
    Rectangle {   // caret
        visible: field.ctl.authState !== "auth" && caretOn
        property bool caretOn: true
        id: caret
        x: 14 + Math.min(dots.contentWidth, dots.width) + 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2; height: 18; color: Theme.accent
        Timer { interval: 530; repeat: true; running: Config.motion; onTriggered: caret.caretOn = !caret.caretOn }
    }
}
