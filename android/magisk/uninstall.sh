#!/system/bin/sh
# Undo what Ultimit changed outside its own files.
PKG=org.ultimit.launcher
cmd notification disallow_listener "$PKG/$PKG.TickerListener" 2>/dev/null
# Hand the system palette back to the wallpaper picker if the launcher set it.
case "$(settings get secure theme_customization_overlay_packages)" in
  *_applied_timestamp*) settings delete secure theme_customization_overlay_packages ;;
esac
rm -rf /data/adb/ultimit
