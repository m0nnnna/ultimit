# Ultimit keybindings

All compositor keybindings live in one table: `compositor/src/keys.c` (`bindings[]`).
Edit it to add or change a shortcut; `ultimitctl keys` prints it as JSON (for a cheat sheet),
and this page is generated from that output (`scripts/gen-keybindings.py`). "Gesture" rows are
documentation only; their behaviour is implemented elsewhere (input.c, alttab.c).


## Windows

| Keys | Action |
|---|---|
| Alt+Tab | Switch windows (hold Alt, Tab to step, release to go) |
| Alt+Shift+Tab | Switch windows, backwards |
| Super+Tab | Switch windows (same as Alt+Tab) |
| Super+Shift+Tab | Switch windows, backwards |
| Escape | Cancel the window switcher (while it is open) |
| Alt+F4 | Close window |
| Super+Left | Snap left (repeat: next snap width, Settings > Windows; Super+Right restores) |
| Super+Right | Snap right (repeat: next snap width, Settings > Windows; Super+Left restores) |
| Super+Up | Maximize |
| Super+Down | Restore a snapped/maximized window, otherwise minimize |
| Alt+F10 | Maximize / restore |
| Alt+F11 | Fullscreen |
| Super+F | Fullscreen |
| Super+D | Show desktop (minimize all; press again to restore) |
| Drag titlebar to a screen edge | Snap to that side (first snap width); the top edge maximizes |
| Alt/Super + left drag | Move a window from anywhere |
| Alt/Super + right drag | Resize a window from anywhere |

## Apps

| Keys | Action |
|---|---|
| Ctrl+Alt+T | Open a terminal |
| Super+E | Open DATA (files) |
| Super+R | Open the launcher |
| Super+V | Clipboard history (Enter pastes, P pins) |
| Super+/ | Show these keyboard shortcuts |
| Super (tap) | Open the launcher when Super is tapped on its own |

## Session

| Keys | Action |
|---|---|
| Super+L | Lock the screen |
| Super+Shift+S | Screenshot a region |
| Super+Shift+R | Record a region (press again to stop and save) |
| Super+Alt+R | Record the screen (press again to stop and save) |
| PrtSc | Screenshot the screen |
| Ctrl+Alt+Delete | Open TASKS, the task manager |
| Ctrl+Alt+Backspace | Quit Ultimit (log out) |
| Ctrl+Alt+F1..F12 | Switch virtual terminal |

## Media

| Keys | Action |
|---|---|
| Volume up key | Volume up |
| Volume down key | Volume down |
| Mute key | Mute |
| Mic mute key | Mute microphone |
| Brightness up key | Brightness up |
| Brightness down key | Brightness down |
| Play key | Play / pause |
| Pause key | Play / pause |
| Next track key | Next track |
| Previous track key | Previous track |
