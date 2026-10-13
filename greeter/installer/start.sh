#!/bin/sh
# greeter/installer/start.sh - the Ultimit installer screen, started by Ubuntu's installer (subiquity) as
# an autoinstall early command on the Ultimit ISO (scripts/build-iso.sh). Runs as root in the live
# system:
#   1. unpacks what the screen needs (ultimit/installer-layer.tar.zst: Mesa, Qt, seatd...; and
#      /opt/ultimit from the release on the ISO)
#   2. runs the Ultimit compositor with greeter/installer.qml on VT 7
#   3. returns once the screen has written the answers (/autoinstall.yaml, answers.py);
#      subiquity then reads that again and installs without questions, while the screen shows
#      the progress and waits for "Restart" (a late command written by answers.py)
# If anything here fails, or the screen doesn't come up, or the person picks Ubuntu's own
# installer, it returns without answers: subiquity asks its usual questions on VT 1.
# Log: /var/log/ultimit-installer.log (the screen's own: /run/ultimit-installer/ui.log)
ISO=/cdrom/ultimit
RUN=/run/ultimit-installer
mkdir -p "$RUN"
exec >>/var/log/ultimit-installer.log 2>&1
echo "== $(date) Ultimit installer"

fallback() {
	echo "Ubuntu's installer takes over: $*"
	[ -n "${ui:-}" ] && kill "$ui" 2>/dev/null
	chvt 1 2>/dev/null
	exit 0
}

layer=$ISO/installer-layer.tar.zst
release=$(ls "$ISO"/ultimit-*-amd64.tar.gz 2>/dev/null | head -n1)
[ -f "$layer" ] && [ -n "$release" ] || fallback "no installer layer or release on the ISO"

# ---- 1. what the screen needs
tar --zstd -xf "$layer" -C / --keep-directory-symlink --no-overwrite-dir || fallback "unpacking the layer failed"
tar -xzf "$release" -C / opt/ultimit || fallback "unpacking Ultimit failed"
ldconfig
mkdir -p /usr/share/fonts/truetype/ultimit
cp /opt/ultimit/assets/fonts/*.ttf /usr/share/fonts/truetype/ultimit/ 2>/dev/null
fc-cache -f >/dev/null 2>&1
systemctl daemon-reload   # wpa_supplicant's units, for Wi-Fi

# ---- 2. the screen
chvt 7
seatd -g root >"$RUN/seatd.log" 2>&1 &
for i in $(seq 50); do [ -S /run/seatd.sock ] && break; sleep 0.1; done
[ -S /run/seatd.sock ] || fallback "seatd didn't start"

export XDG_RUNTIME_DIR="$RUN/xdg" XDG_CACHE_HOME="$RUN/cache" HOME=/root
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME" && chmod 700 "$XDG_RUNTIME_DIR"
export LIBSEAT_BACKEND=seatd QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=Ultimit XDG_SESSION_TYPE=wayland
export LD_LIBRARY_PATH=/opt/ultimit/lib/x86_64-linux-gnu
export ULTIMIT_INSTALLER_BASE=$ISO/installer/base.json ULTIMIT_INSTALLER_RUN=$RUN
setsid /opt/ultimit/bin/ultimit -x -s "/opt/ultimit/bin/qs -p /opt/ultimit/greeter/installer.qml" >"$RUN/ui.log" 2>&1 &
ui=$!
echo "screen started (pid $ui)"

# ---- 3. wait for the answers (the screen says it's up within a minute, or it's given up on)
i=0
while kill -0 "$ui" 2>/dev/null; do
	[ -e "$RUN/answered" ] && { echo "answers written"; exit 0; }
	[ -e "$RUN/text" ] && fallback "the person chose Ubuntu's installer"
	i=$((i + 1))
	[ $i -gt 60 ] && [ ! -e "$RUN/ui-up" ] && fallback "the screen didn't come up"
	sleep 1
done
fallback "the screen stopped (see $RUN/ui.log)"
