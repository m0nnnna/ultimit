pragma Singleton

// Toasts.qml - reusable toast queue. Rendered by components/ToastOverlay.qml.
//   Toasts.show("Title", "message")                    // plain
//   Toasts.show("Mailer", "No mail app — try:", "sudo apt install thunderbird")  // + selectable command
import QtQuick
import Quickshell

Singleton {
    id: root

    property alias model: list
    property int _seq: 0

    ListModel { id: list }

    function show(title, message, command, timeoutMs) {
        const id = ++_seq;
        list.append({ tid: id, title: title || "", message: message || "", command: command || "" });
        while (list.count > 4) list.remove(0);
        const ms = timeoutMs || (command ? 12000 : 4200);
        const t = timerComp.createObject(root, { tid: id, interval: ms });
        t.start();
    }
    function dismiss(id) {
        for (let i = 0; i < list.count; i++)
            if (list.get(i).tid === id) { list.remove(i); return; }
    }

    Component {
        id: timerComp
        Timer {
            property int tid: 0
            onTriggered: { root.dismiss(tid); destroy(); }
        }
    }
}
