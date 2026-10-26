#!/bin/sh
# install-icons.sh [mine|amber|silver|verdant|sakura|paper|void]
#
# Builds the Ultimit icon themes with build-icons.py into $DEST (default ~/.local/share/icons) and
# prints the theme name for the chosen skin (default: $ULTIMIT_SKIN, else "skin" in
# ~/.config/ultimit/shell.json, else mine), e.g. "Ultimit-Amber".
#
# All four Ultimit-<Skin> themes are always installed (the shell switches between them live);
# the argument only picks which name is printed. Idempotent; replaces the Ultimit-* dirs only.
# Does not touch gsettings: to make GTK apps use it run
#     gsettings set org.gnome.desktop.interface icon-theme "$(install-icons.sh)"
here=$(dirname "$(readlink -f "$0")")
DEST=${DEST:-${XDG_DATA_HOME:-$HOME/.local/share}/icons}

skin=${1:-${ULTIMIT_SKIN:-}}
if [ -z "$skin" ] && [ -r "$HOME/.config/ultimit/shell.json" ]; then
	skin=$(sed -n 's/.*"skin"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' "$HOME/.config/ultimit/shell.json" | head -n 1)
fi
case "$skin" in mine|amber|silver|verdant|sakura|paper|void) ;; "") skin=mine ;; *) echo "install-icons: unknown skin '$skin'" >&2; exit 2 ;; esac

mkdir -p "$DEST" || exit 1
python3 "$here/build-icons.py" "$DEST" >&2 || exit 1
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	for t in Mine Amber Silver Verdant Sakura Paper Void; do
		gtk-update-icon-cache -q -f -t "$DEST/Ultimit-$t" 2>/dev/null || true
	done
fi
printf 'Ultimit-%s%s\n' "$(printf %s "$skin" | cut -c1 | tr a-z A-Z)" "$(printf %s "$skin" | cut -c2-)"
