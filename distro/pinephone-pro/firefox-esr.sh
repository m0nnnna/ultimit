#!/bin/sh
# Firefox ESR (Mozilla's own arm64 .deb) made phone-shaped by postmarketOS's mobile-config-firefox,
# with uBlock Origin + Bitwarden and GPU/RAM-saving defaults (firefox/ultimit-phone.js).
# ESR because mobile-config-firefox's CSS keeps up with it; the Flatpak's monthly releases broke it.
# Run as root on the phone from this directory: sudo sh firefox-esr.sh
# Undo: apt-get remove firefox-esr; rm /etc/apt/sources.list.d/mozilla.sources /etc/apt/preferences.d/mozilla
set -eu
cd "$(dirname "$0")"
MCF_TAG=5.5.1
FF=/usr/lib/firefox-esr
KEY=/etc/apt/keyrings/packages.mozilla.org.asc
FPR=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3

install -d -m755 /etc/apt/keyrings
curl -fsSLo "$KEY.new" https://packages.mozilla.org/apt/repo-signing-key.gpg
gpg --show-keys --with-colons "$KEY.new" 2>/dev/null | grep -q "^fpr:*$FPR:" \
  || { echo "Mozilla's signing key fingerprint doesn't match; stopping" >&2; rm -f "$KEY.new"; exit 1; }
mv "$KEY.new" "$KEY"
cat > /etc/apt/sources.list.d/mozilla.sources <<EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $KEY
EOF
# only Firefox from Mozilla's repo; everything else stays Ubuntu's
cat > /etc/apt/preferences.d/mozilla <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 100

Package: firefox-esr*
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -yq firefox-esr git make

mcf=$(mktemp -d)
git clone -q --depth 1 --branch "$MCF_TAG" https://gitlab.postmarketos.org/postmarketOS/mobile-config-firefox.git "$mcf"
make -C "$mcf" FIREFOX_DIR="$FF" install >/dev/null
rm -rf "$mcf"
# our policy (uBlock Origin, Bitwarden, no onboarding, mobile site layouts) over its own
python3 - firefox/policies.json "$FF/distribution/policies.json" <<'PY'
import json, sys
ours = json.load(open(sys.argv[1]))["policies"]; m = json.load(open(sys.argv[2]))
p = m["policies"]; p.pop("SearchEngines", None)
for k, v in ours.items():
    if k in ("Preferences", "ExtensionSettings"): p.setdefault(k, {}).update(v)
    else: p[k] = v
json.dump(m, open(sys.argv[2], "w"), indent=2)
PY
install -m644 firefox/ultimit-phone.js "$FF/defaults/pref/ultimit-phone.js"

if [ -n "${SUDO_USER:-}" ]; then
  su - "$SUDO_USER" -c 'xdg-mime default firefox-esr.desktop x-scheme-handler/http x-scheme-handler/https text/html' || true
fi
echo "done: Firefox ESR $(dpkg-query -Wf '${Version}' firefox-esr)"
