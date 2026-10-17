// PhotoFrame.qml - one photo frame on the desktop (see Frames.qml), drawn inside Wallpaper.
// Unlocked: drag to move, drag the bottom-right corner to resize (the picture keeps its shape).
// Right-click opens the frame menu (lock, change picture, remove) through the desktop
// ContextMenu; double-click opens the picture in IMAGE. A locked frame stays put.
// Moving and resizing stay local until the button is let go, then go to Frames once.
import QtQuick
import ".."

Item {
    id: fr

    required property string frameId
    property string screenName: ""
    readonly property var f: Frames.list.find(o => o.id === fr.frameId) || null
    readonly property bool locked: !!(f && f.locked)

    readonly property int pad: 8
    // Height over width: the picture's own once it loaded, until then the saved size's.
    readonly property real ratio: pic.status === Image.Ready && pic.implicitWidth > 0 ? pic.implicitHeight / pic.implicitWidth
        : (f && f.h > 0 ? f.h / f.w : 0.75)
    property real liveW: -1                       // while resizing
    property real dx: 0; property real dy: 0      // while moving
    readonly property real picW: liveW >= 0 ? liveW : (f ? f.w : Frames.defaultWidth)
    readonly property real picH: Math.round(picW * ratio)

    visible: f !== null
    width: picW + 2 * pad
    height: picH + 2 * pad
    // Kept on screen, also when the screen got smaller since.
    x: f && parent ? Math.max(0, Math.min(f.x + dx, parent.width - width)) : 0
    y: f && parent ? Math.max(0, Math.min(f.y + dy, parent.height - height)) : 0

    // The picture's shape, once known, is saved with the frame; a new picture's longer side
    // gets the saved width (so a tall one doesn't come out twice as high).
    function settle() {
        if (!f || f.h > 0 || pic.status !== Image.Ready || pic.implicitWidth <= 0) return;
        const r = pic.implicitHeight / pic.implicitWidth;
        const w = Math.max(Frames.minSize, Math.round(r > 1 ? f.w / r : f.w));
        Frames.update(frameId, { w: w, h: Math.round(w * r) });
    }

    Rectangle {   // the mat
        anchors.fill: parent
        color: Theme.panel
        border.width: 1
        border.color: hover.containsMouse && !fr.locked ? Theme.accent : Theme.lineStrong
        Brackets { size: 10; visible: hover.containsMouse || fr.locked }
    }

    Image {
        id: pic
        x: fr.pad; y: fr.pad
        width: fr.picW; height: fr.picH
        source: fr.f ? "file://" + fr.f.path : ""
        sourceSize: Qt.size(1600, 1600)   // fits inside, keeps the shape; plenty for a desktop frame
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true; mipmap: true
        onStatusChanged: fr.settle()
    }
    Text {
        visible: pic.status === Image.Error
        anchors.centerIn: pic
        width: pic.width - 16
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WrapAnywhere
        text: "PICTURE MISSING\n" + (fr.f ? fr.f.path : "")
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
    }

    MouseArea {   // move, menu, open
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: fr.locked ? Qt.ArrowCursor : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
        property point start
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                const p = mapToItem(null, mouse.x, mouse.y);
                Config.openMenu(fr.screenName, p.x, p.y, fr.frameId);
                return;
            }
            start = mapToItem(null, mouse.x, mouse.y);
        }
        onPositionChanged: mouse => {
            if (!pressed || fr.locked || !(pressedButtons & Qt.LeftButton)) return;
            const p = mapToItem(null, mouse.x, mouse.y);
            fr.dx = p.x - start.x; fr.dy = p.y - start.y;
        }
        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton || (fr.dx === 0 && fr.dy === 0)) return;
            const nx = Math.round(fr.x), ny = Math.round(fr.y);
            fr.dx = 0; fr.dy = 0;
            Frames.update(fr.frameId, { x: nx, y: ny });
        }
        onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) Frames.openInImage(fr.frameId); }
    }

    Item {   // resize grip, bottom-right (its strokes show while the pointer is on the frame)
        visible: !fr.locked
        width: 18; height: 18
        anchors.right: parent.right; anchors.bottom: parent.bottom
        Repeater {   // three accent strokes, rising to the corner
            model: 3
            Rectangle {
                required property int index
                visible: hover.containsMouse || grip.containsMouse || grip.pressed
                width: 2; height: 4 + index * 4
                x: 4 + index * 5; y: 15 - height
                color: Theme.accent
            }
        }
        MouseArea {
            id: grip
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            property point start
            property real startW
            onPressed: mouse => { start = mapToItem(null, mouse.x, mouse.y); startW = fr.picW }
            onPositionChanged: mouse => {
                if (!pressed || !fr.parent) return;
                const p = mapToItem(null, mouse.x, mouse.y);
                // Follow whichever way the pointer went further, keeping the picture's shape.
                const byX = startW + (p.x - start.x), byY = startW + (p.y - start.y) / fr.ratio;
                const maxW = Math.min(fr.parent.width - fr.x, (fr.parent.height - fr.y) / fr.ratio) - 2 * fr.pad;
                fr.liveW = Math.round(Math.max(Frames.minSize, Math.min(Math.max(byX, byY), maxW)));
            }
            onReleased: {
                if (fr.liveW < 0) return;
                const w = fr.liveW;
                Frames.update(fr.frameId, { w: w, h: Math.round(w * fr.ratio) });
                fr.liveW = -1;
            }
        }
    }
}
