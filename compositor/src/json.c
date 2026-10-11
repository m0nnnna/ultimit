/* json.c: the tiny JSON writer shared by ipc.c and keys.c. */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include "json.h"

void put(struct out *o, const char *fmt, ...) {
	va_list ap;
	for (;;) {
		va_start(ap, fmt);
		int n = vsnprintf(o->data + o->len, o->cap - o->len, fmt, ap);
		va_end(ap);
		if (n >= 0 && (size_t)n < o->cap - o->len) {
			o->len += n;
			return;
		}
		o->cap = o->cap ? o->cap * 2 : 4096;
		o->data = realloc(o->data, o->cap);
	}
}

void put_str(struct out *o, const char *s) {
	put(o, "\"");
	for (; s && *s; s++) {
		unsigned char c = *s;
		if (c == '"' || c == '\\') put(o, "\\%c", c);
		else if (c < 0x20) put(o, "\\u%04x", c);
		else put(o, "%c", c);
	}
	put(o, "\"");
}

void put_box(struct out *o, struct wlr_box b) {
	put(o, "{\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d}", b.x, b.y, b.width, b.height);
}

