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
   release, and checks the download against the checksum. It also downloads the `.sig` and checks
   it against the release key in `/opt/ultimit/distro/release-signers` (the one the installed
   version shipped), and that the tarball really is that version. An unsigned or badly signed
   release doesn't install, and Settings doesn't offer a release until it is signed.
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

## From a terminal, and edge PCs

`ultimit-update` does the same from a terminal or a script, as your normal user (it asks for
your password through sudo):

```bash
ultimit-update                  # the newest release, like Settings > Updates
ultimit-update --edge           # the newest commit on main, built on this PC
ultimit-update --edge --check   # exit 0 = up to date, 10 = an update is waiting
```

`--edge` is for test and edge PCs that should run the latest code rather than the latest
release. It keeps its own clone of the repository in `~/.cache/ultimit-build/ultimit-src`
(reset to the branch on every update, so don't work in it) and runs that clone's
`scripts/install.sh --no-apps --keep-gnome`. `--branch NAME` follows another branch, `--apps`
also installs the apps in `distro/`, `--force` reinstalls the same commit, `--yes` doesn't ask.
Before installing it copies `/opt/ultimit` to `/opt/ultimit.previous` and puts it back if the
install fails. On a PC installed from a release or the ISO, the first `--edge` update builds
wlroots, SceneFX, Quickshell and oo7 (20-40 minutes, 12 GB free in `~/.cache`); later ones only
rebuild the compositor and copy the rest.

An edge install reports a version like `v0.2.0-5-gabc1234`, so Settings never offers it the
older `v0.2.0` release, only the next one.

## Publishing a release

Push a version tag; GitHub builds and publishes the release:

```bash
git tag -a v0.2.0 -m "Ultimit 0.2.0" && git push origin v0.2.0
```

The **Release** workflow (`.github/workflows/release.yml`) checks out the tag, runs
`scripts/install.sh --no-apps --keep-login-screen` in a clean Ubuntu 26.04 container, packs
`/opt/ultimit` with `scripts/build-release.sh` and uploads the tarball and its `.sha256` to the
release, then signs it (below). It takes about an hour. Release notes come from
`docs/releases/<tag>.md` when it is in the tagged commit, otherwise GitHub writes them from the
commits. To rebuild a tag that's already pushed: Actions › Release › Run workflow, with the tag
(it replaces the release's files and signs them again).

### From a PC instead

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

### Signing

Releases are signed on GitHub: the Release workflow, or publishing one from a PC, starts the
**Sign release** workflow (`.github/workflows/sign-release.yml`). It waits for the owner's approval (the `release-signing`
environment; GitHub sends a mail, or approve it under Actions), checks the tarball against its
`.sha256` and its VERSION against the tag, then signs it with `ssh-keygen -Y sign` and uploads
`ultimit-<version>-amd64.tar.gz.sig`. PCs are offered the release once that `.sig` is there. To
sign a release by hand: Actions › Sign release › Run workflow, with the tag.

The private key is only in the environment's `ULTIMIT_SIGNING_KEY` secret; nothing else can use it
without that approval. `scripts/setup-release-signing.sh` made it (once) and wrote the public half
to `distro/release-signers`. A fork runs that script for its own repository.

Edge updates (`ultimit-update --edge`) build from the git branch, so they aren't covered by
release signing; they trust GitHub's HTTPS like `git clone` does.

The ISO (`docs/iso.md`) is too big for a GitHub release (2 GB limit); share it some other way.
Its installs then update from the releases.

### Trying a release before publishing it

On a test machine or VM, serve the folder with the tarball and its `.sha256` over HTTP and point
the helper at it (root only):

```bash
sudo UPDATES_RELEASE_BASE=http://192.168.1.10:8000 /usr/libexec/ultimit/updates-helper ultimit v0.2.0
```
