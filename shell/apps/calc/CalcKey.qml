// CalcKey.qml - one calculator key: flat outlined square, hover wash, accent fill for "=".
import QtQuick
import "../.."

Item {
    id: root
    property string text: ""
    property string kind: "num"      // num | op | fn | eq
    property bool on: false
    signal clicked()
    implicitHeight: 42
    implicitWidth: 64
    readonly property bool fill: kind === "eq" || on
    Rectangle {
        anchors.fill: parent; anchors.margins: 2
        color: root.fill ? Theme.accent : (ma.pressed ? Theme.lineStrong : (ma.containsMouse ? Theme.panel2 : (root.kind === "num" ? Theme.panel2 : "transparent")))
        border.width: 1; border.color: root.fill ? Theme.accent : (root.kind === "op" ? Theme.lineStrong : Theme.line)
        Text {
            anchors.centerIn: parent
            text: root.text
            color: root.fill ? Theme.onAccent : (root.kind === "op" ? Theme.accent : (root.kind === "fn" ? Theme.dim : Theme.fg))
            font.family: root.kind === "fn" ? Theme.mono : Theme.ui
            font.pixelSize: root.kind === "fn" ? 13 : 18
            font.weight: Font.DemiBold
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
