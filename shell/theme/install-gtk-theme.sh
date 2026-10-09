#!/bin/sh
# Install the Ultimit GTK theme into the user's theme dir (idempotent).
# Harmless to the normal GNOME session: nothing selects "Ultimit" there; only
# Ultimit sessions export GTK_THEME=Ultimit (see session-env.sh).
# Usage: install-gtk-theme.sh [--copy]   (default: symlink, so edits are live)
set -eu
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SRC="$HERE/gtk/Ultimit"
DEST_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
DEST="$DEST_ROOT/Ultimit"

mkdir -p "$DEST_ROOT"
if [ "${1:-}" = "--copy" ]; then
  rm -rf "$DEST"
  cp -r "$SRC" "$DEST"
  echo "copied $SRC -> $DEST"
else
  # replace an old copy or stale link; ln -sfn keeps it idempotent
  [ -L "$DEST" ] || rm -rf "$DEST"
  ln -sfn "$SRC" "$DEST"
  echo "linked $DEST -> $SRC"
fi
