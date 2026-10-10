// Agents.qml - instantiates the prompt window per screen and exposes the IPC target "agents"
// used by bin/ultimit-agents:  qs ipc call agents ask <id> <kind> <json> | cancel <id>
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    IpcHandler {
        target: "agents"
        function ask(id: string, kind: string, json: string): void { AgentPrompt.ask(id, kind, json); }
        function cancel(id: string): void { AgentPrompt.cancel(id); }
    }

    Variants {
        model: Quickshell.screens
        AgentDialog {
            required property var modelData
            screen: modelData
            screenName: modelData.name
        }
    }
}
