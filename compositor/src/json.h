#ifndef ULTIMIT_JSON_H
#define ULTIMIT_JSON_H

#include <stddef.h>
#include <wlr/util/box.h>

/* Growable output buffer; put* append (printf style / escaped string / box). */
struct out {
	char *data;
	size_t len, cap;
};

void put(struct out *o, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void put_str(struct out *o, const char *s);
void put_box(struct out *o, struct wlr_box b);

#endif
