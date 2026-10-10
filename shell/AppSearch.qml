pragma Singleton

// AppSearch.qml - DesktopEntries filtering shared by the Launcher and the Settings -> Rail picker.
// Hides NoDisplay entries and Config.launcherHidden; ranks by name/generic name/keywords/comment.
import QtQuick
import Quickshell

Singleton {
    function subseq(needle, hay) {
        let i = 0;
        for (let j = 0; j < hay.length && i < needle.length; j++) if (hay[j] === needle[i]) i++;
        return i === needle.length;
    }
    function score(e, q) {
        const n = (e.name || "").toLowerCase();
        if (n.startsWith(q)) return 100;
        if (n.indexOf(" " + q) >= 0) return 90;
        if (n.indexOf(q) >= 0) return 80;
        const g = (e.genericName || "").toLowerCase();
        if (g.indexOf(q) >= 0) return 60;
        const kw = (e.keywords || []).join(" ").toLowerCase();
        if (kw.indexOf(q) >= 0) return 50;
        if ((e.comment || "").toLowerCase().indexOf(q) >= 0) return 30;
        if (q.length >= 3 && subseq(q, n)) return 20;
        return 0;
    }
    function visible(e) { return !e.noDisplay && Config.launcherHidden.indexOf(e.id) < 0; }
    // Entries matching `query` (all when empty), best first / alphabetical.
    function filter(query) {
        const q = (query || "").trim().toLowerCase();
        const all = DesktopEntries.applications.values.filter(visible);
        if (q === "") return all.slice().sort((a, b) => a.name.localeCompare(b.name));
        return all.map(e => ({ e: e, s: score(e, q) })).filter(x => x.s > 0)
            .sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name)).map(x => x.e);
    }
}
