pragma Singleton

// Feeds.qml - RSS/Atom headlines for the bottom ticker.
// apps/news/feeds.py (stdlib python) does the fetching and parsing and keeps a cache of the last good
// result in ~/.cache/ultimit/feeds.json, so the ticker has content at login and while offline.
// Refreshes every 15 minutes and on demand (Settings -> News, `qs ipc call feeds refresh`).
// Feed content is untrusted text: the helper strips markup, the ticker renders PlainText, and
// open() only ever hands http/https URLs to xdg-open.
//   urls     - feed list (synced with shell.json "feeds" by Persist.qml); [] = built-in headlines only
//   shown    - [{ t: time label, h: headline, link }] for the ticker, newest first
//   status   - per feed [{ url, title, link, ok, error, count, fetched, stale }]
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string defaultFeed: "https://meowops.net/feed.xml"
    property var urls: [defaultFeed]

    property var items: []            // raw items from the helper
    property var shown: []            // display items (time labels applied)
    property var status: []
    property double updatedMs: 0      // when the last network refresh finished (0 = never)
    property bool busy: false
    property string error: ""         // helper-level error (e.g. every feed failed)
    readonly property bool hasItems: shown.length > 0

    readonly property string cacheFile: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/ultimit/feeds.json"
    readonly property string script: Quickshell.shellDir + "/apps/news/feeds.py"
    readonly property bool dryRun: Quickshell.env("ULTIMIT_DRY_RUN") === "1"

    // Where the rail NEWS button should go: the homepage of the newest item's feed,
    // else the newest link, else the first feed that reported a homepage. "" = nothing loaded.
    readonly property string homeUrl: {
        if (items.length > 0) {
            const it = items[0];
            if (isHttp(it.site)) return it.site;
            if (isHttp(it.link)) return it.link;
        }
        for (const f of status) if (isHttp(f.link)) return f.link;
        return "";
    }

    function isHttp(u) { return typeof u === "string" && /^https?:\/\/[^\s\/?#]\S*$/i.test(u) && !/[\u0000-\u001f]/.test(u); }

    // Open a feed link in the default browser; anything but http/https is ignored.
    function open(url) {
        if (!isHttp(url)) { console.warn("ultimit: refusing to open non-http(s) link"); return false; }
        if (dryRun) console.log("[dry-run] xdg-open " + url);
        else Quickshell.execDetached(["xdg-open", url]);
        return true;
    }

    // ---- time label like the ticker's: "4:39 PM" today, "YDAY", "OCT 07" ----
    readonly property var months: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    function label(ts) {
        if (!ts) return "";
        const d = new Date(ts * 1000), n = new Date();
        const day = x => x.getFullYear() * 10000 + x.getMonth() * 100 + x.getDate();
        if (day(d) === day(n)) return ((d.getHours() % 12) || 12) + ":" + String(d.getMinutes()).padStart(2, "0") + (d.getHours() < 12 ? " AM" : " PM");
        const y = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1);
        if (day(d) === day(y)) return "YDAY";
        return months[d.getMonth()] + " " + String(d.getDate()).padStart(2, "0");
    }
    function rebuild() {
        const out = items.map(it => ({ t: label(it.ts), h: it.title, link: isHttp(it.link) ? it.link : "" }));
        if (JSON.stringify(out) !== JSON.stringify(shown)) shown = out;   // keep the scroll running when nothing changed
    }

    // ---- fetching ----
    property bool gotNet: false
    property bool pending: false
    function validUrls() { return (urls || []).filter(u => isHttp(u)); }

    function refresh() {
        const list = validUrls();
        if (list.length === 0) {
            items = []; status = []; error = ""; shown = []; updatedMs = 0;
            return;
        }
        if (net.running) { pending = true; return; }
        busy = true;
        net.command = ["python3", "-I", script, "--cache", cacheFile, "--"].concat(list);
        net.running = true;
    }
    function loadCached() {
        const list = validUrls();
        if (list.length === 0 || cached.running) return;
        cached.command = ["python3", "-I", script, "--cache", cacheFile, "--cached", "--"].concat(list);
        cached.running = true;
    }
    function apply(txt, fromNet) {
        let d = null;
        try { d = JSON.parse(txt); } catch (e) { d = null; }
        if (!d) { if (fromNet) { error = "helper failed"; updatedMs = Date.now(); } return; }
        if (!fromNet && gotNet) return;
        items = d.items || [];
        status = d.feeds || [];
        error = d.error || "";
        if (fromNet) { gotNet = true; updatedMs = Date.now(); }
        rebuild();
    }

    onUrlsChanged: if (started) debounce.restart()
    property bool started: false
    function start() {
        if (started) return;
        started = true;
        loadCached();
        refresh();
    }

    Timer { id: debounce; interval: 400; onTriggered: { root.gotNet = false; root.loadCached(); root.refresh(); } }
    Timer { interval: 15 * 60 * 1000; repeat: true; running: root.started && !Config.gameModeActive; onTriggered: root.refresh() }
    Timer { interval: 5 * 60 * 1000; repeat: true; running: root.started && !Config.gameModeActive; onTriggered: root.rebuild() }   // YDAY rollover

    Process {
        id: cached
        stdout: StdioCollector { onStreamFinished: root.apply(text, false) }
    }
    Process {
        id: net
        stdout: StdioCollector { onStreamFinished: root.apply(text, true) }
        onExited: {
            root.busy = false;
            if (root.pending) { root.pending = false; root.refresh(); }
        }
    }
}
