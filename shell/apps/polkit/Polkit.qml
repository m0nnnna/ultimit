// Polkit.qml - Ultimit polkit authentication agent.
// Registers a Quickshell PolkitAgent for this login session (polkitd allows one agent per
// session; in an Ultimit session GNOME Shell isn't running so nothing conflicts) and shows
// PolkitDialog on the UI screen while an authentication request is active.
//
// Env: ULTIMIT_POLKIT_DEMO=1 skips registration entirely and shows the dialog with fake
// data (password "demo" succeeds, anything else fails) - for UI testing; can't hijack auth.
// IPC (demo mode only): qs ipc call polkit demo
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import "../.."

Scope {
    id: root

    readonly property bool demo: Quickshell.env("ULTIMIT_POLKIT_DEMO") === "1"

    // ---- real agent (not instantiated in demo mode) ----
    Loader {
        active: !root.demo
        sourceComponent: PolkitAgent {
            id: agent
            onAuthenticationRequestStarted: console.log("polkit: request", agent.flow ? agent.flow.actionId : "?")

            // isRegistered is set asynchronously; if it never comes true another agent
            // (e.g. gnome-shell) owns the session, or polkitd is unavailable.
            property Timer watchdog: Timer {
                interval: 3000; running: true
                onTriggered: if (!agent.isRegistered) {
                    console.warn("polkit: agent registration failed (another agent registered, or polkitd unavailable); admin prompts will not be shown by Ultimit");
                    Toasts.show("Polkit", "Could not register the authentication agent. Another agent may be running.");
                }
            }
            Component.onCompleted: root.agentRef = agent
        }
    }
    property var agentRef: null

    // ---- demo flow ----
    QtObject {
        id: demoFlow
        property string message: "Authentication is required to install software"
        property string iconName: ""
        property string actionId: "org.freedesktop.packagekit.package-install"
        property var identities: [{ string: Quickshell.env("USER") || "user", displayName: Quickshell.env("USER") || "User" }, { string: "root", displayName: "System Administrator" }]
        property var selectedIdentity: identities[0]
        property bool isResponseRequired: true
        property string inputPrompt: "Password:"
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool failed: false
        signal authenticationFailed()
        function submit(v) {
            if (v === "demo") { root.demoActive = false; return; }
            failed = true; supplementaryMessage = "Sorry, try again."; supplementaryIsError = true;
            authenticationFailed();
        }
        function cancelAuthenticationRequest() { root.demoActive = false; }
    }
    property bool demoActive: root.demo
    onDemoActiveChanged: if (demoActive) { demoFlow.failed = false; demoFlow.supplementaryMessage = ""; }

    IpcHandler {
        target: "polkit"
        function demo(): void { if (root.demo) root.demoActive = true; }
    }

    readonly property var flow: demo ? (demoActive ? demoFlow : null) : (agentRef && agentRef.isActive ? agentRef.flow : null)

    Variants {
        model: Quickshell.screens
        PolkitDialog {
            required property var modelData
            screen: modelData
            screenName: modelData.name
            flow: root.flow
        }
    }
}
