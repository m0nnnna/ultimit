// Tray.qml - StatusNotifierItem tray for the bottom bar (the app-icon half of StatusTray.qml).
// Left click = activate, middle = secondary activate, right click = the item's DBusMenu
// (TrayMenu overlay, opened above the bar). Hover tooltip (500 ms) reuses the WindowUi tip.
// Collapses to zero width when empty. Icons are shown as provided by the app (not tinted:
// full-colour app icons turn into blobs when forced monochrome).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import ".."

Row {
    id: root
    property string screenName: ""
    property real barX: 0       // x of this item inside the bar window; the bar sits at Config.railWidth
    readonly property int shown: {
        let n = 0;
        const v = SystemTray.items.values;
        for (let i = 0; i < v.length; i++) if (v[i].status !== Status.Passive) n++;
        return n;
    }
    visible: shown > 0
    height: parent ? parent.height : Config.tickerHeight
    spacing: 0

    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: ent
            required property var modelData
            readonly property bool vis: modelData.status !== Status.Passive
            visible: vis
            width: vis ? 28 : 0; height: root.height
            readonly property string tip: modelData.tooltipTitle || modelData.title || modelData.id
            function centerX() { return Config.railWidth + ent.mapToItem(null, ent.width / 2, 0).x; }

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: ent.tip || "Tray item"
            Accessible.onPressAction: ent.trigger(Qt.LeftButton)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { ent.trigger(Qt.LeftButton); event.accepted = true; }
                else if (event.key === Qt.Key_Menu) { ent.trigger(Qt.RightButton); event.accepted = true; }
            }
            function trigger(button) {
                tipTimer.stop(); WindowUi.hideTip();
                const it = ent.modelData;
                if (button === Qt.RightButton) {
                    if (it.hasMenu) TrayUi.openMenu(it, 0, root.screenName, ent.centerX());
                    else it.secondaryActivate();
                } else if (button === Qt.MiddleButton) {
                    it.secondaryActivate();
                } else if (it.onlyMenu && it.hasMenu) {
                    TrayUi.openMenu(it, 0, root.screenName, ent.centerX());
                } else {
                    it.activate();
                }
            }

            Rectangle {
                anchors.fill: parent
                color: mouse.pressed ? Theme.press : (mouse.containsMouse ? Theme.hover : Theme.clear(Theme.hover))
                Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            }
            Rectangle {   // keyboard focus ring
                anchors.fill: parent; anchors.margins: 1
                color: "transparent"; border.width: 1; border.color: Theme.accent
                visible: ent.activeFocus
            }
            Image {
                id: img
                anchors.centerIn: parent
                width: Theme.icon.md; height: Theme.icon.md
                source: ent.modelData.icon
                sourceSize: Qt.size(Theme.icon.md * 2, Theme.icon.md * 2)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                scale: mouse.pressed ? Theme.pressScale : 1
                Behavior on scale { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                visible: status === Image.Ready && !ent.tintDark
                onStatusChanged: if (status === Image.Ready && Theme.light) probe.loadImage(ent.modelData.icon)
            }
            // On a light skin a white / near-white symbolic icon vanishes: sample it, and when it is
            // mostly light (and not colourful) draw it as a dark silhouette instead.
            property bool tintDark: false
            Canvas {
                id: probe
                width: Theme.icon.md; height: Theme.icon.md; visible: false
                onImageLoaded: requestPaint()
                onPaint: {
                    const src = ent.modelData.icon;
                    if (!Theme.light || !isImageLoaded(src)) { ent.tintDark = false; return; }
                    const c = getContext("2d");
                    c.clearRect(0, 0, width, height);
                    c.drawImage(src, 0, 0, width, height);
                    const d = c.getImageData(0, 0, width, height).data;
                    let n = 0, lum = 0, sat = 0;
                    for (let i = 0; i < d.length; i += 4) {
                        if (d[i + 3] < 128) continue;
                        n++;
                        lum += (d[i] + d[i + 1] + d[i + 2]) / 765;
                        sat += (Math.max(d[i], d[i + 1], d[i + 2]) - Math.min(d[i], d[i + 1], d[i + 2])) / 255;
                    }
                    ent.tintDark = n > 8 && lum / n > 0.8 && sat / n < 0.15;
                }
            }
            Connections { target: Theme; function onLightChanged() { if (Theme.light && img.status === Image.Ready) probe.loadImage(ent.modelData.icon); else ent.tintDark = false; } }
            MultiEffect {
                anchors.centerIn: parent
                width: Theme.icon.md; height: Theme.icon.md
                source: img
                visible: ent.tintDark
                colorization: 1.0
                colorizationColor: Theme.fg
                scale: mouse.pressed ? Theme.pressScale : 1
                Behavior on scale { NumberAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
            }
            Rectangle {   // fallback when the icon cannot be resolved
                anchors.centerIn: parent
                width: Theme.icon.md; height: Theme.icon.md
                visible: !img.visible
                color: Theme.field
                Text {
                    anchors.centerIn: parent
                    text: (ent.tip || "?").charAt(0).toUpperCase()
                    color: Theme.fg; font.family: Theme.display; font.pixelSize: Theme.type.label
                }
            }
            Rectangle {   // needs-attention marker
                visible: ent.modelData.status === Status.NeedsAttention
                anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 4
                width: 5; height: 5; color: Theme.warn
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onEntered: tipTimer.restart()
                onExited: { tipTimer.stop(); WindowUi.hideTip(); }
                onWheel: wheel => ent.modelData.scroll(wheel.angleDelta.y, false)
                onClicked: mouseEvent => ent.trigger(mouseEvent.button)
            }
            Timer {
                id: tipTimer; interval: 500
                onTriggered: WindowUi.showBarTip(ent.tip, ent.centerX(), root.screenName)
            }
        }
    }
}
