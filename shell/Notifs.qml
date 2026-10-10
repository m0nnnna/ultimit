pragma Singleton

// Notifs.qml - notification server (replaces GNOME Shell's) + popup/history state.
//   Notifs.popups   ListModel of live popups (rendered by components/ToastOverlay.qml)
//   Notifs.list     ListModel of history, newest first, max 50 (alias: Notifs.history)
//   Notifs.count    history length
//   Notifs.dnd      do-not-disturb: suppresses popups (critical ones still show), history is kept
//   Notifs.clear()  / Notifs.dismiss(id) / Notifs.toggleDnd()
// Row roles (both models): nid, kind ("notif"|"toast"), app, title, body (sanitized StyledText),
// icon, image, urgency (0 low, 1 normal, 2 critical), timeout (ms, 0 = sticky), actions (JSON
// [{id,text}] without "default"), hasDefault, command, time (epoch ms), rev.
// Toasts.show() feeds the same popups (kind "toast", negative nid, not kept in history).
// IPC: qs ipc call notifs toggleDnd|dnd <bool>|clear|count
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool dnd: false
    readonly property int maxHistory: 50
    readonly property int maxPopups: 5
    readonly property alias popups: popupModel
    readonly property alias list: historyModel
    readonly property alias history: historyModel
    readonly property int count: historyModel.count
    readonly property int popupCount: popupModel.count

    ListModel { id: popupModel }
    ListModel { id: historyModel }

    property var live: ({})      // nid -> Notification (tracked while its popup is up)
    property var watchers: ({})  // nid -> Connections holder
    property int _toastSeq: 0

    // ---------- helpers ----------
    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    // Body markup (freedesktop subset) -> Qt StyledText: everything escaped, then only
    // <b> <i> <u> <br> and <a href="http(s)://..."> are re-enabled. Images/other tags stay inert text.
    function sanitize(s) {
        let t = esc(s || "");
        t = t.replace(/&lt;(\/?)(b|i|u)&gt;/gi, "<$1$2>");
        t = t.replace(/&lt;br\s*\/?&gt;/gi, "<br>");
        t = t.replace(/&lt;a\s+href=(?:"|&quot;)?(https?:\/\/[^"'\s<>&]*)(?:"|&quot;)?[^&]*?&gt;/gi, '<a href="$1">');
        t = t.replace(/&lt;\/a&gt;/gi, "</a>");
        t = t.replace(/\r?\n/g, "<br>");
        return t;
    }
    function iconUrl(name) {
        if (!name) return "";
        if (name.startsWith("/")) return "file://" + name;
        if (name.startsWith("file:") || name.startsWith("image:")) return name;
        return Icons.path(name);
    }
    function entryFrom(n, prev) {
        const acts = [];
        let hasDefault = false;
        const a = n.actions || [];
        for (let i = 0; i < a.length; i++) {
            if (a[i].identifier === "default") { hasDefault = true; continue; }
            if (acts.length < 3) acts.push({ id: a[i].identifier, text: a[i].text || a[i].identifier });
        }
        const urg = n.urgency === NotificationUrgency.Critical ? 2 : (n.urgency === NotificationUrgency.Low ? 0 : 1);
        const t = n.expireTimeout;                     // seconds; -1 = server default, 0 = never
        const ms = urg === 2 ? 0 : (t > 0 ? Math.round(t * 1000) : (t === 0 ? 0 : 6000));
        return {
            nid: n.id, kind: "notif",
            app: n.appName || n.desktopEntry || "",
            title: n.summary || "", body: sanitize(n.body),
            icon: iconUrl(n.appIcon), image: n.image || "",
            urgency: urg, timeout: ms,
            actions: JSON.stringify(acts), hasDefault: hasDefault, command: "",
            time: prev ? prev.time : Date.now(), rev: prev ? prev.rev + 1 : 0
        };
    }
    function indexOfNid(model, nid) {
        for (let i = 0; i < model.count; i++) if (model.get(i).nid === nid) return i;
        return -1;
    }

    // ---------- notification intake ----------
    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        imageSupported: true
        persistenceSupported: true
        actionIconsSupported: false
        inlineReplySupported: false

        onNotification: n => root.intake(n)
    }

    Component {
        id: watcherComp
        Connections {
            id: w
            property int nid: 0
            function upd() { if (target) root.refresh(target); }
            function onSummaryChanged() { upd(); }
            function onBodyChanged() { upd(); }
            function onAppIconChanged() { upd(); }
            function onImageChanged() { upd(); }
            function onActionsChanged() { upd(); }
            function onUrgencyChanged() { upd(); }
            function onExpireTimeoutChanged() { upd(); }
            function onClosed(reason) { root.closedByApp(nid); }
        }
    }

    function intake(n) {
        const critical = n.urgency === NotificationUrgency.Critical;
        const show = !dnd || critical;
        const e = entryFrom(n, null);
        if (!n.transient) {
            historyModel.insert(0, e);
            while (historyModel.count > maxHistory) historyModel.remove(historyModel.count - 1);
        }
        if (!show) return;               // not tracked -> server drops it (history keeps a copy)
        n.tracked = true;
        live[n.id] = n;
        watchers[n.id] = watcherComp.createObject(root, { target: n, nid: n.id });
        popupModel.append(e);
        while (popupModel.count > maxPopups) release(popupModel.get(0).nid, false);
    }

    // In-place update (replaces_id).
    function refresh(n) {
        let i = indexOfNid(popupModel, n.id);
        const prevP = i >= 0 ? popupModel.get(i) : null;
        const e = entryFrom(n, prevP ? { time: prevP.time, rev: prevP.rev } : null);
        if (i >= 0) popupModel.set(i, e);
        const h = indexOfNid(historyModel, n.id);
        if (h >= 0) {
            const old = historyModel.get(h);
            e.time = old.time; e.rev = old.rev + 1;
            historyModel.set(h, e);
        }
    }

    function forget(nid) {
        const w = watchers[nid];
        if (w) { w.target = null; w.destroy(); }
        delete watchers[nid];
        delete live[nid];
    }
    function closedByApp(nid) {              // CloseNotification from the sender
        forget(nid);
        const i = indexOfNid(popupModel, nid);
        if (i >= 0) popupModel.remove(i);
    }

    // Remove a popup (history stays). dismissed = user closed it, else it timed out.
    function release(nid, dismissed) {
        const i = indexOfNid(popupModel, nid);
        if (i >= 0) popupModel.remove(i);
        const n = live[nid];
        if (n) {
            forget(nid);
            if (dismissed) n.dismiss(); else n.expire();
        }
    }
    function expirePopup(nid) { release(nid, false); }
    function closePopup(nid) { release(nid, true); }

    function invoke(nid, actionId) {
        const n = live[nid];
        if (!n) return;
        const a = n.actions || [];
        for (let i = 0; i < a.length; i++) {
            if (a[i].identifier === actionId) { a[i].invoke(); break; }
        }
        release(nid, true);
    }

    // ---------- public API ----------
    function dismiss(id) {
        release(id, true);
        const h = indexOfNid(historyModel, id);
        if (h >= 0) historyModel.remove(h);
    }
    function clear() {
        while (popupModel.count > 0) release(popupModel.get(0).nid, true);
        historyModel.clear();
    }
    function toggleDnd() { dnd = !dnd; }

    // Toasts.show() lands here.
    function toast(title, message, command, timeoutMs) {
        const nid = -(++_toastSeq);
        popupModel.append({
            nid: nid, kind: "toast", app: title || "", title: "",
            body: esc(message || ""), icon: "", image: "", urgency: 1,
            timeout: timeoutMs || (command ? 12000 : 4200),
            actions: "[]", hasDefault: false, command: command || "",
            time: Date.now(), rev: 0
        });
        while (popupModel.count > maxPopups) release(popupModel.get(0).nid, false);
    }

    IpcHandler {
        target: "notifs"
        function toggleDnd(): void { root.toggleDnd(); }
        function dnd(on: bool): void { root.dnd = on; }
        function clear(): void { root.clear(); }
        function count(): int { return root.count; }
    }
}
