#!/system/bin/sh
# Late-start service: runs after every boot once the system is up.
PKG=org.ultimit.launcher
STATE=/data/adb/ultimit
mkdir -p "$STATE"
LOG=$STATE/ultimit.log

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 5

{
  echo "== $(date) =="
  if ! pm path "$PKG" >/dev/null 2>&1; then echo "launcher not installed"; exit 0; fi

  # Default home. Only set it if nothing else was chosen since, so picking another
  # launcher in Settings sticks. Delete /data/adb/ultimit/home_set to force it again.
  if [ ! -f /data/adb/ultimit/home_set ]; then
    cmd package set-home-activity --user 0 "$PKG/.MainActivity" && touch /data/adb/ultimit/home_set
  fi

  # Ticker, Mailer, News and the Audio now-playing card read notifications and media sessions.
  cmd notification allow_listener "$PKG/$PKG.TickerListener"
  # Play time in Games.
  appops set "$PKG" GET_USAGE_STATS allow
  # System colors: on first boot after install, switch Android's Material You palette
  # (quick settings, shade, Settings, dynamic-color apps) to the Mine skin and dark mode.
  # After that the launcher keeps it in step with the chosen skin. Delete
  # /data/adb/ultimit/palette_set to re-apply.
  if [ ! -f /data/adb/ultimit/palette_set ]; then
    SDK=$(getprop ro.build.version.sdk)
    if [ "$SDK" -ge 34 ]; then STYLE=MONOCHROMATIC; elif [ "$SDK" -ge 33 ]; then STYLE=SPRITZ; else STYLE=TONAL_SPOT; fi
    SRC=""; [ "$SDK" -ge 33 ] && SRC='"android.theme.customization.color_source":"preset",'
    TS=$(date +%s)000
    settings put secure theme_customization_overlay_packages "{\"android.theme.customization.system_palette\":\"FFD4EBFF\",\"android.theme.customization.accent_color\":\"FFD4EBFF\",$SRC\"android.theme.customization.theme_style\":\"$STYLE\",\"_applied_timestamp\":$TS}" \
      && cmd uimode night yes \
      && touch /data/adb/ultimit/palette_set
    echo "palette: Mine, $STYLE"
  fi
  echo "ok"
} >> "$LOG" 2>&1
