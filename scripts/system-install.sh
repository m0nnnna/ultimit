#!/bin/bash
# The system half of installing Ultimit; runs as root. scripts/install.sh calls it after building
# from source; the Ultimit ISO calls it while installing (on the new system, in a chroot).
#
#   system-install.sh --tree DIR     shell, session, greeter... come from the checkout DIR
#                                    (the libraries and binaries are already in /opt/ultimit)
#   system-install.sh --release F    unpack a release (scripts/build-release.sh) first: no building
#   system-install.sh                /opt/ultimit is complete already (unpacked by the ISO installer)
# Options:
#   --no-apps              skip distro/packages-install.txt, the Flatpaks and DXVK
#   --apps-at-first-boot   install those on the first boot instead (installer chroots: Flatpak
#                          needs a running system)
#   --apps-new             only the apps this release added to the lists since the version it
#                          replaces (updates: an app you removed stays removed)
#   --keep-login-screen    don't make greetd/the Ultimit login screen the display manager
#   --desktop-network      let NetworkManager run all networking (systems installed from Ubuntu's
#                          server image use systemd-networkd, which NetworkManager can't manage)
#
# Every step is safe to repeat.
set -euo pipefail
PREFIX=/opt/ultimit
TREE="" RELEASE="" APPS=now SWITCH_DM=true DESKTOP_NET=false
while [ $# -gt 0 ]; do
	case "$1" in
	--tree) TREE=$2; shift ;;
	--release) RELEASE=$2; shift ;;
	--no-apps) APPS=no ;;
	--apps-at-first-boot) APPS=firstboot ;;
	--keep-login-screen) SWITCH_DM=false ;;
	--desktop-network) DESKTOP_NET=true ;;
	-h | --help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done
[ "$(id -u)" = 0 ] || { echo "system-install.sh runs as root (scripts/install.sh calls it with sudo)" >&2; exit 1; }

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
warn() { printf '\033[1;33m   ! %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mInstall stopped: %s\033[0m\n' "$*"; exit 1; }
trap 'die "a command failed (system-install.sh line $LINENO)"' ERR
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | grep -vxF -f <(printf '%s\n' ${ULTIMIT_SKIP_PACKAGES:-} "") || true; }
export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------------ the files
if [ -n "$RELEASE" ]; then
	step "Unpacking $(basename "$RELEASE")"
	rm -rf "$PREFIX.new" && mkdir -p "$PREFIX.new"
	tar -C "$PREFIX.new" -xf "$RELEASE"
	[ -x "$PREFIX.new/opt/ultimit/bin/ultimit" ] || die "$RELEASE isn't an Ultimit release"
	# The previous version stays as $PREFIX.previous until this install has passed its checks
	# (Settings > Updates puts it back if not)
	rm -rf "$PREFIX.previous"; [ -e "$PREFIX" ] && mv "$PREFIX" "$PREFIX.previous"
	mv "$PREFIX.new/opt/ultimit" "$PREFIX"
	# DXVK (install-apps.sh) lives in /opt/ultimit but isn't part of a release
	if [ -d "$PREFIX.previous/dxvk" ] && [ ! -e "$PREFIX/dxvk" ]; then cp -a "$PREFIX.previous/dxvk" "$PREFIX/dxvk"; fi
	install -D -m644 "$PREFIX.new/usr/lib/x86_64-linux-gnu/security/pam_oo7.so" /usr/lib/x86_64-linux-gnu/security/pam_oo7.so
	rm -rf "$PREFIX.new"
	note "Ultimit $(cat "$PREFIX/VERSION")"
elif [ -n "$TREE" ]; then
	step "Installing the shell, session and login screen to $PREFIX"
	rev=$(git -C "$TREE" describe --tags --always --dirty 2>/dev/null || echo unknown)
	stage=$(mktemp -d)
	tar -C "$TREE" --exclude=__pycache__ --exclude=test-results --exclude='*.pyc' \
		-cf - shell session greeter distro assets scripts docs/keybindings.md docs/install.md LICENSE | tar -C "$stage" -xf -
	echo "$rev" >"$stage/VERSION"
	for d in shell session greeter distro assets scripts docs; do
		rm -rf "$PREFIX/$d.new"; cp -a "$stage/$d" "$PREFIX/$d.new"
		rm -rf "$PREFIX/$d.old"; [ -e "$PREFIX/$d" ] && mv "$PREFIX/$d" "$PREFIX/$d.old"
		mv "$PREFIX/$d.new" "$PREFIX/$d"; rm -rf "$PREFIX/$d.old"
	done
	cp "$stage/VERSION" "$stage/LICENSE" "$PREFIX/"
	rm -rf "$stage"
	note "Ultimit $rev"
fi
[ -x "$PREFIX/bin/ultimit" ] && [ -d "$PREFIX/shell" ] || die "$PREFIX is incomplete (build with scripts/install.sh, or give --release)"
# Debug info and tools nothing runs only take space (Quickshell's debug info alone is ~200 MB);
# installs made before scripts/install.sh stripped them get it here
rm -f "$PREFIX/bin/oo7-cli"
if command -v strip >/dev/null; then
	for b in "$PREFIX/bin/quickshell" "$PREFIX/bin/oo7-daemon" "$PREFIX/libexec/oo7-daemon-login" "$PREFIX/bin/ultimit"; do
		# a new file renamed over the old one: a running quickshell keeps its copy until it restarts
		if [ -f "$b" ] && LC_ALL=C file "$b" | grep -q "not stripped"; then
			strip --strip-unneeded -o "$b.stripped" "$b" && mv -f "$b.stripped" "$b"
		fi
	done
fi
chown -R root:root "$PREFIX"; chmod -R go-w,a+rX "$PREFIX"

# ------------------------------------------------------------------------------------ packages
step "Installing the packages the desktop needs (apt)"
dpkg --configure -a   # finish anything an earlier run left half-done
apt-get update -q
mapfile -t pkgs < <(list "$PREFIX/distro/packages-core.txt")
# A precompiled release also lists the libraries its binaries link to (scripts/release-deps.sh)
if [ -f "$PREFIX/distro/packages-runtime.txt" ]; then
	mapfile -t -O ${#pkgs[@]} pkgs < <(list "$PREFIX/distro/packages-runtime.txt")
fi
apt-get install -y -q "${pkgs[@]}"

# ------------------------------------------------------------------------------------ NVIDIA
# The desktop needs NVIDIA's graphics libraries (EGL, and GBM for Wayland). Ubuntu's server
# installer installs the compute-only driver (--gpgpu: the kernel module, no graphics), and then
# nothing can draw. Swap it for the desktop driver ubuntu-drivers recommends.
if lspci -n 2>/dev/null | grep -qE ' 03(00|02): 10de:'; then
	if ! dpkg-query -W -f='${Status}' libnvidia-egl-gbm1 2>/dev/null | grep -q "install ok installed"; then
		step "Installing NVIDIA's desktop driver (graphics libraries)"
		if ubuntu-drivers install; then
			note "$(dpkg-query -W -f='${Package} ' 'nvidia-driver-*' 2>/dev/null | head -c 200)"
		else
			warn "ubuntu-drivers couldn't install the NVIDIA desktop driver; run 'sudo ubuntu-drivers install' later"
		fi
	fi
fi

# ------------------------------------------------------------------------------------ trim
step "Trimming Ubuntu's server parts (crash dumps, cloud, SAN disks, snapd...)"
"$PREFIX/scripts/trim-ubuntu.sh" --yes || warn "Ubuntu's server parts were left in place (see above)"

# ------------------------------------------------------------------------------------ system
step "Setting up the system (fonts, session, keyring unlock, helpers, commands)"
P=$PREFIX
# Fonts the look uses (SIL Open Font License, see assets/fonts)
install -D -m644 -t /usr/share/fonts/truetype/ultimit "$P"/assets/fonts/*.ttf "$P"/assets/fonts/OFL-*.txt
fc-cache -f /usr/share/fonts/truetype/ultimit >/dev/null
# The session the login screen offers
mkdir -p /usr/share/wayland-sessions /usr/share/applications /etc/X11
sed "s|@SESSION@|$P/session/ultimit-session|g" "$P/session/ultimit.desktop" >/usr/share/wayland-sessions/ultimit.desktop
# Root helpers and polkit policies (FIREWALL, Updates, Users) and the virtual camera
( cd "$P/distro/system" && find . -name __pycache__ -prune -o -type f -print | while read -r f; do
	mode=644; [ -x "$f" ] && mode=755
	install -D -m $mode "$f" "/$f"
done )
# umu-launcher's package (distro/debs.txt) links /etc/apparmor.d/bwrap-userns-restrict-umu to
# extra-profiles/bwrap-userns-restrict, which Ubuntu 26.04 doesn't have (it ships that profile as
# /etc/apparmor.d/bwrap-userns-restrict), so apparmor.service failed on every boot. Divert the link
# out of /etc/apparmor.d, for umu updates too.
umu_aa=/etc/apparmor.d/bwrap-userns-restrict-umu
if [ ! -e /usr/share/apparmor/extra-profiles/bwrap-userns-restrict ] && ! dpkg-divert --list "$umu_aa" | grep -q .; then
	mkdir -p /var/lib/ultimit
	dpkg-divert --quiet --local --rename --divert /var/lib/ultimit/bwrap-userns-restrict-umu.diverted --add "$umu_aa"
	if systemctl is-failed --quiet apparmor.service; then
		systemctl reset-failed apparmor.service; systemctl restart apparmor.service || warn "AppArmor still fails to load a profile (journalctl -u apparmor)"
	fi
fi
# controllers plugged in now get the new udev rules too (72-ultimit-gamepads.rules)
udevadm control --reload 2>/dev/null && udevadm trigger --subsystem-match=hidraw 2>/dev/null || true
# Ultimit commands on everyone's PATH (other apps open folders with ultimit-data, ...)
for b in "$P"/shell/bin/*; do ln -sfn "$b" "/usr/local/bin/$(basename "$b")"; done
# Ultimit apps in every app menu
for d in "$P"/shell/apps/*/ultimit-*.desktop; do
	sed "s|^Exec=ultimit-|Exec=$P/shell/bin/ultimit-|" "$d" >"/usr/share/applications/$(basename "$d")"
done
# Unlock the keyring (oo7) with the password typed at the login screen
if ! grep -q pam_oo7 /etc/pam.d/greetd 2>/dev/null; then
	printf "\n# Ultimit: unlock the oo7 keyring with the login password.\nauth     optional pam_oo7.so\nsession  optional pam_oo7.so auto_start\n" >>/etc/pam.d/greetd
fi
# Dual boot: Ubuntu has GRUB skip other systems (os-prober off); turn it on so Windows is in the
# boot menu (GRUB then shows its menu at start when it found one)
if [ -d /etc/default/grub.d ] && command -v update-grub >/dev/null; then
	printf '# Written by Ultimit: list Windows and other systems in the boot menu\nGRUB_DISABLE_OS_PROBER=false\n' \
		>/etc/default/grub.d/90-ultimit-os-prober.cfg
	update-grub >/dev/null 2>&1 || warn "update-grub failed (the boot menu may not list other systems)"
fi
# Where the login screen remembers the last user and session
GU=$(getent passwd _greetd >/dev/null && echo _greetd || echo greeter)
mkdir -p /var/lib/ultimit-greeter && chown "$GU" /var/lib/ultimit-greeter
# and each user's monitor setup (session/ultimit-greeter-displays): anyone may add their own copy
install -d -m 1777 /var/lib/ultimit-greeter/displays

if $DESKTOP_NET; then
	step "Handing networking to NetworkManager (as on Ubuntu Desktop)"
	mkdir -p /etc/netplan/ultimit-disabled
	for f in /etc/netplan/*.yaml; do
		[ -e "$f" ] && [ "$(basename "$f")" != 01-network-manager-all.yaml ] && mv "$f" /etc/netplan/ultimit-disabled/
	done
	printf '# Written by Ultimit: NetworkManager runs every network device (as on Ubuntu Desktop).\nnetwork:\n  version: 2\n  renderer: NetworkManager\n' \
		>/etc/netplan/01-network-manager-all.yaml
	chmod 600 /etc/netplan/01-network-manager-all.yaml
	# cloud-init must not write its own network config over it on later boots
	mkdir -p /etc/cloud/cloud.cfg.d
	echo "network: {config: disabled}" >/etc/cloud/cloud.cfg.d/99-ultimit-network.cfg
	systemctl disable systemd-networkd-wait-online.service systemd-networkd.service 2>/dev/null || true
	systemctl enable NetworkManager.service
fi

if $SWITCH_DM; then
	step "Making the Ultimit login screen the one this PC starts with"
	[ -f /etc/greetd/config.toml ] && cp --update=none /etc/greetd/config.toml /etc/greetd/config.toml.before-ultimit
	cat >/etc/greetd/config.toml <<CONF
# Written by Ultimit scripts/system-install.sh
[terminal]
# Ubuntu's greetd.service owns tty7 (Conflicts=getty@tty7).
vt = 7

[default_session]
command = "$P/session/ultimit-greeter-session"
user = "$GU"
CONF
	systemctl disable gdm3 sddm lightdm 2>/dev/null || true
	systemctl enable --force greetd
	echo /usr/sbin/greetd >/etc/X11/default-display-manager
	systemctl set-default graphical.target
	[ "$(readlink -f /etc/systemd/system/display-manager.service)" = "$(readlink -f /usr/lib/systemd/system/greetd.service)" ] \
		|| die "greetd didn't become the login screen"
fi

# ------------------------------------------------------------------------------------ apps
case "$APPS" in
new)
	# What the lists gained since the version this replaces (still in $PREFIX.previous)
	added=""
	if [ -d "$PREFIX.previous/distro" ]; then
		for l in packages-install.txt flatpaks.txt; do
			added="$added $(comm -13 <(list "$PREFIX.previous/distro/$l" 2>/dev/null | sort -u) <(list "$P/distro/$l" | sort -u) | tr '\n' ' ')"
		done
		added="$added $(comm -13 <(sed -e 's/#.*//' "$PREFIX.previous/distro/debs.txt" 2>/dev/null | awk 'NF {print $1}' | sort -u) \
			<(sed -e 's/#.*//' "$P/distro/debs.txt" | awk 'NF {print $1}' | sort -u) | tr '\n' ' ')"
	fi
	added=$(echo $added)
	if [ -n "$added" ]; then
		step "New apps in this version: $added"
		ULTIMIT_APPS_ONLY="$added" "$P/scripts/install-apps.sh" --yes || warn "some new apps didn't install (they can be installed later with $P/scripts/install-apps.sh --yes)"
	fi
	;;
now)
	step "Installing the apps (distro/packages-install.txt, Flatpaks, DXVK)"
	"$P/scripts/install-apps.sh" --yes
	;;
firstboot)
	step "Apps (Flatpaks, Steam, Wine, DXVK...) install on the first boot"
	cat >/etc/systemd/system/ultimit-firstboot.service <<UNIT
[Unit]
Description=Ultimit: install the apps (first boot)
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/var/lib/ultimit/firstboot-done

[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/bin/sh -c '$P/scripts/install-apps.sh --yes >>/var/log/ultimit-firstboot.log 2>&1 && mkdir -p /var/lib/ultimit && touch /var/lib/ultimit/firstboot-done'
TimeoutStartSec=3h
# A failed try (network not there yet, a mirror hiccup) tries again; the log has each attempt
Restart=on-failure
RestartSec=2min

[Install]
WantedBy=multi-user.target
UNIT
	systemctl enable ultimit-firstboot.service
	;;
esac

# ------------------------------------------------------------------------------------ check
step "Checking the install"
fail=0
for f in bin/ultimit bin/qs bin/oo7-daemon libexec/oo7-daemon-login session/ultimit-session session/ultimit-greeter-session greeter/shell.qml shell/shell.qml; do
	[ -e "$PREFIX/$f" ] || { warn "missing $PREFIX/$f"; fail=1; }
done
for b in ultimit qs; do
	[ -e "$PREFIX/bin/$b" ] || continue   # (reported as missing above)
	gone=$(ldd "$PREFIX/bin/$b" | awk '/not found/ {print $1}' | tr '\n' ' ')
	[ -z "$gone" ] || { warn "$b is missing libraries: $gone"; fail=1; }
done
"$PREFIX/bin/qs" --version >/dev/null 2>&1 || { warn "Quickshell doesn't start"; fail=1; }
# (no "fc-list | grep -q": with pipefail, grep quitting early makes fc-list fail with SIGPIPE)
[ "$(fc-list : family | grep -c -E 'Michroma|Chakra Petch|Share Tech Mono')" -ge 3 ] || { warn "fonts not found by fontconfig"; fail=1; }
[ -f /usr/share/wayland-sessions/ultimit.desktop ] || { warn "session file missing"; fail=1; }
[ -f /usr/lib/x86_64-linux-gnu/security/pam_oo7.so ] || { warn "keyring unlock module missing"; fail=1; }
[ "$fail" = 0 ] || die "the install is incomplete (see the warnings above)"
rm -rf "$PREFIX.previous"
note "Ultimit $(cat "$PREFIX/VERSION") is in place"
