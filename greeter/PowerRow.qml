// PowerRow.qml - Suspend / Restart / Shut down, each needs a second press (CONFIRM?) within 4 s.
import QtQuick

Row {
    id: root
    spacing: 8
    property int armed: -1
    signal action(string name)
    readonly property var items: [
        { id: "suspend", label: "Suspend" }, { id: "reboot", label: "Restart" }, { id: "poweroff", label: "Shut down" }]
    Timer { id: disarm; interval: 4000; onTriggered: root.armed = -1 }
    Repeater {
        model: root.items
        delegate: ChamferButton {
            required property var modelData
            required property int index
            text: root.armed === index ? "Confirm?" : modelData.label
            primary: root.armed === index
            onClicked: {
                if (root.armed === index) { root.armed = -1; disarm.stop(); root.action(modelData.id); }
                else { root.armed = index; disarm.restart(); }
            }
            onActiveFocusChanged: if (!activeFocus && root.armed === index) root.armed = -1
        }
    }
}
