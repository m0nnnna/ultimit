// MicPage.qml - MICROPHONE tab: device picker, live level, noise removal, room echo removal, hear yourself.
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

    readonly property var mic: Broadcast.mic
    readonly property bool idle: Broadcast.busy === ""
    property string pending: ""          // device picked but not yet made the default

    function devs() {
        return (mic.devices || []).map(d => ({ id: d.id, label: d.description, tag: d.default ? "default" : "" }));
    }

    Grid {   // phone: the two columns stack
        id: cols
        width: root.width - 8
        columns: Config.mobile ? 1 : 2
        spacing: 20

        // ---- left: which microphone ----
        Column {
            width: Config.mobile ? cols.width : 270
            spacing: 10
            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                GLabel { text: "Microphone"; strong: true }
            }
            DeviceList {
                width: parent.width
                devices: root.devs()
                current: root.pending !== "" ? root.pending : (root.mic.device ? String(root.mic.device.id) : "")
                emptyText: "No microphone found"
                onPicked: id => root.pending = id
            }
            Column {
                width: parent.width
                spacing: 8
                visible: root.pending !== "" && root.mic.device && root.pending !== String(root.mic.device.id)
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "BROADCAST cleans your default microphone. Picking another one makes it the default microphone for the whole system."
                    color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
                }
                Row {
                    spacing: 8
                    GButton { text: "Make default"; primary: true; enabled: root.idle; onClicked: { Broadcast.useMic(root.pending); root.pending = ""; } }
                    GButton { text: "Cancel"; onClicked: root.pending = "" }
                }
            }
            Column {
                width: parent.width
                spacing: 8
                visible: Broadcast.audioRunning && !!root.mic.eeNode && !root.mic.routed
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Apps only hear the cleaned sound when they use “Easy Effects Source” as their microphone."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                }
                GButton { text: "Make it the default mic"; enabled: root.idle; onClicked: Broadcast.route("mic") }
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                visible: Broadcast.audioRunning && root.mic.routed
                text: "✓ Apps use “Easy Effects Source” as the microphone."
                color: Theme.ok; font.family: Theme.ui; font.pixelSize: 12
            }
        }

        // ---- right: level + effects ----
        Column {
            width: Config.mobile ? cols.width : cols.width - 290
            spacing: 12

            Rectangle {
                width: parent.width; height: 112
                color: Theme.panel2; border.color: Theme.line; border.width: 1
                Brackets { color: Theme.accent; size: 10; thickness: 2 }
                GLabel { x: 18; y: 14; text: "Input level" + (root.mic.enabled && Broadcast.audioRunning ? " · after noise removal" : " · raw") }
                GLabel {
                    anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 14 }
                    visible: !Config.mobile
                    text: root.mic.device ? root.mic.device.description : ""
                    elide: Text.ElideRight; width: parent.width / 2; horizontalAlignment: Text.AlignRight
                }
                LevelMeter {
                    x: 18; y: 48
                    width: parent.width - 36
                    nodeName: Broadcast.meterNode
                    active: root.visible && Broadcast.open && Broadcast.tab === "mic"
                }
            }

            EffectCard {
                width: parent.width
                title: "Noise removal"
                desc: "Takes keyboard, fans and room noise out of your voice, for every app."
                checked: root.mic.enabled === true
                onToggled: v => { if (root.idle) Broadcast.micSet("enabled", v); }
                GSeg {
                    options: [{ id: "strong", label: "Strong" }, { id: "light", label: "Light" }]
                    current: root.mic.strength || "strong"
                    opacity: root.mic.enabled ? 1 : 0.5
                    onPicked: id => { if (root.idle) Broadcast.micSet("strength", id); }
                }
            }
            EffectCard {
                width: parent.width
                title: "Room echo removal"
                desc: "Reduces the hollow echo of a bare room."
                checked: root.mic.echo === true
                available: true
                onToggled: v => { if (root.idle) Broadcast.micSet("echo", v); }
            }
            EffectCard {
                width: parent.width
                title: "Hear yourself"
                desc: "Plays your cleaned voice back in your speakers or headphones, to check how you sound."
                checked: Broadcast.monitorOn
                onToggled: v => { if (root.idle) Broadcast.monitor(v); }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Use headphones: through speakers this feeds back into your microphone."
                    color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
                }
            }
        }
    }
}
