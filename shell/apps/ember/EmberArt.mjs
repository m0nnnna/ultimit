// EmberArt.mjs - Ember's portrait as ASCII line art: the left half of a symmetric base, mirrored, with
// the eyes, mouth, bow and hair drawn over it per frame. frame(state) returns the rows (strings).
// Plain ASCII so every mono font draws it; one colour, the window's text colour.

const W = 51, MID = 25;
const SWAP = { "/": "\\", "\\": "/", "(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{", "<": ">", ">": "<" };
function mirror(s) { let o = ""; for (let i = s.length - 1; i >= 0; i--) o += SWAP[s[i]] || s[i]; return o; }

// left half: 26 columns, the last one is the centre column
const LEFT = [
    "                   _..--''",
    "               .-''     .|",
    "            .-'      .-' |",
    "           /      .-'  .'|",
    "          /     .'   .'  |",
    "         /    .'   .'  .'|",
    "        /    /    /   /  |",
    "       |    /    /   /   |",
    "       |   |    /   /    |",
    "       |   |-.-'-.-'-.-'-.",
    "       |   ||     ,---    ",
    "       |   ||             ",
    "       |   ||             ",
    "       |   ||             ",
    "       |   ||             ",
    "       |   ||             ",
    "       |   | \\            ",
    "       |   |  \\           ",
    "       |   |   '.         ",
    "       |   |     '.       ",
    "       |   |       '-.____",
    "       |   |          |   ",
    "      /    |          |   ",
    "     /    /|    _.--'     ",
    "    /    / | .-'          ",
    "   /    /  |/             ",
    "  |    |   |              ",
    "  |    |   |              ",
    "  |    |   |              ",
    "  |    |   |              ",
];
const BASE = LEFT.map(s => s.substring(0, MID) + s[MID] + mirror(s.substring(0, MID)));
export const rows = BASE.length;
export const cols = W;

// the eyes: 3 rows from EYE_ROW, the left eye's block starts at column EYE_COL (9 wide); the right
// eye is its mirror
const EYE_ROW = 11, EYE_COL = 14;
const EYES = {
    open:   [" _,=====,", "  \\ (@) /", "   '---' "],
    half:   [" _,     ,", "  \\=(@)=/", "   '---' "],
    closed: [" _,     ,", "  '-===-'", "         "],
    happy:  ["         ", "   ,---, ", "  '     '"],
    wide:   [" _,=====,", "  \\ (O) /", "   '---' "],
    up:     [" _,==@==,", "  \\     /", "   '---' "],
    down:   [" _,     ,", "  \\=====/", "   '(@)' "],
    left:   [" _,=====,", "  \\(@)  /", "   '---' "],
    right:  [" _,=====,", "  \\  (@)/", "   '---' "],
    shut:   ["         ", "  >---< ", "         "],
};
// the mouth: one row, centred
const MOUTH_ROW = 17;
const MOUTHS = { rest: "._.", smile: "\\_/", o: "(_)", a: "(o)", e: ".-.", flat: "---", small: " - " };
// the bow at the collar, centred
const BOW = [[22, ".-.   .-."], [23, "(   >o<   )"], [24, "'-' / \\ '-'"], [25, "/_/   \\_\\"]];
const ACCENTS = [[15, ","], [27, "."], [29, "."]];

function put(r, col, s, opaque) {
    const line = r[col.row];
    let out = line.substring(0, col.c);
    for (let j = 0; j < s.length; j++) out += (!opaque && s[j] === " ") ? line[col.c + j] : s[j];
    r[col.row] = out + line.substring(col.c + s.length);
}
function centred(r, row, s) { put(r, { row: row, c: MID - Math.floor(s.length / 2) }, s, true); }

// st: { eyes, mouth, sway (phase, radians), swayAmp (columns), thought (0-3 dots) }
export function frame(st) {
    const r = BASE.slice();
    const e = EYES[st.eyes] || EYES.open;
    // a look to one side: the right eye is the mirror of the look the other way
    const other = st.eyes === "left" ? EYES.right : st.eyes === "right" ? EYES.left : e;
    for (let i = 0; i < 3; i++) {
        put(r, { row: EYE_ROW + i, c: EYE_COL }, e[i], true);
        put(r, { row: EYE_ROW + i, c: W - EYE_COL - e[i].length }, mirror(other[i]), true);
    }
    for (const a of ACCENTS) centred(r, a[0], a[1]);
    centred(r, MOUTH_ROW, MOUTHS[st.mouth] || MOUTHS.rest);
    for (const b of BOW) centred(r, b[0], b[1]);
    // the long hair outside the face sways, more toward its ends
    const amp = st.swayAmp === undefined ? 1 : st.swayAmp;
    for (let i = 18; i < r.length; i++) {
        const k = (i - 17) / (r.length - 17);
        const d = Math.round(Math.sin((st.sway || 0) - i * 0.45) * amp * k * 1.4);
        if (d === 0) continue;
        r[i] = shift(r[i], 0, 11, d);
        r[i] = shift(r[i], W - 11, W, d);
    }
    // thinking: a small trail of dots above her head
    if (st.thought) {
        const dots = ["  o", " .  o", "  .   O"];
        for (let i = 0; i < st.thought && i < 3; i++)
            put(r, { row: 2 - i, c: 40 + i }, dots[i].trim(), false);
    }
    return r;
}
// move line[a, b) by d columns; nothing moves when that would push a stroke out of the segment
function shift(line, a, b, d) {
    let seg = line.substring(a, b);
    if ((d > 0 ? seg.substring(seg.length - d) : seg.substring(0, -d)).trim() !== "") return line;
    seg = d > 0 ? " ".repeat(d) + seg.substring(0, seg.length - d) : seg.substring(-d) + " ".repeat(-d);
    return line.substring(0, a) + seg + line.substring(b);
}
