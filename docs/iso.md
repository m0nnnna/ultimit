# The Ultimit ISO

A USB stick that installs Ubuntu 26.04 with Ultimit, never GNOME. It is Ubuntu's own server ISO,
patched: the boot menu's first entry, **Install Ultimit**, starts the **Ultimit installer
screen**, a few plain pages in Ultimit's look:

1. **Welcome**, with the note about keeping Windows (below).
2. **Internet**, only when there is no cable: pick the Wi-Fi network, type its password. The new
   system remembers it.
3. **Drive**: every drive with its size and what's on it ("Windows is on this drive · 149 GB
   free space"). The USB stick can't be picked. For a drive with Windows and enough free space
   next to it, **Use the free space, keep Windows** is chosen already; **Erase the drive** is
   always a separate choice, and the last page makes you tick "I understand: everything on this
   drive will be erased" before it does.
4. **About you**: your name; the user name and computer name fill themselves in; the password
   twice.
5. **Ready to install**: what will happen to which drive, in words, then **Install Ultimit**.

Then Ubuntu's own installer (subiquity) does the work, no questions asked, while the screen shows
its progress:

1. installs the minimal Ubuntu base, the NVIDIA driver when the PC needs it, and media codecs;
2. unpacks Ultimit **precompiled** (no building) into `/opt/ultimit` and runs
   `scripts/system-install.sh` on the new system: desktop packages from the Ubuntu archive, the
   Ultimit login screen, fonts, helpers, and NetworkManager in charge of networking;
3. says "Ultimit is installed" and restarts when you press **Restart** (after taking the USB
   stick out). On the first boot `ultimit-firstboot.service` installs the apps in the background
   (Wine, Flatpaks, DXVK; log in `/var/log/ultimit-firstboot.log`). Steam installs from GAMES,
   which asks you to accept Valve's licence.

The installer needs internet (packages come from Ubuntu's archive). If the Ultimit screen can't
start, or you press **Use Ubuntu's text installer**, Ubuntu's own text questions take over.

## Keeping Windows (dual boot): shrink Windows first

> **Make room in Windows before you start the installer.** Ultimit installs into *free space*
> next to Windows; it never shrinks or moves Windows itself (that is the one step where an
> installer can lose your files, so it's done with Windows' own tool):
>
> 1. In Windows, right-click Start › **Disk Management**.
> 2. Right-click the **(C:)** partition › **Shrink Volume…**, and shrink it by **50 GB or more**
>    (51200 MB; 25 GB is the minimum). Leave the new space **Unallocated**: don't make a
>    partition in it.
> 3. Turn off **Fast Startup** (Control Panel › Power Options › Choose what the power buttons do).
> 4. If **BitLocker** (Device Encryption) is on, have your recovery key ready
>    (aka.ms/myrecoverykey): Windows may ask for it once after Ultimit is installed.
>
> Then boot the Ultimit USB stick. The installer offers **Use the free space, keep Windows**.
> Afterwards, the PC's boot menu lets you choose Windows or Ultimit each time it starts.

Putting Ultimit on a **second drive** is the simplest of all: pick that drive and
**Erase the drive** (only that drive is touched).

## How it works

- `greeter/installer/` is the screen (Quickshell, the login screen's look) and its two helpers:
  `probe.py` (drives, network, progress; reads only) and `answers.py` (writes the answers as
  `/autoinstall.yaml`; the password only as a hash).
- The ISO's `autoinstall.yaml` has one early command, `greeter/installer/start.sh`: it unpacks
  what the screen needs into the live system (`ultimit/installer-layer.tar.zst`, 53 MB: Mesa,
  Qt, seatd...; made by `scripts/build-installer-layer.sh`) and Ultimit itself, runs the
  compositor with the screen on VT 7, and returns once the answers are written. Subiquity reads
  `/autoinstall.yaml` again after its early commands, so the install then runs without
  questions. "Keep Windows" is subiquity's `use_gap` layout: the largest free gap, nothing else
  touched.
- Logs: `/var/log/ultimit-installer.log`, `/run/ultimit-installer/ui.log`, and subiquity's in
  `/var/log/installer/`. Ctrl+Alt+F1 shows subiquity's own screen; Ctrl+Alt+F7 goes back.
- Try the screen without installing anything (in the devbox or any Ultimit session):
  `ULTIMIT_INSTALLER_DRY=1 PROBE_FAKE_DIR=$PWD/greeter/installer/fixtures/windows-gap qs -p greeter/installer.qml`

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

`--text` leaves the Ultimit screen out (Ubuntu's text questions). `--unattended USER PASSWORD`
builds a test ISO that asks nothing and **wipes the first disk**:
only for virtual machines.
