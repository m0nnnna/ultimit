pragma Singleton

// AgentPrompt.qml - state of the Ultimit background-agent prompts (BlueZ pairing agent and
// NetworkManager secret agent, both implemented by bin/ultimit-agents).
//
// Protocol (see NOTES / bin/ultimit-agents):
//   daemon -> shell : qs -p <shell> ipc call agents ask <id> <kind> <json>
//                     qs -p <shell> ipc call agents cancel <id>
//   shell -> daemon : one JSON line {"id":..,"ok":bool,"values":{..}} written to the unix
//                     socket $XDG_RUNTIME_DIR/ultimit-agents.sock (override ULTIMIT_AGENTS_SOCK).
// The answer goes over the socket from inside this process, so a typed secret is never
// part of any argv, environment or URL.
//
// <json> for ask: { title?, message?, detail?, code?, entered?, fields?: [{key,label,
//   secret?,value?,minLen?,digits?,max?}], retry?: bool(show "wrong password" hint) }
// kinds: confirm | pin | passkey | display | authorize | wifi | 8021x | vpn
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string sockPath: Quickshell.env("ULTIMIT_AGENTS_SOCK")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ultimit-agents.sock")

    // FIFO of { id, kind, data }; the first one is shown.
    property var queue: []
    readonly property var current: queue.length > 0 ? queue[0] : null
    // bumps whenever the shown prompt changes or is updated in place, so views reset
    property int serial: 0

    function ask(id, kind, json) {
        let data = {};
        try { data = JSON.parse(json); } catch (e) { data = {}; }
        const q = queue.slice();
        for (let i = 0; i < q.length; ++i) {
            if (q[i].id === id) {            // update in place (e.g. DisplayPasskey progress)
                q[i] = { id: id, kind: kind, data: data };
                queue = q; serial++;
                return;
            }
        }
        q.push({ id: id, kind: kind, data: data });
        queue = q; serial++;
    }

    function cancel(id) {
        const q = queue.filter(p => p.id !== id);
        if (q.length !== queue.length) { queue = q; serial++; }
    }

    // Answer the shown prompt. values: plain object (field key -> string).
    function answer(ok, values) {
        const p = current;
        if (!p) return;
        queue = queue.slice(1);
        serial++;
        reply(p.id, ok, values || {});
    }

    function reply(id, ok, values) {
        const line = JSON.stringify({ id: id, ok: ok, values: values }) + "\n";
        const s = sockComp.createObject(root, { line: line });
        s.connected = true;
    }

    Component {
        id: sockComp
        Socket {
            id: sock
            property string line: ""
            path: root.sockPath
            connected: false
            onConnectedChanged: if (connected) { write(line); flush(); line = ""; closer.start(); }
            onError: err => { console.warn("agents: reply socket error", err); closer.start(); }
            property Timer closer: Timer {
                interval: 400
                onTriggered: sock.destroy()
            }
        }
    }
}
