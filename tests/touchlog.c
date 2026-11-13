/* touchlog - window that prints the touch and pointer events it receives.
 * Usage: touchlog [notouch]   notouch leaves wl_touch unbound */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "touchlog-xdg-protocol.h"

static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct xdg_wm_base *wm;
static struct wl_surface *surface;
static struct wl_touch *touch;
static struct xdg_toplevel *tl;
static struct wl_pointer *pointer;
static int notouch, cfgw = 640, cfgh = 480;

static void t_down(void *d, struct wl_touch *t, uint32_t serial, uint32_t time,
		struct wl_surface *s, int32_t id, wl_fixed_t x, wl_fixed_t y)
{ printf("touch down %d %.0f %.0f\n", id, wl_fixed_to_double(x), wl_fixed_to_double(y)); fflush(stdout);
  if (getenv("TOUCHLOG_LATE_ID")) xdg_toplevel_set_app_id(tl, getenv("TOUCHLOG_LATE_ID")); }
static void t_up(void *d, struct wl_touch *t, uint32_t serial, uint32_t time, int32_t id)
{ printf("touch up %d\n", id); fflush(stdout); }
static void t_motion(void *d, struct wl_touch *t, uint32_t time, int32_t id, wl_fixed_t x, wl_fixed_t y)
{ printf("touch motion %d %.0f %.0f\n", id, wl_fixed_to_double(x), wl_fixed_to_double(y)); fflush(stdout); }
static void t_frame(void *d, struct wl_touch *t) {}
static void t_cancel(void *d, struct wl_touch *t)
{ printf("touch cancel\n"); fflush(stdout); }
static void t_shape(void *d, struct wl_touch *t, int32_t id, wl_fixed_t a, wl_fixed_t b) {}
static void t_orient(void *d, struct wl_touch *t, int32_t id, wl_fixed_t o) {}
static const struct wl_touch_listener touch_l = { t_down, t_up, t_motion, t_frame, t_cancel, t_shape, t_orient };

static void p_enter(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s, wl_fixed_t x, wl_fixed_t y)
{ printf("pointer enter %.0f %.0f\n", wl_fixed_to_double(x), wl_fixed_to_double(y)); fflush(stdout); }
static void p_leave(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s) {}
static void p_motion(void *d, struct wl_pointer *p, uint32_t time, wl_fixed_t x, wl_fixed_t y)
{ printf("pointer motion %.0f %.0f\n", wl_fixed_to_double(x), wl_fixed_to_double(y)); fflush(stdout); }
static void p_button(void *d, struct wl_pointer *p, uint32_t serial, uint32_t time, uint32_t b, uint32_t state)
{ printf("pointer button %u %u\n", b, state); fflush(stdout); }
static void p_axis(void *d, struct wl_pointer *p, uint32_t time, uint32_t a, wl_fixed_t v) {}
static void p_frame(void *d, struct wl_pointer *p) {}
static void p_source(void *d, struct wl_pointer *p, uint32_t s) {}
static void p_stop(void *d, struct wl_pointer *p, uint32_t time, uint32_t a) {}
static void p_discrete(void *d, struct wl_pointer *p, uint32_t a, int32_t v) {}
static const struct wl_pointer_listener pointer_l = { p_enter, p_leave, p_motion, p_button,
	p_axis, p_frame, p_source, p_stop, p_discrete };

static void k_keymap(void *d, struct wl_keyboard *k, uint32_t f, int fd, uint32_t size) { close(fd); }
static void k_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *f, struct wl_array *a) {}
static void k_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *f) {}
static void k_key(void *d, struct wl_keyboard *k, uint32_t s, uint32_t t, uint32_t key, uint32_t state)
{ printf("key %u %u\n", key, state); fflush(stdout); }
static void k_mods(void *d, struct wl_keyboard *k, uint32_t s, uint32_t dep, uint32_t la, uint32_t lo, uint32_t g)
{ printf("mods %u\n", dep); fflush(stdout); }
static void k_repeat(void *d, struct wl_keyboard *k, int32_t r, int32_t de) {}
static const struct wl_keyboard_listener keyboard_l = { k_keymap, k_enter, k_leave, k_key, k_mods, k_repeat };
static struct wl_keyboard *keyboard;

static void seat_caps(void *d, struct wl_seat *s, uint32_t caps)
{
	if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
		keyboard = wl_seat_get_keyboard(s);
		wl_keyboard_add_listener(keyboard, &keyboard_l, NULL);
	}
	if ((caps & WL_SEAT_CAPABILITY_TOUCH) && !touch && !notouch) {
		touch = wl_seat_get_touch(s);
		wl_touch_add_listener(touch, &touch_l, NULL);
	}
	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
		pointer = wl_seat_get_pointer(s);
		wl_pointer_add_listener(pointer, &pointer_l, NULL);
	}
}
static void seat_name(void *d, struct wl_seat *s, const char *n) {}
static const struct wl_seat_listener seat_l = { seat_caps, seat_name };

static void wm_ping(void *d, struct xdg_wm_base *b, uint32_t serial) { xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_l = { wm_ping };

static void attach(int w, int h)
{
	int fd = memfd_create("touchlog", 0), stride = w * 4;
	void *data;
	struct wl_shm_pool *pool;
	struct wl_buffer *buf;

	ftruncate(fd, stride * h);
	data = mmap(NULL, stride * h, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	memset(data, 0x80, stride * h);
	pool = wl_shm_create_pool(shm, fd, stride * h);
	buf = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	wl_surface_attach(surface, buf, 0, 0);
	wl_surface_damage_buffer(surface, 0, 0, w, h);
}

static void xs_configure(void *d, struct xdg_surface *xs, uint32_t serial)
{
	xdg_surface_ack_configure(xs, serial);
	attach(cfgw, cfgh);
	wl_surface_commit(surface);
}
static const struct xdg_surface_listener xs_l = { xs_configure };
static void tl_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *st)
{ if (getenv("TOUCHLOG_CONF")) { printf("conf %d %d\n", w, h); fflush(stdout); } if (w > 0 && h > 0 && !getenv("TOUCHLOG_DIALOG")) { cfgw = w; cfgh = h; } }
static void tl_close(void *d, struct xdg_toplevel *t) { if (getenv("TOUCHLOG_CLOSES")) exit(0); }
static void tl_bounds(void *d, struct xdg_toplevel *t, int32_t w, int32_t h) {}
static void tl_caps(void *d, struct xdg_toplevel *t, struct wl_array *c) {}
static const struct xdg_toplevel_listener tl_l = { tl_configure, tl_close, tl_bounds, tl_caps };

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver)
{
	if (!strcmp(iface, "wl_compositor"))
		comp = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	else if (!strcmp(iface, "wl_shm"))
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	else if (!strcmp(iface, "wl_seat")) {
		seat = wl_registry_bind(r, name, &wl_seat_interface, 5);
		wl_seat_add_listener(seat, &seat_l, NULL);
	} else if (!strcmp(iface, "xdg_wm_base")) {
		wm = wl_registry_bind(r, name, &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(wm, &wm_l, NULL);
	}
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

int main(int argc, char **argv)
{
	struct wl_display *dpy = wl_display_connect(NULL);
	struct xdg_surface *xs;

	notouch = argc > 1 && !strcmp(argv[1], "notouch");
	if (!dpy)
		return 1;
	wl_registry_add_listener(wl_display_get_registry(dpy), &reg_l, NULL);
	wl_display_roundtrip(dpy);
	surface = wl_compositor_create_surface(comp);
	xs = xdg_wm_base_get_xdg_surface(wm, surface);
	xdg_surface_add_listener(xs, &xs_l, NULL);
	tl = xdg_surface_get_toplevel(xs);
	xdg_toplevel_add_listener(tl, &tl_l, NULL);
	xdg_toplevel_set_title(tl, getenv("TOUCHLOG_TITLE") ? getenv("TOUCHLOG_TITLE") : "touchlog");
	xdg_toplevel_set_app_id(tl, getenv("TOUCHLOG_TITLE") ? getenv("TOUCHLOG_TITLE") : "touchlog");
	/* a fixed size dialog with a shadow, as GTK draws it: the window starts well inside the surface */
	if (getenv("TOUCHLOG_DIALOG")) {
		cfgw = 322; cfgh = 230;
		xdg_toplevel_set_min_size(tl, 200, 120);
		xdg_toplevel_set_max_size(tl, 200, 120);
		xdg_surface_set_window_geometry(xs, 61, 55, 200, 120);
	}
	if (getenv("TOUCHLOG_FS"))
		xdg_toplevel_set_fullscreen(tl, NULL);
	wl_surface_commit(surface);
	while (wl_display_dispatch(dpy) != -1);
	return 0;
}
