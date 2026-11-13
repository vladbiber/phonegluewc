#!/usr/bin/env python3
"""Adds a fake touchscreen to a COPY of phonegluewc.c: PHONEGLUEWC_FAKETOUCH names a script
played one line per tick. Lines: d ID X Y | m ID X Y | u ID | c ID | f | w MS | p LABEL | x CMD
| M X Y | B 0/1 | F 0/1 (a fake mouse and F4, for the laptop test mode)"""
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('#include <wlr/types/wlr_touch.h>\n',
    '#include <wlr/types/wlr_touch.h>\n#include <wlr/interfaces/wlr_touch.h>\n#include <wlr/interfaces/wlr_keyboard.h>\n#include <wlr/interfaces/wlr_pointer.h>\n', 1)
hook = r'''
static struct wlr_touch ft;
static struct wlr_pointer fp;
static const struct wlr_pointer_impl fp_impl = { .name = "fake-mouse" };
static struct wlr_keyboard fk;
static const struct wlr_keyboard_impl fk_impl = { .name = "fake-keys" };
static const struct wlr_touch_impl ft_impl = { .name = "fake-touch" };
static FILE *ft_script;
static struct wl_event_source *ft_timer;
static uint32_t ft_time = 1000;
static const char *ft_counts(void)
{
	static char b[32];
	Client *c;
	int n[NUMWS] = {0}, i;

	wl_list_for_each(c, &clients, link)
		if (c->mon == selmon && c->ws < NUMWS)
			n[c->ws]++;
	for (i = 0; i < NUMWS; i++)
		b[i] = (char)('0' + n[i]);
	b[NUMWS] = 0;
	return b;
}
static int ft_suspended(void)
{
	Client *c;
	int n = 0;

	wl_list_for_each(c, &clients, link)
		n += !client_is_x11(c) && c->surface.xdg->toplevel->scheduled.suspended;
	return n;
}
static int ft_layerh(const char *ns)
{
	LayerSurface *l;

	if (!selmon)
		return 0;
	wl_list_for_each(l, &selmon->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link)
		if (l->mapped && l->layer_surface->namespace && !strcmp(l->layer_surface->namespace, ns))
			return l->layer_surface->current.actual_height;
	return 0;
}
static int ft_layer(const char *ns)
{
	LayerSurface *l;

	if (!selmon)
		return 0;
	wl_list_for_each(l, &selmon->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link)
		if (l->mapped && l->layer_surface->namespace && !strcmp(l->layer_surface->namespace, ns))
			return l->scene->node.enabled ? 1 : 0;
	return 0;
}
#define FT_BOX(b) (b).x, (b).y, (b).width, (b).height
/* every box the frame test asserts on, in logical px */
static void ft_geom(const char *label)
{
	Client *c;
	LayerSurface *l;
	Monitor *m = selmon;
	int i;

	if (!m)
		return;
	fprintf(stderr, "GEOM %s mon closes=%d m=%d,%d,%d,%d w=%d,%d,%d,%d scale=%.3f tf=%d res=%dx%d ws=%u ov=%d card=%d,%d,%d,%d card0=%d,%d,%d,%d card2=%d,%d,%d,%d st=%d,%d,%d,%d,%d,%d,%d\n", label, wl_list_length(&close_anims),
			FT_BOX(m->m), FT_BOX(m->w), m->wlr_output->scale, m->wlr_output->transform,
			m->wlr_output->width, m->wlr_output->height, m->ws, overview_visible, FT_BOX(m->overview[1]), FT_BOX(m->overview[0]), FT_BOX(m->overview[2]),
			touch_gesture, touch_n, m->overview_animating, overview_dragging, wsdrag.active, glide.m != NULL, overview_drag_cmd != NULL);
	for (i = 0; i < NUMWS; i++) {
		struct wlr_box g;

		if (GRIDLT(m) && gridcard(m, (unsigned int)i, &g))
			fprintf(stderr, "GEOM %s grid ws=%d box=%d,%d,%d,%d wide=%d scroll=%.0f\n", label, i, FT_BOX(g), gridwide(m, (unsigned int)i), grid_scroll);
	}
	wl_list_for_each(c, &clients, link) {
		struct wlr_box b = overviewwindowbox(m, c, &m->overview[1]);
		fprintf(stderr, "GEOM %s client title=%s ws=%u geom=%d,%d,%d,%d surf=%d,%d fs=%d shown=%d cardwin=%d,%d,%d,%d fit=%.3f anim=%d,%.2f,%.2f node=%d,%d\n", label,
				client_get_title(c) ? client_get_title(c) : "-", c->ws, FT_BOX(c->geom),
				client_surface(c)->current.width, client_surface(c)->current.height,
				c->isfullscreen, c->scene->node.enabled, FT_BOX(b), c->fit, c->anim.active, c->anim.t, c->anim.zoom ? c->anim.scale : 1.0f, c->scene->node.x, c->scene->node.y);
	}
	for (i = 0; i < 4; i++)
		wl_list_for_each(l, &m->layers[i], link)
			if (l->mapped)
				fprintf(stderr, "GEOM %s layer ns=%s lyr=%d box=%d,%d,%d,%d excl=%d\n", label,
						l->layer_surface->namespace, i, l->scene->node.x, l->scene->node.y,
						l->layer_surface->current.actual_width, l->layer_surface->current.actual_height,
						l->layer_surface->current.exclusive_zone);
}
static int ft_tick(void *data)
{
	char line[1024], label[64];
	int id, wait = 16;
	double x, y;

	ft_time += 16;
	if (!fgets(line, sizeof line, ft_script)) {
		fprintf(stderr, "FT done\n");
		return 0;
	}
	if (sscanf(line, "d %d %lf %lf", &id, &x, &y) == 3) {
		struct wlr_touch_down_event e = { &ft, ft_time, id, x, y };
		wl_signal_emit_mutable(&ft.events.down, &e);
	} else if (sscanf(line, "m %d %lf %lf", &id, &x, &y) == 3) {
		struct wlr_touch_motion_event e = { &ft, ft_time, id, x, y };
		wl_signal_emit_mutable(&ft.events.motion, &e);
	} else if (sscanf(line, "u %d", &id) == 1) {
		struct wlr_touch_up_event e = { &ft, ft_time, id };
		wl_signal_emit_mutable(&ft.events.up, &e);
	} else if (sscanf(line, "c %d", &id) == 1) {
		struct wlr_touch_cancel_event e = { &ft, ft_time, id };
		wl_signal_emit_mutable(&ft.events.cancel, &e);
	} else if (sscanf(line, "F %d", &id) == 1) {
		mouse_four = id;
	} else if (sscanf(line, "M %lf %lf", &x, &y) == 2) {
		struct wlr_pointer_motion_absolute_event e = { &fp, ft_time, x, y };
		wl_signal_emit_mutable(&fp.events.motion_absolute, &e);
	} else if (sscanf(line, "B %d", &id) == 1) {
		struct wlr_pointer_button_event e = { &fp, ft_time, BTN_LEFT,
			id ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED };
		wl_signal_emit_mutable(&fp.events.button, &e);
	} else if (sscanf(line, "K %d %d", &id, &wait) == 2) {
		struct wlr_keyboard_key_event e = { ft_time, id, true,
			wait ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED };
		wlr_keyboard_notify_key(&fk, &e);
		wait = 16;
	} else if (sscanf(line, "g %63s", label) == 1) {
		ft_geom(label);
	} else if (line[0] == 'D') {
		if (active_text_input)
			imdeactivate(active_text_input);
	} else if (line[0] == 'R') {
		reloadconfig(NULL);
	} else if (line[0] == 's') {
		togglefullscreen(NULL);
	} else if (line[0] == 'k') {
		if (shell_pid > 0)
			kill(shell_pid, SIGKILL);
	} else if (line[0] == 'f') {
		wl_signal_emit_mutable(&ft.events.frame, NULL);
	} else if (sscanf(line, "w %d", &wait) == 1) {
		ft_time += wait;
	} else if (line[0] == 'x') {
		line[strcspn(line, "\n")] = 0;
		Arg a = {.v = (const char *[]){ "/bin/sh", "-c", line + 2, NULL }};
		spawn(&a);
	} else if (sscanf(line, "p %63s", label) == 1) {
		fprintf(stderr, "FT %s ws=%u overview=%d visible=%d fingers=%d gesture=%d emu=%d cursor=%.0f,%.0f pts0=%.0f,%.0f focus=%s caps=%u dim=%.2f counts=%s pill=%d card=%d,%d tray=%d menu=%d kbd=%d menuh=%d locked=%d lock=%d pin=%d edge=%d,%d,%d,%d bar=%d,%.2f menuseq=%u editseq=%u sus=%d\n",
			label, selmon ? selmon->ws : 99, overview_active, overview_visible, touch_n,
			touch_gesture, touch_emu, cursor->x, cursor->y, touch_pts[0].x, touch_pts[0].y,
			focustop(selmon) ? client_get_title(focustop(selmon)) : "-", seat->capabilities,
			selmon ? selmon->overview_dim : 0.0f, ft_counts(), pill ? pill->node.y : -1,
			selmon ? selmon->overview[1].width : 0, selmon ? selmon->overview[1].x : 0, ft_layer("phone-tray"), ft_layer("phone-menu"), ft_layer("phone-keyboard"), ft_layerh("phone-menu"), locked, cur_lock != NULL, ft_layer("phone-pin"), edge_node && edge_node->node.enabled, edge_armed, edge_node ? edge_node->node.x : 0, edge_node ? edge_node->dst_width : 0, bar_shown, bar_t, menuseq, editseq, ft_suspended());
	}
	wl_event_source_timer_update(ft_timer, wait);
	return 0;
}
static void ft_start(void)
{
	const char *path = getenv("PHONEGLUEWC_FAKETOUCH");

	if (!path || !(ft_script = fopen(path, "r")))
		return;
	wlr_touch_init(&ft, &ft_impl, "fake-touch");
	inputdevice(NULL, &ft.base);
	wlr_pointer_init(&fp, &fp_impl, "fake-mouse");
	inputdevice(NULL, &fp.base);
	wlr_keyboard_init(&fk, &fk_impl, "fake-keys");
	createkeyboard(&fk);
	ft_timer = wl_event_loop_add_timer(wl_display_get_event_loop(dpy), ft_tick, NULL);
	wl_event_source_timer_update(ft_timer, 2500);
}
'''
s = s.replace('\nvoid\nrun(char *startup_cmd)\n', hook + '\nvoid\nrun(char *startup_cmd)\n', 1)
a = 'void\nrun(char *startup_cmd)\n{\n'
assert s.count(a) == 1
s = s.replace(a, a + '\tft_start();\n', 1)
# how long the software renderer takes for a frame, and how far apart frames are
c = '\n\twlr_scene_output_commit(m->scene_output, NULL);\n\nskip:\n'
assert s.count(c) == 1
s = s.replace(c, """
	{
		static double last, lastcpu;
		extern void *dlsym(void *, const char *);
		static void (*finish)(void);
		struct timespec fa, fb, fc;
		int log = getenv("PHONEGLUEWC_FRAMELOG") != NULL;
		if (log && !finish)
			finish = (void (*)(void))dlsym(NULL, "glFinish");
		clock_gettime(CLOCK_MONOTONIC, &fa);
		wlr_scene_output_commit(m->scene_output, NULL);
		/* software GL draws on its own threads: wait for it, or this only times the queueing */
		if (log && finish)
			finish();
		clock_gettime(CLOCK_MONOTONIC, &fb);
		clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &fc);
		double fs = fa.tv_sec * 1e3 + fa.tv_nsec / 1e6, cpu = fc.tv_sec * 1e3 + fc.tv_nsec / 1e6;
		if (log)
			fprintf(stderr, "FRAME commit=%.2f gap=%.2f cpu=%.2f gl=%d\\n", fb.tv_sec * 1e3 + fb.tv_nsec / 1e6 - fs, fs - last, cpu - lastcpu, finish != NULL);
		last = fs;
		lastcpu = cpu;
	}

skip:
""", 1)
open(p, 'w').write(s)
