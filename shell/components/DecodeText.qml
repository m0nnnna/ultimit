// DecodeText.qml - a text that "decodes" when it appears: the characters scramble for ~150 ms
// (five 30 ms steps, settling left to right), then show the real text. Like Boot's lines coming up.
// Use it for panel titles and headers. Runs when created, when it becomes visible and when `text`
// changes; plain text with `decode: false`, Config.decodeText off, reduced motion, or while a
// fullscreen window pauses the desktop. Its width comes from the final text, so the layout does not
// shift while the glyphs change (best with Theme.mono).
//   DecodeText { text: "SOUND"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.size.sm }
import QtQuick
import ".."

Item {
    id: root

    property string text: ""
    property alias font: label.font
    property alias color: label.color
    property alias elide: label.elide
    property alias horizontalAlignment: label.horizontalAlignment
    property bool decode: true

    readonly property int steps: 5
    readonly property bool active: root.decode && Config.decodeText && Config.motion && !Config.desktopPaused
    property int step: root.steps
    property string shown: root.text

    implicitWidth: Math.ceil(metrics.advanceWidth)
    implicitHeight: label.implicitHeight

    TextMetrics { id: metrics; font: label.font; text: root.text }
    Text { id: label; anchors.fill: parent; text: root.shown; textFormat: Text.PlainText }

    readonly property string glyphs: "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#/<>_+"
    function scramble() {
        const settled = Math.floor(root.text.length * root.step / root.steps);
        let s = "";
        for (let i = 0; i < root.text.length; i++) {
            const ch = root.text[i];
            if (i < settled || ch === " ") { s += ch; continue; }
            const g = root.glyphs[Math.floor(Math.random() * root.glyphs.length)];
            s += ch === ch.toLowerCase() && ch !== ch.toUpperCase() ? g.toLowerCase() : g;
        }
        root.shown = s;
    }
    function run() {
        if (!root.active || !root.visible || root.text === "") { tick.stop(); root.step = root.steps; root.shown = root.text; return; }
        root.step = 0;
        root.scramble();
        tick.restart();
    }
    Timer {
        id: tick
        interval: 30
        repeat: true
        onTriggered: {
            root.step++;
            if (root.step >= root.steps) { tick.stop(); root.shown = root.text; }
            else root.scramble();
        }
    }
    onTextChanged: root.run()
    onVisibleChanged: if (root.visible) root.run()
    Component.onCompleted: root.run()
}
