// SpeakersPage.qml - SPEAKERS tab: the output device and noise removal for what you hear (calls, streams).
import QtQuick
import QtQuick.Controls
import "../.."
import "../games"

Flickable {
    id: root
    contentHeight: Math.max(cols.implicitHeight, height)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    readonly property var spk: Broadcast.spk
    readonly property bool idle: Broadcast.busy === ""

    Row {
        id: cols
        width: root.width - 8
        spacing: 20

        Column {
            width: 270
            spacing: 10
            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                GLabel { text: "Speakers"; strong: true }
            }
            DeviceList {
                width: parent.width
                devices: (root.spk.devices || []).map(d => ({ id: d.id, label: d.description, tag: d.default ? "default" : "" }))
                current: root.spk.device ? String(root.spk.device.id) : ""
                emptyText: "No speakers found"
                onPicked: id => {}
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: "Shows your current output. Change it in Settings, Sound."
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
            }
            Column {
                width: parent.width
                spacing: 8
                visible: Broadcast.audioRunning && !!root.spk.eeNode && !root.spk.routed
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Only apps that play through “Easy Effects Sink” are cleaned."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                }
                GButton { text: "Make it the default output"; enabled: root.idle; onClicked: Broadcast.route("speakers") }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                visible: Broadcast.audioRunning && root.spk.routed
                text: "✓ Apps play through “Easy Effects Sink”."
                color: Theme.ok; font.family: Theme.ui; font.pixelSize: 12
            }
        }

        Column {
            width: cols.width - 290
            spacing: 12
            EffectCard {
                width: parent.width
                title: "Noise removal"
                desc: "Cleans background noise out of what other people say in calls and streams before it reaches your ears."
                checked: root.spk.enabled === true
                onToggled: v => { if (root.idle) Broadcast.speakersSet("enabled", v); }
                GSeg {
                    options: [{ id: "strong", label: "Strong" }, { id: "light", label: "Light" }]
                    current: root.spk.strength || "strong"
                    opacity: root.spk.enabled ? 1 : 0.5
                    onPicked: id => { if (root.idle) Broadcast.speakersSet("strength", id); }
                }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: "Music and games are cleaned too while this is on. Turn it off for them."
                color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
            }
        }
    }
}
