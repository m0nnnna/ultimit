# Ultimit Magisk module

Built by CI into `Ultimit-magisk-<run>.zip`. Flash it in Magisk, reboot.

What it does:

- Installs the launcher as a system app (`/system/app/UltimitLauncher`). It is a plain
  system app, not priv-app, so no privileged-permission allowlist can block boot.
- On every boot (`service.sh`): makes Ultimit the default home once, grants its
  notification listener and usage access. Log: `/data/adb/modules/ultimit/ultimit.log`.
- Your stock launcher stays installed. If Ultimit ever breaks, pick the stock one in
  Settings → Apps → Default apps → Home app, or disable the module in Magisk.

System colors: turn on **Accessory → Match Android colors to skin** in the launcher. It
writes Android's Material You palette (the same setting the wallpaper picker uses), so
quick settings, the notification shade, Settings and dynamic-color apps follow the skin.
Uninstalling the module hands the palette back to the wallpaper picker.
