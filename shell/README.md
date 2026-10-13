# Ultimit shell

Quickshell (QML) desktop shell for Ultimit, styled after `docs/design/mockup.html`.

## Run

Inside the Ultimit compositor (needs wlr-layer-shell; GNOME/Mutter will not work):

    compositor/build/ultimit -s "~/.local/ultimit-deps/bin/qs -p $PWD/shell"

Headless smoke test: prefix with `WLR_BACKENDS=headless timeout -s INT 15`.
Environment: `ULTIMIT_SKIN=mine|amber|silver|verdant`, `ULTIMIT_MOTION=0` (static wallpaper).

## Files

- `shell.qml` - entry point; one set of panels per screen (`Variants` over `Quickshell.screens`).
- `Theme.qml` - singleton: tokens for the four skins, fonts, `skin` property.
- `Config.qml` - singleton: launch commands, app_id match lists, ticker headlines, motion/fps, metrics.
- `qmldir`, `components/qmldir` - register singletons/components.
- `components/Wallpaper.qml` - background-layer window; Canvas port of the mockup's shard/hex/ring drawing (<= 20 fps, once when motion is off); hosts the wordmark.
- `components/Wordmark.qml` - "[ ULTIMIT ]" + caption.
- `components/Rail.qml`, `RailButton.qml` - left rail (exclusive zone 84), launch/focus logic via ToplevelManager.
- `components/Icon.qml`, `Emblem.qml` - Shape/PathSvg ports of the mockup SVG icons and hex emblem.
- `components/StatusBlock.qml` - clock, date, system row (placeholders), bottom layer.
- `components/Ticker.qml` - bottom news ticker (exclusive zone 26, left margin = rail width).
- `Persist.qml` - loads/saves `~/.config/ultimit/shell.json` (skin, motion, shardDensity, bootOnStart) via FileView/JsonAdapter and syncs it with Theme/Config. Env vars (`ULTIMIT_SKIN`, `ULTIMIT_MOTION`, `ULTIMIT_BOOT=0`) override the file for that run without being saved.
- `Boot.qml` - boot sequence overlay (overlay layer, per screen); plays at startup unless `Config.bootOnStart` is false, and on `Config.playBoot()` (Accessory button, desktop menu, `qs ipc call boot play`).
- `apps/settings/` - Settings window (FloatingWindow titled "SETTINGS", rail ACCESSORY button): appearance, display (15 s revert, saves `~/.config/ultimit/displays.conf`), sound, network, Bluetooth, power/idle, input (`compositor.ini`), default apps, date & time, users (`users.py` lists accounts and changes your own password through `passwd`; other accounts go through `distro/system/usr/libexec/ultimit/users-helper` via pkexec, polkit `org.ultimit.users`; tests: `python3 apps/settings/test_users.py`), updates (`updates.py` reads apt/Flatpak/fwupd state; installing goes through `distro/system/usr/libexec/ultimit/updates-helper` via pkexec, polkit action `org.ultimit.updates`; tests: `python3 apps/settings/test_updates.py`, `UPDATES_FAKE_DIR` for fake data), about. IPC: `qs ipc call settings open <page>|toggle|close`. `ULTIMIT_DRY_RUN=1` logs system changes instead of making them.
- `apps/accessory/` - shared widgets (ChamferButton, ToggleRow, SliderField, SkinCard, SectionLabel).
- `apps/data/` - DATA file manager (FloatingWindow titled "DATA"): `Data.qml` singleton, `DataWindow.qml`, `data.py` stdlib helper (listing, jobs, trash, properties, open-with). Tabs: Ctrl+T new, Ctrl+W close, Ctrl+Shift+T reopen, Ctrl+(Shift+)Tab / Ctrl+PgUp/PgDn switch, Ctrl+Shift+PgUp/PgDn move, Ctrl+1..9; middle-click a folder, archive, sidebar place or path segment to open it in a background tab, middle-click a tab to close it, drag tabs to reorder, drop files on a tab to move them there. Opening a path while DATA is showing opens a new tab. IPC: `qs ipc call data open <path>|newtab <path>|toggle|close`; CLI `bin/ultimit-data [path]`. Env: `ULTIMIT_DATA_START`, `ULTIMIT_DRY_RUN=1`, `ULTIMIT_FAKE_LSBLK=<file>`.
- `apps/clipboard/` - clipboard history (Super+V, `bin/ultimit-clipboard`): `clip.py watch` runs under the shell for the session (`wl-paste --watch`), keeping the newest 50 texts/PNGs plus pinned ones in `~/.local/share/ultimit/clipboard/` (secrets marked by password managers are skipped; a new login keeps only pinned). `ClipboardPanel.qml` (overlay, bottom-right): Enter pastes into the previous window (wtype Ctrl+V, Ctrl+Shift+V for terminals), P pins, Del removes. IPC: `qs ipc call clipboard toggle|open|close|list`. Tests: `python3 apps/clipboard/test_clip.py`.
- `apps/store/` - STORE (own process, `store-shell.qml`; `bin/ultimit-store [--search WORDS | --app ID | --installed]`): app store over Flathub. `store.py` indexes the AppStream data flatpak keeps on disk (cached in `~/.cache/ultimit/store/`) for picks, categories, search and app pages; install/remove are queued `flatpak` runs (system installation, polkit asks), and STORE stays running until they finish. The rail's not-installed MAILER/NEWS/AUDIO and uninstalled pins open STORE on a search. IPC: `qs -p shell/store-shell.qml ipc call store open|search <w>|app <id>|installed|install <id>|dump`. Tests: `python3 apps/store/test_store.py`.
- `apps/firewall/` - FIREWALL (own process, `firewall-shell.qml`; `bin/ultimit-firewall [--blocked]`): ufw on/off, presets that open an app's ports to the home network only (VTube Studio, iFacialMocap/VBridger, VMC, Steam Remote Play, Sunshine, OBS remote, KDE Connect, LocalSend, SSH), the connections ufw blocked in the last 30 min (one click to allow), and every rule. `firewall.py` parses and decides; the root part is `distro/system/usr/libexec/ultimit/firewall-helper` (pkexec, polkit action `org.ultimit.firewall`; reading needs no password for admins, changes ask). IPC: `qs -p shell/firewall-shell.qml ipc call firewall open|blocked|dump`. `FIREWALL_FAKE=1` + `fixtures/make-state.sh` runs it against a fake ufw; tests: `python3 apps/firewall/test_firewall.py`.
- Wallpaper: `Config.wallpaper` ("" = generative shards, else an image) and `wallpaperFit` (fill|fit|stretch|center), saved in shell.json; picked in Settings > Appearance (picture folders, Browse… via zenity), from DATA's "Set as wallpaper", `bin/ultimit-wallpaper FILE [fit] | --shards` or `qs ipc call wallpaper set <file> <fit>|shards|get`. A missing file falls back to the shards.
- `bin/ultimit-screenshot` - screenshots (area/full) and screen recordings (`record-area` Super+Shift+R, `record-full` Super+Alt+R; the same key stops; `stop`, `status`): wf-recorder, H.264 via VA-API on the Intel/AMD GPU with a CPU fallback, plus the sound the PC plays; saved to ~/Videos/Recordings.
- `components/Privacy.qml` - markers in the bottom bar (StatusTray) while something uses the microphone (PipeWire capture streams), the camera (/dev/video* held open) or shares the screen (the portal's screen-cast stream), and REC with a timer while recording (click to stop).
- `components/ShortcutSheet.qml` - every keyboard shortcut on one screen (Super+/, Settings > Input, `bin/ultimit-shortcuts`, `qs ipc call shortcuts toggle`), read live from `ultimitctl keys`; typing filters.
- `Toasts.qml` - singleton toast queue (`Toasts.show(title, msg, command?)`); `components/ToastOverlay.qml` renders it top-right.
- `components/Launcher.qml` - app launcher (rail emblem; `qs ipc call launcher toggle|open|close`): DesktopEntries search, power row with two-step confirm.
- `components/WindowList.qml`, `WindowPopups.qml`, `WindowUi.qml` - rail "WINDOWS" list of every toplevel (click minimize/activate, middle close, right menu, hover tooltip). IPC: `qs ipc call toasts notify "Title" "Msg"` (`show` is shadowed by the `qs ipc show` subcommand, so use `notify`).
- `components/ContextMenu.qml` - desktop right-click menu (opened by Wallpaper).
- `Config.apps[].tryCmds` - ordered candidate commands, probed once at startup; unavailable apps dim in the rail and toast an install hint.
