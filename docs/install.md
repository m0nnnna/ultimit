# Installing Ultimit on another computer

Ultimit installs on top of **Ubuntu 26.04 LTS** (64-bit). Everything goes to `/opt/ultimit` and
works for every user on the computer. The Ultimit login screen replaces Ubuntu's.

## Before you start

- A fresh or existing **Ubuntu 26.04** install. The normal desktop install is fine; GNOME stays as a
  fallback until you remove it.
- **NVIDIA card:** install the NVIDIA driver first. Run `sudo ubuntu-drivers install`, then
  reboot. The installer warns you if the driver isn't running.
- Internet, about **20 GB free** and **30–60 minutes**. wlroots, SceneFX, Quickshell and oo7 are
  built on the machine.
- An account that can use `sudo`. The installer asks for your password once and keeps it for the
  whole run.

## Install

The repository is private, so the new computer needs your GitHub login to get it:

```bash
sudo apt install -y git gh
gh auth login
gh repo clone m0nnnna/ultimit
cd ultimit
scripts/install.sh
```

Without GitHub on that machine, copy the `ultimit` folder over instead (USB stick, network share).
The installer runs from any copy; keep the hidden `.git` folder so updates work.

It asks once before starting, then runs on its own. Steam's licence is the one exception: you
accept it when the apps are installed near the end. When it says **Ultimit … is installed**,
reboot. The Ultimit login screen comes up; pick your account and type your password.

Options:

| | |
|---|---|
| `--no-apps` | only the desktop; skip Steam, Wine, Flatpaks (Chromium, OBS, EasyEffects, ProtonPlus), DXVK… |
| `--keep-login-screen` | leave GDM as the login screen; Ultimit is in its session list (gear icon) |
| `--yes` | don't ask before starting |
| `--jobs N` | build jobs (default comes from cores and memory) |

A log of every run is kept in `~/.local/state/ultimit/install-*.log`.

## Multiple monitors

Settings › Display lets you drag the screens into place and pick the main display. It also sets
resolution, refresh rate, scale, rotation and VRR for each screen, and Extend or Duplicate. Each
monitor's settings follow it to whatever port it's plugged into. New monitors start at their
highest refresh rate.

## Updating

```bash
cd ultimit && git pull && scripts/install.sh
```

Steps that are already done (the library builds) are skipped, so an update takes a few minutes.

## After installing

- **Other people:** add them in Settings › Users. They log in at the Ultimit login screen.
- **Removing GNOME** (optional, once you're happy): `scripts/purge-gnome.sh` shows what would go;
  `scripts/purge-gnome.sh --yes` does it.
- **VPN:** Settings › Network › VPN (WireGuard and OpenVPN files). Private Internet Access's own
  app also works, and its icon shows in the tray.

## If something goes wrong

- **The login screen doesn't come up:** press **Ctrl+Alt+F3**, log in on the text console, and
  run `cd ultimit && scripts/uninstall.sh --yes`, then `sudo reboot`. That gives GDM back. Or,
  just to switch login screens:
  `sudo systemctl disable greetd && sudo systemctl enable gdm3 && sudo reboot`.
- **The desktop crashed:** Ultimit restarts it by itself. Crash reports are in
  `~/.local/state/ultimit/crashes/`; the session log is `~/.local/state/ultimit/session.log`.
- **An install step failed:** the message names the step and the log. Fix the cause (usually a
  network problem) and run `scripts/install.sh` again; finished steps are skipped.

## Removing Ultimit

`scripts/uninstall.sh --yes` removes `/opt/ultimit` and the system pieces, and gives the login
back to GDM. Users' own settings and the installed apps are left alone.
