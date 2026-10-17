// SettingsPanel.qml - plug an AI into Ember: pick the provider, give it an API key (kept in the login
// keyring), the address (for a local or custom server) and the model (fetched from the provider, or
// typed), Claude's effort; and whether she may act without asking. Changes apply from the next message.
import QtQuick
import QtQuick.Controls
import "../.."
import "../accessory"
import "../claude" as C

Rectangle {
    id: root
    property var host
    property string sel: Ember.provider            // the provider being edited
    readonly property var p: Ember.prov(sel) || ({})
    property var models: []
    property string note: ""
    property bool noteBad: false
    property bool fetching: false

    implicitHeight: col.implicitHeight + 40
    color: Theme.bg1
    border.width: 1; border.color: Theme.lineStrong
    Keys.onEscapePressed: host.overlay = ""

    function say(t, bad) { note = t; noteBad = !!bad; }
    function pick(id) {
        sel = id; models = []; say("");
        keyEntry.text = ""; baseEntry.text = (Ember.prov(id) || {}).base || ""; modelEntry.text = (Ember.prov(id) || {}).model || "";
    }
    function saveFields(cb) {
        const o = { providers: {} };
        o.providers[sel] = { base: baseEntry.text, model: modelEntry.text };
        Ember.save(o, cb);
    }
    function fetchModels() {
        fetching = true; say("Asking " + p.name + " for its models…");
        saveFields(() => Ember.run(["models", sel], o => {
            fetching = false;
            if (o.ok) { models = o.models; say(o.models.length ? o.models.length + " models. Pick one." : "No models found.", !o.models.length); }
            else { models = []; say(o.err, true); }
        }));
    }
    function saveKey() {
        const k = keyEntry.text.trim();
        if (k === "") return;
        Ember.run(["key-set", sel], o => {
            keyEntry.text = "";
            if (!o.ok) { say(o.err, true); return; }
            say(o.where === "keyring" ? "Key saved in your login keyring." : "Key saved in a private file (no keyring found).");
            Ember.reload(() => root.fetchModels());
        }, k);
    }
    Component.onCompleted: pick(Ember.provider)

    Column {
        id: col
        x: 20; y: 20; width: parent.width - 40
        spacing: 12

        SectionLabel { text: "Ember's mind" }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: "Choose the AI Ember thinks with. She keeps your chats whichever you use, and can switch mid-conversation."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }

        // the providers
        Flow {
            width: parent.width; spacing: 8
            Repeater {
                model: Ember.providers
                Rectangle {
                    required property var modelData
                    width: (col.width - 16) / 3; height: 54
                    color: root.sel === modelData.id ? Theme.panel2 : (pm.containsMouse ? Qt.rgba(Theme.panel2.r, Theme.panel2.g, Theme.panel2.b, 0.5) : "transparent")
                    border.width: 1; border.color: root.sel === modelData.id ? Theme.accent : Theme.lineStrong
                    Rectangle {
                        x: 10; y: 12; width: 7; height: 7; radius: 4
                        color: Ember.usable(modelData) ? Theme.ok : Theme.dim
                    }
                    Column {
                        x: 26; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 34
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: modelData.name + (Ember.provider === modelData.id ? "  ·  IN USE" : "")
                            color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: modelData.maker.toUpperCase()
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.2
                        }
                    }
                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick(parent.modelData.id) }
                }
            }
        }

        // key
        Column {
            width: parent.width; spacing: 6
            visible: !!root.p.key
            Row {
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "API KEY"
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.p.hasKey ? "SET ✓" : "NOT SET"
                    color: root.p.hasKey ? Theme.ok : Theme.warn
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                }
                C.SmallLink {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!root.p.keyUrl
                    text: "GET A KEY ↗"
                    onClicked: Qt.openUrlExternally(root.p.keyUrl)
                }
                C.SmallLink {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!root.p.hasKey
                    text: "FORGET KEY"
                    onClicked: Ember.run(["key-clear", root.sel], () => { Ember.reload(); root.say("Key removed."); })
                }
            }
            Row {
                width: parent.width; spacing: 8
                Rectangle {
                    width: parent.width - keyBtn.width - 8; height: 32
                    color: "transparent"
                    border.width: 1; border.color: keyEntry.activeFocus ? Theme.accent : Theme.lineStrong
                    TextInput {
                        id: keyEntry
                        anchors.fill: parent; anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                        font.family: Theme.mono; font.pixelSize: 13
                        clip: true
                        onAccepted: root.saveKey()
                        Text {
                            visible: keyEntry.text === ""
                            text: root.p.hasKey ? "Paste a new key to replace it" : "Paste your " + (root.p.maker || "") + " API key"
                            color: Theme.dim; font: keyEntry.font; anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
                ChamferButton { id: keyBtn; implicitHeight: 32; text: "Save key"; primary: keyEntry.text !== ""; onClicked: root.saveKey() }
            }
        }

        // address
        Column {
            width: parent.width; spacing: 6
            Text {
                text: root.sel === "local" ? "SERVER ADDRESS  ·  OLLAMA :11434/v1  ·  LM STUDIO :1234/v1  ·  LLAMA.CPP :8080/v1" : "API ADDRESS"
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
            }
            C.Entry { id: baseEntry; width: parent.width; mono: true; placeholder: "https://…/v1"; onAccepted: root.fetchModels() }
        }

        // model
        Column {
            width: parent.width; spacing: 6
            Row {
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MODEL"
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                }
                C.SmallLink { anchors.verticalCenter: parent.verticalCenter; text: root.fetching ? "LOADING…" : "LIST MODELS"; onClicked: if (!root.fetching) root.fetchModels() }
            }
            C.Entry { id: modelEntry; width: parent.width; mono: true; placeholder: "Pick from the list, or type a model name"; onAccepted: root.saveFields() }
            Rectangle {
                visible: root.models.length > 0
                width: parent.width; height: Math.min(modelList.contentHeight + 2, 150)
                color: "transparent"; border.width: 1; border.color: Theme.line
                ListView {
                    id: modelList
                    anchors.fill: parent; anchors.margins: 1
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    model: root.models
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property string modelData
                        width: ListView.view.width; height: 26
                        color: modelData === modelEntry.text ? Theme.panel2 : mm.containsMouse ? Qt.rgba(Theme.panel2.r, Theme.panel2.g, Theme.panel2.b, 0.5) : "transparent"
                        Text {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData
                            color: parent.modelData === modelEntry.text ? Theme.accent : Theme.fg
                            font.family: Theme.mono; font.pixelSize: 12
                        }
                        MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { modelEntry.text = parent.modelData; root.saveFields(); } }
                    }
                }
            }
        }

        // Claude: effort
        Row {
            visible: root.p.kind === "anthropic"
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "EFFORT"
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                width: 60
            }
            Repeater {
                model: Ember.efforts
                Rectangle {
                    required property string modelData
                    width: et.implicitWidth + 18; height: 26
                    color: root.p.effort === modelData ? Theme.accent : "transparent"
                    border.width: 1; border.color: root.p.effort === modelData ? Theme.accent : Theme.lineStrong
                    Text {
                        id: et; anchors.centerIn: parent
                        text: parent.modelData.toUpperCase()
                        color: root.p.effort === parent.modelData ? Theme.onAccent : Theme.fg
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { const o = { providers: {} }; o.providers[root.sel] = { effort: parent.modelData }; Ember.save(o); }
                    }
                }
            }
        }

        Text {
            visible: root.note !== ""
            width: parent.width; wrapMode: Text.Wrap
            text: root.note
            color: root.noteBad ? Theme.bad : Theme.dim
            font.family: Theme.mono; font.pixelSize: 11
        }

        Rectangle { width: parent.width; height: 1; color: Theme.line }

        // trust
        Item {
            width: parent.width; height: trustCol.implicitHeight
            Column {
                id: trustCol
                width: parent.width - 70
                spacing: 3
                Text {
                    text: "Let Ember act without asking"
                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: "Off: you approve every command, file she writes and window she closes. On: she just does it."
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                }
            }
            Rectangle {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 48; height: 24
                color: Ember.trust ? Theme.accent : "transparent"
                border.width: 1; border.color: Ember.trust ? Theme.accent : Theme.lineStrong
                Rectangle {
                    width: 16; height: 16; y: 4
                    x: Ember.trust ? parent.width - 20 : 4
                    color: Ember.trust ? Theme.onAccent : Theme.dim
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Ember.setTrust(!Ember.trust) }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: 10
            ChamferButton { text: "Close"; onClicked: { root.saveFields(); root.host.overlay = ""; } }
            ChamferButton {
                text: Ember.provider === root.sel ? "In use" : "Use " + (root.p.name || "");
                primary: Ember.provider !== root.sel
                onClicked: root.saveFields(() => { Ember.use(root.sel); root.host.overlay = ""; })
            }
        }
    }
}
