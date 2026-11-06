#!/bin/bash
# Install NekoShot (full-system backup CLI, behind BACKUP) into PREFIX/nekoshot. Pure Python stdlib: no build step.
#
#   scripts/build-nekoshot.sh WORK_DIR [PREFIX]      (PREFIX default: /opt/ultimit)
#
# The commit is pinned below (branch ultimit; push it before a release build). The tools it shells out to
# (rsync, zstd, gpg, sfdisk) are installed by system-install.sh.
set -euo pipefail
NEKOSHOT_URL=https://github.com/m0nnnna/NekoShot
NEKOSHOT_REF=bc491e3288fcee36d6a39818aee65db6a0b91fd7   # branch ultimit
WORK=${1:?usage: build-nekoshot.sh WORK_DIR [PREFIX]}
PREFIX=${2:-/opt/ultimit}
N=$PREFIX/nekoshot

if [ "$(cat "$N/REF" 2>/dev/null)" = "$NEKOSHOT_REF" ] && [ -f "$N/nekoshot.py" ]; then
	echo "   already installed"; exit 0
fi
d=$WORK/src/nekoshot
if [ ! -d "$d/.git" ]; then rm -rf "$d"; mkdir -p "$WORK/src"; git clone -q --filter=blob:none "$NEKOSHOT_URL" "$d"; fi
git -C "$d" fetch -q origin "$NEKOSHOT_REF"
git -C "$d" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
[ -f "$d/nekoshot.py" ] || { echo "no nekoshot.py in $d" >&2; exit 1; }

# Staged next to the old one and swapped in at the end, so a failed copy leaves it working
sudo rm -rf "$N.new"; sudo mkdir -p "$N.new"
sudo cp -a "$d/." "$N.new/"; sudo rm -rf "$N.new/.git"
echo "$NEKOSHOT_REF" | sudo tee "$N.new/REF" >/dev/null
sudo rm -rf "$N.old"; [ -e "$N" ] && sudo mv "$N" "$N.old"
sudo mv "$N.new" "$N"; sudo rm -rf "$N.old"
echo "   NekoShot ${NEKOSHOT_REF:0:7} in $N"
