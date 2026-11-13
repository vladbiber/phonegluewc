/* A neutral stand-in for an app: windows (xdg_toplevel), a tray item (StatusNotifierItem) or both, in ONE process.
 * fakeapp [-a APPID] [-n WINDOWS] [-t TRAYID] [-m] [-c] [-T] [-s] [-P]
 *   -m the tray menu has Quit   -c ignores window close   -T ignores SIGTERM   -s stays running with no window left   -P a media player on the bus
 * Every event is appended to $FAKEAPP_LOG as "NAME event".
 * $FAKEAPP_CTL names a file read every 100 ms: "RRGGBB [fs]" paints the top 40 rows that colour and asks for fullscreen. */
#define _GNU_SOURCE
#include <gio/gio.h>
#include <glib-unix.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "touchlog-xdg-protocol.h"

static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct xdg_wm_base *wm;
static int ignoreclose, stay, windows;
static const char *name = "fakeapp", *trayid;
static int menu, badicon;
static GDBusConnection *bus;
static char busname[64];

static void say(const char *what)
{
	const char *p = getenv("FAKEAPP_LOG");
	FILE *f = p ? fopen(p, "a") : NULL;
	if (f) { fprintf(f, "%s %s %d\n", name, what, (int)getpid()); fclose(f); }
}

struct win { struct wl_surface *s; struct xdg_surface *xs; struct xdg_toplevel *tl; int w, h; };
static struct win *first;
static int topset, isfs;
static unsigned topcol;

static void paint(struct win *w)
{
	int stride = w->w * 4, fd = memfd_create("fakeapp", 0);
	void *data;
	struct wl_shm_pool *pool;
	struct wl_buffer *buf;

	ftruncate(fd, stride * w->h);
	data = mmap(NULL, stride * w->h, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	memset(data, 0x60, stride * w->h);
	for (int i = 0; topset && i < w->w * (w->h < 40 ? w->h : 40); i++)
		((unsigned *)data)[i] = topcol;
	pool = wl_shm_create_pool(shm, fd, stride * w->h);
	/* FAKEAPP_ARGB: the 0x60 fill becomes a translucent window, for blur behind it */
	buf = wl_shm_pool_create_buffer(pool, 0, w->w, w->h, stride, getenv("FAKEAPP_ARGB") ? WL_SHM_FORMAT_ARGB8888 : WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	munmap(data, stride * w->h);
	wl_surface_attach(w->s, buf, 0, 0);
	wl_surface_damage_buffer(w->s, 0, 0, w->w, w->h);
	wl_surface_commit(w->s);
}
static void configure(void *d, struct xdg_surface *xs, uint32_t serial)
{
	xdg_surface_ack_configure(xs, serial);
	paint(d);
}
static const struct xdg_surface_listener xs_l = { configure };
static gboolean ctl_poll(gpointer dpy)
{
	char line[64] = "";
	unsigned c;
	int fs;
	FILE *f = fopen(getenv("FAKEAPP_CTL"), "r");

	if (!f || !first)
		return f ? fclose(f), G_SOURCE_CONTINUE : G_SOURCE_CONTINUE;
	if (!fgets(line, sizeof line, f) || sscanf(line, "%x", &c) != 1) {
		fclose(f);
		return G_SOURCE_CONTINUE;
	}
	fclose(f);
	fs = strstr(line, "fs") != NULL;
	if (!topset || c != topcol) {
		topset = 1;
		topcol = c;
		paint(first);
	}
	if (fs != isfs) {
		isfs = fs;
		if (fs)
			xdg_toplevel_set_fullscreen(first->tl, NULL);
		else
			xdg_toplevel_unset_fullscreen(first->tl);
	}
	wl_display_flush(dpy);
	return G_SOURCE_CONTINUE;
}
static void tl_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *st)
{ struct win *x = d; if (w > 0 && h > 0) { x->w = w; x->h = h; } }
static void tl_close(void *d, struct xdg_toplevel *t)
{
	struct win *w = d;
	say("close");
	if (ignoreclose)
		return;
	xdg_toplevel_destroy(w->tl);
	xdg_surface_destroy(w->xs);
	wl_surface_destroy(w->s);
	if (--windows == 0 && !stay && !trayid)
		exit(0);
}
static void tl_bounds(void *d, struct xdg_toplevel *t, int32_t w, int32_t h) {}
static void tl_caps(void *d, struct xdg_toplevel *t, struct wl_array *c) {}
static const struct xdg_toplevel_listener tl_l = { tl_configure, tl_close, tl_bounds, tl_caps };
static void wm_ping(void *d, struct xdg_wm_base *b, uint32_t serial) { xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_l = { wm_ping };
static void reg_global(void *d, struct wl_registry *r, uint32_t n, const char *iface, uint32_t ver)
{
	if (!strcmp(iface, "wl_compositor")) comp = wl_registry_bind(r, n, &wl_compositor_interface, 4);
	else if (!strcmp(iface, "wl_shm")) shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
	else if (!strcmp(iface, "xdg_wm_base")) {
		wm = wl_registry_bind(r, n, &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(wm, &wm_l, NULL);
	}
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg_l = { reg_global, reg_remove };

static gboolean wl_ready(gint fd, GIOCondition c, gpointer d)
{
	if (wl_display_dispatch(d) == -1) {
		say("wayland-gone");
		exit(0);
	}
	wl_display_flush(d);
	return G_SOURCE_CONTINUE;
}

static const char sni_xml[] =
"<node><interface name='org.kde.StatusNotifierItem'>"
"<property name='Category' type='s' access='read'/><property name='Id' type='s' access='read'/>"
"<property name='Title' type='s' access='read'/><property name='Status' type='s' access='read'/>"
"<property name='IconName' type='s' access='read'/><property name='ItemIsMenu' type='b' access='read'/>"
"<property name='Menu' type='o' access='read'/><property name='IconPixmap' type='a(iiay)' access='read'/>"
"<method name='Activate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
"</interface></node>";
static const char menu_xml[] =
"<node><interface name='com.canonical.dbusmenu'>"
"<property name='Version' type='u' access='read'/><property name='Status' type='s' access='read'/>"
"<method name='GetLayout'><arg type='i' direction='in'/><arg type='i' direction='in'/><arg type='as' direction='in'/>"
"<arg type='u' direction='out'/><arg type='(ia{sv}av)' direction='out'/></method>"
"<method name='GetGroupProperties'><arg type='ai' direction='in'/><arg type='as' direction='in'/><arg type='a(ia{sv})' direction='out'/></method>"
"<method name='Event'><arg type='i' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='in'/><arg type='u' direction='in'/></method>"
"<method name='AboutToShow'><arg type='i' direction='in'/><arg type='b' direction='out'/></method>"
"</interface></node>";

/* a plain 32x32 square, ARGB big endian */
static GVariant *icon(void)
{
	static guchar px[32 * 32 * 4];
	GVariantBuilder b;
	for (int i = 0; i < 32 * 32; i++) { px[i * 4] = 0xff; px[i * 4 + 1] = 0x20; px[i * 4 + 2] = 0x80; px[i * 4 + 3] = 0xc0; }
	g_variant_builder_init(&b, G_VARIANT_TYPE("a(iiay)"));
	g_variant_builder_add_value(&b, g_variant_new("(ii@ay)", 32, 32, g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, px, sizeof px, 1)));
	return g_variant_builder_end(&b);
}
static GVariant *sni_get(GDBusConnection *c, const char *s, const char *o, const char *i, const char *p, GError **e, gpointer d)
{
	if (!strcmp(p, "Category")) return g_variant_new_string("ApplicationStatus");
	if (!strcmp(p, "Id")) return g_variant_new_string(trayid);
	if (!strcmp(p, "Title")) return g_variant_new_string(name);
	if (!strcmp(p, "Status")) return g_variant_new_string("Active");
	/* -B: a theme name no theme has, and no pixels */
	if (!strcmp(p, "IconName")) return g_variant_new_string(badicon ? "sample-no-such-icon" : "");
	if (!strcmp(p, "IconPixmap")) return badicon ? g_variant_new_array(G_VARIANT_TYPE("(iiay)"), NULL, 0) : icon();
	if (!strcmp(p, "ItemIsMenu")) return g_variant_new_boolean(FALSE);
	if (!strcmp(p, "Menu")) return g_variant_new_object_path(menu ? "/Menu" : "/NO_DBUSMENU");
	return NULL;
}
static void sni_call(GDBusConnection *c, const char *s, const char *o, const char *i, const char *m, GVariant *a, GDBusMethodInvocation *v, gpointer d)
{ g_dbus_method_invocation_return_value(v, NULL); }
static const GDBusInterfaceVTable sni_vt = { sni_call, sni_get, NULL };

static GVariant *entry(int id, const char *label)
{
	GVariantBuilder p, kids;
	g_variant_builder_init(&p, G_VARIANT_TYPE("a{sv}"));
	g_variant_builder_add(&p, "{sv}", "label", g_variant_new_string(label));
	g_variant_builder_init(&kids, G_VARIANT_TYPE("av"));
	return g_variant_new("(ia{sv}av)", id, &p, &kids);
}
static GVariant *layout(void)
{
	GVariantBuilder p, kids;
	g_variant_builder_init(&p, G_VARIANT_TYPE("a{sv}"));
	g_variant_builder_add(&p, "{sv}", "children-display", g_variant_new_string("submenu"));
	g_variant_builder_init(&kids, G_VARIANT_TYPE("av"));
	g_variant_builder_add(&kids, "v", entry(1, "About"));
	g_variant_builder_add(&kids, "v", entry(2, "Quit"));
	return g_variant_new("(ia{sv}av)", 0, &p, &kids);
}
static void menu_call(GDBusConnection *c, const char *s, const char *o, const char *i, const char *m, GVariant *a, GDBusMethodInvocation *v, gpointer d)
{
	if (!strcmp(m, "GetLayout")) {
		GVariant *l = layout();
		g_dbus_method_invocation_return_value(v, g_variant_new("(u@(ia{sv}av))", 1, l));
	} else if (!strcmp(m, "AboutToShow")) {
		g_dbus_method_invocation_return_value(v, g_variant_new("(b)", FALSE));
	} else if (!strcmp(m, "GetGroupProperties")) {
		g_dbus_method_invocation_return_value(v, g_variant_new_parsed("(@a(ia{sv}) [],)"));
	} else {
		int id; const char *ev; GVariant *data; guint32 ts;
		g_variant_get(a, "(i&svu)", &id, &ev, &data, &ts);
		g_dbus_method_invocation_return_value(v, NULL);
		g_dbus_connection_flush_sync(c, NULL, NULL);
		if (!strcmp(ev, "clicked") && id == 2) {
			say("quit-menu");
			exit(0);
		}
	}
}
static GVariant *menu_get(GDBusConnection *c, const char *s, const char *o, const char *i, const char *p, GError **e, gpointer d)
{ return !strcmp(p, "Version") ? g_variant_new_uint32(3) : g_variant_new_string("normal"); }
static const GDBusInterfaceVTable menu_vt = { menu_call, menu_get, NULL };

static gboolean tray_register(gpointer d)
{
	GError *e = NULL;
	GVariant *r = g_dbus_connection_call_sync(bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
		"org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem", g_variant_new("(s)", busname),
		NULL, G_DBUS_CALL_FLAGS_NONE, 2000, NULL, &e);
	if (!r) { say(e->message); g_clear_error(&e); return G_SOURCE_CONTINUE; }
	g_variant_unref(r);
	say("registered");
	return G_SOURCE_REMOVE;
}
static void on_bus_closed(GDBusConnection *c, gboolean peer, GError *e, gpointer d) { say("bus-gone"); _exit(0); }
static void tray_start(void)
{
	GDBusNodeInfo *n;
	bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
	if (!bus)
		exit(1);
	/* GDBus would end us by SIGTERM, which -T ignores: a fake must not outlive the test's bus */
	g_dbus_connection_set_exit_on_close(bus, FALSE);
	g_signal_connect(bus, "closed", G_CALLBACK(on_bus_closed), NULL);
	n = g_dbus_node_info_new_for_xml(sni_xml, NULL);
	g_dbus_connection_register_object(bus, "/StatusNotifierItem", n->interfaces[0], &sni_vt, NULL, NULL, NULL);
	if (menu) {
		n = g_dbus_node_info_new_for_xml(menu_xml, NULL);
		g_dbus_connection_register_object(bus, "/Menu", n->interfaces[0], &menu_vt, NULL, NULL, NULL);
	}
	snprintf(busname, sizeof busname, "org.kde.StatusNotifierItem-%d-1", (int)getpid());
	g_bus_own_name_on_connection(bus, busname, 0, NULL, NULL, NULL, NULL);
	g_timeout_add(300, tray_register, NULL);
}
static const char mpris_xml[] =
"<node><interface name='org.mpris.MediaPlayer2'><property name='Identity' type='s' access='read'/><property name='CanQuit' type='b' access='read'/>"
"<property name='CanRaise' type='b' access='read'/><property name='HasTrackList' type='b' access='read'/><property name='DesktopEntry' type='s' access='read'/>"
"<method name='Raise'/><method name='Quit'/></interface>"
"<interface name='org.mpris.MediaPlayer2.Player'><property name='PlaybackStatus' type='s' access='read'/><property name='Metadata' type='a{sv}' access='read'/>"
"<property name='CanControl' type='b' access='read'/><property name='CanPlay' type='b' access='read'/><property name='CanPause' type='b' access='read'/>"
"<property name='CanGoNext' type='b' access='read'/><property name='CanGoPrevious' type='b' access='read'/><property name='CanSeek' type='b' access='read'/>"
"<property name='Position' type='x' access='read'/><property name='Rate' type='d' access='read'/><property name='Volume' type='d' access='read'/>"
"<method name='Next'/><method name='Previous'/><method name='PlayPause'/><method name='Play'/><method name='Pause'/><method name='Stop'/></interface></node>";
static int playing = 1;
static const char *play_state(void) { return playing ? "Playing" : "Paused"; }
static GVariant *mpris_get(GDBusConnection *c, const char *s, const char *o, const char *i, const char *p, GError **e, gpointer d)
{
	if (!strcmp(p, "Identity")) return g_variant_new_string("Sample Player");
	if (!strcmp(p, "DesktopEntry")) return g_variant_new_string("");
	if (!strcmp(p, "PlaybackStatus")) return g_variant_new_string(play_state());
	if (!strcmp(p, "Position")) return g_variant_new_int64(0);
	if (!strcmp(p, "Rate") || !strcmp(p, "Volume")) return g_variant_new_double(1);
	if (!strcmp(p, "CanQuit") || !strcmp(p, "CanRaise") || !strcmp(p, "HasTrackList") || !strcmp(p, "CanSeek")) return g_variant_new_boolean(FALSE);
	if (!strcmp(p, "Metadata")) return g_variant_new_parsed("{'mpris:trackid': <objectpath '/sample/1'>, 'xesam:title': <'Sample Track'>, 'xesam:artist': <['Sample Artist']>, 'mpris:length': <int64 180000000>}");
	return g_variant_new_boolean(TRUE);
}
static void mpris_call(GDBusConnection *c, const char *s, const char *o, const char *i, const char *m, GVariant *a, GDBusMethodInvocation *v, gpointer d)
{
	char what[64];
	snprintf(what, sizeof what, "mpris-%s", m);
	say(what);
	if (!strcmp(m, "PlayPause") || !strcmp(m, "Pause") || !strcmp(m, "Play")) {
		playing = !strcmp(m, "PlayPause") ? !playing : !strcmp(m, "Play");
		g_dbus_connection_emit_signal(c, NULL, o, "org.freedesktop.DBus.Properties", "PropertiesChanged",
			g_variant_new_parsed("('org.mpris.MediaPlayer2.Player', {'PlaybackStatus': <%s>}, @as [])", play_state()), NULL);
	}
	g_dbus_method_invocation_return_value(v, NULL);
}
static const GDBusInterfaceVTable mpris_vt = { mpris_call, mpris_get, NULL };
static void mpris_start(void)
{
	GDBusNodeInfo *n = g_dbus_node_info_new_for_xml(mpris_xml, NULL);
	if (!bus && !(bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL)))
		exit(1);
	g_dbus_connection_register_object(bus, "/org/mpris/MediaPlayer2", n->interfaces[0], &mpris_vt, NULL, NULL, NULL);
	g_dbus_connection_register_object(bus, "/org/mpris/MediaPlayer2", n->interfaces[1], &mpris_vt, NULL, NULL, NULL);
	g_bus_own_name_on_connection(bus, "org.mpris.MediaPlayer2.sample", 0, NULL, NULL, NULL, NULL);
}
static void on_term(int s) { say("term"); _exit(0); }
static void on_term_ignored(int s) { say("term-ignored"); }

int main(int argc, char **argv)
{
	const char *appid = NULL;
	int o, want = 0, igterm = 0, player = 0;
	struct wl_display *dpy = NULL;

	while ((o = getopt(argc, argv, "a:n:t:mcTsPBBE")) != -1)
		switch (o) {
		case 'a': appid = optarg; name = optarg; break;
		case 'n': want = atoi(optarg); break;
		case 't': trayid = optarg; if (!appid) name = optarg; break;
		case 'm': menu = 1; break;
		case 'c': ignoreclose = 1; break;
		case 'T': igterm = 1; break;
		case 's': stay = 1; break;
		case 'P': player = 1; break;
		case 'B': badicon = 1; break;
		}
	signal(SIGTERM, igterm ? on_term_ignored : on_term);
	say("start");
	if (want > 0) {
		if (!(dpy = wl_display_connect(NULL)))
			return 1;
		wl_registry_add_listener(wl_display_get_registry(dpy), &reg_l, NULL);
		wl_display_roundtrip(dpy);
		for (int i = 0; i < want; i++) {
			struct win *w = calloc(1, sizeof *w);
			w->w = 300; w->h = 300;
			w->s = wl_compositor_create_surface(comp);
			w->xs = xdg_wm_base_get_xdg_surface(wm, w->s);
			xdg_surface_add_listener(w->xs, &xs_l, w);
			w->tl = xdg_surface_get_toplevel(w->xs);
			xdg_toplevel_add_listener(w->tl, &tl_l, w);
			xdg_toplevel_set_title(w->tl, name);
			if (appid) xdg_toplevel_set_app_id(w->tl, appid);
			wl_surface_commit(w->s);
			if (!first)
				first = w;
		}
		windows = want;
		wl_display_flush(dpy);
		g_unix_fd_add(wl_display_get_fd(dpy), G_IO_IN, wl_ready, dpy);
		if (getenv("FAKEAPP_CTL"))
			g_timeout_add(100, ctl_poll, dpy);
	}
	if (trayid)
		tray_start();
	if (player)
		mpris_start();
	g_main_loop_run(g_main_loop_new(NULL, FALSE));
	return 0;
}
