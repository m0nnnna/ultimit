// DMenu.qml - in-window context menu in the ContextMenu.qml style (panel fill, 1px line,
// accent hover row, mono labels). Fill `items` ({ id, label, hint?, check?, disabled? } or
// { kind: "sep" }), call popup(x, y); emits picked(id). Closes on click-away / Escape.
import QtQuick
import "../.."
import "../../components"

FocusScope {
    id: root
    visible: false
    anchors.fill: parent
    z: 50

    property var items: []
    property int cur: -1
    readonly property int rowH: 32
    readonly property int menuW: 260
    signal picked(string id)
    signal dismissed()

    readonly property int menuH: {
        let h = 12;
        for (const it of items) h += it.kind === "sep" ? 9 : rowH;
        return h;
    }
    function popup(x, y) {
        cur = -1;
        menu.x = Math.max(6, Math.min(x, root.width - menuW - 6));
        menu.y = Math.max(6, Math.min(y, root.height - menuH - 6));
        visible = true;
        forceActiveFocus();
    }
    function close() { if (visible) { visible = false; dismissed(); } }
    function rowY(idx) {
        let y = 6;
        for (let i = 0; i < idx; i++) y += items[i].kind === "sep" ? 9 : rowH;
        return y;
    }
    function step(d) {
        let i = cur;
        for (let n = 0; n < items.length; n++) {
            i = (i + d + items.length) % items.length;
            if (items[i].kind !== "sep" && !items[i].disabled) { cur = i; return; }
        }
    }
    function activate(it) {
        if (!it || it.kind === "sep" || it.disabled) return;
        visible = false;
        picked(it.id);
        dismissed();
    }

    Keys.onPressed: event => {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) close();
        else if (event.key === Qt.Key_Down) step(1);
        else if (event.key === Qt.Key_Up) step(-1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (cur >= 0) activate(items[cur]);
        } else event.accepted = false;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: root.close()
    }

    Rectangle {
        id: menu
        width: root.menuW; height: root.menuH
        color: Qt.rgba(Theme.bg1.r, Theme.bg1.g, Theme.bg1.b, 0.97)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
        Rectangle { anchors.fill: parent; color: Theme.panel }
        Brackets { size: 8 }

        Repeater {
            model: root.items
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool sep: modelData.kind === "sep"
                readonly property bool off: !!modelData.disabled
                x: 0; y: root.rowY(index)
                width: menu.width; height: sep ? 9 : root.rowH
                readonly property bool hot: root.cur === index && !off

                Rectangle { visible: row.sep; x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 20; height: 1; color: Theme.divider }
                Rectangle {
                    visible: !row.sep
                    anchors.fill: parent; anchors.leftMargin: 1; anchors.rightMargin: 1
                    color: row.hot ? Theme.selection : Theme.clear(Theme.selection)
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                }
                Text {
                    visible: !row.sep
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label || ""
                    color: row.off ? Theme.dim : (row.hot ? Theme.accent : Theme.fg)
                    Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                    opacity: row.off ? 0.55 : 1
                    font.family: Theme.ui; font.pixelSize: Theme.type.body
                }
                Text {
                    visible: !row.sep
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.check === true ? "■" : (row.modelData.hint || "")
                    color: row.modelData.check === true ? Theme.accent : Theme.dim
                    font.family: Theme.mono; font.pixelSize: Theme.type.label
                }
                MouseArea {
                    enabled: !row.sep && !row.off
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.cur = row.index
                    onClicked: root.activate(row.modelData)
                }
            }
        }
    }
}
