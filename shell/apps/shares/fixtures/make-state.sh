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
