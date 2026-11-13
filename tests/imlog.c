/* Minimal input method: commits argv[1] each time a text field activates it. */
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>
#include "input-method-protocol.h"

static struct wl_seat *seat;
static struct zwp_input_method_manager_v2 *mgr;
static struct zwp_input_method_v2 *im;
static const char *text;
static int pending, active;
static uint32_t serial;

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v)
{
	if (!strcmp(iface, "wl_seat"))
		seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
	else if (!strcmp(iface, "zwp_input_method_manager_v2"))
		mgr = wl_registry_bind(r, name, &zwp_input_method_manager_v2_interface, 1);
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg_lis = { reg_global, reg_remove };

static void activate(void *d, struct zwp_input_method_v2 *i) { active = 1; pending = 1; puts("activate"); }
static void deactivate(void *d, struct zwp_input_method_v2 *i) { active = 0; puts("deactivate"); }
static void surrounding(void *d, struct zwp_input_method_v2 *i, const char *t, uint32_t c, uint32_t a) { printf("surrounding '%s'\n", t); }
static void cause(void *d, struct zwp_input_method_v2 *i, uint32_t c) {}
static void ctype(void *d, struct zwp_input_method_v2 *i, uint32_t h, uint32_t p) { printf("content_type %u %u\n", h, p); }
static void done(void *d, struct zwp_input_method_v2 *i)
{
	serial++;
	if (active && pending) {
		pending = 0;
		zwp_input_method_v2_commit_string(im, text);
		zwp_input_method_v2_commit(im, serial);
		printf("committed %s\n", text);
	}
	fflush(stdout);
}
static void unavailable(void *d, struct zwp_input_method_v2 *i) { puts("unavailable"); }
static const struct zwp_input_method_v2_listener im_lis = { activate, deactivate, surrounding, cause, ctype, done, unavailable };

int main(int argc, char **argv)
{
	struct wl_display *dpy = wl_display_connect(NULL);
	struct wl_registry *reg;

	text = argc > 1 ? argv[1] : "x";
	if (!dpy)
		return 1;
	reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &reg_lis, NULL);
	wl_display_roundtrip(dpy);
	if (!seat || !mgr) {
		puts("no input method manager");
		return 1;
	}
	im = zwp_input_method_manager_v2_get_input_method(mgr, seat);
	zwp_input_method_v2_add_listener(im, &im_lis, NULL);
	puts("ready");
	fflush(stdout);
	while (wl_display_dispatch(dpy) != -1)
		;
	return 0;
}
