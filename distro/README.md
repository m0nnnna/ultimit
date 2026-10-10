# distro/: what an Ultimit install contains

The future ISO (and a fresh install script) is built from these lists, on
top of Ubuntu 26.04 LTS. Keep them in step with what this dev machine runs.

- `packages-install.txt`: apt packages Ultimit needs or ships
- `packages-remove.txt`: apt packages removed (GNOME; see scripts/purge-gnome.sh
  for the autoremove protection)
- `flatpaks.txt`: Flathub apps installed system-wide
- `snaps-remove.txt`: snaps Ubuntu preinstalls that Ultimit removes

Setup scripts used by both: scripts/purge-gnome.sh, scripts/setup-browser.sh,
scripts/install-system.sh, scripts/switch-dm.sh greetd.
