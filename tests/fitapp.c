/* fitapp - a window that will not go below a width.  Red right column, green left, a blue
 * subsurface near the right edge, a yellow popup on a tap in the lower half; prints what it gets.
 * FIT_MIN declares the minimum, FIT_BIG only insists on it by committing that wide. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "touchlog-xdg-protocol.h"

static struct wl_compositor *comp;
static struct wl_subcompositor *subcomp;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct xdg_wm_base *wm;
static struct xdg_surface *xs;
static struct xdg_toplevel *tl;
static struct wl_surface *surface, *sub, *pop;
static struct wl_subsurface *subs;
static struct wl_touch *touch;
static int minw, bigw, w = 640, h = 480;
#define RED 0xffe02020u
#define GREEN 0xff20e020u
#define BLUE 0xff2020e0u
#define YELLOW 0xffe0e020u
#define GREY 0xff505050u

static void fill(struct wl_surface *s, int bw, int bh, unsigned c, int columns)
{
	int fd = memfd_create("fitapp", 0), x, y, n = bw * bh * 4;
	unsigned *p;
	struct wl_shm_pool *pool;
	struct wl_buffer *b;

	ftruncate(fd, n);
	p = mmap(NULL, n, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	for (y = 0; y < bh; y++)
		for (x = 0; x < bw; x++)
			p[y * bw + x] = columns && x >= bw - 20 ? RED : columns && x < 20 ? GREEN : c;
	munmap(p, n);
	pool = wl_shm_create_pool(shm, fd, n);
	b = wl_shm_pool_create_buffer(pool, 0, bw, bh, bw * 4, WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	wl_surface_attach(s, b, 0, 0);
	wl_surface_damage_buffer(s, 0, 0, bw, bh);
}

static void draw(void)
{
	wl_subsurface_set_position(subs, w - 100, 100);
	fill(surface, w, h, GREY, 1);
	wl_surface_commit(surface);
}

static void p_configure(void *d, struct xdg_surface *s, uint32_t serial)
{
	xdg_surface_ack_configure(s, serial);
	fill(pop, 100, 60, YELLOW, 0);
	wl_surface_commit(pop);
}
static const struct xdg_surface_listener ps_l = { p_configure };
static void pp_configure(void *d, struct xdg_popup *p, int32_t x, int32_t y, int32_t pw, int32_t ph)
{ printf("popup at %d %d %d %d\n", x, y, pw, ph); fflush(stdout); }
static void pp_done(void *d, struct xdg_popup *p) {}
static void pp_repos(void *d, struct xdg_popup *p, uint32_t t) {}
static const struct xdg_popup_listener pp_l = { pp_configure, pp_done, pp_repos };

static void openpopup(int x, int y)
{
	struct xdg_positioner *q = xdg_wm_base_create_positioner(wm);
	struct xdg_surface *ps;
	struct xdg_popup *p;

	xdg_positioner_set_size(q, 100, 60);
	xdg_positioner_set_anchor_rect(q, x, y, 1, 1);
	xdg_positioner_set_anchor(q, XDG_POSITIONER_ANCHOR_BOTTOM_RIGHT);
	xdg_positioner_set_gravity(q, XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT);
	xdg_positioner_set_constraint_adjustment(q, XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X
			| XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y);
	pop = wl_compositor_create_surface(comp);
	ps = xdg_wm_base_get_xdg_surface(wm, pop);
	xdg_surface_add_listener(ps, &ps_l, NULL);
	p = xdg_surface_get_popup(ps, xs, q);
	xdg_popup_add_listener(p, &pp_l, NULL);
	xdg_positioner_destroy(q);
	wl_surface_commit(pop);
}

static void t_down(void *d, struct wl_touch *t, uint32_t serial, uint32_t time,
		struct wl_surface *s, int32_t id, wl_fixed_t fx, wl_fixed_t fy)
{
	int x = wl_fixed_to_int(fx), y = wl_fixed_to_int(fy);

	printf("%s down %d %d\n", s == sub ? "sub" : s == surface ? "body" : "popup", x, y);
	fflush(stdout);
	if (s == surface && y > h / 2)
		openpopup(x, y);
}
static void t_up(void *d, struct wl_touch *t, uint32_t serial, uint32_t time, int32_t id) {}
static void t_motion(void *d, struct wl_touch *t, uint32_t time, int32_t id, wl_fixed_t x, wl_fixed_t y)
{ printf("motion %d %d\n", wl_fixed_to_int(x), wl_fixed_to_int(y)); fflush(stdout); }
static void t_frame(void *d, struct wl_touch *t) {}
static void t_cancel(void *d, struct wl_touch *t) {}
static void t_shape(void *d, struct wl_touch *t, int32_t id, wl_fixed_t a, wl_fixed_t b) {}
static void t_orient(void *d, struct wl_touch *t, int32_t id, wl_fixed_t o) {}
static const struct wl_touch_listener touch_l = { t_down, t_up, t_motion, t_frame, t_cancel, t_shape, t_orient };

static void seat_caps(void *d, struct wl_seat *s, uint32_t caps)
{
	if ((caps & WL_SEAT_CAPABILITY_TOUCH) && !touch) {
		touch = wl_seat_get_touch(s);
		wl_touch_add_listener(touch, &touch_l, NULL);
	}
}
static void seat_name(void *d, struct wl_seat *s, const char *n) {}
static const struct wl_seat_listener seat_l = { seat_caps, seat_name };
static void wm_ping(void *d, struct xdg_wm_base *b, uint32_t serial) { xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_l = { wm_ping };

static int configured;
static void xs_configure(void *d, struct xdg_surface *s, uint32_t serial)
{
	configured = 1;
	xdg_surface_ack_configure(s, serial);
	draw();
	printf("size %d %d\n", w, h);
	fflush(stdout);
}
static const struct xdg_surface_listener xs_l = { xs_configure };
static void tl_configure(void *d, struct xdg_toplevel *t, int32_t cw, int32_t ch, struct wl_array *st)
{
	if (cw > 0 && ch > 0) {
		w = cw < minw ? minw : cw < bigw ? bigw : cw;
		h = ch;
	}
}
static void tl_close(void *d, struct xdg_toplevel *t) {}
static void tl_bounds(void *d, struct xdg_toplevel *t, int32_t a, int32_t b) {}
static void tl_caps(void *d, struct xdg_toplevel *t, struct wl_array *c) {}
static const struct xdg_toplevel_listener tl_l = { tl_configure, tl_close, tl_bounds, tl_caps };

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver)
{
	if (!strcmp(iface, "wl_compositor"))
		comp = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	else if (!strcmp(iface, "wl_subcompositor"))
		subcomp = wl_registry_bind(r, name, &wl_subcompositor_interface, 1);
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

int main(void)
{
	struct wl_display *dpy = wl_display_connect(NULL);

	if (!dpy)
		return 1;
	minw = getenv("FIT_MIN") ? atoi(getenv("FIT_MIN")) : 0;
	bigw = getenv("FIT_BIG") ? atoi(getenv("FIT_BIG")) : 0;
	wl_registry_add_listener(wl_display_get_registry(dpy), &reg_l, NULL);
	wl_display_roundtrip(dpy);
	surface = wl_compositor_create_surface(comp);
	xs = xdg_wm_base_get_xdg_surface(wm, surface);
	xdg_surface_add_listener(xs, &xs_l, NULL);
	tl = xdg_surface_get_toplevel(xs);
	xdg_toplevel_add_listener(tl, &tl_l, NULL);
	xdg_toplevel_set_title(tl, "fitapp");
	xdg_toplevel_set_app_id(tl, "fitapp");
	if (minw)
		xdg_toplevel_set_min_size(tl, minw, 0);
	sub = wl_compositor_create_surface(comp);
	subs = wl_subcompositor_get_subsurface(subcomp, sub, surface);
	wl_subsurface_set_desync(subs);
	fill(sub, 60, 60, BLUE, 0);
	wl_surface_commit(sub);
	wl_surface_commit(surface);
	if (bigw)
		for (;;) {
			usleep(200000);
			wl_display_dispatch_pending(dpy);
			if (configured)
				draw();
			if (wl_display_roundtrip(dpy) < 0)
				return 0;
		}
	while (wl_display_dispatch(dpy) != -1);
	return 0;
}
