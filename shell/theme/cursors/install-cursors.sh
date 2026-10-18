#!/bin/sh
# Build and install the UltimitCursor-<Skin> themes, one per skin in shell/Theme.qml.
# Usage: install-cursors.sh [DEST]   (default: $HOME/.local/share/icons)
# Quiet and idempotent: skips the rebuild when build-cursors.py and Theme.qml are
# unchanged and every theme is already present (sha256 stamp per theme).
# Needs python3-cairo; a failed build is logged to ~/.local/state/ultimit/cursors.log.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
THEME="$HERE/../../Theme.qml"
DEST=${1:-${DEST:-$HOME/.local/share/icons}}
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/ultimit/cursors.log"
SKINS=$(sed -n 's/^[[:space:]]*\([a-z][a-z]*\)[[:space:]]*:[[:space:]]*{.*/\1/p' "$THEME" \
	| while read -r s; do printf '%s%s\n' "$(printf %s "$s" | cut -c1 | tr a-z A-Z)" "$(printf %s "$s" | cut -c2-)"; done)
[ -n "$SKINS" ] || SKINS="Mine Amber Silver Verdant"
# Your own accent (shell.json "accent") is drawn into every skin's cursor, and the cursor style
# ("cursorStyle") picks the set, so both are part of the stamp.
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ultimit/shell.json"
ACCENT=$(sed -n 's/.*"accent"[[:space:]]*:[[:space:]]*"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$CONF" 2>/dev/null | head -n 1)
STYLE=$(sed -n 's/.*"cursorStyle"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' "$CONF" 2>/dev/null | head -n 1)
SUM=$({ cat "$HERE/build-cursors.py" "$THEME"; echo "$ACCENT"; echo "$STYLE"; } | sha256sum | cut -d' ' -f1)

fresh=1
for s in $SKINS; do
	t="$DEST/UltimitCursor-$s"
	if [ ! -f "$t/.stamp" ] || [ "$(cat "$t/.stamp")" != "$SUM" ] || [ ! -e "$t/cursors/default" ]; then
		fresh=0
	fi
done
[ "$fresh" = 1 ] && exit 0

mkdir -p "$DEST" "$(dirname "$LOG")"
TMP=$(mktemp -d "$DEST/.ulcur-build.XXXXXX")
trap 'rm -rf "${TMP:?}"' EXIT
if ! python3 "$HERE/build-cursors.py" "$TMP" --theme "$THEME" >"$LOG" 2>&1; then
	echo "install-cursors: build failed, see $LOG" >&2
	exit 1
fi
for s in $SKINS; do
	t="UltimitCursor-$s"
	[ -d "$TMP/$t" ] || continue
	printf '%s\n' "$SUM" > "$TMP/$t/.stamp"
	rm -rf "${DEST:?}/${t:?}"
	mv "$TMP/$t" "$DEST/$t"
done
