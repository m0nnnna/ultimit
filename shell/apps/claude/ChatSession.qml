// ChatSession.qml - the chat on screen in a ClaudeWindow: its history (items), and while Claude works,
// the running `claude.py session` (Claude Code in stream-json mode) with what it streams back.
// load(project, chat) shows a chat ("" = a new one); send() starts or resumes Claude Code as needed.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property string projectId: ""
    property string chatId: ""          // "" = a new chat, not saved until its first message
    property var meta: ({})             // { title, account, session, ... } from claude.py
    property bool loading: false
    property bool busy: false           // a turn is running
    property bool live: proc !== null   // Claude Code is running for this chat
    property string liveText: ""        // the reply as it streams in
    property bool thinking: false
    property string statusText: ""      // Claude Code's own one-line summary of what it is doing
    property var ask: null              // the permission request waiting for an answer
    property var askQueue: []
    property string info: ""            // after a turn: "2 turns · $0.01 · 4.1 s"
    property string limit: ""           // usage warning from Claude Code
    property var usage: null            // this chat's totals: { cost, input, output, cacheRead, cacheWrite, turns }
    property var context: null          // { used, window }: how full the context was after the last turn
    property string modelName: ""       // the model Claude Code reports
    property var proc: null
    property var pending: []            // messages typed before Claude Code was ready
    property bool sysinfoUsed: false    // the system summary went with a message in this chat

    readonly property alias items: itemModel
    signal changed()                    // the chat list should reload (a new chat was saved, a title set)

    ListModel { id: itemModel }

    function addItem(o) {
        itemModel.append({ k: o.k || "note", text: o.text || "", name: o.name || "", summary: o.summary || "",
                       status: o.status || "", out: o.out || "", tid: o.id || "", kind: o.kind || "",
                       sysinfo: !!o.sysinfo });
    }
    function toolResult(id, error, out) {
        for (let i = itemModel.count - 1; i >= 0; i--) {
            if (itemModel.get(i).k === "tool" && itemModel.get(i).tid === id) {
                itemModel.setProperty(i, "status", error ? "error" : "ok");
                itemModel.setProperty(i, "out", out || "");
                return;
            }
        }
    }

    // ---- which chat ----
    function load(pid, cid) {
        stopProc();
        projectId = pid; chatId = cid || ""; meta = ({}); itemModel.clear();
        liveText = ""; statusText = ""; info = ""; limit = ""; modelName = ""; ask = null; askQueue = [];
        usage = null; context = null;
        busy = false; thinking = false; sysinfoUsed = false; pending = [];
        if (chatId === "") return;
        loading = true;
        const want = chatId;
        Claude.run(["chat", pid, cid], o => {
            if (root.chatId !== want) return;
            root.loading = false;
            if (!o.ok) { root.addItem({ k: "note", kind: "error", text: o.err }); return; }
            root.meta = o.meta;
            root.usage = o.meta.usage || null;
            root.context = o.meta.context || null;
            for (const it of o.items) {
                root.addItem(it);
                if (it.sysinfo) root.sysinfoUsed = true;
            }
        });
    }

    // ---- talking to Claude Code ----
    function send(text, withSysinfo) {
        text = text.trim();
        if (text === "") return;
        addItem({ k: "user", text: text, sysinfo: withSysinfo });
        if (withSysinfo) sysinfoUsed = true;
        busy = true; info = ""; statusText = ""; liveText = "";
        const cmd = JSON.stringify({ op: "send", text: text, sysinfo: !!withSysinfo });
        if (proc && proc.ready) proc.write(cmd + "\n");
        else { pending = pending.concat([cmd]); if (!proc) startProc(); }
    }
    function interrupt() { if (proc) proc.write(JSON.stringify({ op: "interrupt" }) + "\n"); }
    function permit(allow, always) {
        if (!ask || !proc) return;
        proc.write(JSON.stringify({ op: "permit", rid: ask.rid, allow: allow, always: always }) + "\n");
        addItem({ k: "note", kind: "perm", text: (allow ? (always ? "Allowed (always)" : "Allowed") : "Declined") + ": " + ask.tool + " " + ask.summary });
        nextAsk();
    }
    function nextAsk() { ask = askQueue.length ? askQueue[0] : null; askQueue = askQueue.slice(1); }
    function stopProc() {
        if (!proc) return;
        proc.write(JSON.stringify({ op: "close" }) + "\n");
        proc.onEvent = null;     // a closing chat no longer touches the screen
        proc = null;
    }

    function startProc() {
        const p = Claude.stream(["session", projectId, chatId === "" ? "new" : chatId], o => root.handle(o));
        p.ready = false;
        proc = p;
    }

    function handle(o) {
        switch (o.ev) {
        case "started":
            proc.ready = true;
            if (chatId === "") chatId = o.chat;
            meta = o.meta;
            for (const c of pending) proc.write(c + "\n");
            pending = [];
            break;
        case "init":
            modelName = o.model || "";
            break;
        case "delta":
            thinking = false;
            liveText += o.text;
            break;
        case "thinking":
            thinking = true;
            break;
        case "status":
            statusText = o.text || "";
            break;
        case "text":
            liveText = ""; thinking = false;
            addItem({ k: "claude", text: o.text });
            break;
        case "tool":
            liveText = ""; thinking = false;
            addItem({ k: "tool", name: o.name, summary: o.summary, id: o.id, status: "run" });
            break;
        case "tool_result":
            toolResult(o.id, o.error, o.out);
            break;
        case "ask":
            if (ask) askQueue = askQueue.concat([o]); else ask = o;
            break;
        case "asked":
            if (o.cancelled) {
                if (ask && ask.rid === o.rid) nextAsk();
                else askQueue = askQueue.filter(a => a.rid !== o.rid);
            }
            break;
        case "retry":
            statusText = "Connection trouble, trying again (" + o.attempt + " of " + o.max + ")";
            break;
        case "limit":
            limit = o.used ? Math.round(o.used * 100) + "% of the " + (o.type || "").replace(/_/g, "-") + " limit used" : "";
            break;
        case "usage":
            Claude.setUsage(o.account, o);
            break;
        case "result": {
            if (o.usage) usage = o.usage;
            if (o.context) context = o.context;
            busy = false; thinking = false; statusText = ""; liveText = "";
            if (o.error && o.text) addItem({ k: "note", kind: "error", text: o.text });
            const parts = [];
            if (o.turns) parts.push(o.turns + (o.turns === 1 ? " step" : " steps"));
            if (o.cost) parts.push("$" + Number(o.cost).toFixed(o.cost < 0.1 ? 3 : 2));
            if (o.ms) parts.push((o.ms / 1000).toFixed(1) + " s");
            if (o.denied) parts.push(o.denied + " declined");
            info = parts.join(" · ");
            root.changed();
            break;
        }
        case "note":
            addItem({ k: "note", kind: "error", text: o.text });
            break;
        case "exit":
            if (o.code !== 0 && (o.err || o.code === -1)) addItem({ k: "note", kind: "error", text: o.err || "Claude Code stopped." });
            busy = false; thinking = false; liveText = ""; ask = null; askQueue = [];
            proc = null;
            root.changed();
            break;
        }
    }
    Component.onDestruction: stopProc()
}
