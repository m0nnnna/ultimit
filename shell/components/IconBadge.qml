// IconBadge.qml - the app icon for apps the Ultimit theme does not draw: a hex badge (Config.appIcons
// "letters") or the older chamfered square ("original" mode, where a real icon sits inside it) with
// the app's icon or, failing that, its first letter inside. One component so the rail pins, the
// launcher, the WINDOWS list and Alt-Tab all show the same thing.
//   IconBadge { size: 30; letter: "F"; iconSrc: Icons.app("firefox"); active: false }
import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root

    property int size: 30
    property string letter: ""
    property string iconSrc: ""
    property bool active: false
    property color textColor: root.active ? Theme.accent : Theme.fg
    property string shape: Config.appIcons === "letters" ? "hex" : "chamfer"
    readonly property bool hex: root.shape === "hex"
    readonly property bool hasImage: root.iconSrc !== "" && img.status !== Image.Error

    width: size; height: size

    // pointy-top hexagon in the box, or the box with its top-right / bottom-left corners cut
    readonly property var pts: {
        const s = root.size, c = s / 2, r = s / 2 - 0.5, out = [];
        if (root.hex) {
            for (let k = 0; k <= 6; k++) {
                const a = (-90 + 60 * k) * Math.PI / 180;
                out.push(Qt.point(c + r * Math.cos(a), c + r * Math.sin(a)));
            }
            return out;
        }
        const k = s * 5 / 30;
        return [Qt.point(0.5, 0.5), Qt.point(s - 0.5 - k, 0.5), Qt.point(s - 0.5, 0.5 + k), Qt.point(s - 0.5, s - 0.5),
                Qt.point(0.5 + k, s - 0.5), Qt.point(0.5, s - 0.5 - k), Qt.point(0.5, 0.5)];
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1
            strokeColor: root.active ? Theme.accent : Theme.lineStrong
            fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.active ? 0.14 : 0.08)
            joinStyle: ShapePath.MiterJoin
            PathPolyline { path: root.pts }
        }
    }
    Image {
        id: img
        anchors.centerIn: parent
        width: Math.round(root.size * (root.hex ? 0.52 : 0.66)); height: width
        visible: root.iconSrc !== "" && status !== Image.Error
        source: root.iconSrc
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
    Text {
        anchors.centerIn: parent
        visible: !root.hasImage
        text: root.letter
        color: root.textColor
        font.family: Theme.display; font.pixelSize: Theme.ds(Math.round(root.size * 0.4))
    }
}
