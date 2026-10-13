# Roadmap: a GNOME-free Ultimit

The proof that Ultimit is a complete desktop: purge GNOME from this Ubuntu
26.04 install and everything still works.

**Removed at the end:** gnome-shell, mutter, GDM, gnome-session,
gnome-settings-daemon, gnome-control-center, every GNOME app (Files, Text
Editor, Calculator, Ptyxis/GNOME Terminal, Papers, Loupe, Disks, Logs,
Clocks, Characters, ...), gnome-keyring, gvfs, GNOME Online Accounts,
evolution-data-server, Yaru GNOME Shell theme.

**Kept as libraries:** GTK, GLib, dconf (Firefox and most Linux apps and game
launchers need them).

GNOME stays installed as a safety net until phase 4.

## Phase 1: system controls in the shell
- [x] Notification server (popups in the Altimit toast style, history,
      do-not-disturb)
- [x] On-screen display for volume and brightness; media/volume/brightness
      keys bound in the compositor
- [x] Real status row (network, battery, volume, Bluetooth)
- [x] Quick settings panel: Wi-Fi, Bluetooth, output/input volume,
      brightness, battery, now playing (MPRIS), power menu
- [x] System tray (StatusNotifierItem: Steam, Discord, ...)

## Phase 2: session
- [x] Compositor: ext-session-lock-v1, ext-idle-notify-v1, idle-inhibit
- [x] Lock screen (PAM), idle dim/lock/suspend, lock on lid close/suspend
- [x] Polkit authentication agent
- [x] Secret service replacement for gnome-keyring (oo7; login PAM unlock comes with the greeter)
- [x] Display configuration (wlr-output-management) and input settings
      (touchpad tap, natural scroll, keyboard layout, pointer speed)
- [x] Ultimit login screen on greetd, replacing GDM

## Phase 3: Ultimit apps
- [x] Settings (grows out of Accessory): display, sound, network,
      Bluetooth, power, input, appearance, users, about
- [x] DATA: file manager (trash, removable drives, network shares via
      udisks/mount; no gvfs)
- [x] Text editor (MEMO, own process, draft recovery)
- [x] Calculator (CALC)
- [x] Terminal: foot, themed
- [x] Non-GNOME picks for PDF and images: zathura, imv (to be replaced later)

## Phase 3b: what GNOME did quietly
- [x] SSH agent: export gcr's socket (gcr4 stays)
- [x] Icon theme for the shell without a Qt platform theme (QS_ICON_THEME)
- [x] Bluetooth pairing agent (PIN/passkey/confirm prompts)
- [x] NetworkManager secret agent (Wi-Fi password, 802.1X, VPN prompts)
- [x] Printer setup UI: system-config-printer (GTK, not GNOME)
- [ ] Secret portal for Flatpak apps: oo7-portal (only if Flatpak is ever used)

## Phase 4: the proof
Dry run (`apt-get -s purge`, 2026-10-10) removes exactly these 30 packages
and nothing else: evolution-data-server ubuntu-desktop-minimal gdm3
gnome-calculator gnome-characters gnome-clocks ubuntu-session
gnome-shell-ubuntu-extensions gnome-shell gnome-control-center
gnome-disk-utility gnome-initial-setup seahorse gnome-keyring gnome-logs
gnome-online-accounts gnome-session-bin gnome-settings-daemon
gnome-terminal gnome-text-editor xdg-desktop-portal-gnome nautilus
gvfs-backends gvfs-fuse gvfs gvfs-daemons loupe papers ptyxis
yaru-theme-gnome-shell. Follow with `apt autoremove` (review its list).

- [x] Purge the packages above, reboot, log in through the Ultimit greeter
      (2026-10-10: 135 packages removed by scripts/purge-gnome.sh; greetd's
      display-manager alias had to be re-enabled by hand, now automatic)
- [x] `scripts/test.sh` green; manual checklist (2026-10-10): Wi-Fi, sound,
      Bluetooth pairing (phone, via ultimit-agents), suspend/resume, lock,
      screenshots, USB phone over MTP (DATA + go-mtpfs), portal file picker.
      Printing untested (no printer; CUPS + system-config-printer installed)
- [x] Then: gaming (Steam, Proton, NVIDIA offload, VRR, direct scanout) (done 2026-10-13)
  - [x] Wine games: i386 + wine32 + 32-bit Vulkan, pinned DXVK (scripts/get-dxvk.sh),
        X11 placement/fullscreen fixes; WoW 3.3.5a via NekoCoreLauncher runs well (2026-10-11)
  - [x] GAMES app lists non-Steam games (desktop entries, manual .exe/commands) with per-game launch options
  - [x] Steam (deb), Proton (umu + version picker in GAMES), MangoHud, gamescope
- [x] Bug: X11 windows that commit their only frame before Xwayland's
      surface pairing never mapped (~1 in 25 launches under load). Fixed in
      xwayland.c (map on associate when a buffer is already there).

## Phase 5: everyday completeness (from docs/audit-2026-10-11.md)
Done:
- [x] Tray flyouts: network, sound, Bluetooth, battery, clock/notifications
- [x] Video/music player + codecs + video thumbnails (mpv, ffmpeg, ffmpegthumbnailer); MIME defaults (mailto -> NekoMail still open)
- [x] Firewall on by default (ufw deny incoming) and the FIREWALL app
- [x] Window snapping (Super+Left/Right/Up/Down, drag to edges) and Alt+Tab overlay
- [x] Shortcuts: Super+D/E/R/Tab, one key table (keys.c, `ultimitctl keys`, docs/keybindings.md)
- [x] Archives in DATA (extract here/to, browse inside, compress zip/7z/tar.gz, passwords, zip-slip safe)
- [x] Window capture for sharing (ext-image-copy-capture)

### 5a: gaps (daily use on the laptop)
- [x] Low-battery warning and critical action (warnings at 20/10/5%; UPower's own action at 2%)
- [x] Power menu: log out, hibernate (when the system can), confirmation
  - [ ] Make hibernate possible here (resume setup, NVIDIA video memory preservation): logind says no today
- [x] Updates page in Settings (apt, flatpak, fwupd; reboot-needed; apply via pkexec)
- [x] App store over Flathub (STORE: install/remove; updates in Settings); "not installed" hints lead there
- [x] Crash recovery: a compositor crash leaves a trace and a way back; shell fallback without a git checkout
- [x] Session hygiene: stale oo7-daemon processes and logind sessions after restarts
  - [ ] Keyring unlock with autologin (no password at login, so oo7 asks once)

### 5b: what Windows users expect, part 1 (the desktop)
- [ ] ~~Workspaces~~ (dropped, 2026-10-13: not wanted)
- [x] Clipboard history (Super+V); emoji picker dropped (2026-10-13)
- [x] Cheat sheet overlay (Super+/)
  - [ ] Configurable bindings (still edited in keys.c)
- [x] Wallpaper picker (images alongside the shard wallpaper)
- [x] Screen recording (in ultimit-screenshot), and camera/mic/screencast privacy indicators
- [ ] ~~Night light~~ (skipped, 2026-10-13)
- [x] Compositor honours the shell's motion setting (open animation, focus sweep)

### 5c: what Windows users expect, part 2 (the system)
- [ ] ~~Keyboard layouts and input methods~~ (not now, 2026-10-13: left for someone else)
- [ ] ~~Accessibility~~ (not now, 2026-10-13)
- [x] Users page (create user, change password, administrator, delete)
  - [x] New accounts start Ultimit once it is installed with scripts/install.sh
- [x] Multiple displays: arrangement canvas, main display, Duplicate, rotation, scale 100-300 %, highest refresh by default, settings follow the monitor, windows follow their screen on hotplug
- [x] VPN: WireGuard / OpenVPN import, sign-in with keyring, bar marker (PIA app or OpenVPN files)
  - [ ] Hotspot, captive portal
- [x] Consistent window titles (GAMES, SETTINGS; rail/Alt+Tab match on them)

## Phase 6: installable (ISO blockers, see the audit)
- [x] Install compositor, shell, session, deps (wlroots/scenefx/qs/oo7) system-wide under /opt/ultimit; no $HOME/.local/ultimit-deps or checkout paths (scripts/install.sh, docs/install.md; tested 2026-10-13 on a fresh Ubuntu 26.04 VM: install, apps, login as a new user)
- [x] Session runs the installed shell (fallback is the last good copy, no git needed)
  - [ ] Themes, icons and cursors still generated per user at each login (works, a little slow)
- [x] greetd config for any user, no autologin (keyring unlocks with the typed password)
  - [ ] NekoMail packaged (MAILER falls back to STORE until then)
- [x] distro/ manifest: packages-build.txt, packages-core.txt, packages-install.txt; fonts vendored
  - [ ] snap removal list complete (cups, snap-store, firmware-updater...)
