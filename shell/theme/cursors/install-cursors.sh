#!/bin/sh
# Build and install the four UltimitCursor-<Skin> themes.
# Usage: install-cursors.sh [DEST]   (default: $HOME/.local/share/icons)
# Quiet and idempotent: skips the rebuild when build-cursors.py is unchanged
# and every theme is already present (sha256 stamp per theme).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEST=${1:-${DEST:-$HOME/.local/share/icons}}
SKINS="Mine Amber Silver Verdant"
SUM=$(sha256sum "$HERE/build-cursors.py" | cut -d' ' -f1)

fresh=1
for s in $SKINS; do
    t="$DEST/UltimitCursor-$s"
    if [ ! -f "$t/.stamp" ] || [ "$(cat "$t/.stamp")" != "$SUM" ] || [ ! -e "$t/cursors/default" ]; then
        fresh=0
    fi
done
[ "$fresh" = 1 ] && exit 0

mkdir -p "$DEST"
TMP=$(mktemp -d "$DEST/.ulcur-build.XXXXXX")
trap 'rm -rf "${TMP:?}"' EXIT
python3 "$HERE/build-cursors.py" "$TMP" >/dev/null
for s in $SKINS; do
    t="UltimitCursor-$s"
    printf '%s\n' "$SUM" > "$TMP/$t/.stamp"
    rm -rf "${DEST:?}/${t:?}"
    mv "$TMP/$t" "$DEST/$t"
done
