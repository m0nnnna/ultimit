# Polish pass: the rules

Goal: the finish of a well-made desktop (consistent light, clear layers, few lines, calm type,
one motion language) without losing Ultimit's look: square corners, glass, accent lines, mono
labels, corner brackets (they stay as they are).

Every value below lives in `shell/Theme.qml` (mirrored in `greeter/Theme.qml` and
`compositor/src/theme.h` via `chromeArgs`). Components use the tokens; literals are a bug.

## 1. Light comes from above

- Every L1 surface gets a **top highlight**: a 1 px line on its top edge, skin `edge` colour at
  `hl` alpha (dark skins .14, light skins .55), fading to 0 over the outer 15 % of the width.
- L1 fills carry a **soft vertical sheen**: fill colour at the top, 4 % darker at the bottom.
- No other strokes on L1. The bottom and sides are defined by shadow.

## 2. Three surface levels

| Level | What | Fill | Edge | Shadow |
|---|---|---|---|---|
| L0 chrome | rail, top bar (ticker, status, tray) | `rail` | none | `elev1` onto the desktop |
| L1 floating | windows, flyouts, launcher, menus, notifications, dialogs | `panel` (one alpha, shared with compositor + greeter) | top highlight; brackets on windows/dialogs only | `elev2` |
| L2 inset | inner cards, rows, inputs, tiles | `field` | none, or `line` on inputs only | none |

New colour tokens (per skin, derived from fg/accent where possible): `field`, `hover`
(fg @ .06), `press` (fg @ .10), `selection` (accent @ .18), `divider` (fg @ .08),
`scrim` (shade @ .55). `line` stays for inputs; `lineStrong` is only for focus.

Dividers only between list rows that need them, never around a card. Spacing separates; lines
are the exception.

## 3. Type scale

| Token | px | Use |
|---|---|---|
| `type.label` | 12 | uppercase mono labels (tracked), captions |
| `type.body` | 14 | everything readable |
| `type.title` | 17 | card / section titles |
| `type.head` | 24 | page headings |
| `type.hero` | `ds(64)` | clocks, wordmarks |

Nothing under 12 px. Uppercase tracked mono only for real labels (section names, keycaps,
status), never for body text or buttons with more than two words.

## 4. Spacing

4 px grid via `Theme.space(n)`: 4, 8, 12, 16, 24, 32. Panel padding 16, card padding 12,
row height 36 (dense 28), gap between sections 24.

## 5. Icons

`icon.sm` 16, `icon.md` 20, `icon.lg` 24, `icon.xl` 32. Tray and rail use md; launcher rows lg.
No letter badges where a real icon exists (theme icon first, then our drawn glyph, then the
letter hex as last resort, dimmed).

## 6. Motion

| Token | ms | Easing | Use |
|---|---|---|---|
| `motion.fast` | 100 | OutCubic | hover, press, colour |
| `motion.base` | 180 | OutCubic | flyouts, toggles, selection |
| `motion.slow` | 280 | OutQuint | panels opening, page changes |

All through `Config.dur()`. Every hover/press/selected colour change animates (`Behavior on
color` with `motion.fast`); nothing snaps.

## 7. Elevation

`elev1`: blur 16, y 2, black .30. `elev2`: blur 32, y 8, black .45 (matches the compositor's
window shadow, `UL_SHADOW_SIGMA`).

## Order of work

1. Tokens in Theme.qml / greeter Theme / theme.h (greeter uses the shell's panel alpha).
2. Shared L1 recipe component (`Surface.qml`: fill + sheen + highlight + shadow + optional
   brackets) and move Flyout, Launcher, PopupMenu, ContextMenu, TrayMenu, NotifCard onto it.
3. Compositor frame: top highlight + sheen in the titlebar, keep brackets, glow and outline.
4. Rail, WindowList, TopBar (+ bar/ items), Tray, QuickSettings: type scale, icon sizes, real icons.
5. Apps, by audit impact: DATA, CLAUDE, EMBER, Settings, MEMO, GAMES, SHARES, DISKS.
6. Rough spots: version strings, duplicate launcher entries, letter icons.

Each step: before/after screenshots per skin (amber, mine, paper at least).
