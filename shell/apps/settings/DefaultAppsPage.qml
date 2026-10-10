// Default apps: browser, mail, files, terminal, text editor, images. Candidates come from the
// installed .desktop files' MimeType= lines; the default is queried / set with xdg-mime.
// The terminal choice has no MIME type: it is written to ~/.config/xdg-terminals.list (xdg-terminal-exec).
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Page {
    id: pg
    title: "Default apps"

    readonly property var cats: [
        { id: "browser",  n: "Web browser",  probe: "x-scheme-handler/http", set: ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"] },
        { id: "mail",     n: "Mail",         probe: "x-scheme-handler/mailto", set: ["x-scheme-handler/mailto"] },
        { id: "files",    n: "File manager", probe: "inode/directory", set: ["inode/directory"] },
        { id: "terminal", n: "Terminal",     category: "TerminalEmulator" },
        { id: "editor",   n: "Text editor",  probe: "text/plain", set: ["text/plain", "text/markdown", "text/x-log"] },
        { id: "images",   n: "Image viewer", probe: "image/png", set: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml", "image/avif", "image/tiff"] }
    ]
    property var apps: []        // [{ id, name, mimes: ";a;b;", cats: ";X;" }]
    property var cur: ({})       // category id -> desktop file id

    function candidates(c) {
        const seen = {}; const out = [];
        for (const a of apps) {
            if (seen[a.id]) continue;
            const ok = c.category ? a.cats.indexOf(";" + c.category + ";") >= 0 : a.mimes.indexOf(";" + c.probe + ";") >= 0;
            if (!ok) continue;
            seen[a.id] = true;
            out.push({ id: a.id, label: a.name + "  (" + a.id.replace(/\.desktop$/, "") + ")" });
        }
        out.sort((x, y) => x.label.localeCompare(y.label));
        return out;
    }
    function setDefault(c, id) {
        if (c.category) {
            const path = SetSys.dryRun ? SetSys.dryDir + "/xdg-terminals.list" : SetSys.home + "/.config/xdg-terminals.list";
            SetSys.writeFile(path, "# Written by Ultimit Settings (xdg-terminal-exec)\n" + id + "\n");
        } else {
            setCmd.argv = ["xdg-mime", "default", id].concat(c.set);
            setCmd.shown = "xdg-mime default " + id + " " + c.set.join(" ");
            setCmd.go();
        }
        const n = Object.assign({}, cur); n[c.id] = id; cur = n;
    }

    Cmd {
        id: setCmd
        mutating: true
        onDone: (out, code) => { if (code !== 0) Toasts.show("Default apps", "xdg-mime failed"); }
    }
    Cmd {
        id: probe
        argv: ["sh", "-c", [
            'for m in ' + cats.filter(c => c.probe).map(c => c.probe).join(" ") + '; do echo "cur|$m|$(xdg-mime query default $m 2>/dev/null)"; done',
            'echo "cur|terminal|$(grep -v "^#" "$HOME/.config/xdg-terminals.list" 2>/dev/null | head -n1)"',
            'for d in /usr/share/applications /usr/local/share/applications "$HOME/.local/share/applications" /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications" /var/lib/snapd/desktop/applications; do [ -d "$d" ] || continue',
            'for f in "$d"/*.desktop; do [ -f "$f" ] || continue; grep -q "^NoDisplay=true" "$f" && continue',
            'echo "app|$(basename "$f")|$(sed -n "s/^Name=//p" "$f" | head -n1)|;$(sed -n "s/^MimeType=//p" "$f" | head -n1)|;$(sed -n "s/^Categories=//p" "$f" | head -n1)"; done; done'
        ].join("\n")]
        onDone: out => {
            const a = []; const c = {};
            for (const line of out.split("\n")) {
                const p = line.split("|");
                if (p[0] === "cur" && p.length >= 3) {
                    for (const cat of pg.cats) if (cat.id === p[1] || cat.probe === p[1]) c[cat.id] = p[2];
                } else if (p[0] === "app" && p.length >= 5) a.push({ id: p[1], name: p[2] || p[1], mimes: p[3], cats: p[4] });
            }
            pg.apps = a; pg.cur = c;
        }
    }
    Component.onCompleted: probe.go()

    Repeater {
        model: pg.cats
        delegate: Dropdown {
            id: dd
            required property var modelData
            label: modelData.n
            options: { pg.apps; return pg.candidates(modelData); }
            current: pg.cur[modelData.id] || ""
            placeholder: "Not set"
            onPicked: id => pg.setDefault(modelData, id)
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Candidates are the installed apps that declare support for the type. The terminal choice is saved to ~/.config/xdg-terminals.list."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12; wrapMode: Text.WordWrap
    }
}
