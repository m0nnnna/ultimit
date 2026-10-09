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
- `Boot.qml` - boot sequence overlay (overlay layer, per screen); plays at startup unless `Config.bootOnStart` is false, and on `Config.playBoot()` (Accessory button, rail emblem, `qs ipc call boot play`).
- `apps/accessory/` - Accessory window (FloatingWindow toplevel titled "Accessory"): skin cards, wallpaper toggle/slider, boot button. IPC: `qs ipc call accessory toggle|open|close`.
