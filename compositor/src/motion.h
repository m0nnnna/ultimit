/* motion.h - the compositor's half of the shell's motion scale (shell/Theme.qml motion.*):
 * fast 100 / base 180 / slow 280 ms. Durations of 280 use OutQuint, the rest OutCubic.
 * Window animations (anim.c) and the focus fade / accent sweep (decoration.c) take their
 * timings from here so the chrome moves at the same speed as the shell. */
#ifndef UL_MOTION_H
#define UL_MOTION_H

#define UL_MOTION_FAST 100
#define UL_MOTION_BASE 180
#define UL_MOTION_SLOW 280

/* open: accent line draws out, the content wipes down; 280 ms in all, OutQuint */
#define UL_OPEN_LINE_MS   100
#define UL_OPEN_WIPE_AT   60   /* the line is ~99 % out by then */
#define UL_OPEN_WIPE_MS   (UL_MOTION_SLOW - UL_OPEN_WIPE_AT)
/* close: content wipes up, then the line retracts; 180 ms in all, OutCubic */
#define UL_CLOSE_WIPE_MS  110
#define UL_CLOSE_LINE_MS  (UL_MOTION_BASE - UL_CLOSE_WIPE_MS)
/* minimize / restore: 280 ms, OutQuint. Maximize / snap morph: 180 ms, OutCubic. */
#define UL_MINIMIZE_MS    UL_MOTION_SLOW
#define UL_MORPH_MS       UL_MOTION_BASE
/* focus border fade (OutCubic) and the accent sweep across the titlebar (OutQuint) */
#define UL_FOCUS_MS       UL_MOTION_FAST
#define UL_SWEEP_MS       UL_MOTION_SLOW

static inline double ul_clamp01(double t) { return t < 0 ? 0 : (t > 1 ? 1 : t); }

/* Ease-out cubic, close to the mockup's cubic-bezier(.2,.8,.2,1). */
static inline double ul_ease_out_cubic(double t) {
	double u = 1 - ul_clamp01(t);
	return 1 - u * u * u;
}

/* Ease-out quint: the long, soft landing used for the 280 ms motions. */
static inline double ul_ease_out_quint(double t) {
	double u = 1 - ul_clamp01(t);
	return 1 - u * u * u * u * u;
}

#endif
