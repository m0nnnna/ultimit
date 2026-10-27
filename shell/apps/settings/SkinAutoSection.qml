// SkinAutoSection.qml - Day / night: switch the skin by the clock (Theme.skinAuto, "skinAuto" in
// shell.json; the schedule itself runs in Persist.qml).
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

ColumnLayout {
    id: root
    spacing: 14

    readonly property var a: Theme.skinAuto
    readonly property var skinOptions: Object.keys(Theme.skins).map(k => ({ id: k, label: k }))
    function set(patch) { Theme.skinAuto = Theme.cleanAuto(Object.assign({}, Theme.skinAuto, patch)); }

    SectionLabel { text: "Day / night" }
    ToggleRow {
        Layout.fillWidth: true
        text: "Switch skin by time of day"
        checked: root.a.enabled
        // turning it on keeps the skin you have now as the night one (unless that is the day skin)
        onToggled: value => root.set(value ? { enabled: true, night: Theme.skin !== root.a.day ? Theme.skin : root.a.night } : { enabled: false })
    }
    ColumnLayout {
        visible: root.a.enabled
        Layout.fillWidth: true
        spacing: 10
        Text { text: "DAY SKIN"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2.2 }
        Chips { Layout.fillWidth: true; options: root.skinOptions; current: root.a.day; onPicked: id => root.set({ day: id }) }
        Text { text: "NIGHT SKIN"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2.2 }
        Chips { Layout.fillWidth: true; options: root.skinOptions; current: root.a.night; onPicked: id => root.set({ night: id }) }
        RowLayout {
            spacing: 10
            Text { text: "DAY FROM"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2.2 }
            TextEntry {
                implicitWidth: 72; placeholder: "07:00"; text: root.a.dayStart
                onAccepted: { if (Theme.validTime(text.trim())) root.set({ dayStart: text.trim() }); else text = root.a.dayStart; }
            }
            Text { text: "NIGHT FROM"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2.2 }
            TextEntry {
                implicitWidth: 72; placeholder: "19:00"; text: root.a.nightStart
                onAccepted: { if (Theme.validTime(text.trim())) root.set({ nightStart: text.trim() }); else text = root.a.nightStart; }
            }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "24-hour HH:MM, Enter to apply. Picking a skin by hand holds until the next switch."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
        }
    }
}
