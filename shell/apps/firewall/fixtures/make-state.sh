#!/bin/sh
# make-state.sh DIR SCENARIO - seed the fake system state used with FIREWALL_FAKE=1.
#   nohelper  ufw installed and on, but the FIREWALL helper is not installed yet
#   noufw     helper installed, ufw missing
#   off       helper + ufw installed, firewall off, no rules
#   ready     firewall on, a few rules (one VTube Studio rule added by hand, SSH, Samba via SHARES)
#             and blocked connections in the log (iFacialMocap, VTube Studio, mDNS noise)
set -e
d=$1; sc=${2:-ready}
here=$(cd "$(dirname "$0")" && pwd)
sys="$here/../../../../distro/system"
rm -rf "$d"; mkdir -p "$d/root/etc/ufw/applications.d"
printf '[Samba]\ntitle=SMB/CIFS server\ndescription=Samba\nports=137,138/udp|139,445/tcp\n' >"$d/root/etc/ufw/applications.d/samba"
install_helper() {
	for f in usr/libexec/ultimit/firewall-helper usr/share/polkit-1/actions/org.ultimit.firewall.policy \
		usr/share/polkit-1/rules.d/50-ultimit-firewall.rules; do
		install -D "$sys/$f" "$d/root/$f"
	done
}
case $sc in
nohelper) touch "$d/ufw-installed" "$d/active" ;;
noufw) install_helper ;;
off) install_helper; touch "$d/ufw-installed" ;;
ready)
	install_helper; touch "$d/ufw-installed" "$d/active"
	cat >"$d/added" <<'R'
ufw allow 22/tcp
ufw allow from 192.168.1.0/24 to any port 25565 comment 'VTube Studio iPhone'
ufw allow from 192.168.1.0/24 to any app Samba comment 'Ultimit SHARES'
R
	k='host kernel: [UFW BLOCK] IN=wlan0 OUT= MAC=f4:7b'
	cat >"$d/log" <<L
1500 $k SRC=192.168.1.164 DST=192.168.1.42 LEN=64 TOS=0x00 PROTO=TCP SPT=49187 DPT=8080 WINDOW=65535 SYN
420 $k SRC=192.168.1.164 DST=192.168.1.42 LEN=249 PROTO=UDP SPT=53138 DPT=49983 LEN=229
300 $k SRC=192.168.1.164 DST=192.168.1.42 LEN=2635 PROTO=UDP SPT=53138 DPT=49983 LEN=2615
95 $k SRC=192.168.1.164 DST=192.168.1.42 LEN=2635 PROTO=UDP SPT=63674 DPT=49983 LEN=2615
200 $k SRC=192.168.1.164 DST=192.168.1.42 LEN=64 PROTO=TCP SPT=49190 DPT=25565 WINDOW=65535 SYN
60 $k SRC=192.168.1.20 DST=224.0.0.251 LEN=100 PROTO=UDP SPT=5353 DPT=5353 LEN=80
40 $k SRC=192.168.1.20 DST=192.168.1.255 LEN=120 PROTO=UDP SPT=1716 DPT=1716 LEN=100
30 $k SRC=0.0.0.0 DST=224.0.0.1 LEN=32 PROTO=2
L
	;;
esac
