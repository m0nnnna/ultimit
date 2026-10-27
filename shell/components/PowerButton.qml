// PowerButton.qml - small chamfered button with optional two-step confirm.
// First click arms it ("Sure?" in warn color, auto-disarms after 3s); second click emits activated().
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root
    property string text: ""
    property bool confirm: false
    property bool armed: false
    signal activated()
    signal disarmed()

    // Tighter padding and lettering where a row of them must fit one line (the launcher's power row).
    property bool compact: false
    implicitWidth: lbl.implicitWidth + (compact ? 16 : 24)
    implicitHeight: Theme.space(8)
    opacity: enabled ? 1 : 0.4
    readonly property real c: 6

    function disarm() { armed = false; }
    Timer { interval: 3000; running: root.armed; onTriggered: root.armed = false }

    function trigger() {
        if (!enabled) return;
        if (confirm && !armed) { armed = true; return; }
        armed = false;
        activated();
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1
            strokeColor: root.armed ? Theme.warn : (root.activeFocus ? Theme.accent : Theme.lineStrong)
            fillColor: mouse.containsMouse && root.enabled ? Theme.hover : Theme.clear(Theme.hover)
            Behavior on fillColor { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            startX: root.c + .5; startY: .5
            PathLine { x: root.width - .5; y: .5 }
            PathLine { x: root.width - .5; y: root.height - root.c - .5 }
            PathLine { x: root.width - root.c - .5; y: root.height - .5 }
            PathLine { x: .5; y: root.height - .5 }
            PathLine { x: .5; y: root.c + .5 }
            PathLine { x: root.c + .5; y: .5 }
        }
    }
    Text {
        id: lbl
        anchors.centerIn: parent
        text: root.compact ? (root.armed ? "Sure?" : root.text) : (root.armed ? "Sure?" : root.text).toUpperCase()
        color: root.armed ? Theme.warn : Theme.fg
        font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: Theme.type.label
        font.letterSpacing: root.compact ? 0 : 1.6
    }
    activeFocusOnTab: false
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.trigger()
    }
}
