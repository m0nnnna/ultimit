# Ultimit icon theme

Four freedesktop icon themes, one per skin: `Ultimit-Mine`, `Ultimit-Amber`, `Ultimit-Silver`,
`Ultimit-Verdant`. Thin 1.5 px strokes on a 48 px grid, chamfered corners, translucent accent
fill, hex / corner-bracket motifs. Original artwork.

    make-templates.py   authoring tool: writes templates/<context>/<name>.svg (placeholder colours)
    templates/          the SVG sources ({accent} {fg} {dim} {fill} {fillop} {folder})
    build-icons.py      substitutes the per-skin palette -> OUTDIR/Ultimit-<Skin>/ (stdlib python3)
    install-icons.sh    builds into $DEST (default ~/.local/share/icons), prints the theme name
    contact-sheet.qml   renders a built theme (see its header) for visual checks

Layout of a built theme: `index.theme`, `names.json`, `scalable/{apps,places,devices,mimetypes}/`,
`symbolic/{apps,places,devices}/*-symbolic.svg`. Aliases are relative symlinks. Inherits
`Yaru-dark,Adwaita,hicolor` (Silver: `Yaru,Adwaita,hicolor`), so undrawn icons fall back.

## How the shell picks the icons (and why it can change them live)
* `Quickshell.iconPath()` goes through the Qt icon theme, which Quickshell sets once from
  `QS_ICON_THEME` at startup. There is no QML API to change it at runtime, so a skin switch
  could not re-skin icons that way.
* Chosen: `shell/Icons.qml` reads `names.json` of the *current* skin
  (`~/.local/share/icons/Ultimit-<Skin>/`, honouring `XDG_DATA_HOME` / `ULTIMIT_ICON_HOME`) and
  returns `file://` URLs into it; the URL is a binding on `Theme.skin`, so the icons change the
  moment the skin does. Names the theme does not draw fall back to `Quickshell.iconPath()`, i.e.
  `QS_ICON_THEME` and its Inherits chain, so third-party app icons are unaffected. If the theme is
  not installed everything degrades to plain `iconPath()`.
* Before `iconPath()`, `Icons.qml` also checks icons an app installed for the user
  (`$XDG_DATA_HOME/icons/hicolor`, rescanned when desktop entries change). Qt would pick
  `/usr/share`'s hicolor copy instead, which for Steam is the cardboard-box stand-in from Ubuntu's
  `steam-installer`; Steam links its real icon (and `steam_icon_<appid>` for games) into the user
  directory. Windows of running Steam games (class `steam_app_<appid>`) get the game's icon, else Steam's.
* App icons in the launcher, window list, Alt-Tab and pins go through `Icons.app()`: with
  Settings > Appearance > Other apps' icons = Letters (the default) only names this theme draws
  resolve, and every other app gets a letter tile in the skin's colours; Original uses `Icons.path()`.
* `QS_ICON_THEME` (theme/session-env.sh) still matters for native lookups: launcher entries,
  tray, notifications of other processes. It is set to `Ultimit-<skin>` at session start; it is not
  updated on a live switch (those lookups keep the start-up skin's colours until the next login).
* GTK apps read `gsettings org.gnome.desktop.interface icon-theme`. The session should run
  `gsettings set org.gnome.desktop.interface icon-theme "$QS_ICON_THEME"` once (the scripts in this
  directory never touch gsettings).
