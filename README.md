# [ ULTIMIT ]

A gaming-first Linux desktop for people who grew up wishing their computer
looked like Altimit OS from the *.hack* games: a dark icon rail, crystal-shard
wallpapers, hexagon grids, bracketed type and glass windows that open like a
console line drawing itself.

Ultimit is built on Ubuntu 26.04 LTS. It is its own Wayland compositor and
desktop shell, not a theme on top of another desktop.

> Status: early development. Nothing here is usable as a daily desktop yet.

## Goals

1. **Games work without fuss.** Steam and Proton, NVIDIA and hybrid laptops,
   fullscreen direct scanout, VRR and tearing control. A desktop decision that
   costs games frames or latency is the wrong decision.
2. **It looks like nothing else.** The approved design lives in
   [`docs/design/mockup.html`](docs/design/mockup.html). Open it in a browser
   and click around; it is the reference for every screen.
3. **It installs on plain Ubuntu.** Ultimit ships as packages first and as an
   ISO later, so it stays a thin layer over a well-supported base.

## Install

On Ubuntu 26.04: clone (or copy) this repository, then run `scripts/install.sh`.
Everything goes to `/opt/ultimit` for every user; see [`docs/install.md`](docs/install.md).

## Layout

| Path | What lives there |
|---|---|
| `docs/design/` | The interactive design mockup |
| `docs/architecture.md` | Stack choices and why |
| `docs/install.md` | Installing on another computer, updating, removing |
| `docs/iso.md` | The Ultimit ISO: Ubuntu's server installer, patched to set up Ultimit |
| `docs/updates.md` | Updates: Ubuntu's packages the Ubuntu way, Ultimit from GitHub releases; publishing one |
| `scripts/install.sh` | The installer (builds the libraries, installs to `/opt/ultimit`, sets up the login screen) |
| `assets/fonts/` | Michroma, Chakra Petch, Share Tech Mono (SIL Open Font License, licences beside them) |

## Credits

The look is a tribute to Altimit OS from *.hack* by CyberConnect2 and
Bandai Namco. Ultimit is an unofficial fan project. Its emblem, wallpapers and
code are original.

Successor to [nekOS](https://github.com/m0nnnna/nekos).

## License

MIT. See [LICENSE](LICENSE).
