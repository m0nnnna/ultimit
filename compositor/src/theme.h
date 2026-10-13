/*
 * theme.h: the "Mine" skin as the compositor sees it until the shell sends
 * its current skin (ipc "skin"). Mirrors the tokens at
 * the top of docs/design/mockup.html so window chrome matches the shell.
 * Colors are straight RGBA floats; scene rects premultiply on their own.
 */

#ifndef ULTIMIT_THEME_H
#define ULTIMIT_THEME_H

#define UL_RGBA(r, g, b, a) { (r) / 255.0f, (g) / 255.0f, (b) / 255.0f, (a) }

/* Window chrome metrics, in logical pixels. */
#define UL_TITLEBAR_H      38
#define UL_BORDER          1
#define UL_BRACKET_LEN     14
#define UL_BRACKET_W       2
#define UL_SHADOW_SIGMA    24.0f
#define UL_RESIZE_MARGIN   6
#define UL_BUTTON_MIN_W    30 /* titlebar button hit cell */

/* Mine palette. */
#define UL_COLOR_BG            UL_RGBA(5, 6, 7, 1.0f)
#define UL_COLOR_PANEL         UL_RGBA(13, 15, 18, 0.80f)
#define UL_COLOR_PANEL_DIM     UL_RGBA(13, 15, 18, 0.70f)
#define UL_COLOR_FG            UL_RGBA(238, 241, 244, 1.0f)
#define UL_COLOR_DIM           UL_RGBA(141, 148, 158, 1.0f)
#define UL_COLOR_LINE          UL_RGBA(235, 240, 245, 0.16f)
#define UL_COLOR_LINE_STRONG   UL_RGBA(235, 240, 245, 0.48f)
#define UL_COLOR_ACCENT        UL_RGBA(212, 235, 255, 1.0f)
#define UL_COLOR_ACCENT_DIM    UL_RGBA(212, 235, 255, 0.22f)
#define UL_COLOR_BAD           UL_RGBA(255, 138, 138, 1.0f)
#define UL_COLOR_SHADOW        UL_RGBA(0, 0, 0, 0.45f)

/* Fonts (installed from Google Fonts; fontconfig falls back if missing). */
#define UL_FONT_TITLE   "Michroma 11.5"
#define UL_FONT_SUB     "Share Tech Mono 8.5"
#define UL_FONT_BUTTON  "Share Tech Mono 10.5"

#endif
