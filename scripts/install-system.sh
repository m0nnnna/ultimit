#!/bin/sh
# Install the pieces of Ultimit that must work before anyone logs in into
# /opt/ultimit, and prepare greetd with the Ultimit greeter. Does NOT switch
# the display manager; see scripts/switch-dm.sh.
#
# The login screen runs as greetd's own user, which can't read a private
# home folder, so it can't use ~/code/ultimit or ~/.local/ultimit-deps.
# Your sessions still run from this checkout.
#
# Re-run after rebuilding the compositor or changing greeter/ to update.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS=${ULTIMIT_DEPS:-$HOME/.local/ultimit-deps}
SRC=${ULTIMIT_SRC:-$HOME/.local/src}
OPT=/opt/ultimit
LIBDIR="$DEPS/lib/x86_64-linux-gnu"

[ -x "$ROOT/compositor/build/ultimit" ] || { echo "Build the compositor first"; exit 1; }
[ -f "$ROOT/greeter/shell.qml" ] || { echo "greeter/ is missing"; exit 1; }

# pam_oo7 starts oo7-daemon-login from a path fixed at build time.
if [ -d "$SRC/oo7" ]; then
	(
		cd "$SRC/oo7"
		OO7_DAEMON_LOGIN_PATH=$OPT/libexec/oo7-daemon-login \
			PATH="$HOME/.cargo/bin:$PATH" cargo build --release -j 4 -p oo7-pam -q
	)
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/libexec" "$STAGE/fonts"
cp "$ROOT/compositor/build/ultimit" "$DEPS/bin/qs" "$STAGE/bin/"
cp -a "$LIBDIR"/libwlroots-0.19.so* "$LIBDIR"/libscenefx-0.4.so* "$STAGE/lib/"
cp -a "$ROOT/greeter" "$STAGE/greeter"
cp "$HOME"/.local/share/fonts/ultimit/*.ttf "$STAGE/fonts/" 2>/dev/null || true
if [ -d "$SRC/oo7/target/release" ]; then
	cp "$SRC/oo7/target/release/oo7-daemon" "$SRC/oo7/target/release/oo7-cli" "$STAGE/bin/"
	cp "$SRC/oo7/target/release/oo7-daemon-login" "$STAGE/libexec/"
fi
cat >"$STAGE/libexec/ultimit-greeter-session" <<'EOF'
#!/bin/sh
# Run by greetd as its greeter user: the Ultimit compositor with the login
# screen as its only client; when the greeter quits (after starting a
# session), the compositor exits (-x) and greetd takes over.
export LD_LIBRARY_PATH=/opt/ultimit/lib
export XDG_CURRENT_DESKTOP=Ultimit XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
# The greeter user may have no writable home; keep Quickshell's state in
# the runtime dir.
export XDG_CACHE_HOME="${XDG_RUNTIME_DIR:-/tmp}/ultimit-greeter/cache"
export XDG_STATE_HOME=/var/lib/ultimit-greeter
mkdir -p "$XDG_CACHE_HOME"
exec /opt/ultimit/bin/ultimit -x -s "/opt/ultimit/bin/qs -p /opt/ultimit/greeter"
EOF

echo "Installing to $OPT (sudo)..."
sudo sh -e <<EOF
apt-get install -y greetd >/dev/null
rm -rf $OPT.new
mkdir -p $OPT.new
cp -a "$STAGE/bin" "$STAGE/lib" "$STAGE/libexec" "$STAGE/greeter" $OPT.new/
chmod 755 $OPT.new/bin/* $OPT.new/libexec/*
chmod -R a+rX $OPT.new
rm -rf $OPT.old
[ -d $OPT ] && mv $OPT $OPT.old
mv $OPT.new $OPT
rm -rf $OPT.old

# Fonts the greeter needs (system-wide; harmless for every session).
mkdir -p /usr/local/share/fonts/ultimit
cp "$STAGE"/fonts/*.ttf /usr/local/share/fonts/ultimit/ 2>/dev/null || true
fc-cache -f /usr/local/share/fonts/ultimit >/dev/null

# Remembered user/session for the greeter.
GREETER_USER=\$(awk -F'"' '/^user/ {print \$2; exit}' /etc/greetd/config.toml 2>/dev/null)
[ -n "\$GREETER_USER" ] || GREETER_USER=_greetd
mkdir -p /var/lib/ultimit-greeter
chown "\$GREETER_USER" /var/lib/ultimit-greeter 2>/dev/null || true

# Keyring unlock at login: oo7 gets the password typed into the greeter.
if [ -f "$SRC/oo7/target/release/libpam_oo7.so" ]; then
	install -m644 "$SRC/oo7/target/release/libpam_oo7.so" /lib/x86_64-linux-gnu/security/pam_oo7.so
	grep -q pam_oo7 /etc/pam.d/greetd || cat >>/etc/pam.d/greetd <<'PAM'

# Ultimit: unlock the oo7 keyring with the login password.
auth     optional pam_oo7.so
session  optional pam_oo7.so auto_start
PAM
fi
EOF
echo "Installed. greetd is installed but not active; GDM is still the login screen."
echo "Test the greeter in a window:   scripts/test-greeter.sh"
echo "Switch login screens:          scripts/switch-dm.sh greetd   (back: scripts/switch-dm.sh gdm)"
