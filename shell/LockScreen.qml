// LockScreen.qml - session lock, idle handling and lock-on-sleep (Phase 2).
//
//  * WlSessionLock (ext-session-lock-v1): one LockSurface per output; the compositor keeps
//    the session covered if this process dies. Unlocks only after PAM accepts the password.
//  * IPC `qs ipc call lock lock`, Config.lock() (quick settings / launcher buttons).
//  * IdleMonitor (ext-idle-notify-v1): dim -> lock -> suspend, timings in Config
//    (dimAfter / lockAfter / suspendAfter / suspendOnAC). Inhibitors are respected.
//  * After a compositor crash it is restarted with ULTIMIT_START_LOCKED=1 and already covered:
//    lock at once so there's a password prompt to get back in.
//  * logind: lock on PrepareForSleep(true) (suspend, lid close) holding a delay inhibitor until
//    the lock is up, and on `loginctl lock-session`.
//
// Animations (see components/LockView.qml, LockFx.qml): lock = accent line sweeps across and the screen
// darkens (LockFx overlay), then the lock engages and the shards, emblem and clock assemble; unlock =
// everything collapses into the accent line, the session unlocks and the black halves wipe away from
// the centre (LockFx). Logind-triggered locks (sleep, lid) and crash recovery engage at once.
//
// Preview (ULTIMIT_LOCK_PREVIEW=1): the lock view in a normal window, no ext-session-lock and no
// PAM: lock() shows it, the password "demo" unlocks, anything else fails. IPC `lock lock` replays it.
//
// Test hook (inert unless ULTIMIT_DRY_RUN=1): `lock simulate "<logind line>"`
// feeds a fake logind signal. There is deliberately no way to skip PAM.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import "components"

Scope {
    id: root

    readonly property bool dryRun: Quickshell.env("ULTIMIT_DRY_RUN") === "1"

    readonly property bool preview: Quickshell.env("ULTIMIT_LOCK_PREVIEW") === "1"
    property bool previewLocked: false
    // Our own copy of the lock state: Quickshell 0.3.2's WlSessionLock never emits a change when it
    // unlocks, so a binding on sessionLock.locked stays true after the first unlock (the desktop's
    // animations stay paused and lock() refuses to lock again).
    property bool sessionLocked: false
    readonly property bool locked: preview ? previewLocked : sessionLocked
    property bool unlocking: false        // password accepted, the unlock animation is playing
    onLockedChanged: UiSounds.play(locked ? "lock" : "unlock")
    // shared lock-screen state (rendered by every LockSurface)
    property string password: ""          // typed text (kept here so any output can take keystrokes)
    property string authState: "idle"     // idle | auth | fail
    property string message: ""
    property bool capsLock: false
    property int shakeTick: 0
    property string pendingSecret: ""
    property bool pendingOk: false
    property bool sleeping: false

    // ---------------- lock / unlock ----------------
    // `instant`: engage at once (sleep, crash recovery); otherwise the desktop goes dark first.
    function lock(instant) {
        if (locked || fx.busy) return;
        password = ""; authState = "idle"; message = ""; pendingSecret = "";
        Config.closeLauncher(); Config.closeMenu(); SysState.closeQs();
        if (instant === true || !Config.motion) engage();
        else fx.playLock(root.engage);
    }
    function engage() {
        unlocking = false;
        if (preview) previewLocked = true; else { sessionLock.locked = true; sessionLocked = sessionLock.locked; }
        if (preview && fx.mode === "hold") releaseFx.restart();
    }
    // Password accepted: play the collapse under the lock, then release it and let LockFx wipe.
    function beginUnlock() {
        if (!locked || unlocking) return;
        if (!Config.motion) { unlock(); return; }
        unlocking = true;
        fx.arm();
        unlockTimer.restart();
    }
    Timer {
        id: unlockTimer
        interval: 650
        onTriggered: { fx.playUnlock(); root.unlock(); }
    }
    // The lock surfaces are up: LockFx (black + line, under the cover) is no longer needed.
    Timer { id: releaseFx; interval: 400; onTriggered: fx.release() }
    function unlock() {
        password = ""; pendingSecret = ""; authState = "idle"; message = ""; unlocking = false;
        if (preview) previewLocked = false; else { sessionLock.locked = false; sessionLocked = false; }
    }
    LockFx { id: fx }
    Connections {
        target: Config
        function onLockRequestChanged() { root.lock(); }
    }
    Component.onCompleted: {
        if (Quickshell.env("ULTIMIT_START_LOCKED") === "1") { console.log("[lock] restarted after a crash: locking"); root.lock(true); }
        else if (preview) root.lock(true);
        else lockedProbe.running = true;
    }
    // The shell itself crashed while locked: the compositor kept the screen covered and is still
    // locked, so lock again (the compositor lets only the shell take the lock over).
    Process {
        id: lockedProbe
        command: ["ultimitctl", "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (JSON.parse(text).locked === true && !root.locked) {
                        console.log("[lock] shell restarted while locked: locking");
                        root.lock(true);
                    }
                } catch (e) {}
            }
        }
    }
    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        // TEST ONLY (ULTIMIT_DRY_RUN=1): feed a fake logind line, e.g. `lock simulate "...PrepareForSleep (true,)"`.
        function simulate(line: string): void { if (root.dryRun) root.logindLine(line); }
    }

    WlSessionLock {
        id: sessionLock
        LockSurface { ctl: root }
        onSecureChanged: {
            if (secure && fx.mode === "hold") releaseFx.restart();
            // Also fires when the compositor ends the lock itself: resync our copy once Quickshell has
            // finished tearing the lock down (it emits this mid-teardown, while still "locked").
            if (!secure) Qt.callLater(() => root.sessionLocked = sessionLock.locked);
        }
    }

    // Preview window (ULTIMIT_LOCK_PREVIEW=1): the same view, an ordinary toplevel.
    LazyLoader {
        active: root.preview && root.previewLocked
        FloatingWindow {
            title: "Ultimit lock preview"
            implicitWidth: 1280; implicitHeight: 720
            color: "#000000"
            LockView { anchors.fill: parent; ctl: root; primary: true }
        }
    }

    // ---------------- authentication (PAM) ----------------
    // Dedicated service when installed (no login delay / nologin checks), else "login".
    property string pamConfig: Config.pamFallback
    Process {
        running: true
        command: ["test", "-e", "/etc/pam.d/" + Config.pamService]
        onExited: code => root.pamConfig = code === 0 ? Config.pamService : Config.pamFallback
    }
    PamContext {
        id: pam
        config: root.pamConfig
        onPamMessage: {
            if (!responseRequired) return;
            if (root.pendingSecret !== "") {
                const s = root.pendingSecret;
                root.pendingSecret = "";
                respond(s);
            } else {
                abort();   // a second prompt (OTP, ...) is not supported yet
            }
        }
        onCompleted: result => root.finish(result === PamResult.Success)
        onError: err => console.log("[lock] pam error " + err)
    }

    function submit() {
        if (authState === "auth" || password.length === 0 || unlocking) return;
        authState = "auth"; message = "";
        if (preview) { finish(password === "demo"); return; }   // preview: no PAM, nothing is locked
        pendingSecret = password;
        if (!pam.start()) { pendingSecret = ""; finish(false); }
    }
    // Hold the "AUTHENTICATING" state briefly so it is visible, then apply the result.
    function finish(ok) { pendingOk = ok; resultTimer.restart(); }
    Timer {
        id: resultTimer
        interval: 450
        onTriggered: {
            root.pendingSecret = "";
            if (root.pendingOk) { console.log("[lock] unlocked"); root.beginUnlock(); return; }
            console.log("[lock] authentication failed");
            root.password = "";
            root.authState = "fail";
            root.message = "ACCESS DENIED";
            root.shakeTick++;
        }
    }

    // Keystrokes from any lock surface.
    function onKey(e) {
        e.accepted = true;
        if (authState === "auth" || unlocking) return;
        const mods = e.modifiers;
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { submit(); return; }
        if (e.key === Qt.Key_CapsLock) { capsLock = !capsLock; return; }
        if (e.key === Qt.Key_Shift || e.key === Qt.Key_Control || e.key === Qt.Key_Alt || e.key === Qt.Key_Meta
            || e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R) return;
        if (authState === "fail") { authState = "idle"; message = ""; }
        if (e.key === Qt.Key_Escape) { password = ""; return; }
        if (e.key === Qt.Key_Backspace) {
            password = (mods & Qt.ControlModifier) ? "" : password.slice(0, -1);
            return;
        }
        if ((mods & Qt.ControlModifier) && e.key === Qt.Key_U) { password = ""; return; }
        if (mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        const t = e.text;
        if (t.length === 1 && t >= " " && t.charCodeAt(0) !== 127) {
            // caps-lock guess: a letter whose case disagrees with the Shift state
            if (t.toLowerCase() !== t.toUpperCase()) {
                const upper = t !== t.toLowerCase(), shifted = (mods & Qt.ShiftModifier) !== 0;
                capsLock = upper !== shifted;
            }
            if (password.length < 256) password += t;
        }
    }

    // ---------------- idle: dim -> lock -> suspend ----------------
    IdleMonitor {
        id: dimMon
        enabled: Config.dimAfter > 0 && !root.locked
        timeout: Config.dimAfter
        respectInhibitors: true
    }
    IdleMonitor {
        id: lockMon
        enabled: Config.lockAfter > 0
        timeout: Config.lockAfter
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) { console.log("[lock] idle: locking"); root.lock(); }
    }
    IdleMonitor {
        id: suspendMon
        enabled: Config.suspendAfter > 0
        timeout: Config.suspendAfter
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.idleSuspend()
    }
    function idleSuspend() {
        if (!Config.suspendOnAC && !UPower.onBattery) {
            console.log("[lock] idle suspend skipped (on AC)");
            return;
        }
        if (dryRun) { console.log("[dry-run] systemctl suspend (idle)"); return; }
        Quickshell.execDetached(["systemctl", "suspend"]);
    }

    // Dim overlay: 60% black on every output while idle (input passes through and wakes us).
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: dim
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "ultimit-dim"
            readonly property bool want: dimMon.isIdle && dimMon.enabled && !root.locked
            visible: shade.opacity > 0.001
            Rectangle {
                id: shade
                anchors.fill: parent
                color: "black"
                opacity: dim.want ? 0.6 : 0
                Behavior on opacity { NumberAnimation { duration: Config.dur(dim.want ? 1200 : 150) } }
            }
        }
    }

    // ---------------- logind: lock before sleep / lid close / lock-session ----------------
    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID") || ""
    function logindLine(l) {
        let m = l.match(/PrepareForSleep \((true|false)/);
        if (m) {
            sleeping = m[1] === "true";
            console.log("[lock] PrepareForSleep " + m[1]);
            if (sleeping) root.lock(true);
            else releaseKeys.restart();
            return;
        }
        m = l.match(/login1\/session\/(\S+): org\.freedesktop\.login1\.Session\.Lock \(\)/);
        if (m && sessionId !== "") {
            const id = m[1].replace(/^_([0-9a-fA-F]{2})/, (x, h) => String.fromCharCode(parseInt(h, 16)));
            if (id === sessionId) { console.log("[lock] logind Lock signal"); root.lock(); }
        }
    }
    Process {
        id: logind
        running: Config.lockOnSleep
        // setpriv --pdeathsig: dies with the shell even if the shell is killed.
        command: ["setpriv", "--pdeathsig", "TERM", "--",
                  "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser { onRead: line => root.logindLine(line) }
        onExited: if (Config.lockOnSleep) restart.start()
    }
    Timer { id: restart; interval: 3000; onTriggered: logind.running = true }
    // On resume the USB controller can reset the keyboards and lose a key release (the key that
    // woke the PC, a held Ctrl): that modifier sticks and every shortcut stops working. Once the
    // devices have settled, have the compositor release whatever it still thinks is held.
    Timer {
        id: releaseKeys
        interval: 2000
        onTriggered: if (!dryRun) Quickshell.execDetached(["ultimitctl", "release-keys"])
    }

    // Locked or dimmed: pause the desktop's idle animations (wallpaper, ticker, rail spin).
    Binding { target: Config; property: "desktopIdle"; value: root.locked || (dimMon.enabled && dimMon.isIdle) }

    // Delay inhibitor: held while awake so logind waits for us on suspend; released as soon as
    // the lock is confirmed (or after logind's InhibitDelayMaxSec, 5 s by default).
    Process {
        id: inhibitor
        running: Config.lockOnSleep && !(root.sleeping && sessionLock.secure)
        // Held until this process ends; setpriv --pdeathsig ends it (and so releases the
        // inhibitor) if the shell dies, however it dies.
        command: ["setpriv", "--pdeathsig", "TERM", "--",
                  "systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Ultimit",
                  "--why=Locking the screen before sleep", "sleep", "infinity"]
    }
}
