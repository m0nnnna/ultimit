// Date & time / region: timezone (timedatectl, polkit prompt via the Ultimit agent), NTP, locale (read-only).
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Page {
    id: pg
    title: "Date & time"
    property string tz: ""
    property bool ntp: false
    property bool synced: false
    property bool canNtp: true
    property var zones: []
    property string locale: ""
    property string keymap: ""
    property string now: ""

    function refresh() { show.go(); }
    Cmd {
        id: show
        argv: ["timedatectl", "show"]
        onDone: out => {
            for (const l of out.split("\n")) {
                const i = l.indexOf("="); if (i < 0) continue;
                const k = l.slice(0, i), v = l.slice(i + 1);
                if (k === "Timezone") pg.tz = v;
                else if (k === "NTP") pg.ntp = v === "yes";
                else if (k === "NTPSynchronized") pg.synced = v === "yes";
                else if (k === "CanNTP") pg.canNtp = v === "yes";
                else if (k === "TimeUSec") pg.now = v;
            }
        }
    }
    Cmd {
        id: zonesCmd
        argv: ["timedatectl", "list-timezones", "--no-pager"]
        onDone: out => pg.zones = out.split("\n").filter(z => z !== "").map(z => ({ id: z, label: z }))
    }
    Cmd {
        id: loc
        argv: ["localectl", "status"]
        onDone: out => {
            for (const l of out.split("\n")) {
                const m = l.match(/System Locale:\s*(.*)$/);
                if (m) pg.locale = m[1].trim();
                const k = l.match(/VC Keymap:\s*(.*)$/);
                if (k) pg.keymap = k[1].trim();
                const c = l.match(/^\s+(LANG=.*)$/);
                if (c && !pg.locale) pg.locale = c[1];
            }
        }
    }
    Cmd {
        id: setTz
        mutating: true
        property string zone: ""
        argv: ["timedatectl", "set-timezone", zone]
        onDone: (out, code) => {
            if (code !== 0) Toasts.show("Time zone", out.trim().split("\n")[0] || "Could not change the time zone");
            if (SetSys.dryRun) pg.tz = zone;
            pg.refresh();
        }
    }
    Cmd {
        id: setNtp
        mutating: true
        property bool on: true
        argv: ["timedatectl", "set-ntp", on ? "true" : "false"]
        onDone: (out, code) => {
            if (code !== 0) Toasts.show("Time", out.trim().split("\n")[0] || "Could not change NTP");
            if (SetSys.dryRun) pg.ntp = on;
            pg.refresh();
        }
    }
    Component.onCompleted: { show.go(); zonesCmd.go(); loc.go(); }
    Timer { interval: 15000; running: true; repeat: true; onTriggered: pg.refresh() }

    SectionLabel { text: "Time" }
    InfoRow { Layout.fillWidth: true; label: "Local time"; value: pg.now }
    InfoRow {
        Layout.fillWidth: true; label: "Clock sync"
        value: !pg.ntp ? "automatic sync off" : (pg.synced ? "synchronized" : "waiting for sync")
        valueColor: pg.ntp && pg.synced ? Theme.ok : Theme.fg
    }
    ToggleRow {
        Layout.fillWidth: true
        enabled: pg.canNtp
        text: "Set time automatically (NTP)"
        checked: pg.ntp
        onToggled: v => { setNtp.on = v; setNtp.go(); }
    }

    SectionLabel { text: "Time zone" }
    Dropdown {
        label: "Time zone"
        options: pg.zones
        current: pg.tz
        onPicked: id => { setTz.zone = id; setTz.go(); }
    }
    Text {
        Layout.fillWidth: true
        text: "Changing the time zone asks for authentication."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }

    SectionLabel { text: "Region" }
    InfoRow { Layout.fillWidth: true; label: "System locale"; value: pg.locale || "—" }
    InfoRow { Layout.fillWidth: true; label: "Console keymap"; value: pg.keymap || "—" }
    Text {
        Layout.fillWidth: true
        text: "Locale is read-only for now; change it with localectl."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
    }
}
