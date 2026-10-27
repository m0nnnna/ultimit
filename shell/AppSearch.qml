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

    // The program an entry runs, without the field codes (%U, %f ...): the identity of the entry.
    function exec(e) { return (e.command || []).filter(a => !/^%/.test(a)).join(" "); }
    // The same app listed twice under two ids (a copy in ~/.local/share/applications next to the
    // system one, a renamed file): same name and same program. Different programs that merely
    // share a name (Ultimit's CLAUDE and the Claude desktop app) stay, see hint().
    function unique(list) {
        const seen = {};
        return list.filter(e => {
            const k = (e.name || "").toLowerCase() + "\u0000" + exec(e);
            if (seen[k]) return false;
            return (seen[k] = true);
        });
    }
    property var _names: ({})   // lower-case name -> how many listed entries have it
    // For an entry whose name another listed app shares: the program it runs, so the two read apart.
    function hint(e) {
        if (!e || (_names[(e.name || "").toLowerCase()] || 0) < 2) return "";
        const b = exec(e).split(" ")[0].split("/").pop();
        return b;
    }
    // Entries matching `query` (all when empty), best first / alphabetical.
    function filter(query) {
        const q = (query || "").trim().toLowerCase();
        const all = unique(DesktopEntries.applications.values.filter(visible));
        const n = {};
        for (const e of all) { const k = (e.name || "").toLowerCase(); n[k] = (n[k] || 0) + 1; }
        _names = n;
        if (q === "") return all.slice().sort((a, b) => a.name.localeCompare(b.name));
        return all.map(e => ({ e: e, s: score(e, q) })).filter(x => x.s > 0)
            .sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name)).map(x => x.e);
    }
}
