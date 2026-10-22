#!/bin/sh
# Patch the PinePhone Pro DTB so eg25-manager can run the modem.
#
# megi's DT hangs a "quectel,eg25" child off uart3 for his modem-power driver
# (CONFIG_MODEM_POWER), which neither our kernel nor pmOS's builds. That child
# keeps /dev/ttyS3 from appearing, and with no consumer the vcc_4g / vcc_4g_5v
# regulators get switched off after boot, so the modem never powers up.
# Fix: disable the child and keep both regulators on.
#
# usage: sudo dtb-modem-fix.sh /boot/dtb-7.0.5-ppp   (keeps a .orig copy)
set -eu
dtb=$1
command -v dtc >/dev/null || { echo "needs device-tree-compiler" >&2; exit 1; }
[ -e "$dtb.orig" ] || cp "$dtb" "$dtb.orig"
tmp=$(mktemp -d)
dtc -q -I dtb -O dts -o "$tmp/a.dts" "$dtb.orig"
awk '
	/^\tregulator-vcc-4g(-5v)? \{/ { reg = 1 }
	reg && /regulator-name/ { print; print "\t\tregulator-always-on;"; print "\t\tregulator-boot-on;"; reg = 0; next }
	/^\tserial@ff1b0000 \{/ { uart = 1 }
	uart && /^\t\tmodem \{/ { print; print "\t\t\tstatus = \"disabled\";"; uart = 0; next }
	{ print }
' "$tmp/a.dts" > "$tmp/b.dts"
[ "$(grep -c regulator-always-on "$tmp/b.dts")" -gt "$(grep -c regulator-always-on "$tmp/a.dts")" ] || { echo "regulators not found" >&2; exit 1; }
dtc -q -I dts -O dtb -o "$tmp/b.dtb" "$tmp/b.dts"
cp "$tmp/b.dtb" "$dtb"
rm -rf "$tmp"
echo "patched $dtb (original: $dtb.orig)"
