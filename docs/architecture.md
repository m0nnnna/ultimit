# Architecture

## Stack

| Layer | Choice | Why |
|---|---|---|
| Base OS | Ubuntu 26.04 LTS | Current kernel and Mesa, NVIDIA drivers packaged by Ubuntu, long support window |
| Compositor | Own C compositor on **wlroots 0.19** + **SceneFX** | wlroots brings DRM/KMS, direct scanout, tearing control, VRR, explicit sync and XWayland. SceneFX adds blur, shadows and rounded corners to the wlroots scene graph |
| Shell | **Quickshell** (Qt 6.10 / QML) | GPU-rendered UI with real animation, live reload during development, layer-shell panels |
| Games | Steam, Proton, Gamescope (optional per game), GameMode, MangoHud | Standard Linux gaming stack; the compositor stays out of the way of fullscreen games |
| Packaging | `.deb` packages / PPA, then an ISO built from Ubuntu | Users can install Ultimit on an existing Ubuntu system |

## Components

- **compositor**: window management, the window open/close line-draw
  animation, corner brackets and glass blur, input, outputs, the session
  entry for the login screen.
- **shell**: the left icon rail, wallpaper (shards, hex grid, rings), wordmark,
  clock and status, news ticker, notifications, launcher and lock screen,
  written in QML.
- **apps**: Games (Steam library front end with per-game GPU, Proton and
  Gamescope options), Mailer, News, Audio, Data and Accessory, following the
  mockup.
- **skins**: Mine, Amber, Silver, Verdant, Sakura, Paper and Void. One token file per skin, shared
  by the compositor and the shell.

## Gaming rules

- Fullscreen games get direct scanout, so the compositor does not copy their
  frames.
- Tearing control (`wp_tearing_control_v1`) and adaptive sync are supported
  and on by default for fullscreen games.
- NVIDIA explicit sync (`linux-drm-syncobj-v1`) is supported.
- On hybrid laptops the desktop renders on the integrated GPU, and games are
  offloaded to the discrete GPU by default.
- Blur and animation are switched off for any fullscreen game.

## Development loop

The compositor runs nested inside a window on an existing Wayland or X11
desktop, using the wlroots Wayland/X11 backends, so it can be rebuilt and
restarted without logging out. Quickshell reloads QML on save. Real-hardware
testing (games, VRR, NVIDIA offload) happens by choosing the Ultimit session on
the login screen.

Reference test machine: Intel UHD (Tiger Lake) + NVIDIA GTX 1650 Mobile,
driver 595 (open kernel module).
