// News: the feeds behind the ticker in the top bar (Feeds.qml, saved in shell.json "feeds").
// RSS 2.0 and Atom; http/https only. With no feeds the ticker shows the built-in headlines.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Page {
    id: pg
    title: "News"
    subtitle: "Feeds for the ticker in the top bar. Headlines refresh every 15 minutes; the last good result is cached for offline use. With no feeds the ticker shows the built-in headlines."

    property string formError: ""
    function when(ms) {
        if (!ms) return "never";
        const d = new Date(ms);
        return ((d.getHours() % 12) || 12) + ":" + String(d.getMinutes()).padStart(2, "0") + (d.getHours() < 12 ? " AM" : " PM");
    }
    function statusOf(url) {
        for (const f of Feeds.status) if (f.url === url) return f;
        return null;
    }
    function add() {
        const u = entry.text.trim();
        if (!Feeds.isHttp(u)) { formError = "Enter an http:// or https:// address"; return; }
        if (Feeds.urls.indexOf(u) >= 0) { formError = "That feed is already in the list"; return; }
        formError = "";
        Feeds.urls = Feeds.urls.concat([u]);
        entry.text = "";
    }

    SectionLabel { text: "Ticker" }
    ToggleRow {
        Layout.fillWidth: true
        text: "Show the news ticker in the top bar"
        checked: Config.tickerOn
        onToggled: value => Config.tickerOn = value
    }
    ToggleRow {
        Layout.fillWidth: true
        text: "Show notifications in the ticker"
        checked: Config.tickerNotifs
        enabled: Config.tickerOn
        onToggled: value => Config.tickerNotifs = value
    }

    SectionLabel { text: "Feeds" }
    Text {
        visible: Feeds.urls.length === 0
        Layout.fillWidth: true
        text: "No feeds. The ticker shows the built-in headlines."
        color: Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
    }
    Repeater {
        model: Feeds.urls
        delegate: ItemRow {
            id: row
            required property string modelData
            readonly property var st: { Feeds.status; return pg.statusOf(modelData); }
            title: st && st.title ? st.title : modelData
            subtitle: {
                if (!st) return Feeds.busy ? "loading" : "not loaded yet";
                const url = st.title ? "  \u2014  " + modelData : "";
                if (st.ok) return st.count + " items, updated " + pg.when(st.fetched * 1000) + url;
                return st.error + (st.stale ? " (cached from " + pg.when(st.fetched * 1000) + ")" : "") + url;
            }
            badge: st ? (st.ok ? "ok" : "error") : ""
            badgeColor: st && !st.ok ? Theme.bad : Theme.ok
            ChamferButton {
                text: "Remove"; implicitHeight: 30
                onClicked: Feeds.urls = Feeds.urls.filter(u => u !== row.modelData)
            }
        }
    }

    SectionLabel { text: "Add a feed" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        TextEntry {
            id: entry
            Layout.fillWidth: true
            placeholder: "https://example.com/feed.xml"
            onAccepted: pg.add()
            onTextChanged: pg.formError = ""
        }
        ChamferButton { text: "Add"; primary: true; onClicked: pg.add() }
    }
    Text {
        visible: pg.formError !== ""
        Layout.fillWidth: true
        text: pg.formError; color: Theme.bad
        font.family: Theme.ui; font.pixelSize: Theme.type.label
    }

    SectionLabel { text: "Status" }
    InfoRow { Layout.fillWidth: true; label: "Last updated"; value: pg.when(Feeds.updatedMs) + (Feeds.busy ? "  (refreshing)" : "") }
    InfoRow {
        Layout.fillWidth: true
        visible: Feeds.error !== ""
        label: "Error"; value: Feeds.error; valueColor: Theme.bad
    }
    InfoRow { Layout.fillWidth: true; label: "Headlines"; value: Feeds.hasItems ? String(Feeds.shown.length) + " from feeds" : "built-in" }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        ChamferButton { text: Feeds.busy ? "Refreshing…" : "Refresh now"; onClicked: Feeds.refresh() }
        ChamferButton {
            text: "Restore default feed"
            visible: Feeds.urls.indexOf(Feeds.defaultFeed) < 0
            onClicked: Feeds.urls = Feeds.urls.concat([Feeds.defaultFeed])
        }
    }
}
