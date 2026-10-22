#!/bin/sh
# Phone-only setup on top of a normal Ultimit install on the PinePhone Pro.
# Run as root on the phone from this directory: sudo sh phone-setup.sh
# Everything here is prebuilt packages and config; nothing compiles.
set -eu
cd "$(dirname "$0")"

# rotation sensor, screen transforms, modem, cameras; GNOME Web, which fits a phone screen
# (Chromium's window can't get narrower than 500 px; the phone is 360 wide at 2x)
DEBIAN_FRONTEND=noninteractive apt-get install -yq iio-sensor-proxy wlr-randr \
  eg25-manager modemmanager gnome-snapshot pipewire-libcamera libcamera-tools v4l-utils device-tree-compiler \
  epiphany-browser git make
udevadm trigger -s iio -c add   # iio-sensor-proxy needs the sensors re-tagged once
systemctl enable --now eg25-manager ModemManager

# swap to zstd-compressed RAM before the eMMC swapfile (faster, and spares the flash)
DEBIAN_FRONTEND=noninteractive apt-get install -yq systemd-zram-generator
printf '[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd\nswap-priority = 100\n' \
  > /etc/systemd/zram-generator.conf
printf 'vm.swappiness = 100\nvm.page-cluster = 0\n' > /etc/sysctl.d/90-ultimit-zram.conf
systemctl daemon-reload && systemctl start dev-zram0.swap && sysctl -q -p /etc/sysctl.d/90-ultimit-zram.conf

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

# OSK key click: feedbackd's key-pressed sound isn't in the freedesktop theme
install -Dm644 sounds/key-pressed.wav /usr/local/share/sounds/freedesktop/stereo/key-pressed.wav

# modem: free uart3 and keep its regulators on (see dtb-modem-fix.sh); reboot after
# (zz-ppp-dtb re-applies it whenever a kernel update copies a fresh DTB)
install -m755 dtb-modem-fix.sh /usr/local/sbin/ppp-dtb-modem-fix
install -m755 zz-ppp-dtb /etc/kernel/postinst.d/zz-ppp-dtb
for d in /boot/dtb-*-ppp; do [ -e "$d" ] && ppp-dtb-modem-fix "$d"; done
# GNOME Web as the default browser for the user who ran sudo
if [ -n "${SUDO_USER:-}" ]; then
  su - "$SUDO_USER" -c 'xdg-mime default org.gnome.Epiphany.desktop x-scheme-handler/http x-scheme-handler/https text/html' || true
fi
# Firefox (flatpak) for Bitwarden and passkeys, made phone-shaped by postmarketOS's
# mobile-config-firefox (plain CSS/prefs, installed into the flatpak's systemconfig dir);
# our policy (Bitwarden extension, no onboarding, mobile site layouts) is merged over its own
flatpak install -y --noninteractive flathub org.mozilla.firefox com.bitwarden.desktop
mcf=$(mktemp -d)
git clone -q --depth 1 https://gitlab.postmarketos.org/postmarketOS/mobile-config-firefox.git "$mcf"
make -C "$mcf" FLATPAK=1 install >/dev/null
python3 - firefox/policies.json \
  /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/aarch64/stable/policies/policies.json <<'PY'
import json, sys
ours = json.load(open(sys.argv[1]))["policies"]; m = json.load(open(sys.argv[2]))
p = m["policies"]; p.pop("SearchEngines", None)
for k, v in ours.items():
    if k == "Preferences": p.setdefault(k, {}).update(v)
    else: p[k] = v
json.dump(m, open(sys.argv[2], "w"), indent=2)
PY
rm -rf "$mcf"
echo "done; reboot for the modem fix"
