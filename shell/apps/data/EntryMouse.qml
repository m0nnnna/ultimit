// EntryMouse.qml - mouse handling shared by list rows and grid cells: click / ctrl / shift
// selection, double-click open, right-click menu, and drag start (move; Ctrl = copy).
// `win` is the DataWindow (provides ghost + openItemMenu).
import QtQuick
import "../.."

MouseArea {
    id: root
    required property var host
    required property var entry
    required property int idx
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    property real px: 0
    property real py: 0
    property bool dragging: false

    onPressed: mouse => {
        host.forceActiveFocus();
        if (mouse.button === Qt.RightButton) {
            if (!Data.isSel(entry.p)) Data.selectOnly(idx);
            const pt = mapToItem(host.ui, mouse.x, mouse.y);
            host.openItemMenu(pt.x, pt.y);
            return;
        }
        px = mouse.x; py = mouse.y; dragging = false;
        if (mouse.modifiers & Qt.ControlModifier) Data.toggleSel(idx);
        else if (mouse.modifiers & Qt.ShiftModifier) Data.selectRange(idx);
        else if (!Data.isSel(entry.p)) Data.selectOnly(idx);
        else Data.setCur(idx);   // keep multi-selection so it can be dragged
    }
    onReleased: mouse => {
        if (dragging) {
            dragging = false;
            host.ghostDrop(mouse.modifiers & Qt.ControlModifier);
            return;
        }
        if (mouse.button === Qt.LeftButton && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
            && Data.selCount > 1 && Data.isSel(entry.p)) Data.selectOnly(idx);
    }
    onPositionChanged: mouse => {
        if (!pressed || !(pressedButtons & Qt.LeftButton) || Data.isTrash) return;
        if (!dragging && Math.abs(mouse.x - px) + Math.abs(mouse.y - py) > 10) {
            dragging = true;
            host.ghostStart(Data.dragPaths(entry), entry.n);
        }
        if (dragging) { const pt = mapToItem(host.ui, mouse.x, mouse.y); host.ghostMove(pt.x, pt.y); }
    }
    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) Data.openEntry(entry); }
}
