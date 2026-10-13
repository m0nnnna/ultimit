# Updates

Ultimit updates in two halves:

- **Ubuntu's packages** (the kernel, Mesa, NVIDIA, Qt, everything from the archive) update the
  normal Ubuntu way: security updates install by themselves every day, the rest from
  Settings › Updates › System.
- **Ultimit itself** (`/opt/ultimit`: the compositor, shell, login screen, scripts) comes from
  this repository's [GitHub releases](https://github.com/m0nnnna/ultimit/releases). Settings ›
  Updates › Ultimit shows when a newer release is out and installs it. The new version starts at
  the next login.

## What happens when you press Install

1. The root helper (`/usr/libexec/ultimit/updates-helper ultimit TAG`, through pkexec, so it
   asks for your password) downloads `ultimit-<version>-amd64.tar.gz` and its `.sha256` from the
   release, and checks the download against the checksum.
2. It runs the release's own `scripts/system-install.sh --release`: the new `/opt/ultimit` goes
   in place, the packages its binaries need are installed (`distro/packages-runtime.txt`), and
   the helpers, fonts, session and login screen are refreshed. DXVK carries over.
3. If anything fails, the previous `/opt/ultimit` is put back. The log is
   `/var/log/ultimit-update.log`.

It keeps going if Settings closes or reloads halfway (it is replacing Settings' own files).

Apps (`distro/packages-install.txt`, `flatpaks.txt`, `debs.txt`): an update installs the ones
the new release **added** to those lists, nothing else, so an app you removed stays removed.
Flatpaks update in the Apps section.

The repository it asks is in `/opt/ultimit/distro/update-source` (`m0nnnna/ultimit`). A fork
points it at its own.

## Publishing a release

On a machine with Ultimit built from source (`scripts/install.sh`), with the
[GitHub CLI](https://cli.github.com) logged in (`gh auth login`):

```bash
git tag -a v0.2.0 -m "Ultimit 0.2.0"
scripts/install.sh --no-apps --keep-login-screen     # /opt/ultimit now reports v0.2.0
scripts/publish-release.sh v0.2.0                   # builds, pushes the tag, uploads
```

`publish-release.sh` refuses unless the work tree is clean, the tag is `HEAD`, and `/opt/ultimit`
was installed from that tag, so what goes out is exactly the tagged code. `--notes FILE` uses
your own release notes (Markdown; Settings shows them), otherwise GitHub writes them from the
commits. `--draft` uploads without publishing, so nobody is offered it until you publish it on
GitHub.

Versions only go up: a PC is offered a release when its tag is newer than what it has. A PC
installed from a commit rather than a release (an ISO built from a commit, or `git pull &&
scripts/install.sh`) counts as older than any release. One built from source ahead of the last
release (`v0.2.0-3-gabc1234`) is not offered `v0.2.0` again.

The ISO (`docs/iso.md`) is too big for a GitHub release (2 GB limit); share it some other way.
Its installs then update from the releases.

### Trying a release before publishing it

On a test machine or VM, serve the folder with the tarball and its `.sha256` over HTTP and point
the helper at it (root only):

```bash
sudo UPDATES_RELEASE_BASE=http://192.168.1.10:8000 /usr/libexec/ultimit/updates-helper ultimit v0.2.0
```
