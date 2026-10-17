#!/bin/bash
# Build NekoMail, Ultimit's mail app (the rail's MAILER), into PREFIX/nekomail. scripts/install.sh
# runs it (as your user; sudo for the copy), so a release carries the finished app and
# system-install.sh only links it into the system (nekomail command, menu entry, mailto: handler,
# the user unit that syncs mail in the background).
#
#   scripts/build-nekomail.sh WORK_DIR [PREFIX]      (PREFIX default: /opt/ultimit)
#
# The NekoMail commit is pinned below. Mail data stays per user, in ~/.config/nekomail and
# ~/.local/share/nekomail; nothing is written under PREFIX at run time.
set -euo pipefail
NEKOMAIL_URL=https://github.com/m0nnnna/NekoMail
NEKOMAIL_REF=ab20de6823f36e5a04f4fb91949a3012565ef4dc   # branch ultimit
WORK=${1:?usage: build-nekomail.sh WORK_DIR [PREFIX]}
PREFIX=${2:-/opt/ultimit}
N=$PREFIX/nekomail

if [ "$(cat "$N/REF" 2>/dev/null)" = "$NEKOMAIL_REF" ] && [ -x "$N/bin/nekomail" ]; then
	echo "   already installed"; exit 0
fi

d=$WORK/src/nekomail
if [ ! -d "$d/.git" ]; then rm -rf "$d"; git clone -q --filter=blob:none "$NEKOMAIL_URL" "$d"; fi
git -C "$d" fetch -q origin "$NEKOMAIL_REF"
git -C "$d" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
git -C "$d" clean -qfdx -e frontend/node_modules

echo "   frontend (npm)"
( cd "$d/frontend" && npm ci --no-audit --no-fund --loglevel=error && npm run build --silent ) >/dev/null

# Staged next to the old one and swapped in at the end, so a failed build leaves it working
sudo rm -rf "$N.new"; sudo mkdir -p "$N.new/bin" "$N.new/share"
tar -C "$d" --exclude=.venv --exclude=__pycache__ --exclude=spikes --exclude=app/static \
	--exclude='*.spec' --exclude='requirements-desktop.txt' -cf - backend | sudo tar -C "$N.new" -xf -
sudo cp -r "$d/frontend/dist" "$N.new/backend/app/static"
sudo install -m644 "$d/ultimit/nekomail.svg" "$N.new/share/nekomail.svg"
sudo install -m644 "$d/frontend/public/icons/icon-192.png" "$N.new/share/nekomail-192.png"
sudo install -m644 "$d/frontend/public/icons/icon-512.png" "$N.new/share/nekomail-512.png"

echo "   Python packages (venv)"
# --system-site-packages: pywebview's GTK backend uses the system PyGObject + WebKitGTK
# (python3-gi, gir1.2-webkit2-4.1 in distro/packages-core.txt). The venv only runs through
# venv/bin/python, which finds its packages relative to itself, so it can be moved into place.
sudo python3 -m venv --system-site-packages "$N.new/venv"
sudo "$N.new/venv/bin/python" -m pip install -q --no-cache-dir --disable-pip-version-check --prefer-binary \
	-r "$N.new/backend/requirements-linux.txt"
sudo "$N.new/venv/bin/python" -m pip uninstall -q -y pip >/dev/null 2>&1 || true
sudo "$N.new/venv/bin/python" -c 'import fastapi, webview, sqlalchemy' \
	|| { echo "NekoMail's Python packages don't import" >&2; exit 1; }

sudo tee "$N.new/bin/nekomail" >/dev/null <<EOF
#!/bin/sh
# NekoMail window (single instance; \`nekomail mailto:...\` opens a new message). Starts the
# sync server (nekomail.service) if needed.
# Wayland: talk to the compositor directly (not XWayland) so the app_id is "nekomail".
[ -n "\${WAYLAND_DISPLAY:-}" ] && export GDK_BACKEND="\${GDK_BACKEND:-wayland}"
exec "$N/venv/bin/python" "$N/backend/desktop_app.py" "\$@"
EOF
sudo chmod 755 "$N.new/bin/nekomail"

sudo tee "$N.new/share/nekomail.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=NekoMail
GenericName=Mail
Comment=Read and write mail
Exec=$N/bin/nekomail %u
Icon=nekomail
Terminal=false
Categories=Network;Email;
MimeType=x-scheme-handler/mailto;
StartupWMClass=nekomail
StartupNotify=false
EOF

sudo tee "$N.new/share/nekomail.service" >/dev/null <<EOF
[Unit]
Description=NekoMail background mail sync
After=network-online.target

[Service]
Type=simple
ExecStart=$N/venv/bin/python $N/backend/launcher.py
Environment=PYTHONUNBUFFERED=1
Environment=WINDOW_COMMAND=$N/bin/nekomail
Restart=on-failure
RestartSec=5
# launcher.py stops cleanly on SIGTERM (IDLE connections, runtime files).
TimeoutStopSec=20
NoNewPrivileges=yes

[Install]
WantedBy=default.target
EOF

echo "$NEKOMAIL_REF" | sudo tee "$N.new/REF" >/dev/null
sudo rm -rf "$N.old"; [ -e "$N" ] && sudo mv "$N" "$N.old"
sudo mv "$N.new" "$N"; sudo rm -rf "$N.old"
echo "   NekoMail ${NEKOMAIL_REF:0:7} in $N"
