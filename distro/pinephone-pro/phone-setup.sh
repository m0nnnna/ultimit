#!/bin/sh
# Phone-only setup on top of a normal Ultimit install on the PinePhone Pro.
# Run as root on the phone from this directory: sudo sh phone-setup.sh
# Everything here is prebuilt packages and config; nothing compiles.
set -eu
cd "$(dirname "$0")"

# rotation sensor, screen transforms, modem, cameras
DEBIAN_FRONTEND=noninteractive apt-get install -yq iio-sensor-proxy wlr-randr \
  eg25-manager modemmanager gnome-snapshot pipewire-libcamera libcamera-tools v4l-utils device-tree-compiler
udevadm trigger -s iio -c add   # iio-sensor-proxy needs the sensors re-tagged once
systemctl enable --now eg25-manager ModemManager

# power key: the compositor blanks the screen; a long press still powers off
install -Dm644 logind-ppp.conf /etc/systemd/logind.conf.d/ultimit-ppp.conf
systemctl kill -s HUP systemd-logind

# audio: pmOS's UCM profile (speaker/earpiece/headphones/mics, voice call),
# matched by the card's driver + long name
cp -r ucm2/PinePhonePro /usr/share/alsa/ucm2/
install -d /usr/share/alsa/ucm2/conf.d/simple-card
ln -sf ../../PinePhonePro/PINE64-PinePhonePro-.conf \
  /usr/share/alsa/ucm2/conf.d/simple-card/PINE64-PinePhonePro.conf

# cameras: Snapshot via libcamera only (the raw ISP nodes aren't cameras)
install -Dm644 wireplumber/50-ppp-libcamera-only.conf \
  /etc/wireplumber/wireplumber.conf.d/50-ppp-libcamera-only.conf

# modem: free uart3 and keep its regulators on (see dtb-modem-fix.sh); reboot after
# (zz-ppp-dtb re-applies it whenever a kernel update copies a fresh DTB)
install -m755 dtb-modem-fix.sh /usr/local/sbin/ppp-dtb-modem-fix
install -m755 zz-ppp-dtb /etc/kernel/postinst.d/zz-ppp-dtb
for d in /boot/dtb-*-ppp; do [ -e "$d" ] && ppp-dtb-modem-fix "$d"; done
echo "done; reboot for the modem fix"
