#!/bin/sh
# make-state.sh DIR SCENARIO - seed the fake system state used with SHARES_FAKE=1.
#   fresh    nothing set up: Samba missing
#   partial  Samba installed + running, but no sambashare group, no password, firewall unknown
#   (HOME for the app is $DIR/home)
#   ready    everything set up, two shares
set -e
d=$1; sc=${2:-ready}
rm -rf "$d"; mkdir -p "$d/home" "$d/shares" "$d/usershares" "$d/ufw-apps"
printf '[Samba]\ntitle=SMB/CIFS server\nports=139,445/tcp|137,138/udp\n' >"$d/ufw-apps/samba"
touch "$d/ufw"
case $sc in
fresh) ;;
partial) touch "$d/installed" "$d/active" ;;
ready)
	touch "$d/installed" "$d/active" "$d/group" "$d/fw_rule"
	echo "sambashare:x:123:$(id -un)" >"$d/etc_group"
	mkdir -p "$d/home/.local/state/ultimit"
	touch "$d/home/.local/state/ultimit/shares-password-set"
	echo 192.168.1.0/24 >"$d/home/.local/state/ultimit/shares-firewall"
	mkdir -p "$d/home/Public" "$d/home/Music"
	printf 'path=%s\ncomment=Family photos\nusershare_acl=Everyone:R,\nguest_ok=n\n' "$d/home/Public" >"$d/shares/public"
	printf 'path=%s\ncomment=\nusershare_acl=Everyone:F,\nguest_ok=y\n' "$d/home/Music" >"$d/shares/music"
	;;
esac
# fake network for connect.py (see connect-fake.json); `ready` also starts with one connected share and one saved connection
cp "$(dirname "$0")/connect-fake.json" "$d/connect-fake.json"
if [ "$sc" = ready ]; then
	mkdir -p "$d/mnt/smb-share:server=family-nas.local,share=media"
	python3 - "$d" <<'PY'
import json, sys
d = sys.argv[1]; p = d + "/connect-fake.json"; j = json.load(open(p))
j["mounts"].append({"uri": "smb://family-nas.local/media", "name": "media on family-nas.local",
                    "path": d + "/mnt/smb-share:server=family-nas.local,share=media", "scheme": "smb"})
json.dump(j, open(p, "w"), indent=1)
saved = [{"name": "media on family-nas.local", "uri": "smb://family-nas.local/media", "user": "", "domain": "", "remember": False, "reconnectAtLogin": True},
         {"name": "docs on office-pc", "uri": "smb://office-pc/docs", "user": "bob", "domain": "", "remember": True, "reconnectAtLogin": False}]
import os
os.makedirs(d + "/config/ultimit/shares", exist_ok=True)
json.dump(saved, open(d + "/config/ultimit/shares/connections.json", "w"), indent=1)
PY
fi
