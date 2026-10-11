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
- [ ] Then: gaming (Steam, Proton, NVIDIA offload, VRR, direct scanout)
- [x] Bug: X11 windows that commit their only frame before Xwayland's
      surface pairing never mapped (~1 in 25 launches under load). Fixed in
      xwayland.c (map on associate when a buffer is already there).

## Phase 5: everyday completeness (from docs/audit-2026-10-11.md)
Windows-parity gaps found by the read-only audit, in priority order.
- [ ] Tray flyouts: network, sound, Bluetooth, battery, clock/notifications (in progress)
- [ ] Video/music player + codecs + video thumbnails (mpv, ffmpeg, ffmpegthumbnailer); MIME defaults incl. mailto -> NekoMail
- [ ] Firewall on by default (ufw deny incoming)
- [ ] Low-battery warning and critical action
- [ ] Updates page in Settings (apt, flatpak, fwupd; reboot-needed; apply via pkexec)
- [ ] App store over Flathub (install/remove/update flatpaks)
- [ ] Window snapping (Super+Left/Right/Up), workspaces, Alt+Tab overlay
- [ ] Shortcuts: Super+D/E/R/V/Space, configurable bindings, cheat sheet
- [ ] Wallpaper picker (images alongside the shard wallpaper)
- [ ] Archives in DATA (extract/compress; 7z/zip/tar)
- [ ] Users page (create user, change password)
- [ ] Privacy indicators (camera/mic/screencast), screen recording, window capture for sharing
- [ ] Clipboard history (Super+V) and emoji picker
- [ ] Input methods (text-input-v3 / input-method-v2 in the compositor; IBus/Fcitx) and layout switching
- [ ] Network extras: VPN/WireGuard import, hotspot, captive portal
- [ ] Night light, accessibility toggles, logout/hibernate in the power menu
- [ ] Session hygiene: stale oo7-daemon processes and logind sessions after restarts; keyring unlock with autologin

## Phase 6: installable (ISO blockers, see the audit)
- [ ] Install compositor, shell, session, deps (wlroots/scenefx/qs/oo7) system-wide under /opt/ultimit; no $HOME/.local/ultimit-deps or checkout paths
- [ ] Session runs installed shell (no git-archive fallback); theme/icon/cursor install at package time, not per login
- [ ] greetd config and autologin for the installing user, not "mino"; NekoMail packaged
- [ ] distro/ manifest complete (ufw, unattended-upgrades, VPN plugins, fonts, players); snap removal list complete
