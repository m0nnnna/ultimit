// Greeter.qml - login state machine shared by every output's surface.
// Real mode talks to greetd through Quickshell.Services.Greetd; demo mode (no greetd socket, or
// ULTIMIT_GREETER_DEMO=1) simulates the flow: password "demo" succeeds and only logs the command.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

Scope {
    id: ctl

    readonly property bool demo: !Greetd.available || Quickshell.env("ULTIMIT_GREETER_DEMO") === "1"

    // ---- data ----
    property var users: []            // [{name, display}]
    property int userIndex: 0
    property var sessions: []         // [{name, exec, desktopNames, type, file}]
    property int sessionIndex: 0
    property bool loaded: false
    readonly property var curUser: users.length > 0 ? users[userIndex] : null
    readonly property var curSession: sessions.length > 0 ? sessions[sessionIndex] : null

    // ---- flow state ----
    // loading | starting | prompt | auth | launching | error
    property string phase: "loading"
    property string promptText: "PASSWORD"
    property bool promptEcho: false
    property string input: ""
    property string message: ""
    property bool messageErr: false
    property bool denied: false
    property int shakeTick: 0

    // ---- power ----
    function power(action) {
        const cmd = { suspend: ["systemctl", "suspend"], reboot: ["systemctl", "reboot"], poweroff: ["systemctl", "poweroff"] }[action];
        if (!cmd) return;
        if (demo) { console.log("DEMO POWER: " + cmd.join(" ")); return; }
        powerProc.command = cmd;
        powerProc.running = true;
    }
    Process { id: powerProc }

    // ---- loading users, sessions and remembered choices ----
    readonly property string loadScript: [
        'd="${XDG_STATE_HOME:+$XDG_STATE_HOME/ultimit-greeter}"; d="${d:-/var/lib/ultimit-greeter}"',
        'if [ -r "$d/state" ]; then while IFS= read -r l; do printf "STATE|%s\\n" "$l"; done < "$d/state"; fi',
        "getent passwd | awk -F: '$3>=1000 && $3<=59999 && $7!~/(nologin|false)$/ {print \"USER|\"$1\"|\"$5}'",
        'for dir in /usr/share/wayland-sessions /usr/share/xsessions; do',
        '  case "$dir" in *xsessions) t=x11;; *) t=wayland;; esac',
        '  for f in "$dir"/*.desktop; do',
        '    [ -r "$f" ] || continue',
        '    grep -qiE "^(NoDisplay|Hidden)=true" "$f" && continue',
        '    n=$(grep -m1 "^Name=" "$f" | cut -d= -f2-); e=$(grep -m1 "^Exec=" "$f" | cut -d= -f2-)',
        '    dn=$(grep -m1 "^DesktopNames=" "$f" | cut -d= -f2-)',
        '    printf "SESSION|%s|%s|%s|%s|%s\\n" "$t" "$n" "$e" "$dn" "$f"',
        '  done',
        'done'
    ].join("\n")

    Process {
        id: loader
        command: ["sh", "-c", ctl.loadScript]
        running: true
        stdout: StdioCollector { onStreamFinished: ctl.parseLoad(text) }
    }

    function parseLoad(text) {
        const us = [], ss = [];
        let lastUser = "", lastSession = "";
        for (const line of text.split("\n")) {
            const p = line.split("|");
            if (p[0] === "STATE") {
                const kv = line.substring(6);
                if (kv.startsWith("user=")) lastUser = kv.substring(5);
                else if (kv.startsWith("session=")) lastSession = kv.substring(8);
            } else if (p[0] === "USER" && p[1]) {
                const g = (p[2] || "").split(",")[0].trim();
                us.push({ name: p[1], display: g !== "" ? g : p[1] });
            } else if (p[0] === "SESSION" && p[2]) {
                ss.push({ type: p[1], name: p[2], exec: p[3] || "", desktopNames: p[4] || "", file: p[5] || "" });
            }
        }
        users = us;
        sessions = ss;
        let ui = us.findIndex(u => u.name === lastUser);
        userIndex = ui >= 0 ? ui : 0;
        // default session: the one named Ultimit, else the remembered one, else the first
        let si = ss.findIndex(s => s.name.toLowerCase() === "ultimit");
        if (si < 0) si = ss.findIndex(s => s.name === lastSession);
        sessionIndex = si >= 0 ? si : 0;
        loaded = true;
        console.log("greeter: " + us.length + " user(s), " + ss.length + " session(s), demo=" + demo);
        if (us.length === 0) { phase = "error"; message = "NO LOGIN USERS FOUND"; messageErr = true; }
        else startSession(false);
    }

    function saveState() {
        if (!curUser) return;
        saver.command = ["sh", "-c",
            'd="${XDG_STATE_HOME:+$XDG_STATE_HOME/ultimit-greeter}"; d="${d:-/var/lib/ultimit-greeter}"; ' +
            'mkdir -p "$d" 2>/dev/null && printf "user=%s\\nsession=%s\\n" "$1" "$2" > "$d/state" 2>/dev/null; true',
            "sh", curUser.name, curSession ? curSession.name : ""];
        saver.running = true;
    }
    Process { id: saver }

    // ---- flow ----
    function selectUser(i) {
        if (i === userIndex || i < 0 || i >= users.length) return;
        userIndex = i;
        denied = false; message = "";
        retryTimer.stop();
        startSession(false);
    }

    function startSession(keepMsg) {
        if (!curUser) return;
        phase = "starting";
        input = "";
        if (!keepMsg) { message = ""; messageErr = false; denied = false; }
        if (demo) { demoStart.restart(); return; }
        if (Greetd.state !== 0) Greetd.cancelSession();
        Greetd.createSession(curUser.name);
    }

    function submit() {
        if (phase !== "prompt") return;
        const v = input;
        input = "";
        phase = "auth";
        saveState();
        if (demo) { demoPw = v; demoAuth.restart(); }
        else Greetd.respond(v);
    }

    function typed() { if (denied || message !== "") { denied = false; message = ""; messageErr = false; } }

    function failed() {
        denied = true; message = ""; shakeTick++;
        phase = "starting";
        input = "";
        retryTimer.restart();
    }

    Timer { id: retryTimer; interval: 900; onTriggered: ctl.startSession(true) }

    // Split a .desktop Exec line into argv (quotes honoured, field codes dropped).
    function splitExec(s) {
        const out = [];
        const re = /"((?:[^"\\]|\\.)*)"|'([^']*)'|(\S+)/g;
        let m;
        while ((m = re.exec(s.replace(/%[a-zA-Z%]/g, ""))) !== null)
            out.push(m[1] !== undefined ? m[1].replace(/\\(.)/g, "$1") : (m[2] !== undefined ? m[2] : m[3]));
        return out;
    }

    function launchSession() {
        const s = curSession;
        if (!s) { phase = "error"; message = "NO SESSION AVAILABLE"; messageErr = true; return; }
        const names = s.desktopNames !== "" ? s.desktopNames.split(";").filter(x => x !== "") : [s.name];
        const env = ["XDG_SESSION_TYPE=" + s.type, "XDG_CURRENT_DESKTOP=" + names.join(":"), "XDG_SESSION_DESKTOP=" + names[0]];
        const cmd = splitExec(s.exec);
        phase = "launching";
        message = "";
        if (demo) {
            console.log("DEMO LAUNCH user=" + curUser.name + " cmd=" + JSON.stringify(cmd) + " env=" + JSON.stringify(env));
            demoReset.restart();
            return;
        }
        Greetd.launch(cmd, env);
    }

    // ---- greetd signals ----
    Connections {
        target: Greetd
        enabled: !ctl.demo
        function onAuthMessage(msg, error, responseRequired, echo) {
            const t = msg.trim().replace(/:$/, "");
            if (responseRequired) {
                ctl.promptText = t.toUpperCase() || "PASSWORD";
                ctl.promptEcho = echo;
                ctl.input = "";
                ctl.phase = "prompt";
            } else {
                ctl.message = t.toUpperCase();
                ctl.messageErr = error;
                ctl.denied = false;
            }
        }
        function onAuthFailure(msg) { console.log("greeter: auth failure: " + msg); ctl.failed(); }
        function onReadyToLaunch() { ctl.launchSession(); }
        function onError(msg) {
            console.log("greeter: greetd error: " + msg);
            ctl.message = "GREETD ERROR"; ctl.messageErr = true; ctl.phase = "starting";
            retryTimer.restart();
        }
    }

    // ---- demo simulation ----
    property string demoPw: ""
    Timer { id: demoStart; interval: 250
            onTriggered: { ctl.promptText = "PASSWORD"; ctl.promptEcho = false; ctl.phase = "prompt"; } }
    Timer { id: demoAuth; interval: 700
            onTriggered: { if (ctl.demoPw === "demo") ctl.launchSession(); else ctl.failed(); } }
    Timer { id: demoReset; interval: 2000; onTriggered: ctl.startSession(false) }
}
