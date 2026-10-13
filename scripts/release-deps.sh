#!/bin/bash
# The Ubuntu packages a precompiled Ultimit needs at run time: every library that a binary or plugin
# under DIR links to, mapped to the package that ships it. A from-source install gets these through
# distro/packages-build.txt; a release (scripts/build-release.sh) carries this list instead, as
# distro/packages-runtime.txt, and system-install.sh installs it.
#
#   scripts/release-deps.sh DIR      (DIR: an Ultimit tree, e.g. /opt/ultimit)
# Run it on the machine that built DIR (an Ubuntu 26.04 with the build packages installed).
set -euo pipefail
DIR=${1:?usage: release-deps.sh DIR}
libs=$(find "$DIR" -type f \( -perm -u+x -o -name '*.so*' \) \
	| while read -r f; do [ "$(head -c4 "$f" | tr -d '\0')" = $'\x7fELF' ] && echo "$f" || true; done \
	| while read -r f; do LD_LIBRARY_PATH="$DIR/lib/x86_64-linux-gnu" ldd "$f" 2>/dev/null || true; done \
	| awk '$2 == "=>" && $3 ~ /^\// {print $3}' | sort -u)
# (ldd's "not found" lines have no path, so they'd slip through: check them separately)
missing=$(find "$DIR/bin" -type f -exec env LD_LIBRARY_PATH="$DIR/lib/x86_64-linux-gnu" ldd {} \; 2>/dev/null | grep 'not found' || true)
# Ultimit's own libraries (wlroots, scenefx) come with the release.
for l in $libs; do
	case "$l" in "$DIR"/*) continue ;; esac
	r=$(readlink -f "$l")
	dpkg -S "$r" 2>/dev/null || dpkg -S "$l" 2>/dev/null || dpkg -S "${l#/usr}" 2>/dev/null \
		|| echo "release-deps: no package owns $l" >&2
done | cut -d: -f1 | sed 's/,.*//' | sort -u
[ -z "$missing" ] || { echo "release-deps: unresolved libraries in $DIR" >&2; exit 1; }
