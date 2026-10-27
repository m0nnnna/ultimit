// Selector.qml - chamfered picker. Collapsed: Left/Right/Up/Down cycle the choice, Enter or click opens
// the list. Open: Up/Down move the highlight, Enter or click commits, Esc/focus loss closes.
import QtQuick
import QtQuick.Shapes

FocusScope {
    id: root
    property var model: []            // [{label, sub}]
    property int currentIndex: 0
    property string caption: ""
    property bool expanded: false
    property int hl: 0
    signal activated(int index)

    activeFocusOnTab: true
    readonly property real c: 8
    readonly property int rowH: 30
    readonly property bool multi: model.length > 1
    implicitHeight: 40 + (expanded ? model.length * rowH + 4 : 0)
    height: implicitHeight
    onActiveFocusChanged: if (!activeFocus) expanded = false

    function step(d) {
        const n = model.length;
        if (n < 2) return;
        if (expanded) hl = (hl + d + n) % n;
        else root.activated((currentIndex + d + n) % n);
    }
    function toggle() {
        if (!multi) return;
        if (expanded) { expanded = false; root.activated(hl); }
        else { hl = currentIndex; expanded = true; }
    }
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) { step(-1); e.accepted = true; }
        else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down) { step(1); e.accepted = true; }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { toggle(); e.accepted = true; }
        else if (e.key === Qt.Key_Escape && expanded) { expanded = false; e.accepted = true; }
    }

    Item {
        id: head
        width: parent.width; height: 40
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1
                strokeColor: root.activeFocus ? Theme.accent : Theme.lineStrong
                fillColor: hm.containsMouse ? Theme.panel2 : "transparent"
                startX: root.c + .5; startY: .5
                PathLine { x: head.width - .5; y: .5 }
                PathLine { x: head.width - .5; y: head.height - root.c - .5 }
                PathLine { x: head.width - root.c - .5; y: head.height - .5 }
                PathLine { x: .5; y: head.height - .5 }
                PathLine { x: .5; y: root.c + .5 }
                PathLine { x: root.c + .5; y: .5 }
            }
        }
        Text {
            id: cap
            x: 14; anchors.verticalCenter: parent.verticalCenter
            text: root.caption; color: Theme.dim
            font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2.4
        }
        Text {
            id: lbl
            anchors.verticalCenter: parent.verticalCenter
            x: cap.x + cap.width + 12
            width: parent.width - x - arrow.width - 24
            elide: Text.ElideRight
            readonly property var cur: root.model[root.currentIndex]
            text: cur ? (cur.label || "") : "—"
            color: Theme.fg
            font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 15; font.letterSpacing: 1.5
        }
        Text {
            id: arrow
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right; anchors.rightMargin: 14
            visible: root.multi
            text: root.expanded ? "▴" : "◂▸"; color: root.activeFocus ? Theme.accent : Theme.dim
            Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            font.family: Theme.mono; font.pixelSize: 12
        }
        MouseArea {
            id: hm; anchors.fill: parent; hoverEnabled: true
            cursorShape: root.multi ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.toggle(); }
        }
    }

    Column {
        visible: root.expanded
        y: 44; width: parent.width
        Repeater {
            model: root.model
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: root.width; height: root.rowH
                color: index === root.hl ? Theme.panel2 : "transparent"
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                border.width: 0
                Rectangle {
                    width: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent
                    height: index === root.hl ? parent.height : 0; visible: height > 0
                    Behavior on height { NumberAnimation { duration: Config.dur(Theme.motion.base); easing.type: Theme.easeBase } }
                }
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * .5 - 20; elide: Text.ElideRight
                    text: parent.modelData.label; color: Theme.fg
                    font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 13; font.letterSpacing: 1.2
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * .5 - 20; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
                    text: parent.modelData.sub || ""; color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.5
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: root.hl = index
                    onClicked: { root.hl = index; root.expanded = false; root.activated(index); }
                }
            }
        }
    }
}
