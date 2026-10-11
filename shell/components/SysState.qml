pragma Singleton

// SysState.qml - live system state shared by the status row and the quick settings panel:
// network (Quickshell.Networking), battery (UPower), audio (PipeWire), Bluetooth, backlight
// (sysfs + logind), power profile (powerprofilesctl) and the panel open state.
// Every side effect goes through exec()/setters here, so ULTIMIT_DRY_RUN=1 turns them into
// log lines ("[dry-run] ...") instead of changing real system state.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import ".."

Singleton {
    id: root

    readonly property bool dryRun: Quickshell.env("ULTIMIT_DRY_RUN") === "1"

    // ---------------- panel state ----------------
    property bool qsOpen: false
    property string qsScreen: ""
    // Where the panel sits: "top" (under the desktop clock, top right) or "bottom" (above the tray, bottom right).
    property string qsAnchor: "top"
    function openQs(screenName, anchor) { Config.closeLauncher(); Config.closeMenu(); qsScreen = screenName || ""; qsAnchor = anchor || "top"; qsOpen = true; }
    function closeQs() { qsOpen = false; }
    function toggleQs(screenName, anchor) { if (qsOpen) closeQs(); else openQs(screenName, anchor); }
    function isQsScreen(name) {
        if (qsScreen !== "") return qsScreen === name;
        const s = Quickshell.screens;
        return s.length > 0 && s[0].name === name;
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { root.toggleQs(""); }
        function toggleBottom(): void { root.toggleQs("", "bottom"); }
        function open(): void { root.openQs(""); }
        function close(): void { root.closeQs(); }
    }

    // ---------------- debug: fake status ----------------
    // ULTIMIT_FAKE_STATUS='{"batt":15,"charging":true,...}' (JSON, read once at startup) overrides what the
    // tray and quick settings *display*. Display only: nothing real is changed. Keys (all optional):
    //   batt (0-100, implies a battery), charging, full, battTime ("1h 05m"), profile
    //   net ("wifi"|"eth"|"off"), ssid, signal (0..1), ip, airplane (bool: Wi-Fi radio off)
    //   bt ("none"|"off"|"on"|"connected"), btDevices (["Name", ...])
    //   vol (0-100), muted, sinkName
    //   dnd (bool, applied to Notifs once), unread (int, extra badge count when no real history)
    readonly property var fake: {
        const e = Quickshell.env("ULTIMIT_FAKE_STATUS");
        if (!e) return ({});
        try { const o = JSON.parse(e); return (o && typeof o === "object") ? o : ({}); }
        catch (err) { console.warn("ULTIMIT_FAKE_STATUS: bad JSON: " + err); return ({}); }
    }
    function fk(key, real) { return fake[key] !== undefined ? fake[key] : real; }
    Component.onCompleted: { if (fake.dnd !== undefined) Notifs.dnd = !!fake.dnd; refreshBrightness(); refreshIp(); }

    // ---------------- side-effect helper ----------------
    // argv: command; shown: optional text for the log (to mask secrets).
    function exec(argv, shown) {
        if (dryRun) { console.log("[dry-run] " + (shown || argv.join(" "))); return; }
        Quickshell.execDetached(argv);
    }
    function note(text) { if (dryRun) console.log("[dry-run] " + text); }

    // ---------------- network ----------------
    readonly property bool wifiEnabled: fake.airplane !== undefined ? !fake.airplane : Networking.wifiEnabled
    readonly property var wifiDev: {
        const v = Networking.devices.values;
        for (let i = 0; i < v.length; i++) if (v[i].type === DeviceType.Wifi) return v[i];
        return null;
    }
    readonly property bool ethConnected: fake.net !== undefined ? fake.net === "eth" : ethConnectedReal
    readonly property bool ethConnectedReal: {
        const v = Networking.devices.values;
        for (let i = 0; i < v.length; i++) if (v[i].type === DeviceType.Wired && v[i].connected) return true;
        return false;
    }
    readonly property string ethName: {
        const v = Networking.devices.values;
        for (let i = 0; i < v.length; i++) if (v[i].type === DeviceType.Wired && v[i].connected) return v[i].name;
        return "";
    }
    readonly property var activeWifi: {
        if (!wifiDev || !Networking.wifiEnabled) return null;
        const n = wifiDev.networks.values;
        for (let i = 0; i < n.length; i++) if (n[i].connected) return n[i];
        return null;
    }
    // "wifi" | "eth" | "off"
    readonly property string netKind: fake.net !== undefined ? fake.net : (activeWifi ? "wifi" : (ethConnected ? "eth" : "off"))
    readonly property string netName: fake.ssid !== undefined ? fake.ssid : (activeWifi ? activeWifi.name : "")
    readonly property real netStrength: fake.signal !== undefined ? fake.signal : (activeWifi ? activeWifi.signalStrength : 0)
    // IPv4 address of the default route (read-only `ip route get`), refreshed on network changes and every 60 s.
    property string netIp: fake.ip !== undefined ? fake.ip : ""
    function refreshIp() { if (fake.ip === undefined) { ipProc.running = false; ipProc.running = true; } }
    Process {
        id: ipProc
        command: ["sh", "-c", "ip -4 route get 1.1.1.1 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: { const m = /\bsrc\s+([0-9.]+)/.exec(text); root.netIp = m ? m[1] : ""; }
        }
    }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.refreshIp() }
    onNetKindChanged: refreshIp()
    onNetNameChanged: refreshIp()
    // Nearby networks: connected first, then by signal at the time the set last changed. The
    // list only rebuilds when the set of SSIDs / the connected one changes (stable rows, so an
    // inline password field keeps focus) and never while `netFreeze` is set.
    property var netList: []
    property bool netFreeze: false
    property string _netKey: ""
    function refreshNets() {
        if (netFreeze || !wifiDev) return;
        const v = wifiDev.networks.values.filter(n => n.name !== "");
        const key = v.map(n => n.name + (n.connected ? "*" : "")).sort().join("|");
        if (key === _netKey) return;
        _netKey = key;
        v.sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength));
        netList = v;
    }
    Connections {
        target: root.wifiDev ? root.wifiDev.networks : null
        function onValuesChanged() { root.refreshNets(); }
    }
    onWifiDevChanged: refreshNets()
    onNetFreezeChanged: if (!netFreeze) refreshNets()
    function isSecured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }
    function setWifiEnabled(on) {
        if (dryRun) { note("Networking.wifiEnabled = " + on); return; }
        Networking.wifiEnabled = on;
    }
    property string netBusy: ""
    function connectWifi(ssid, password) {
        const argv = ["nmcli", "device", "wifi", "connect", ssid];
        let shown = argv.join(" ");
        if (password) { argv.push("password", password); shown += " password ****"; }
        if (dryRun) { console.log("[dry-run] " + shown); return; }
        netBusy = ssid;
        nmProc.command = argv;
        nmProc.running = true;
    }
    function disconnectWifi() {
        if (!wifiDev) return;
        exec(["nmcli", "device", "disconnect", wifiDev.name]);
    }
    Process {
        id: nmProc
        stderr: StdioCollector { id: nmErr }
        stdout: StdioCollector { id: nmOut }
        onExited: code => {
            root.netBusy = "";
            if (code !== 0) Toasts.show("Wi-Fi", (nmErr.text || nmOut.text || "Connection failed").trim().split("\n")[0]);
        }
    }

    // ---------------- Bluetooth ----------------
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btAvailable: fake.bt !== undefined ? fake.bt !== "none" : btAdapter !== null
    readonly property bool btOn: fake.bt !== undefined ? (fake.bt === "on" || fake.bt === "connected") : (btAdapter ? btAdapter.enabled : false)
    readonly property var btPaired: btAdapter ? btAdapter.devices.values.filter(d => d.paired || d.bonded) : []
    readonly property var btConnectedNames: fake.bt !== undefined ? (fake.bt === "connected" ? (fake.btDevices || ["Fake Headset"]) : [])
        : (btAdapter ? btAdapter.devices.values.filter(d => d.connected).map(d => d.name || d.address) : [])
    readonly property int btConnectedCount: btConnectedNames.length
    function setBtEnabled(on) {
        if (dryRun) { note("Bluetooth.defaultAdapter.enabled = " + on); return; }
        if (btAdapter) btAdapter.enabled = on;
    }
    function btToggleDevice(d) {
        if (dryRun) { note("BluetoothDevice(" + d.name + ")." + (d.connected ? "disconnect" : "connect") + "()"); return; }
        if (d.connected) d.disconnect(); else d.connect();
    }

    // ---------------- audio ----------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source].filter(n => n) }
    readonly property bool sinkReady: fake.vol !== undefined || (sink !== null && sink.audio !== null)
    readonly property bool srcReady: source !== null && source.audio !== null
    readonly property int sinkVol: fake.vol !== undefined ? fake.vol : (sinkReady ? Math.round(sink.audio.volume * 100) : 0)
    readonly property bool sinkMuted: fake.muted !== undefined ? !!fake.muted : (sinkReady ? sink.audio.muted : false)
    readonly property string sinkName: fake.sinkName !== undefined ? fake.sinkName : nodeLabel(sink)
    readonly property int srcVol: srcReady ? Math.round(source.audio.volume * 100) : 0
    readonly property bool srcMuted: srcReady ? source.audio.muted : false
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio !== null)
    function nodeLabel(n) { return n ? (n.description || n.nickname || n.name) : ""; }
    function setSinkVol(p) {
        if (dryRun) { note("sink volume = " + p + "%"); return; }
        if (sinkReady) sink.audio.volume = p / 100;
    }
    function toggleSinkMute() {
        if (dryRun) { note("sink muted = " + !sinkMuted); return; }
        if (sinkReady) sink.audio.muted = !sink.audio.muted;
    }
    function setSrcVol(p) {
        if (dryRun) { note("source volume = " + p + "%"); return; }
        if (srcReady) source.audio.volume = p / 100;
    }
    function toggleSrcMute() {
        if (dryRun) { note("source muted = " + !srcMuted); return; }
        if (srcReady) source.audio.muted = !source.audio.muted;
    }
    function setDefaultSink(n) {
        if (dryRun) { note("default sink = " + nodeLabel(n)); return; }
        Pipewire.preferredDefaultAudioSink = n;
    }

    // ---------------- battery ----------------
    readonly property var batt: UPower.displayDevice
    readonly property bool hasBattery: fake.batt !== undefined || (batt !== null && batt.isPresent && (batt.isLaptopBattery || batt.energyCapacity > 0))
    // Quickshell UPower percentage is a 0..1 fraction
    readonly property int battPct: fake.batt !== undefined ? fake.batt : (hasBattery ? Math.round(batt.percentage * 100) : 0)
    readonly property bool charging: fake.batt !== undefined ? !!fake.charging : (hasBattery && (batt.state === UPowerDeviceState.Charging || batt.state === UPowerDeviceState.PendingCharge))
    readonly property bool full: fake.batt !== undefined ? !!fake.full : (hasBattery && batt.state === UPowerDeviceState.FullyCharged)
    readonly property string battState: !hasBattery ? "" : (charging ? "CHARGING" : (full ? "FULL" : "DISCHARGING"))
    function fmtTime(sec) {
        if (!sec || sec <= 0) return "";
        const m = Math.round(sec / 60);
        return Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0") + "m";
    }
    readonly property string battTime: fake.battTime !== undefined ? fake.battTime : (!hasBattery ? "" : (charging ? fmtTime(batt.timeToFull) : (full ? "" : fmtTime(batt.timeToEmpty))))

    // ---------------- power profile ----------------
    property bool profilesAvailable: false
    property var profileList: []
    property string profile: fake.profile !== undefined ? fake.profile : ""
    function refreshProfiles() { profList.running = false; profList.running = true; profGet.running = false; profGet.running = true; }
    function setProfile(p) {
        exec(["powerprofilesctl", "set", p]);
        if (!dryRun) profRefresh.restart();
        profile = p;
    }
    Timer { id: profRefresh; interval: 400; onTriggered: root.refreshProfiles() }
    Process {
        id: profList
        command: ["sh", "-c", "command -v powerprofilesctl >/dev/null && powerprofilesctl list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = [];
                for (const line of text.split("\n")) {
                    const m = line.match(/^\s*\*?\s*([a-z-]+):\s*$/);
                    if (m) names.push(m[1]);
                }
                root.profileList = names;
                root.profilesAvailable = names.length > 1;
            }
        }
    }
    Process {
        id: profGet
        command: ["sh", "-c", "command -v powerprofilesctl >/dev/null && powerprofilesctl get"]
        stdout: StdioCollector { onStreamFinished: { if (root.fake.profile === undefined) root.profile = text.trim(); } }
    }

    // ---------------- backlight ----------------
    property string blDev: ""
    property int blMax: 0
    property int blPct: 0
    readonly property bool hasBacklight: blDev !== "" && blMax > 0
    property double blSetAt: 0
    function refreshBrightness() { blRead.running = false; blRead.running = true; }
    Process {
        id: blRead
        command: ["sh", "-c", "d=$(ls -d /sys/class/backlight/* 2>/dev/null | head -n1); [ -n \"$d\" ] && echo \"$(basename $d) $(cat $d/brightness) $(cat $d/max_brightness)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(" ");
                if (p.length !== 3) return;
                root.blDev = p[0];
                root.blMax = parseInt(p[2]);
                if (Date.now() - root.blSetAt > 1500)
                    root.blPct = Math.round(parseInt(p[1]) * 100 / Math.max(1, root.blMax));
            }
        }
    }
    property int blPending: -1
    function setBrightness(pct) {
        blPct = Math.max(1, Math.min(100, pct));
        blSetAt = Date.now();
        blPending = blPct;
        if (!blThrottle.running) blThrottle.start();
    }
    Timer {
        id: blThrottle
        interval: 90
        onTriggered: {
            if (root.blPending < 0 || !root.hasBacklight) return;
            const v = Math.max(1, Math.round(root.blPending * root.blMax / 100));
            root.blPending = -1;
            root.exec(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                       "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", root.blDev, String(v)]);
        }
    }

    // ---------------- lock screen ----------------
    // LockScreen.qml (in shell.qml) owns the session lock; this just asks it to lock.
    readonly property bool lockAvailable: true
    function lock() { Config.lock(); }

    // ---------------- refresh while the panel is open ----------------
    onQsOpenChanged: {
        if (qsOpen) { _netKey = ""; refreshNets(); refreshBrightness(); refreshProfiles(); }
    }
    Timer {
        interval: 2000; repeat: true; running: root.qsOpen
        onTriggered: { root.refreshBrightness(); root.profGetTick(); }
    }
    function profGetTick() { profGet.running = false; profGet.running = true; }

    // ---------------- media ----------------
    readonly property var player: {
        const v = Mpris.players.values;
        for (let i = 0; i < v.length; i++) if (v[i].isPlaying) return v[i];
        return v.length ? v[0] : null;
    }
}
