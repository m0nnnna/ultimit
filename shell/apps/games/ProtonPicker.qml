// ProtonPicker.qml - Proton version choice: AUTO + every installed build (Games.protons), wrapping.
// `current` is a Proton directory ("" = auto); picked(path). Hint text underneath says what AUTO resolves to.
import QtQuick
import "../.."

Column {
    id: root
    property string current: ""
    signal picked(string path)

    readonly property var items: [{ path: "", name: "Auto" }].concat(Games.protons)
    readonly property bool missing: current !== "" && !Games.protons.some(p => p.path === current)

    spacing: 6

    Flow {
        width: parent.width
        spacing: 6
        Repeater {
            model: root.items
            delegate: Rectangle {
                id: seg
                required property var modelData
                readonly property bool on: root.current === modelData.path
                width: lbl.implicitWidth + 24
                height: 28
                color: on ? Theme.selection : (m.containsMouse ? Theme.hover : Theme.field)
                Behavior on color { ColorAnimation { duration: Config.dur(120) } }
                Text {
                    id: lbl
                    anchors.centerIn: parent
                    text: seg.modelData.name
                    color: seg.on ? Theme.accent : Theme.fg
                    font.family: Theme.mono
                    font.pixelSize: Theme.type.label
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }
                MouseArea {
                    id: m
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(seg.modelData.path)
                }
            }
        }
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: root.missing ? Theme.warn : Theme.dim
        font.family: Theme.ui; font.pixelSize: Theme.type.label
        text: root.missing ? "Chosen Proton not found; Auto is used instead."
            : Games.protons.length === 0 ? "No Proton installed (try ProtonPlus). umu-run will download UMU-Proton on first launch."
            : root.current === "" ? "Auto: newest GE/DW-Proton, else Proton - Experimental."
            : root.current
    }
}
