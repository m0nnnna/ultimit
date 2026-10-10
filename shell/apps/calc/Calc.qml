pragma Singleton

// Calc.qml - state and logic of CALC, the Ultimit calculator. Parsing/evaluation lives in
// CalcEngine.js (hand written recursive descent parser: no eval, no Function).
// Env: ULTIMIT_CALC_SELFTEST=1 runs the expression table at startup and logs PASS/FAIL lines.
// IPC (see CalcWindow.qml):  qs -p <shell> ipc call calc toggle | open | close
import QtQuick
import Quickshell
import "CalcEngine.js" as Engine

Singleton {
    id: root

    property bool open: false
    function toggle() { open = !open; if (open) raise++; }
    function show() { open = true; raise++; }
    function hide() { open = false; }
    property int raise: 0

    property string expr: ""
    property bool deg: true
    property bool sci: false
    property bool fresh: false         // expr currently holds an evaluated result
    property string msg: ""            // error from the last "="
    property real ans: 0
    property var history: []           // [{ expr, result, value }] newest first
    property string copied: ""         // flashes the copied text

    readonly property var res: Engine.calc(expr, { deg: deg, ans: ans })
    readonly property string preview: {
        if (!res.ok || expr.trim() === "") return "";
        return res.text === expr.trim() ? "" : res.text;
    }

    function insert(s) {
        msg = "";
        if (fresh) {
            if (/^[0-9.a-z(π√]/i.test(s)) expr = "";
            fresh = false;
        }
        expr += s;
    }
    function backspace() { msg = ""; fresh = false; expr = expr.slice(0, -1); }
    function clear() { msg = ""; fresh = false; expr = ""; }
    function equals() {
        if (expr.trim() === "") return;
        const r = res;
        if (!r.ok) { msg = r.err; return; }
        msg = "";
        const h = history.slice();
        h.unshift({ expr: expr, result: r.text, value: r.value });
        history = h.slice(0, 60);
        ans = r.value;
        expr = r.text;
        fresh = true;
    }
    function useEntry(e) { msg = ""; fresh = false; expr = e.expr; }
    function clearHistory() { history = []; }
    function copyResult() {
        const t = res.ok && expr.trim() !== "" ? res.text : "";
        if (t === "") return;
        Quickshell.clipboardText = t;
        copied = t;
        copyTimer.restart();
    }
    function paste(s) {
        const clean = s.replace(/[,]/g, ".").replace(/[^0-9a-zA-Z.+\-*\/^%() ×÷−π]/g, "");
        if (clean !== "") insert(clean);
    }
    function pretty(s) { return s.replace(/\*/g, "×").replace(/\//g, "÷").replace(/-/g, "−"); }
    Timer { id: copyTimer; interval: 1200; onTriggered: root.copied = "" }

    Component.onCompleted: {
        if (Quickshell.env("ULTIMIT_CALC_SELFTEST") === "1") {
            const lines = Engine.selfTest();
            for (const l of lines) console.log("CALC " + l);
        }
    }
}
