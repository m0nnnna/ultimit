# Runs inside Magisk's installer.
SKIPUNZIP=0

ui_print "  [ ULTIMIT ]  operating system · mine"
ui_print "  - launcher goes to /system/app/UltimitLauncher"

if [ ! -f "$MODPATH/system/app/UltimitLauncher/UltimitLauncher.apk" ]; then
  abort "  ! UltimitLauncher.apk missing. Use the zip built by CI, not the source folder."
fi

if [ "$API" -lt 31 ]; then
  abort "  ! Android 12 or newer is required (this device is API $API)."
fi

ui_print "  - your stock launcher is left installed as a fallback"
ui_print "  - reboot, then press Home once if Android asks which launcher to use"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
