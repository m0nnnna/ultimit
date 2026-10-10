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
- [ ] Text editor
- [ ] Calculator
- [x] Terminal: foot, themed
- [ ] Non-GNOME picks for PDF and images (to be replaced later)

## Phase 4: the proof
- [ ] Purge the packages above, reboot, log in through the Ultimit greeter
- [ ] `scripts/test.sh` green; manual checklist (Wi-Fi, sound, Bluetooth,
      suspend/resume, lock, screenshots, USB drive, printing, file picker
      in Firefox)
- [ ] Then: gaming (Steam, Proton, NVIDIA offload, VRR, direct scanout)
