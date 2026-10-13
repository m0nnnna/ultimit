# The Ultimit ISO

A USB stick that installs Ubuntu 26.04 with Ultimit, never GNOME. It is Ubuntu's own server ISO,
patched: the boot menu's first entry, **Install Ultimit**, runs Ubuntu's installer with an
autoinstall that asks only for keyboard, network, disk and user, then:

1. installs the minimal Ubuntu base, the NVIDIA driver when the PC needs it, and media codecs;
2. unpacks Ultimit **precompiled** (no building) into `/opt/ultimit` and runs
   `scripts/system-install.sh` on the new system: desktop packages from the Ubuntu archive, the
   Ultimit login screen, fonts, helpers, and NetworkManager in charge of networking;
3. reboots into the Ultimit login screen. On that first boot `ultimit-firstboot.service`
   installs the apps in the background (Steam, Wine, Flatpaks, DXVK; log in
   `/var/log/ultimit-firstboot.log`).

The installer needs internet (packages come from Ubuntu's archive).

## Building one

On a clean Ubuntu 26.04 machine or VM (not a development machine):

```bash
scripts/install.sh --no-apps --keep-login-screen   # builds /opt/ultimit from this checkout
scripts/build-release.sh                           # -> ultimit-<version>-amd64.tar.gz
```

The release also lists the Ubuntu packages its binaries link to (`distro/packages-runtime.txt`,
made by `scripts/release-deps.sh`), so the target machine gets those libraries without the build
packages.

Then, anywhere with `xorriso` (`sudo apt install xorriso`) and Ubuntu's server ISO from
releases.ubuntu.com (check it against their SHA256SUMS):

```bash
scripts/build-iso.sh ubuntu-26.04.1-live-server-amd64.iso ultimit-<version>-amd64.tar.gz
```

That writes `ultimit-<version>-amd64.iso` (and a `.sha256`). Put it on a USB stick with any
image writer (`sudo dd if=ultimit-….iso of=/dev/sdX bs=4M status=progress oflag=sync`, or
balenaEtcher / Ventoy).

`--unattended USER PASSWORD` builds a test ISO that asks nothing and **wipes the first disk**:
only for virtual machines.
