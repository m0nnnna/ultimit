#!/bin/bash
# Install Ultimit on Ubuntu 26.04: everything goes to /opt/ultimit (system-wide, every user can
# log into it), the Ultimit login screen (greetd) replaces the current one, and the apps from
# distro/ are installed. Run it from a clone of the repository, as your normal user (it asks
# for your password through sudo when it needs it):
#
#   git clone https://github.com/m0nnnna/ultimit && cd ultimit && scripts/install.sh
#
# Options:
#   --yes                 don't ask before starting
#   --no-apps             only the desktop itself (skip distro/packages-install.txt, Flatpaks, DXVK)
#   --keep-login-screen   install, but leave the current login screen (GDM) in charge
#   --jobs N              parallel build jobs (default: from CPU cores and memory)
#
# Re-running it updates an existing install (git pull first). Takes 20-40 minutes the first
# time: wlroots, SceneFX, Quickshell and oo7 are built on this machine. A log is kept in
# ~/.local/state/ultimit/install-*.log. To go back: scripts/uninstall.sh.
set -euo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
PREFIX=/opt/ultimit
WORK=${ULTIMIT_BUILD_DIR:-$HOME/.cache/ultimit-build}
LIBDIR=lib/x86_64-linux-gnu
SKIP_PACKAGES=${ULTIMIT_SKIP_PACKAGES:-}   # space separated, e.g. for test machines

# Pinned versions (the ones Ultimit is developed against)
WLROOTS_URL=https://gitlab.freedesktop.org/wlroots/wlroots.git WLROOTS_REF=0.19.2
SCENEFX_URL=https://github.com/wlrfx/scenefx SCENEFX_REF=0.4.1
QUICKSHELL_URL=https://github.com/quickshell-mirror/quickshell QUICKSHELL_REF=v0.3.2
OO7_URL=https://github.com/linux-credentials/oo7 OO7_REF=0.7.0.beta
RUST_TOOLCHAIN=1.99.0

YES=false APPS=true SWITCH_DM=true JOBS=""
while [ $# -gt 0 ]; do
	case "$1" in
	--yes) YES=true ;;
	--no-apps) APPS=false ;;
	--keep-login-screen) SWITCH_DM=false ;;
	--jobs) JOBS=$2; shift ;;
	-h | --help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
	esac
	shift
done

LOG_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/ultimit
mkdir -p "$LOG_DIR" "$WORK"
LOG="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

STEP=0
step() { STEP=$((STEP + 1)); printf '\n\033[1;36m== %d. %s\033[0m\n' "$STEP" "$*"; }
note() { printf '   %s\n' "$*"; }
warn() { printf '\033[1;33m   ! %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mInstall stopped: %s\033[0m\nLog: %s\n' "$*" "$LOG"; exit 1; }
trap 'die "a command failed (line $LINENO). Fix what the log shows and run scripts/install.sh again; finished steps are skipped."' ERR
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | grep -vxF -f <(printf '%s\n' $SKIP_PACKAGES ""); }

# ------------------------------------------------------------------------------------ preflight
step "Checking this computer"
[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root (it uses sudo when needed)"
. /etc/os-release
[ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 26.04 ] || die "Ultimit needs Ubuntu 26.04 (this is ${PRETTY_NAME:-unknown})"
[ "$(uname -m)" = x86_64 ] || die "Ultimit needs a 64-bit PC (x86_64)"
free_gb() { df -Pk "$1" | awk 'NR==2 {print int($4 / 1048576)}'; }
[ "$(free_gb "$WORK")" -ge 12 ] || die "need 12 GB free for building in $WORK"
[ "$(free_gb /)" -ge 8 ] || die "need 8 GB free on / for the install and its packages"
curl -fsS --max-time 15 -o /dev/null https://github.com || die "no internet connection (github.com unreachable)"
mem_gb=$(awk '/MemTotal/ {print int($2 / 1048576)}' /proc/meminfo)
cores=$(nproc)
if [ -z "$JOBS" ]; then   # Quickshell needs ~1.5 GB per compile job
	JOBS=$(( mem_gb * 2 / 3 )); [ "$JOBS" -lt 1 ] && JOBS=1; [ "$JOBS" -gt "$cores" ] && JOBS=$cores
fi
note "Ubuntu $VERSION_ID, $cores cores, ${mem_gb} GB memory -> $JOBS build jobs"
note "Installing to $PREFIX; building in $WORK; log: $LOG"
if lspci 2>/dev/null | grep -qi 'vga.*nvidia\|3d.*nvidia'; then
	if [ -d /proc/driver/nvidia ]; then
		note "NVIDIA driver $(sed -n 's/.*Kernel Module *\([0-9.]*\).*/\1/p' /proc/driver/nvidia/version 2>/dev/null) is loaded"
	else
		warn "This PC has an NVIDIA card but the NVIDIA driver isn't running (nouveau or none)."
		warn "Ultimit works best with it: sudo ubuntu-drivers install, reboot, then run this again."
		$YES || { read -r -p "   Continue anyway? [y/N] " a; [ "$a" = y ] || [ "$a" = Y ] || exit 1; }
	fi
fi
if ! $YES; then
	echo
	echo "This will build and install Ultimit$($APPS && echo " and its apps")$($SWITCH_DM && echo ", and make the Ultimit login screen the one this PC starts with")."
	read -r -p "Go ahead? [Y/n] " a
	case "$a" in n | N) exit 1 ;; esac
fi
sudo true || die "sudo is needed"
# keep sudo alive for the long builds
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

# ------------------------------------------------------------------------------------ packages
step "Installing the packages Ultimit needs (apt)"
sudo apt-get update -q
mapfile -t pkgs < <(list "$ROOT/distro/packages-build.txt"; list "$ROOT/distro/packages-core.txt")
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${pkgs[@]}"
xdg-user-dirs-update 2>/dev/null || true

# ------------------------------------------------------------------------------------ builds
export PKG_CONFIG_PATH="$PREFIX/$LIBDIR/pkgconfig"
src() { # name url ref -> $WORK/src/name at that ref
	local d="$WORK/src/$1"
	if [ ! -d "$d/.git" ] || [ "$(git -C "$d" describe --tags --always 2>/dev/null)" != "$3" ]; then
		rm -rf "$d"
		git -c advice.detachedHead=false clone -q --depth 1 -b "$3" "$2" "$d"
	fi
	echo "$d"
}
built() { [ "$(cat "$PREFIX/.built-$1" 2>/dev/null)" = "$2" ]; }   # name version
setup() { # meson setup that also works on a fresh build folder: setup BUILD SRC ARGS...
	local b=$1; shift
	if [ -f "$b/build.ninja" ]; then meson setup --wipe "$b" "$@"; else rm -rf "$b"; meson setup "$b" "$@"; fi
}
mark() { echo "$2" | sudo tee "$PREFIX/.built-$1" >/dev/null; }
sudo mkdir -p "$PREFIX"

step "Building wlroots $WLROOTS_REF"
if built wlroots "$WLROOTS_REF"; then note "already installed"; else
	d=$(src wlroots "$WLROOTS_URL" "$WLROOTS_REF")
	setup "$d/build" "$d" --prefix="$PREFIX" --libdir="$LIBDIR" --buildtype=release \
		-Dexamples=false -Dwerror=false -Dxwayland=enabled -Dbackends=drm,libinput,x11 -Drenderers=gles2,vulkan
	ninja -C "$d/build" -j "$JOBS"
	sudo ninja -C "$d/build" install >/dev/null
	mark wlroots "$WLROOTS_REF"
fi

step "Building SceneFX $SCENEFX_REF"
if built scenefx "$SCENEFX_REF"; then note "already installed"; else
	d=$(src scenefx "$SCENEFX_URL" "$SCENEFX_REF")
	setup "$d/build" "$d" --prefix="$PREFIX" --libdir="$LIBDIR" --buildtype=release \
		-Dexamples=false -Dc_link_args="-Wl,-rpath,$PREFIX/$LIBDIR"
	ninja -C "$d/build" -j "$JOBS"
	sudo ninja -C "$d/build" install >/dev/null
	mark scenefx "$SCENEFX_REF"
fi

step "Building Quickshell $QUICKSHELL_REF (the longest step)"
if built quickshell "$QUICKSHELL_REF"; then note "already installed"; else
	d=$(src quickshell "$QUICKSHELL_URL" "$QUICKSHELL_REF")
	cmake -GNinja -S "$d" -B "$d/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCRASH_HANDLER=OFF -DDISTRIBUTOR="Ultimit" >/dev/null
	cmake --build "$d/build" -j "$JOBS"
	sudo cmake --install "$d/build" >/dev/null
	mark quickshell "$QUICKSHELL_REF"
fi

step "Building oo7 $OO7_REF (keyring)"
export CARGO_HOME="$WORK/cargo" RUSTUP_HOME="$WORK/rustup"
if built oo7 "$OO7_REF"; then note "already installed"; else
	if [ ! -x "$CARGO_HOME/bin/cargo" ]; then
		note "getting Rust $RUST_TOOLCHAIN (kept in $WORK; your own Rust setup is not touched)"
		curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | \
			sh -s -- -y -q --no-modify-path --profile minimal --default-toolchain "$RUST_TOOLCHAIN"
	fi
	d=$(src oo7 "$OO7_URL" "$OO7_REF")
	( cd "$d" && OO7_DAEMON_LOGIN_PATH="$PREFIX/libexec/oo7-daemon-login" \
		"$CARGO_HOME/bin/cargo" build --release -q -j "$JOBS" -p oo7-daemon -p oo7-pam -p oo7-cli )
	sudo install -D -m755 "$d/target/release/oo7-daemon" "$d/target/release/oo7-cli" -t "$PREFIX/bin/"
	sudo install -D -m755 "$d/target/release/oo7-daemon-login" -t "$PREFIX/libexec/"
	sudo install -D -m644 "$d/target/release/libpam_oo7.so" /usr/lib/x86_64-linux-gnu/security/pam_oo7.so
	mark oo7 "$OO7_REF"
fi

step "Building the Ultimit compositor"
rev=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo unknown)
setup "$WORK/compositor" "$ROOT/compositor" --buildtype=release >/dev/null
ninja -C "$WORK/compositor" -j "$JOBS"
sudo install -D -m755 "$WORK/compositor/ultimit" "$PREFIX/bin/ultimit"
ldd "$PREFIX/bin/ultimit" | grep -q "not found" && die "the compositor can't find a library: $(ldd "$PREFIX/bin/ultimit" | grep 'not found')"

# ------------------------------------------------------------------------------------ the desktop
step "Installing the shell, session and login screen to $PREFIX"
stage="$WORK/stage"
rm -rf "$stage" && mkdir -p "$stage"
tar -C "$ROOT" --exclude=__pycache__ --exclude=test-results --exclude='*.pyc' \
	-cf - shell session greeter distro assets scripts docs/keybindings.md LICENSE | tar -C "$stage" -xf -
echo "$rev" >"$stage/VERSION"
sudo sh -e -c '
	cd "$1"
	for d in shell session greeter distro assets scripts docs; do
		rm -rf "$2/$d.new"; cp -a "$d" "$2/$d.new"
		rm -rf "$2/$d.old"; [ -e "$2/$d" ] && mv "$2/$d" "$2/$d.old"
		mv "$2/$d.new" "$2/$d"; rm -rf "$2/$d.old"
	done
	cp VERSION LICENSE "$2/"
	chown -R root:root "$2"; chmod -R go-w,a+rX "$2"
' sh "$stage" "$PREFIX"
note "Ultimit $rev"

step "Setting up the system (fonts, session, keyring unlock, helpers, commands)"
sudo sh -e -c '
	P=$1
	# Fonts the look uses (SIL Open Font License, see assets/fonts)
	install -D -m644 -t /usr/share/fonts/truetype/ultimit "$P"/assets/fonts/*.ttf "$P"/assets/fonts/OFL-*.txt
	fc-cache -f /usr/share/fonts/truetype/ultimit >/dev/null
	# The session the login screen offers
	mkdir -p /usr/share/wayland-sessions /usr/share/applications /etc/X11
	sed "s|@SESSION@|$P/session/ultimit-session|g" "$P/session/ultimit.desktop" >/usr/share/wayland-sessions/ultimit.desktop
	# Root helpers and polkit policies (FIREWALL, Updates, Users) and the virtual camera
	cd "$P/distro/system"
	find . -name __pycache__ -prune -o -type f -print | while read -r f; do
		mode=644; [ -x "$f" ] && mode=755
		install -D -m $mode "$f" "/$f"
	done
	# Ultimit commands on everyone'"'"'s PATH (other apps open folders with ultimit-data, ...)
	for b in "$P"/shell/bin/*; do ln -sfn "$b" "/usr/local/bin/$(basename "$b")"; done
	# Ultimit apps in every app menu
	for d in "$P"/shell/apps/*/ultimit-*.desktop; do
		sed "s|^Exec=ultimit-|Exec=$P/shell/bin/ultimit-|" "$d" >"/usr/share/applications/$(basename "$d")"
	done
	# Unlock the keyring (oo7) with the password typed at the login screen
	if ! grep -q pam_oo7 /etc/pam.d/greetd 2>/dev/null; then
		printf "\n# Ultimit: unlock the oo7 keyring with the login password.\nauth     optional pam_oo7.so\nsession  optional pam_oo7.so auto_start\n" >>/etc/pam.d/greetd
	fi
	# Where the login screen remembers the last user and session
	GU=$(getent passwd _greetd >/dev/null && echo _greetd || echo greeter)
	mkdir -p /var/lib/ultimit-greeter && chown "$GU" /var/lib/ultimit-greeter
' sh "$PREFIX"

if $SWITCH_DM; then
	step "Making the Ultimit login screen the one this PC starts with"
	sudo sh -e -c '
		P=$1
		GU=$(getent passwd _greetd >/dev/null && echo _greetd || echo greeter)
		[ -f /etc/greetd/config.toml ] && cp -n /etc/greetd/config.toml /etc/greetd/config.toml.before-ultimit
		cat >/etc/greetd/config.toml <<CONF
# Written by Ultimit scripts/install.sh
[terminal]
# Ubuntu'"'"'s greetd.service owns tty7 (Conflicts=getty@tty7).
vt = 7

[default_session]
command = "$P/session/ultimit-greeter-session"
user = "$GU"
CONF
		systemctl disable gdm3 2>/dev/null || true
		systemctl disable sddm lightdm 2>/dev/null || true
		systemctl enable --force greetd
		echo /usr/sbin/greetd >/etc/X11/default-display-manager
		systemctl set-default graphical.target
	' sh "$PREFIX"
	[ "$(readlink -f /etc/systemd/system/display-manager.service)" = "$(readlink -f /usr/lib/systemd/system/greetd.service)" ] \
		|| die "greetd didn't become the login screen; nothing else changed on reboot"
else
	note "keeping the current login screen; Ultimit is in its session list"
fi

# ------------------------------------------------------------------------------------ apps
if $APPS; then
	step "Installing the apps (distro/packages-install.txt, Flatpaks, DXVK)"
	ULTIMIT_SKIP_PACKAGES="$SKIP_PACKAGES" "$ROOT/scripts/install-apps.sh" --yes
fi

# ------------------------------------------------------------------------------------ check
step "Checking the install"
fail=0
for f in bin/ultimit bin/qs bin/oo7-daemon libexec/oo7-daemon-login session/ultimit-session session/ultimit-greeter-session greeter/shell.qml shell/shell.qml; do
	[ -e "$PREFIX/$f" ] || { warn "missing $PREFIX/$f"; fail=1; }
done
for b in ultimit qs; do
	ldd "$PREFIX/bin/$b" | grep -q "not found" && { warn "$b is missing a library"; fail=1; }
done
"$PREFIX/bin/qs" --version >/dev/null 2>&1 || { warn "Quickshell doesn't start"; fail=1; }
fc-list | grep -q Michroma || { warn "fonts not found by fontconfig"; fail=1; }
[ -f /usr/share/wayland-sessions/ultimit.desktop ] || { warn "session file missing"; fail=1; }
[ "$fail" = 0 ] || die "the install is incomplete (see the warnings above)"

cat <<DONE

$(printf '\033[1;32m')Ultimit $rev is installed.$(printf '\033[0m')
$($SWITCH_DM && echo "Reboot and log in at the Ultimit login screen." || echo "Log out and pick Ultimit in your login screen's session list.")
Every user on this PC can use it. To update later: git pull && scripts/install.sh
To remove GNOME once you're happy:  scripts/purge-gnome.sh  (dry run first)
Log: $LOG
DONE
