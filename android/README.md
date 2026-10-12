# Ultimit for Android

The Ultimit desktop as an Android home screen, built for the Surface Duo 2 and fine
on any Android 12+ phone. Native Kotlin and Jetpack Compose; the look is ported
straight from [`docs/design/mockup.html`](../docs/design/mockup.html).

## Install

Every push that touches `android/` builds in GitHub Actions. Open the latest
**Android launcher** run and download the `ultimit-android-<n>` artifact. It holds:

- `UltimitLauncher-<n>.apk`: the launcher on its own. Install it, press Home, pick Ultimit.
- `Ultimit-magisk-<n>.zip`: flash in Magisk and reboot. Installs the launcher as a
  system app, makes it the default home, and grants notification and usage access.
  See [`magisk/README.md`](magisk/README.md).

## What maps to what

| Rail | On the phone |
|---|---|
| GAMES | Installed games (Play category + emulators, Steam Link…), play time and last played |
| MAILER | Mail and messaging apps, plus an inbox of their live notifications |
| NEWS | News readers and browsers, plus a feed of every other notification |
| AUDIO | Now playing from any media app with prev / play / next, plus music and video apps |
| DATA | File, gallery and productivity apps, and internal storage use |
| ACCESSORY | Skins, wallpaper, root options, and everything else |

Long-press any app to open it, see app info, uninstall, or **move it to another rail**.

## Gestures

- Swipe up on the wallpaper, or tap the emblem: all apps with search.
- Swipe down on the wallpaper: notification shade.
- Double-tap the wallpaper: screen off (root).
- Long-press the emblem: replay the boot sequence.
- Back closes the top window. Home while home closes them all.

## Surface Duo 2

Span the launcher across both screens and each screen becomes its own pane: the rail
and orbit shortcuts sit on the left screen, windows open on whichever screen is free,
and `[ → ]` or a sideways drag on a title bar moves a window to the other screen. On one
screen it switches to the mockup's phone layout with the bottom rail.

## Root

All root features are optional and use Magisk's `su`:

- **Accessory → Set up (root)**: default home, notification listener, usage access.
- **Accessory → Match Android colors to skin**: writes Android's Material You palette
  (`theme_customization_overlay_packages`), so quick settings, the shade, Settings and
  dynamic-color apps follow the skin. Mine uses the monochrome style on Android 14+.
  Optionally flips dark / light mode to match (Silver is the light skin).

## Build locally

```sh
gradle -p android assembleRelease   # Gradle 8.10+, JDK 17, Android SDK 35
```

Fonts are Michroma, Chakra Petch and Share Tech Mono, bundled under the SIL Open Font
License (see `fonts-license/`).
