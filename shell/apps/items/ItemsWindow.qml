// ItemsWindow.qml - the ITEMS window: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Devices on the left; on the right the chosen device's profile: lighting, DPI levels and what each button does.
import QtQuick
import Quickshell
import "../.."
import "../games"

FloatingWindow {
    id: win
    title: "ITEMS"
    visible: Items.open
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(760, 520)
    color: "transparent"

    onVisibleChanged: if (visible !== Items.open) Items.open = visible

    component Heading: Text {
        color: Theme.dim
        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
    }
    component FieldError: Text {
        color: Theme.bad
        font.family: Theme.ui; font.pixelSize: 11
        visible: text !== ""
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        // ---------------- devices ----------------
        Rectangle {
            id: side
            width: 230
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            color: Theme.panel2
            Column {
                x: 14; y: 16
                width: parent.width - 28
                spacing: 6
                Heading { text: "DEVICES" }
                Repeater {
                    model: Items.devices
                    delegate: Rectangle {
                        id: devRow
                        required property var modelData
                        readonly property bool on: Items.current === modelData.id
                        width: parent.width
                        height: 52
                        color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (dm.containsMouse ? Theme.panel : "transparent")
                        border.color: on ? Theme.accent : "transparent"
                        Column {
                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 3
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: devRow.modelData.name
                                color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                            }
                            Text {
                                text: (devRow.modelData.present ? "● connected" : "○ not plugged in") + " · " + devRow.modelData.kind
                                color: devRow.modelData.present ? Theme.ok : Theme.dim
                                font.family: Theme.mono; font.pixelSize: 10
                            }
                        }
                        MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; onClicked: Items.select(devRow.modelData.id) }
                    }
                }
                Text {
                    visible: Items.devices.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "No supported devices yet."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                }
            }
            GChip {
                visible: Items.fake
                anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
                text: "Pretend devices"
                tone: Theme.warn
            }
        }

        // ---------------- the chosen device ----------------
        Item {
            id: main
            anchors { top: parent.top; bottom: parent.bottom; left: side.right; right: parent.right; margins: 20 }
            visible: Items.config !== null && Items.schema !== null

            Item {
                id: header
                width: parent.width
                height: 34
                GSeg {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    options: {
                        const o = [];
                        for (let i = 0; i < (Items.schema ? Items.schema.profiles : 0); i++) o.push({ id: String(i), label: "Profile " + (i + 1) });
                        return o;
                    }
                    current: String(Items.profile)
                    onPicked: id => Items.profile = Number(id)
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    GButton { text: "Revert"; visible: Items.dirty; onClicked: Items.revert() }
                    GButton {
                        text: Items.busy ? "Sending…" : "Apply to " + (Items.device ? Items.device.kind : "device")
                        primary: true
                        enabled: !Items.busy
                        onClicked: Items.apply()
                    }
                }
            }

            Text {
                id: noteLine
                anchors { top: header.bottom; topMargin: 8 }
                width: parent.width
                visible: text !== ""
                wrapMode: Text.WordWrap
                text: Items.note !== "" ? Items.note
                    : (Items.device && !Items.device.present ? "The device isn't plugged in. Changes are saved and sent when you apply with it connected." : "")
                color: Items.noteKind === "error" ? Theme.bad : (Items.noteKind === "ok" ? Theme.ok : Theme.dim)
                font.family: Theme.ui; font.pixelSize: 12
            }

            Flickable {
                id: flick
                anchors { top: noteLine.visible ? noteLine.bottom : header.bottom; topMargin: 12; bottom: parent.bottom; left: parent.left; right: parent.right }
                contentHeight: body.implicitHeight + 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: body
                    width: flick.width - 12
                    spacing: 18

                    // ---- lighting ----
                    Column {
                        visible: Items.schema && Items.schema.colors
                        width: parent.width
                        spacing: 10
                        Heading { text: "LIGHTING" }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: Items.schema ? Items.schema.effects : []
                                delegate: GButton {
                                    required property var modelData
                                    text: modelData.label
                                    primary: Items.prof && Items.prof.effect === modelData.id
                                    onClicked: Items.setProf("effect", modelData.id)
                                }
                            }
                        }
                        Row {
                            spacing: 10
                            Text { text: "Color"; width: 80; anchors.verticalCenter: parent.verticalCenter; color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13 }
                            Rectangle {
                                width: 32; height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                border.color: Theme.line
                                color: Items.prof && Items.colorOk(Items.prof.color) ? "#" + String(Items.prof.color).replace("#", "") : "transparent"
                            }
                            GInput {
                                width: 110
                                value: Items.prof ? Items.prof.color : ""
                                placeholder: "ff8800"
                                border.color: Items.prof && !Items.colorOk(Items.prof.color) ? Theme.bad : (input.activeFocus ? Theme.accent : Theme.line)
                                onEdited: v => Items.setProf("color", v.trim())
                            }
                            Repeater {
                                model: ["ff0000", "ff8800", "ffee00", "00ff00", "00ffff", "0055ff", "8800ff", "ff00aa", "ffffff"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 22; height: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#" + modelData
                                    border.color: Items.prof && String(Items.prof.color).toLowerCase().replace("#", "") === modelData ? Theme.fg : Theme.line
                                    border.width: 2
                                    MouseArea { anchors.fill: parent; onClicked: Items.setProf("color", parent.modelData) }
                                }
                            }
                        }
                        Row {
                            spacing: 10
                            Text { text: "Brightness"; width: 80; anchors.verticalCenter: parent.verticalCenter; color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13 }
                            GSeg {
                                options: (Items.schema ? Items.schema.brightness : []).map(b => ({ id: String(b), label: String(b) }))
                                current: Items.prof ? String(Items.prof.brightness) : ""
                                onPicked: id => Items.setProf("brightness", Number(id))
                            }
                        }
                    }

                    // ---- DPI ----
                    Column {
                        visible: Items.schema && Items.schema.dpi
                        width: parent.width
                        spacing: 10
                        Heading { text: "DPI LEVELS  ·  0 TURNS A LEVEL OFF" }
                        Row {
                            spacing: 10
                            Repeater {
                                model: Items.schema && Items.schema.dpi ? Items.schema.dpi.levels : 0
                                delegate: Column {
                                    id: dpiCol
                                    required property int index
                                    readonly property string err: Items.prof ? Items.dpiError(Items.prof.dpi[index]) : ""
                                    spacing: 3
                                    Text { text: "Level " + (dpiCol.index + 1); color: Theme.dim; font.family: Theme.ui; font.pixelSize: 11 }
                                    GInput {
                                        width: 96
                                        value: Items.prof ? String(Items.prof.dpi[dpiCol.index]) : ""
                                        border.color: dpiCol.err !== "" ? Theme.bad : (input.activeFocus ? Theme.accent : Theme.line)
                                        onEdited: v => Items.setDpi(dpiCol.index, v.trim())
                                    }
                                    FieldError { text: dpiCol.err; width: 96; wrapMode: Text.WordWrap }
                                }
                            }
                        }
                    }

                    // ---- buttons ----
                    Column {
                        width: parent.width
                        spacing: 8
                        Heading { text: "BUTTONS" }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Type a key (a, f13, kp_plus, arrow_up), a combination (ctrl+shift+a; modifiers: " + Items.modifiers.join(", ")
                                + ") or a mouse function (" + (Items.schema ? Items.schema.functions.join(", ") : "") + "). raw:… keeps bytes ITEMS doesn't know yet."
                            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                        }
                        Grid {
                            columns: width > 640 ? 2 : 1
                            width: parent.width
                            columnSpacing: 24
                            rowSpacing: 6
                            Repeater {
                                model: Items.schema ? Items.schema.buttons : []
                                delegate: Item {
                                    id: btnRow
                                    required property var modelData
                                    readonly property string val: Items.prof && Items.prof.buttons[modelData.id] !== undefined ? Items.prof.buttons[modelData.id] : ""
                                    readonly property string err: Items.actionError(val)
                                    width: parent.columns === 2 ? (parent.width - 24) / 2 : parent.width
                                    height: 32 + (err !== "" ? 15 : 0)
                                    Text {
                                        id: btnLabel
                                        width: 150
                                        y: 8
                                        elide: Text.ElideRight
                                        text: btnRow.modelData.label
                                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                                    }
                                    GInput {
                                        anchors { left: btnLabel.right; right: parent.right }
                                        value: btnRow.val
                                        border.color: btnRow.err !== "" ? Theme.bad : (input.activeFocus ? Theme.accent : Theme.line)
                                        onEdited: v => Items.setButton(btnRow.modelData.id, v)
                                    }
                                    FieldError { x: btnLabel.width; y: 33; text: btnRow.err }
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 8
                        GButton { text: "Copy this profile to all"; onClicked: Items.copyToAll() }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: main
            visible: !main.visible
            text: Items.devices.length === 0 ? "" : "Loading…"
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }
    }
}
