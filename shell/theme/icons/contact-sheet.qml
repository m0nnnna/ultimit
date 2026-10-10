// contact-sheet.qml - renders every icon of a built Ultimit theme at 48/24/16 px on the skin's panel colour.
// Usage: QT_QPA_PLATFORM=offscreen SHEET_THEME=<dir>/Ultimit-Mine SHEET_PANEL='#0d0f12' SHEET_FG='#eef1f4' \
//        SHEET_OUT=/tmp/x.png [SHEET_ZOOM=2] [SHEET_FILTER=prefix] qs -p contact-sheet.qml
import QtQuick
import Quickshell

ShellRoot {
    id: root
    readonly property string theme: Quickshell.env("SHEET_THEME")
    readonly property string panel: Quickshell.env("SHEET_PANEL") || "#0d0f12"
    readonly property string fgc: Quickshell.env("SHEET_FG") || "#eeeeee"
    readonly property string outPath: Quickshell.env("SHEET_OUT")
    readonly property real zoom: parseFloat(Quickshell.env("SHEET_ZOOM") || "1")
    readonly property string filter: Quickshell.env("SHEET_FILTER")
    property var entries: []

    Component.onCompleted: {
        const x = new XMLHttpRequest();
        x.open("GET", "file://" + theme + "/names.json", false);
        x.send();
        const j = JSON.parse(x.responseText);
        const al = {}; for (const a of j.aliases) al[a] = 1;
        const out = [];
        for (const k of Object.keys(j.icons).sort()) {
            if (al[k] && !Quickshell.env("SHEET_ALL")) continue;
            if (filter && k.indexOf(filter) !== 0 && j.icons[k].indexOf(filter) < 0) continue;
            out.push({ name: k, path: "file://" + theme + "/" + j.icons[k] });
        }
        entries = out;
    }

    FloatingWindow {
        id: win
        visible: true
        color: root.panel
        implicitWidth: 1280
        implicitHeight: Math.ceil(root.entries.length / 8) * (84 * root.zoom + 20) + 20

        Rectangle { id: bgr; anchors.fill: parent; color: root.panel
        Flow {
            id: flow
            x: 10; y: 10; width: parent.width - 20; spacing: 0
            Repeater {
                model: root.entries
                delegate: Item {
                    required property var modelData
                    width: 156 * 1; height: 84 * root.zoom + 20
                    Row {
                        x: 4; y: 4; spacing: 6
                        Image { source: modelData.path; sourceSize: Qt.size(48 * root.zoom, 48 * root.zoom); width: 48 * root.zoom; height: 48 * root.zoom }
                        Column {
                            spacing: 4
                            Image { source: modelData.path; sourceSize: Qt.size(24, 24); width: 24; height: 24 }
                            Image { source: modelData.path; sourceSize: Qt.size(16, 16); width: 16; height: 16 }
                        }
                    }
                    Text {
                        x: 4; y: 56 * root.zoom + 4; width: 150
                        text: modelData.name; elide: Text.ElideRight
                        color: root.fgc; opacity: .7; font.pixelSize: 9; font.family: "monospace"
                    }
                }
            }
        }
        }
        Timer {
            interval: 900; running: root.entries.length > 0; repeat: false
            onTriggered: bgr.grabToImage(r => { r.saveToFile(root.outPath); Qt.quit(); })
        }
    }
}
