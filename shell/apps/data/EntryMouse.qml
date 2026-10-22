// EntryMouse.qml - mouse handling shared by list rows and grid cells: click / ctrl / shift
// selection, double-click open, right-click menu, and drag start (move; Ctrl = copy).
// A drag that leaves the window goes on as a system drag, into other apps.
// `win` is the DataWindow (provides ghost + openItemMenu).
import QtQuick
import "../.."

MouseArea {
    id: root
    required property var host
    required property var entry
    required property int idx
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    property real px: 0
    property real py: 0
    property bool dragging: false
    property bool handedOut: false   // the drag left the window: the system drag has it now
    property bool held: false        // phone: the press became a long-press (context menu), so no tap-open

    onPressed: mouse => {
        host.forceActiveFocus();
        if (mouse.button === Qt.MiddleButton) { Data.openInTabs([entry]); return; }   // folders / archives: background tab
        if (mouse.button === Qt.RightButton) {
            if (!Data.isSel(entry.p)) Data.selectOnly(idx);
            const pt = mapToItem(host.ui, mouse.x, mouse.y);
            host.openItemMenu(pt.x, pt.y);
            return;
        }
        px = mouse.x; py = mouse.y; dragging = false; handedOut = false; held = false;
        if (mouse.modifiers & Qt.ControlModifier) Data.toggleSel(idx);
        else if (mouse.modifiers & Qt.ShiftModifier) Data.selectRange(idx);
        else if (!Data.isSel(entry.p)) Data.selectOnly(idx);
        else Data.setCur(idx);   // keep multi-selection so it can be dragged
    }
    onReleased: mouse => {
        if (dragging) {
            dragging = false;
            if (handedOut) return;
            host.ghostDrop(mouse.modifiers & Qt.ControlModifier);
            return;
        }
        if (mouse.button === Qt.LeftButton && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
            && Data.selCount > 1 && Data.isSel(entry.p)) Data.selectOnly(idx);
    }
    onPositionChanged: mouse => {
        if (!pressed || !(pressedButtons & Qt.LeftButton) || Data.isTrash || Data.isArc || handedOut || Config.mobile) return;   // touch drags scroll the list
        if (!dragging && Math.abs(mouse.x - px) + Math.abs(mouse.y - py) > 10) {
            dragging = true;
            host.ghostStart(Data.dragPaths(entry), entry.n);
        }
        if (!dragging) return;
        const pt = mapToItem(host.ui, mouse.x, mouse.y);
        if (pt.x < 0 || pt.y < 0 || pt.x >= host.ui.width || pt.y >= host.ui.height) { handedOut = true; host.ghostOut(); }
        else host.ghostMove(pt.x, pt.y);
    }
    // phone: a tap opens, a long-press selects and shows the item menu
    onClicked: mouse => { if (Config.mobile && mouse.button === Qt.LeftButton && !held) Data.openEntry(entry); }
    onPressAndHold: mouse => {
        if (!Config.mobile) return;
        held = true;
        if (!Data.isSel(entry.p)) Data.selectOnly(idx);
        const pt = mapToItem(host.ui, mouse.x, mouse.y);
        host.openItemMenu(pt.x, pt.y);
    }
    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) Data.openEntry(entry); }
}
