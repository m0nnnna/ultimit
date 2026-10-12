#!/system/bin/sh
# Late-start service: runs after every boot once the system is up.
PKG=org.ultimit.launcher
LOG=/data/adb/modules/ultimit/ultimit.log

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 5

{
  echo "== $(date) =="
  if ! pm path "$PKG" >/dev/null 2>&1; then echo "launcher not installed"; exit 0; fi

  # Default home. Only set it if nothing else was chosen since, so picking another
  # launcher in Settings sticks. Delete /data/adb/modules/ultimit/home_set to force it again.
  if [ ! -f /data/adb/modules/ultimit/home_set ]; then
    cmd package set-home-activity --user 0 "$PKG/.MainActivity" && touch /data/adb/modules/ultimit/home_set
  fi

  # Ticker, Mailer, News and the Audio now-playing card read notifications and media sessions.
  cmd notification allow_listener "$PKG/$PKG.TickerListener"
  # Play time in Games.
  appops set "$PKG" GET_USAGE_STATS allow
  echo "ok"
} >> "$LOG" 2>&1
