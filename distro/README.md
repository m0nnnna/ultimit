# distro/: what an Ultimit install contains

The future ISO (and a fresh install script) is built from these lists, on
top of Ubuntu 26.04 LTS. Keep them in step with what this dev machine runs.

- `packages-install.txt`: apt packages Ultimit needs or ships
- `packages-remove.txt`: apt packages removed (GNOME; see scripts/purge-gnome.sh
  for the autoremove protection)
- `flatpaks.txt`: Flathub apps installed system-wide
- `snaps-remove.txt`: snaps Ubuntu preinstalls that Ultimit removes

Gaming: scripts/get-dxvk.sh installs the pinned, checksum-verified DXVK
release (32- and 64-bit; Ubuntu ships only 64-bit) into /opt/ultimit/dxvk on
the ISO, or ~/.local/share/ultimit/dxvk per user.

Install everything in these lists (dry run first, then --yes):
scripts/install-apps.sh. It enables 32-bit packages, installs the apt list,
adds Flathub system-wide and installs the Flatpaks (Ungoogled Chromium,
ProtonPlus), and puts DXVK in /opt/ultimit/dxvk. Steam comes from the
steam-installer package; its client downloads on each user's first launch.
ProtonPlus installs Proton builds (GE-Proton, DW-Proton) into that Steam.

Setup scripts used by both: scripts/purge-gnome.sh, scripts/setup-browser.sh,
scripts/install-system.sh, scripts/switch-dm.sh greetd.
