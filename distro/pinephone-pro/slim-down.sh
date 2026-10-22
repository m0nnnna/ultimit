#!/bin/sh
# Drop the desktop-PC packages and services a phone has no use for: less RAM, a faster
# boot, no apt runs eating the CPU after boot, ~1.5 GB of disk back.
# Run as root on the phone from this directory: sudo sh slim-down.sh [--dev]
#   --dev  also remove the build toolchain and -dev headers (only once you build on the PC)
# Undo: apt-get install the packages below, `systemctl enable` the units it disables,
# `systemctl --global unmask` the gvfs monitors, `flatpak install flathub com.github.wwmm.easyeffects`.
set -eu
export DEBIAN_FRONTEND=noninteractive

# feedbackd (the OSK's buzz and click) is only a dependency here, so autoremove would take it
apt-mark manual feedbackd feedbackd-device-themes sound-theme-freedesktop >/dev/null

# firmware for hardware the phone doesn't have (Wi-Fi/BT is Broadcom; Realtek/MediaTek stay
# for USB dongles), firmware updates, the printer applet, unattended upgrades
apt-get remove -yq --purge fwupd system-config-printer system-config-printer-common \
  unattended-upgrades firmware-sof-signed \
  linux-firmware-amd-graphics linux-firmware-amd-misc linux-firmware-intel-graphics \
  linux-firmware-intel-misc linux-firmware-intel-wireless linux-firmware-marvell-wireless \
  linux-firmware-nvidia-graphics linux-firmware-qualcomm-graphics \
  linux-firmware-qualcomm-misc linux-firmware-qualcomm-wireless || true
pkill -f system-config-printer/applet.py || true

if [ "${1:-}" = --dev ]; then
  # shellcheck disable=SC2046
  apt-get remove -yq $(apt-mark showmanual | grep -E -- '-dev$') clang || true
fi

# rsyslog and ubuntu-pro-client are part of ubuntu-minimal: switch them off rather than remove
# (the journal keeps the logs). apt runs only when asked; no boot wait for the network.
systemctl disable --now rsyslog.service ubuntu-advantage.service ua-reboot-cmds.service \
  apt-daily.timer apt-daily-upgrade.timer NetworkManager-wait-online.service 2>/dev/null || true

# gvfs monitors for iPhones, cameras over PTP and online accounts
systemctl --global mask gvfs-afc-volume-monitor.service gvfs-gphoto2-volume-monitor.service \
  gvfs-goa-volume-monitor.service
if [ -n "${SUDO_USER:-}" ]; then
  systemctl --user -M "$SUDO_USER@" stop gvfs-afc-volume-monitor.service \
    gvfs-gphoto2-volume-monitor.service gvfs-goa-volume-monitor.service 2>/dev/null || true
fi

# EasyEffects (the desktop's RNNoise mic cleaner, ~160 MB): the session only sets it up when
# the flatpak is installed, so it stays gone
if [ -n "${SUDO_USER:-}" ]; then
  pkill -u "$SUDO_USER" -f 'easyeffects -w' || true
  rm -f "$(getent passwd "$SUDO_USER" | cut -d: -f6)/.config/autostart/easyeffects-service.desktop"
fi
flatpak uninstall -y --noninteractive com.github.wwmm.easyeffects 2>/dev/null || true

apt-get clean
echo "done. Left for you to look at (not removed):"
apt-get -s autoremove 2>/dev/null | awk '/^Remv/{printf "%s ", $2} END{print ""}'
