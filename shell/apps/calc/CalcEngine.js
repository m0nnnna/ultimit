.pragma library

// CalcEngine.js - safe expression evaluator for CALC (recursive descent; no eval / Function).
//
//   expr   := term (('+' | '-') term)*
//   term   := unary (('*' | '/' | '%'(binary)) unary | implicit-multiplication)*
//   unary  := ('-' | '+') unary | power
//   power  := postfix ('^' unary)?            right associative, so 2^3^2 = 2^9 and -2^2 = -4
//   postfix:= primary ('%')*                  a '%' not followed by an operand means "/100"
//   primary:= number | const | func '(' expr ')' | '(' expr ')'
// Missing closing parentheses at the end of the input are accepted (live preview while typing).
// Names: pi e ans; functions: sqrt sin cos tan asin acos atan ln log abs exp.

var FUNCS = {
    sqrt: function (x) { if (x < 0) throw new Error("sqrt of negative"); return Math.sqrt(x); },
    ln: function (x) { if (x <= 0) throw new Error("ln domain"); return Math.log(x); },
    log: function (x) { if (x <= 0) throw new Error("log domain"); return Math.log(x) / Math.LN10; },
    abs: Math.abs,
    exp: Math.exp
};
var TRIG = ["sin", "cos", "tan"], ATRIG = ["asin", "acos", "atan"];

function tokenize(src) {
    var toks = [], i = 0, n = src.length;
    while (i < n) {
        var c = src[i];
        if (c === " " || c === "\t" || c === "\n") { i++; continue; }
        if ((c >= "0" && c <= "9") || c === ".") {
            var j = i, seenDot = false, digits = 0;
            while (j < n && ((src[j] >= "0" && src[j] <= "9") || (src[j] === "." && !seenDot))) {
                if (src[j] === ".") seenDot = true; else digits++;
                j++;
            }
            if (digits === 0) throw new Error("bad number");
            if (j < n && (src[j] === "e" || src[j] === "E")) {
                // scientific notation 1e5 / 1e-5 only when digits follow; otherwise 'e' is the constant (2e = 2*e)
                var k = j + 1;
                if (k < n && (src[k] === "+" || src[k] === "-")) k++;
                if (k < n && src[k] >= "0" && src[k] <= "9") {
                    while (k < n && src[k] >= "0" && src[k] <= "9") k++;
                    j = k;
                }
            }
            toks.push({ t: "num", v: parseFloat(src.substring(i, j)) });
            i = j; continue;
        }
        if (/[a-zA-Z]/.test(c)) {
            var m = i;
            while (m < n && /[a-zA-Z]/.test(src[m])) m++;
            toks.push({ t: "name", v: src.substring(i, m).toLowerCase() });
            i = m; continue;
        }
        if (c === "π") { toks.push({ t: "name", v: "pi" }); i++; continue; }
        if (c === "√") { toks.push({ t: "name", v: "sqrt" }); i++; continue; }
        if (c === "×") c = "*";
        else if (c === "÷") c = "/";
        else if (c === "−" || c === "–") c = "-";
        if ("+-*/^%()".indexOf(c) >= 0) { toks.push({ t: "op", v: c }); i++; continue; }
        throw new Error("unexpected '" + c + "'");
    }
    return toks;
}

// opts: { deg: bool, ans: number }
function evaluate(src, opts) {
    opts = opts || {};
    var toks = tokenize(src), p = 0;
    if (toks.length === 0) throw new Error("empty");

    function peek() { return p < toks.length ? toks[p] : null; }
    function isOp(t, v) { return t && t.t === "op" && t.v === v; }
    function startsOperand(t) { return t && (t.t === "num" || t.t === "name" || isOp(t, "(") || isOp(t, "-") || isOp(t, "+")); }
    function startsFactor(t) { return t && (t.t === "num" || t.t === "name" || isOp(t, "(")); }

    function expr() {
        var v = term();
        for (;;) {
            var t = peek();
            if (isOp(t, "+")) { p++; v += term(); }
            else if (isOp(t, "-")) { p++; v -= term(); }
            else return v;
        }
    }
    function term() {
        var v = unary();
        for (;;) {
            var t = peek();
            if (isOp(t, "*")) { p++; v *= unary(); }
            else if (isOp(t, "/")) {
                p++; var d = unary();
                if (d === 0) throw new Error("division by zero");
                v /= d;
            }
            else if (isOp(t, "%") && startsOperand(toks[p + 1])) {
                p++; var m = unary();
                if (m === 0) throw new Error("modulo by zero");
                v = v % m;
            }
            else if (startsFactor(t)) v *= unary();          // implicit multiplication: 2pi, 2(3), (1)(2)
            else return v;
        }
    }
    function unary() {
        var t = peek();
        if (isOp(t, "-")) { p++; return -unary(); }
        if (isOp(t, "+")) { p++; return unary(); }
        return power();
    }
    function power() {
        var b = postfix();
        if (isOp(peek(), "^")) {
            p++;
            var e = unary();
            var r = Math.pow(b, e);
            if (isNaN(r)) throw new Error("invalid power");
            return r;
        }
        return b;
    }
    function postfix() {
        var v = primary();
        while (isOp(peek(), "%") && !startsOperand(toks[p + 1])) { p++; v /= 100; }
        return v;
    }
    function primary() {
        var t = peek();
        if (!t) throw new Error("unexpected end");
        p++;
        if (t.t === "num") return t.v;
        if (isOp(t, "(")) {
            var v = expr();
            if (isOp(peek(), ")")) p++;
            else if (peek()) throw new Error("expected )");   // else: auto-close at end of input
            return v;
        }
        if (t.t === "name") {
            if (t.v === "pi") return Math.PI;
            if (t.v === "e") return Math.E;
            if (t.v === "ans") return opts.ans !== undefined ? opts.ans : 0;
            var f = t.v;
            var known = FUNCS.hasOwnProperty(f) || TRIG.indexOf(f) >= 0 || ATRIG.indexOf(f) >= 0;
            if (!known) throw new Error("unknown name '" + f + "'");
            var arg;
            if (isOp(peek(), "(")) { p++; arg = expr(); if (isOp(peek(), ")")) p++; else if (peek()) throw new Error("expected )"); }
            else if (startsFactor(peek()) || isOp(peek(), "-")) arg = unary();   // sin 30, sqrt 2
            else throw new Error("expected (");
            return applyFunc(f, arg, !!opts.deg);
        }
        throw new Error("unexpected '" + t.v + "'");
    }

    var result = expr();
    if (p < toks.length) throw new Error("unexpected '" + toks[p].v + "'");
    if (!isFinite(result)) throw new Error("overflow");
    return clean(result);
}

function applyFunc(f, x, deg) {
    if (FUNCS.hasOwnProperty(f)) return FUNCS[f](x);
    if (TRIG.indexOf(f) >= 0) {
        var r = deg ? x * Math.PI / 180 : x;
        if (f === "tan") {
            var c = Math.cos(r);
            if (Math.abs(c) < 1e-15) throw new Error("tan undefined");
            return Math.sin(r) / c;
        }
        return f === "sin" ? Math.sin(r) : Math.cos(r);
    }
    if ((f === "asin" || f === "acos") && Math.abs(x) > 1) throw new Error(f + " domain");
    var a = f === "asin" ? Math.asin(x) : (f === "acos" ? Math.acos(x) : Math.atan(x));
    return deg ? a * 180 / Math.PI : a;
}

// snap float noise: 0.1+0.2 -> 0.3, sin(pi) -> 0
function clean(x) {
    if (Math.abs(x) < 1e-14) return 0;
    return parseFloat(x.toPrecision(14));
}

function format(x) {
    if (typeof x !== "number" || isNaN(x)) return "";
    if (x === 0) return "0";
    var a = Math.abs(x);
    var s;
    if (a >= 1e15 || a < 1e-9) {
        s = parseFloat(x.toPrecision(12)).toExponential();
        return s.replace("e+", "e");
    }
    s = String(parseFloat(x.toPrecision(12)));
    if (s.indexOf("e") >= 0) s = x.toFixed(12).replace(/\.?0+$/, "");
    return s;
}

// -> { ok, value, text, err }
function calc(src, opts) {
    try { var v = evaluate(src, opts); return { ok: true, value: v, text: format(v), err: "" }; }
    catch (e) { return { ok: false, value: NaN, text: "", err: e.message }; }
}

var TESTS = [
    ["1+2", 3], ["0.1+0.2", 0.3], ["2*3+4", 10], ["2+3*4", 14], ["(2+3)*4", 20], ["10/4", 2.5],
    ["2^10", 1024], ["2^3^2", 512], ["-2^2", -4], ["2^-2", 0.25], ["-(3+4)", -7], ["--5", 5], ["3*-2", -6],
    ["10%3", 1], ["50%", 0.5], ["200*10%", 20], ["7 % 4", 3], ["sqrt(16)", 4], ["sqrt 9", 3],
    ["abs(-7.5)", 7.5], ["ln(e)", 1], ["log(1000)", 3], ["log(100)+ln(1)", 2], ["pi", Math.PI], ["2pi", 2 * Math.PI],
    ["2(3+4)", 14], ["(1+2)(3+4)", 21], ["sin(0)", 0], ["cos(0)", 1], ["1e3+1", 1001], ["1.5e-3*1000", 1.5],
    ["((2+3)", 5], ["sqrt(2)*sqrt(2)", 2], ["1/3*3", 1], ["0.7*3", 2.1], ["123456789*1000", 123456789000],
    ["3 + 4 * 2 / ( 1 - 5 ) ^ 2", 3.5], ["2×3", 6], ["8÷2", 4],
    ["@sin(30)", 0.5], ["@cos(60)", 0.5], ["@tan(45)", 1], ["@sin(180)", 0], ["@cos(90)", 0], ["@asin(1)", 90],
    ["#sin(pi/2)", 1], ["#cos(pi)", -1], ["#sin(pi)", 0], ["#atan(1)*4", Math.PI],
    ["!1/0", "division by zero"], ["!sqrt(-1)", "sqrt of negative"], ["!2+", "unexpected end"], ["!foo(1)", "unknown name 'foo'"],
    ["!1+$", "unexpected '$'"], ["!)", "unexpected ')'"], ["!1 2 )", "unexpected ')'"], ["!ln(0)", "ln domain"], ["!", "empty"]
];

// -> array of "PASS expr = value" / "FAIL ..." lines
function selfTest() {
    var out = [], fails = 0;
    for (var i = 0; i < TESTS.length; i++) {
        var src = TESTS[i][0], want = TESTS[i][1], mode = src[0], deg = false, expectErr = false;
        if (mode === "@") { deg = true; src = src.substring(1); }
        else if (mode === "#") { src = src.substring(1); }
        else if (mode === "!") { expectErr = true; src = src.substring(1); }
        var r = calc(src, { deg: deg });
        var ok;
        if (expectErr) ok = !r.ok && r.err === want;
        else ok = r.ok && Math.abs(r.value - want) <= 1e-9 * Math.max(1, Math.abs(want));
        if (!ok) fails++;
        out.push((ok ? "PASS " : "FAIL ") + (deg ? "[deg] " : "") + src + " => " + (r.ok ? r.text : "error: " + r.err) + (ok ? "" : "   (wanted " + want + ")"));
    }
    var fmt = [[0.1 + 0.2, "0.3"], [1 / 3, "0.333333333333"], [1e21, "1e21"], [1234567.5, "1234567.5"], [-0.00000000012, "-1.2e-10"], [100, "100"]];
    for (var j = 0; j < fmt.length; j++) {
        var got = format(clean(fmt[j][0])), ok2 = got === fmt[j][1];
        if (!ok2) fails++;
        out.push((ok2 ? "PASS " : "FAIL ") + "format(" + fmt[j][0] + ") => " + got + (ok2 ? "" : "   (wanted " + fmt[j][1] + ")"));
    }
    out.push((fails === 0 ? "SELFTEST PASS" : "SELFTEST FAIL") + " (" + (TESTS.length + fmt.length - fails) + "/" + (TESTS.length + fmt.length) + ")");
    return out;
}
