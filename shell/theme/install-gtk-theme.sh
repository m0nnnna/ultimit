#!/bin/sh
# Build and install the Ultimit GTK themes (idempotent):
#   Ultimit-Mine, Ultimit-Amber, Ultimit-Silver, Ultimit-Verdant, and plain
#   "Ultimit" = alias of the current skin (~/.config/ultimit/shell.json).
# Install location is unchanged: ${XDG_DATA_HOME:-~/.local/share}/themes.
# Also seeds gtk-3.0/gtk-4.0 settings.ini with gtk-decoration-layout (only if
# the key is missing) so client-drawn windows get all three window buttons even
# without dconf. Nothing global is touched: no gtk.css, no gsettings.
# Harmless to a normal GNOME session: nothing selects these themes there; only
# Ultimit sessions export GTK_THEME (see session-env.sh).
# Usage: install-gtk-theme.sh [--skin SKIN]   (SKIN for the "Ultimit" alias;
#        default: read from shell.json). Re-run after changing the skin to
#        refresh the alias. Old flag --copy is accepted and ignored.
set -eu
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
DEST_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
LAYOUT="${ULTIMIT_BUTTON_LAYOUT:-:minimize,maximize,close}"
SKIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skin) SKIN=$2; shift ;;
    --copy) ;;
    *) echo "usage: $0 [--skin mine|amber|silver|verdant]" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$DEST_ROOT"
# the old installer symlinked a source dir here; never write through a link
[ -L "$DEST_ROOT/Ultimit" ] && rm "$DEST_ROOT/Ultimit"
if [ -n "$SKIN" ]; then
  python3 "$HERE/gtk/build-gtk.py" "$DEST_ROOT" --alias "$SKIN"
else
  python3 "$HERE/gtk/build-gtk.py" "$DEST_ROOT"
fi

# settings.ini fallback for the decoration layout
for v in 3.0 4.0; do
  d="$CFG/gtk-$v"; f="$d/settings.ini"
  mkdir -p "$d"
  if [ ! -f "$f" ]; then
    printf '[Settings]\ngtk-decoration-layout=%s\n' "$LAYOUT" > "$f"
    echo "created $f"
  elif ! grep -q '^[[:space:]]*gtk-decoration-layout' "$f"; then
    if grep -q '^\[Settings\]' "$f"; then
      sed -i "/^\[Settings\]/a gtk-decoration-layout=$LAYOUT" "$f"
    else
      printf '\n[Settings]\ngtk-decoration-layout=%s\n' "$LAYOUT" >> "$f"
    fi
    echo "added gtk-decoration-layout to $f"
  fi
done
