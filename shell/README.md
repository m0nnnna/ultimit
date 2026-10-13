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
- `apps/settings/` - Settings window (FloatingWindow titled "Settings", rail ACCESSORY button): appearance, display (15 s revert, saves `~/.config/ultimit/displays.conf`), sound, network, Bluetooth, power/idle, input (`compositor.ini`), default apps, date & time, about. IPC: `qs ipc call settings open <page>|toggle|close`. `ULTIMIT_DRY_RUN=1` logs system changes instead of making them.
- `apps/accessory/` - shared widgets (ChamferButton, ToggleRow, SliderField, SkinCard, SectionLabel).
- `apps/data/` - DATA file manager (FloatingWindow titled "DATA"): `Data.qml` singleton, `DataWindow.qml`, `data.py` stdlib helper (listing, jobs, trash, properties, open-with). IPC: `qs ipc call data open <path>|toggle|close`; CLI `bin/ultimit-data [path]`. Env: `ULTIMIT_DATA_START`, `ULTIMIT_DRY_RUN=1`, `ULTIMIT_FAKE_LSBLK=<file>`.
- `apps/firewall/` - FIREWALL (own process, `firewall-shell.qml`; `bin/ultimit-firewall [--blocked]`): ufw on/off, presets that open an app's ports to the home network only (VTube Studio, iFacialMocap/VBridger, VMC, Steam Remote Play, Sunshine, OBS remote, KDE Connect, LocalSend, SSH), the connections ufw blocked in the last 30 min (one click to allow), and every rule. `firewall.py` parses and decides; the root part is `distro/system/usr/libexec/ultimit/firewall-helper` (pkexec, polkit action `org.ultimit.firewall`; reading needs no password for admins, changes ask). IPC: `qs -p shell/firewall-shell.qml ipc call firewall open|blocked|dump`. `FIREWALL_FAKE=1` + `fixtures/make-state.sh` runs it against a fake ufw; tests: `python3 apps/firewall/test_firewall.py`.
- `Toasts.qml` - singleton toast queue (`Toasts.show(title, msg, command?)`); `components/ToastOverlay.qml` renders it top-right.
- `components/Launcher.qml` - app launcher (rail emblem; `qs ipc call launcher toggle|open|close`): DesktopEntries search, power row with two-step confirm.
- `components/WindowList.qml`, `WindowPopups.qml`, `WindowUi.qml` - rail "WINDOWS" list of every toplevel (click minimize/activate, middle close, right menu, hover tooltip). IPC: `qs ipc call toasts notify "Title" "Msg"` (`show` is shadowed by the `qs ipc show` subcommand, so use `notify`).
- `components/ContextMenu.qml` - desktop right-click menu (opened by Wallpaper).
- `Config.apps[].tryCmds` - ordered candidate commands, probed once at startup; unavailable apps dim in the rail and toast an install hint.
