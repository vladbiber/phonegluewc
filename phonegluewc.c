/*
 * See LICENSE file for copyright and license details.
 */
#include <fnmatch.h>
#include <errno.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <fcntl.h>
#include <getopt.h>
#include <sys/inotify.h>
#include <ctype.h>
#include <limits.h>
#include <libinput.h>
#include <drm_fourcc.h>
#include <linux/input-event-codes.h>
#include <strings.h>
#include <math.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/backend/libinput.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_alpha_modifier_v1.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_cursor_shape_v1.h>
#include <wlr/types/wlr_data_control_v1.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_drm.h>
#include <wlr/types/wlr_export_dmabuf_v1.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_gamma_control_v1.h>
#include <wlr/types/wlr_idle_inhibit_v1.h>
#include <wlr/types/wlr_idle_notify_v1.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_keyboard_group.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_linux_dmabuf_v1.h>
#include <wlr/types/wlr_linux_drm_syncobj_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_output_management_v1.h>
#include <wlr/types/wlr_output_power_management_v1.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_pointer_constraints_v1.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_primary_selection.h>
#include <wlr/types/wlr_primary_selection_v1.h>
#include <wlr/types/wlr_relative_pointer_v1.h>
#include <scenefx/types/wlr_scene.h>
#include <scenefx/types/fx/clipped_region.h>
#include <scenefx/render/fx_renderer/fx_renderer.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_screencopy_v1.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_server_decoration.h>
#include <wlr/types/wlr_session_lock_v1.h>
#include <wlr/types/wlr_single_pixel_buffer_v1.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_touch.h>
#include <wlr/interfaces/wlr_touch.h>
#include <wlr/types/wlr_viewporter.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/types/wlr_input_method_v2.h>
#include <wlr/types/wlr_text_input_v3.h>
#include <wlr/types/wlr_virtual_keyboard_v1.h>
#include <wlr/types/wlr_virtual_pointer_v1.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_output_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/log.h>
#include <wlr/util/region.h>
#include <xkbcommon/xkbcommon.h>
#ifdef XWAYLAND
#include <wlr/xwayland.h>
#include <xcb/xcb.h>
#endif

#include "xdg-shell-protocol.h"
#include "util.h"
#include "dwl-ipc-unstable-v2-protocol.h"

/* a phone has no pointer to draw, and this keeps the cursor theme out of memory; the laptop window needs one
 * shortcut: a USB mouse moves an invisible pointer, draw one if that ever matters */
static int mouse_finger;
#define wlr_cursor_set_xcursor(cur, mgr, name) \
	(mouse_finger ? (wlr_cursor_set_xcursor)(cur, mgr, name) : wlr_cursor_unset_image(cur))

/* macros */
#define MAX(A, B)               ((A) > (B) ? (A) : (B))
#define MIN(A, B)               ((A) < (B) ? (A) : (B))
#define CLEANMASK(mask)         (mask & ~WLR_MODIFIER_CAPS)
#define VISIBLEON(C, M)         ((M) && (C)->mon == (M) && (C)->ws == (M)->ws)
#define LENGTH(X)               (sizeof X / sizeof X[0])
#define END(A)                  ((A) + LENGTH(A))
#define NUMWS                   9
#define LISTEN(E, L, H)         wl_signal_add((E), ((L)->notify = (H), (L)))
#define LISTEN_STATIC(E, H)     do { struct wl_listener *_l = ecalloc(1, sizeof(*_l)); _l->notify = (H); wl_signal_add((E), _l); } while (0)
#define SCROLLLT(M)             ((M) && (M)->lt == LtScroll)
#define LTMIGRATE(C, M, WS)     ((C)->mon == (M) && (C)->ws == (WS) \
                                && client_surface(C)->mapped && !client_is_unmanaged(C))
#define DRIFTLT(M)              ((M) && (M)->lt == LtDrift)
#define RESIZEWAIT              300 /* ms an unacked resize may hold up a frame */

/* enums */
enum { CurNormal, CurPressed, CurMove, CurResize,
       CurDragTile, CurResizeCol, CurDriftMove, CurDriftResize,
       CurDriftPan, CurBSPMove, CurBSPResize }; /* cursor */
enum { LtBSP, LtScroll, LtDrift, LtLast }; /* per-monitor layouts */
enum { XDGShell, LayerShell, X11 }; /* client types */
/* LyrOverview sits above the windows but below LyrTop, so the bar stays
 * visible over the overview while a fullscreen client (LyrFS) still covers it */
enum { LyrBg, LyrBottom, LyrTile, LyrFloat, LyrOverview, LyrTop, LyrFS, LyrOverlay, LyrPill, LyrBlock, NUM_LAYERS }; /* scene layers */
enum { ModeInsert, ModeNormal }; /* input modes */
enum { DirLeft, DirRight, DirUp, DirDown }; /* focus/swap directions */
enum { AnimNone, AnimFade, AnimSlide, AnimZoom }; /* open/close animation */

typedef union {
	int i;
	uint32_t ui;
	float f;
	const void *v;
} Arg;

typedef struct {
	unsigned int mod;
	unsigned int button;
	void (*func)(const Arg *);
	const Arg arg;
} Button;

typedef struct Monitor Monitor;
typedef struct Client Client;

typedef struct Node Node;
struct Node {
	int leaf, horiz;
	float ratio;
	Node *a, *b, *par;
	Client *c;
	struct wlr_box box; /* area this node was last tiled into, gaps included */
};

/* one column of the niri-style scrolling layout */
typedef struct Column Column;
struct Column {
	struct wl_list link;    /* Monitor.cols[ws] */
	struct wl_list clients; /* Client.clink, top to bottom */
	float wfrac;            /* width as a fraction of the window area */
	float prevfrac;         /* width to restore after a maximize toggle */
};

struct Client {
	/* Must keep this field first */
	unsigned int type; /* XDGShell or X11* */

	Monitor *mon;
	struct wlr_scene_tree *scene;
	struct {
		struct wlr_scene_rect *top, *bottom, *left, *right;
		struct wlr_scene_rect *top_left, *top_right;
		struct wlr_scene_rect *bottom_right, *bottom_left;
	} border; /* edge-only frame plus four rounded outer-corner pieces */
	struct wlr_scene_tree *scene_surface;
	struct wlr_scene_buffer *surfbuf; /* main surface buffer, for fx */
	struct wlr_scene_blur *blur; /* backdrop blur behind that buffer */
	struct wlr_foreign_toplevel_handle_v1 *ftl;
	struct wl_list link;
	struct wl_list flink;
	struct wlr_box geom; /* layout-relative, includes border */
	struct wlr_box prev; /* layout-relative, includes border */
	struct wlr_box bounds; /* only width and height are used */
	union {
		struct wlr_xdg_surface *xdg;
		struct wlr_xwayland_surface *xwayland;
	} surface;
	struct wlr_xdg_toplevel_decoration_v1 *decoration;
	struct wl_listener commit;
	struct wl_listener precommit;
	struct wl_listener map;
	struct wl_listener maximize;
	struct wl_listener unmap;
	struct wl_listener destroy;
	struct wl_listener set_title;
	struct wl_listener set_app_id;
	struct wl_listener fullscreen;
	struct wl_listener set_decoration_mode;
	struct wl_listener destroy_decoration;
	struct wl_listener ftl_activate;
	struct wl_listener ftl_close;
#ifdef XWAYLAND
	struct wl_listener activate;
	struct wl_listener associate;
	struct wl_listener dissociate;
	struct wl_listener configure;
#endif
	unsigned int bw;
	unsigned int ws;
	Node *node;
	Column *col;          /* scroll layout column, NULL while in a BSP tree */
	int canvassized;      /* canvas holds the window's real size, not a screen box */
	struct wl_list clink; /* position inside Column.clients */
	struct wlr_box canvas; /* drift layout: unscaled canvas rect, includes border */
	int oncanvas;          /* 1 while the client lives on a drift canvas */
	int isfloating, isfullscreen, isfakefull;
	struct {
		int active, fadein, workspace, hide, closing;
		int zoom;    /* the open animation also scales the window up */
		float zoomfrom;
		float scale; /* scale currently painted on the tree, 1 = untouched */
		float t; /* progress 0..1, advanced only on rendered frames */
		int swipe; /* ms: finishing a touchpad swipe, eased out from its speed */
		struct wlr_box from, to; /* only x/y are used */
	} anim;
	uint32_t resize; /* configure serial of a pending resize */
	uint32_t resizeat; /* when that serial was sent, in ms */
	double bufscale; /* scale painted on this client's buffers, 1 = untouched */
	double fit; /* shrink for a window wider than its box, 1 = none */
	int fitw, fith; /* the size the client is asked for */
	int minw, fitbox; /* width it insisted on without declaring it, in a box this wide */
	int offscreen; /* nothing of it lies on its monitor, so it is not drawn */
};

typedef struct {
	uint32_t mod;
	xkb_keysym_t keysym;
	void (*func)(const Arg *);
	const Arg arg;
} Key;

typedef struct {
	uint32_t mod;
	xkb_keysym_t keysym;
	void (*func)(const Arg *);
	Arg arg;
} Bind;

enum { MacroSequence, MacroClick };
enum { MacroOnce, MacroHold, MacroToggle };
enum { MacroStepKey = 1, MacroStepWait, MacroStepClick };

typedef struct {
	int type;
	uint32_t mods;
	xkb_keysym_t keysym;
	uint32_t button;
	int delay;
} MacroStep;

typedef struct {
	char name[64];
	uint32_t trigger_mods;
	xkb_keysym_t trigger_sym;
	int type, mode, interval, press_ms, cps;
	uint32_t button;
	MacroStep *steps;
	size_t nsteps, pos;
	struct wl_event_source *timer;
	int running, trigger_down;
	uint32_t trigger_keycode;
	int down_type;
	uint32_t down_code, down_mods;
} Macro;

typedef struct {
	struct wlr_keyboard_group *wlr_group;

	int nsyms;
	const xkb_keysym_t *keysyms; /* invalid if nsyms == 0 */
	uint32_t mods; /* invalid if nsyms == 0 */
	struct wl_event_source *key_repeat_source;
	int super_down, super_alone;
	uint32_t overview_keycode;

	struct wl_listener modifiers;
	struct wl_listener key;
	struct wl_listener destroy;
} KeyboardGroup;

typedef struct {
	/* Must keep this field first */
	unsigned int type; /* LayerShell */

	Monitor *mon;
	struct wlr_scene_tree *scene;
	struct wlr_scene_tree *popups;
	struct wlr_scene_layer_surface_v1 *scene_layer;
	struct wl_list link;
	int mapped;
	struct wlr_layer_surface_v1 *layer_surface;

	struct wl_listener destroy;
	struct wl_listener unmap;
	struct wl_listener surface_commit;
	struct wl_listener surface_precommit;
	struct {
		int active, closing, from_y, to_y;
		float t;
	} anim;
	struct wlr_scene_blur *blur; /* the app menu and the pull down panel only */
	float blurfade; /* 1 down to 0 while the menu fades out */
} LayerSurface;

struct Monitor {
	struct wl_list link;
	struct wlr_output *wlr_output;
	struct wlr_scene_output *scene_output;
	struct wlr_scene_rect *fullscreen_bg; /* See createmon() for info */
	struct wl_listener frame;
	struct wl_listener destroy;
	struct wl_listener request_state;
	struct wl_listener destroy_lock_surface;
	struct wlr_session_lock_surface_v1 *lock_surface;
	struct wlr_box m; /* monitor area, layout-relative */
	struct wlr_box w; /* window area, layout-relative */
	struct wl_list layers[4]; /* LayerSurface.link */
	unsigned int ws; /* current workspace */
	Node *tree[NUMWS]; /* BSP tree per workspace */
	unsigned int wsmask; /* workspaces occupied at the last wscompact */
	unsigned int lt; /* LtBSP, LtScroll (niri-style) or LtDrift (infinite canvas) */
	struct wl_list cols[NUMWS]; /* Column.link per workspace (scroll layout) */
	int scrollx[NUMWS]; /* horizontal scroll offset per workspace */
	/* drift layout: one camera over an infinite canvas per workspace */
	double camx[NUMWS], camy[NUMWS], camz[NUMWS];
	int driftscaled; /* the visible windows are currently drawn zoomed */
	int gamma_lut_changed;
	uint32_t lastanimtick;
	struct wl_event_source *unblock; /* wakes the output when a client stalls */
	int asleep;
	struct wlr_box overview[3];
	struct wlr_box overview_from[3];
	struct wlr_box overview_to[3];
	float overview_opacity[3];
	float overview_opacity_from[3];
	float overview_opacity_to[3];
	float overview_dim, overview_dim_from, overview_dim_to;
	float overview_anim_t;
	float overview_anim_v; /* the speed the finger left it with, per ms of the settle */
	int overview_animating;
	char mirror_of[64]; /* configured source, "" for none */
	Monitor *mirror_src; /* the source it copies right now, or NULL */
	int mirroring;
};

typedef struct {
	const char *name;
	float scale;
	enum wl_output_transform rr;
	int x, y;
} MonitorRule;

/* one "output = NAME key=value ..." line; later lines for the same name
 * override earlier ones key by key, "*" covers outputs without their own */
typedef struct {
	char name[64];
	int line;
	int has_mode, mw, mh, mhz; /* mw 0 = preferred, mhz 0 = any refresh */
	int has_pos, pos_auto, x, y;
	int has_scale;
	float scale;
	int has_transform;
	enum wl_output_transform transform;
	int has_enabled, enabled;
	int has_mirror;
	char mirror[64];
	int has_vrr, vrr;
} OutputCfg;

typedef struct {
	struct wlr_pointer_constraint_v1 *constraint;
	struct wl_listener destroy;
} PointerConstraint;

typedef struct {
	const char *id;
	const char *title;
	int ws; /* 1-9, 0 = current */
	int isfloating;
	int monitor;
} Rule;

typedef struct {
	struct wlr_scene_tree *scene;

	struct wlr_session_lock_v1 *lock;
	struct wl_listener new_surface;
	struct wl_listener unlock;
	struct wl_listener destroy;
} SessionLock;

typedef struct {
	struct wl_list link;
	struct wl_resource *resource;
	Monitor *mon;
} IpcOutput;

typedef struct {
	struct wlr_scene_tree *tree;
	float scalex, scaley, opacity;
	int srcx, srcy, x, y, radius, count;
	struct wlr_box clip; /* the monitor: nothing is drawn past its edge */
	struct wlr_box card;
} OverviewClone;

typedef struct {
	struct wl_list link;
	struct wlr_scene_buffer *scene;
	float opacity;
	int x, y, width, height;
} CloseBuffer;

typedef struct {
	struct wl_list link;
	struct wl_list buffers;
	struct wlr_scene_tree *tree;
	Monitor *mon;
	float t;
	int x, y, minx, miny, maxx, maxy;
} CloseAnim;

/* function declarations */
static float animease(const float *curve, float t);
static void animkick(Monitor *m);
static void animstop(Monitor *m);
static void applybounds(Client *c, struct wlr_box *bbox);
static void applyeffects(Client *c);
static void applyfakefull(Client *c);
static void applyrules(Client *c);
static void arrange(Monitor *m);
static void arrangelayer(Monitor *m, struct wl_list *list,
		struct wlr_box *usable_area, int exclusive);
static void arrangelayers(Monitor *m);
static void attachclient(Monitor *m, unsigned int ws, Client *c);
static void axisnotify(struct wl_listener *listener, void *data);
static void bsp_attach(Monitor *m, unsigned int ws, Client *c);
static void bsp_detach(Client *c);
static void bsp_dragto(Client *c, double cx, double cy);
static Node *bsp_findsplit(Node *n, int horiz, int after);
static Node *bsp_first(Node *n);
static int bsp_has_tiled(Node *n);
static Node *bsp_nextleaf(Node *tree, Node *cur);
static Node *bsp_prevleaf(Node *tree, Node *cur);
static void bsp_resizeto(Client *c, double cx, double cy);
static void bsp_tile(Node *n, struct wlr_box box);
static void bsp_flip(Node *n);
static void buttonpress(struct wl_listener *listener, void *data);
static void chvt(const Arg *arg);
static void checkidleinhibitor(struct wlr_surface *exclude);
static void clientborders(Client *c, int width, int height, int bw, int radius,
		const struct wlr_box *crop);
static void clientclip(Client *c);
static void clientplace(Client *c, int x, int y);
static int borderwanted(Client *c);
static int boxclip(struct wlr_box *b, const struct wlr_box *clip);
static float clientopacity(Client *c);
static void clientscale(Client *c, float z);
static void clientunscale(Client *c);
static void clientfitlearn(Client *c);
static int closeanimadvance(Monitor *m, float dt);
static void closeanimclear(Monitor *m);
static int closeanimstart(struct wlr_scene_node *node,
		struct wlr_scene_tree *parent, Monitor *m);
static void clientcloseanim(Client *c);
static void cleanup(void);
static void cleanupmon(struct wl_listener *listener, void *data);
static void cleanuplisteners(void);
static void closemon(Monitor *m);
static void commitlayersurfacenotify(struct wl_listener *listener, void *data);
static void commitnotify(struct wl_listener *listener, void *data);
static void topcolorsoon(void);
static void rotsoon(int ms);
static int rotupdate(void *data);
static void rotorientation(const char *name);
static Monitor *rotmon(void);
static int rotfadestep(void *data);
static void rotwrite(const char *name, const char *v);
static int topcolorsample(void *data);
static void precommitlayersurfacenotify(struct wl_listener *listener, void *data);
static void precommitnotify(struct wl_listener *listener, void *data);
static void commitpopup(struct wl_listener *listener, void *data);
static void consumewin(const Arg *arg);
static void createdecoration(struct wl_listener *listener, void *data);
static void createidleinhibitor(struct wl_listener *listener, void *data);
static void createkeyboard(struct wlr_keyboard *keyboard);
static KeyboardGroup *createkeyboardgroup(void);
static void createlayersurface(struct wl_listener *listener, void *data);
static void createlocksurface(struct wl_listener *listener, void *data);
static void createmon(struct wl_listener *listener, void *data);
static void createnotify(struct wl_listener *listener, void *data);
static void createpointer(struct wlr_pointer *pointer);
static void createpointerconstraint(struct wl_listener *listener, void *data);
static void createpopup(struct wl_listener *listener, void *data);
static void cursorconstrain(struct wlr_pointer_constraint_v1 *constraint);
static void cursorframe(struct wl_listener *listener, void *data);
static void cursorwarptohint(void);
static void destroydecoration(struct wl_listener *listener, void *data);
static void destroydragicon(struct wl_listener *listener, void *data);
static void destroyidleinhibitor(struct wl_listener *listener, void *data);
static void destroylayersurfacenotify(struct wl_listener *listener, void *data);
static void destroylock(SessionLock *lock, int unlocked);
static void destroylocksurface(struct wl_listener *listener, void *data);
static void destroynotify(struct wl_listener *listener, void *data);
static void destroypointerconstraint(struct wl_listener *listener, void *data);
static void destroysessionlock(struct wl_listener *listener, void *data);
static void destroykeyboardgroup(struct wl_listener *listener, void *data);
static void detachclient(Client *c);
static Client *dirpick(Monitor *m, Client *from, int dir);
static void driftapply(Monitor *m);
static void driftarrange(Monitor *m);
static void driftattach(Monitor *m, unsigned int ws, Client *c);
static void driftbounds(Monitor *m, unsigned int ws, int withview, struct wlr_box *out);
static int driftcluster(Client *c, Client **out, int max);
static void driftdetach(Client *c);
static void driftdragto(Client *c, double cx, double cy);
static void driftfit(const Arg *arg);
static void driftmove(Client *c, int dx, int dy, int cluster);
static void driftnudge(const Arg *arg);
static void driftpan(const Arg *arg);
static void driftpanto(double cx, double cy);
static void driftpankey(const Arg *arg);
static Client *driftpick(Monitor *m, Client *from, int dir);
static void driftresizeto(Client *c, double cx, double cy);
static void driftreveal(Monitor *m, Client *c);
static void driftscaleclient(Client *c, double z);
static void driftscreen(Monitor *m, Client *c, struct wlr_box *out);
static void driftsnap(Monitor *m, Client *c, struct wlr_box *box);
static void drifttile(Monitor *m);
static int drifttiled(Client *c, Monitor *m, unsigned int ws);
static double driftz(Monitor *m, unsigned int ws);
static void driftzoomkey(const Arg *arg);
static void driftzoomto(Monitor *m, double z, double ax, double ay);
static void entermode(const Arg *arg);
static void expelwin(const Arg *arg);
static void focusclient(Client *c, int lift);
static const float *focuscolorfor(void);
static void focusdir(const Arg *arg);
static void focusnext(const Arg *arg);
static Client *focustop(Monitor *m);
static void ftlactivatenotify(struct wl_listener *listener, void *data);
static void clientraise(Client *c);
static void closeall(void);
static void ftlclosenotify(struct wl_listener *listener, void *data);
static void fullscreennotify(struct wl_listener *listener, void *data);
static void gpureset(struct wl_listener *listener, void *data);
static void handlesig(int signo);
static void inputdevice(struct wl_listener *listener, void *data);
static void ipcmgrbind(struct wl_client *client, void *data, uint32_t version, uint32_t id);
static void ipcnotifyall(void);
static void ipcstatus(IpcOutput *io);
static int keybinding(uint32_t mods, xkb_keysym_t sym);
static void keypress(struct wl_listener *listener, void *data);
static void keypressmod(struct wl_listener *listener, void *data);
static int keyrepeat(void *data);
static void killclient(const Arg *arg);
static int layeranimadvance(Monitor *m, float dt);
static void locksession(struct wl_listener *listener, void *data);
static int macrohandle(uint32_t mods, xkb_keysym_t sym, uint32_t keycode,
		enum wl_keyboard_key_state state);
static void macrostopall(void);
static void mapnotify(struct wl_listener *listener, void *data);
static void menubar(Monitor *m);
static void maximizenotify(struct wl_listener *listener, void *data);
static void motionabsolute(struct wl_listener *listener, void *data);
static void movetows(const Arg *arg);
static uint32_t now_ms(void);
static void toggleopacity(const Arg *arg);
static int keyboardshown(Monitor *m);

static void edgepass(uint32_t time);
static void keyboardforce(Monitor *m, int show);
static float pillprogress(void);
static void motionnotify(uint32_t time, struct wlr_input_device *device, double sx,
		double sy, double sx_unaccel, double sy_unaccel);
static void motionrelative(struct wl_listener *listener, void *data);
static void moveresize(const Arg *arg);
static void movetowsfollow(const Arg *arg);
static void childdie(const char *what, const char *cmd);
static void movewsdir(const Arg *arg);
static void movedir(const Arg *arg);
static void movewsstep(const Arg *arg);
static void outputmgrapply(struct wl_listener *listener, void *data);
static void outputmgrapplyortest(struct wlr_output_configuration_v1 *config, int test);
static void outputmgrtest(struct wl_listener *listener, void *data);
static void applyoutputcfg(Monitor *m);
static void applyoutputcfgs(void);
static void cfgoutput(char *v);
static void cfgoutputcheck(void);
static Monitor *monbyname(const char *name);
static Monitor *mirrorsource(Monitor *m);
static void mirrorstart(Monitor *m);
static void mirrorstop(Monitor *m);
static void mirrorfit(Monitor *m, Monitor *src);
static void placemirrors(void);
static void outcfgmerged(const char *name, OutputCfg *out);
static void saveoutputstate(void);
static const char *transformname(enum wl_output_transform t);
static int cardcloseback(void *data);
static void overviewbuild(void);
static void overviewtouch(Client *c);
static void overviewframes(Monitor *m, struct timespec *now);
static void overviewbutton(struct wlr_pointer_button_event *event);
static void overviewclone(struct wlr_scene_buffer *buffer, int sx, int sy, void *data);
static void savepillstate(void);
static void savescreenstate(void);
static int overviewkey(xkb_keysym_t sym);
static int overviewkeybinding(uint32_t mods, xkb_keysym_t sym);
static int overviewmotion(void);
static void overviewnavigate(unsigned int ws, int dir);
static void overviewrelayout(void);
static void overviewfinish(void);
static int glideadvance(Monitor *m, float dt);
static void glideto(Monitor *m, double x, double v, double tgt);
static void gridreveal(Monitor *m);
static struct wlr_box overviewboxlerp(const struct wlr_box *from, const struct wlr_box *to, float t);
static void overviewset(int active);
static int overviewpassthrough(void);
static int overviewkeypassthrough(void);
static void saveoverviewstate(int active);
static void overviewtoggle(const Arg *arg);
static int startoverview(void *data);
static int overviewvalid(Monitor *m);
static void workspacestep(int dir);
static void overviewstep(int dir);
static void carryland(void);
static void buttonsend(const char *event);
typedef struct Placement Placement;
static Placement *placementfind(Client *c);
static void tilehidden(Monitor *m);
static void arrangehidden(Monitor *m);
static void readphoneconf(void);
static void openswitch(Monitor *m, unsigned int ws);
static void overviewfinish(void);
static void icondragstart(const char *cmd, const char *dir);
static void workspacestepcarry(int dir, int carry);
static void gesturebegin(uint32_t fingers);
static void gestureupdate(uint32_t fingers, double dx, double dy);
static void swipebeginnotify(struct wl_listener *listener, void *data);
static void swipeendnotify(struct wl_listener *listener, void *data);
static void gestureend(int cancelled, uint32_t time);
static void touchcancel(struct wl_listener *listener, void *data);
static void touchdown(struct wl_listener *listener, void *data);
static void touchframe(struct wl_listener *listener, void *data);
static void touchmap(void);
static void touchmotion(struct wl_listener *listener, void *data);
static void createtouch(struct wlr_touch *touch);
static void touchup(struct wl_listener *listener, void *data);
static void swipeupdatenotify(struct wl_listener *listener, void *data);
static void pointerfocus(Client *c, struct wlr_surface *surface,
		double sx, double sy, uint32_t time);
static void powermgrsetmode(struct wl_listener *listener, void *data);
static void quit(const Arg *arg);
static void readconfig(void);
static void cfgerror(const char *fmt, ...);
static int cfgerrorhide(void *data);
static void cfgerrorshow(void);
static void cfgwatch(void);
static int cfgwatchevent(int fd, uint32_t mask, void *data);
static int cfgwatchfire(void *data);
static void reloadconfig(const Arg *arg);
static void rendermon(struct wl_listener *listener, void *data);
static void requestdecorationmode(struct wl_listener *listener, void *data);
static void requeststartdrag(struct wl_listener *listener, void *data);
static void requestmonstate(struct wl_listener *listener, void *data);
static void resize(Client *c, struct wlr_box geo, int interact);
static void run(char *startup_cmd);
static Column *scroll_addcol(Monitor *m, unsigned int ws, struct wl_list *pos);
static void scroll_addclient(Column *col, Client *c, unsigned int ws);
static void scroll_attach(Monitor *m, unsigned int ws, Client *c);
static int scroll_coltiled(Column *col);
static int scroll_colwidth(Monitor *m, Column *col);
static void scroll_detach(Client *c);
static void scroll_dragto(Client *c, double cx);
static void scroll_maximize(Client *sel);
static Client *scroll_next(Monitor *m, Client *sel);
static void scroll_swap(Client *sel, int dir);
static void scroll_tile(Monitor *m);
static int wsdragshows(Client *c);
static void wsdragupdate(double d);
static int wsdragframe(Monitor *m);
static void swipefocus(int dir);
static void overviewfocuscol(int dir);
static void setcursor(struct wl_listener *listener, void *data);
static void setcursorshape(struct wl_listener *listener, void *data);
static void setfloating(Client *c, int floating);
static void setfullscreen(Client *c, int fullscreen);
static void setlayout(Monitor *m, unsigned int lt);
static int layoutstatepath(char *buf, size_t size);
static const char *layoutname(unsigned int lt);
static void loadlayoutstate(void);
static void savelayoutstate(unsigned int lt);
static void setlayoutarg(const Arg *arg);
static void pinchbeginnotify(struct wl_listener *listener, void *data);
static void pinchendnotify(struct wl_listener *listener, void *data);
static void pinchupdatenotify(struct wl_listener *listener, void *data);
static void setmon(Client *c, Monitor *m, int ws);
static void setpsel(struct wl_listener *listener, void *data);
static void setratio(const Arg *arg);
static void setsel(struct wl_listener *listener, void *data);
static void setup(void);
static void spawn(const Arg *arg);
static void startdrag(struct wl_listener *listener, void *data);
static void swapdir(const Arg *arg);
static void swapnodes(Client *sel, Client *t);
static void swapstack(const Arg *arg);
static void toggledecor(const Arg *arg);
static void togglelayout(const Arg *arg);
static void togglefakefullscreen(const Arg *arg);
static void togglefloating(const Arg *arg);
static void togglefullscreen(const Arg *arg);
static void togglesplit(const Arg *arg);
static void unlocksession(struct wl_listener *listener, void *data);
static void unmaplayersurfacenotify(struct wl_listener *listener, void *data);
static void unmapnotify(struct wl_listener *listener, void *data);
static void updatemons(struct wl_listener *listener, void *data);
static void updatetitle(struct wl_listener *listener, void *data);
static void updateappid(struct wl_listener *listener, void *data);
static void savewindowstate(void);
static void viewws(const Arg *arg);
static void virtualkeyboard(struct wl_listener *listener, void *data);
static void virtualpointer(struct wl_listener *listener, void *data);
static void warpto(Client *c);
static Client *wsfocused(Monitor *m, unsigned int ws);
static Client *wsfocusedany(Monitor *m, unsigned int ws);
static void wsstep(const Arg *arg);
static Monitor *xytomon(double x, double y);
static void xytonode(double x, double y, struct wlr_surface **psurface,
		Client **pc, LayerSurface **pl, double *nx, double *ny);

/* variables */
static pid_t child_pid = -1;
static int locked;
static struct wl_event_source *topcolor_timer;
static uint32_t topcolor_at;
#define TOPCOLOR_MS 250
/* the turn of the first output: applied, last read from the sensor, picked with the button while locked */
static enum wl_output_transform rot, rot_sensor, rot_pick;
static int home_upright;
static unsigned int rot_offers;
static struct wl_event_source *rot_timer, *rot_fade_timer;
static struct wlr_scene_rect *rot_fade;
static uint32_t rot_fade_at;
static pid_t sensor_pid;
#define ROT_FADE_MS 220
static struct wl_event_source *closeall_timer;
static int closeall_ticks;
#define CLOSEALL_TICK_MS 200
#define CLOSEALL_TICKS 15
static int inputmode = ModeInsert;
static int decorhidden;

/* runtime configuration (~/.config/phonegluewc/config.conf) */
static Bind *runkeys, *runnormalkeys;
static size_t nrunkeys, nrunnormalkeys;
static char **autostarts;
static size_t nautostarts;
static OutputCfg *outcfgs;
static size_t noutcfgs;
static Macro *macros;
static size_t nmacros;
static char xkb_layout_buf[64], xkb_variant_buf[64], xkb_options_buf[128];

/* status bar IPC (dwl-ipc-unstable-v2, same protocol mmsg/waybar speak) */
static struct wl_list ipc_outputs;
static struct wlr_foreign_toplevel_manager_v1 *ftl_mgr;
static void *exclusive_focus;
static struct wl_display *dpy;
static struct wl_event_loop *event_loop;
static struct wl_event_source *pill_hold;
static int pillhold(void *data);
static int homehold(void *data);
static void saveseq(const char *name, unsigned int seq);
static struct wlr_backend *backend;
static struct wlr_scene *scene;
static struct wlr_scene_tree *layers[NUM_LAYERS];
static struct wlr_scene_tree *drag_icon;
static struct wlr_scene_tree *overview_dim_scene;
static struct wlr_scene_tree *overview_scene;
static struct wlr_scene_tree *overview_panels_scene;
static struct wlr_scene_tree *overview_drag_scene;
static struct wl_list close_anims;
static int overview_active;
static int overview_visible;
static int overview_dirty; /* a window changed under the overview: rebuild */
static struct wl_event_source *overview_watchdog;
/* config file watch: the file is reloaded as soon as an editor closes it, and
 * anything the parser rejected is reported instead of only reaching the log */
static int cfg_wd = -1;
static struct wl_event_source *cfg_watch_src, *cfg_watch_delay;
static struct wlr_scene_rect *cfg_errbar;
static struct wl_event_source *cfg_errbar_timer;
static int cfg_nerrors;
static int cfg_errline, cfg_curline;
static char cfg_errmsg[192];
static char cfg_path[512];
/* app_id/class globs that open fullscreen; fullscreen_apps in the config */
static char fullscreen_apps[512] = "steam_app_* cs2 org.vinegarhq.Sober";
/* a visible full screen window keeps the session awake (X11 games send no inhibitor) */
static int idle_inhibit_fullscreen = 1;
/* X11 apps through xwayland-satellite, started on the first X client; xwayland in the config */
static int xwayland_on = 1;
static int xsat_fd[2] = {-1, -1}, xsat_disp = -1;
static pid_t xsat_pid;
static uint32_t xsat_started;
static struct wl_event_source *xsat_src[2], *xsat_exit;
static void xsatsetup(void);
static void xsatcleanup(void);
static int overview_button_swallow;
static double overview_swipe_dx, overview_swipe_dy;
static int overview_swipe_active, overview_swipe_triggered;
/* a workspace switch that follows the fingers */
static struct {
	Monitor *m;
	int active, vertical, dir, refused;
	unsigned int nb;
	double pos; /* finger travel along the axis */
	double shown; /* on screen, eased toward pos each frame */
	double hpos[8]; /* recent travel, for the release speed */
	uint32_t ht[8];
	int hn;
	uint32_t lastframe;
} wsdrag;
static uint32_t gesture_time;

/* fingers on the touchscreen, in layout coordinates; ox/oy is the surface origin */
typedef struct {
	int32_t id;
	double x, y, ox, oy, z; /* z: the scale of the window it landed on */
} TouchPoint;
typedef struct {
	struct wlr_touch *touch;
	struct wl_listener destroy;
	struct wl_list link;
} TouchDevice;
static struct wl_list touch_devices = {&touch_devices, &touch_devices};
static TouchPoint touch_pts[16];
static int touch_n;
static int32_t touch_emu = -1; /* the finger acting as the left mouse button */
static int touch_gesture; /* 1 swiping, 2 ended and waiting for all fingers to lift, 3 on the pill, 4 on the overview */
static double touch_gdx, touch_gdy;
/* the finger owned by the pill or the overview; mode 0 is undecided.
 * pill: 1 the overview follows, 2 dismisses a shell surface.
 * overview: 1 the cards follow, 2 carries a window, 3 does nothing. */
static struct {
	int32_t id;
	int mode;
	double x0, y0, x, y, velx, vely;
	uint32_t t0, time, moved; /* moved: when it left the slop, 0 until then */
	int settled; /* overview: the cards stood still when it landed */
	int caught; /* overview: it stopped gliding cards, so its lift opens nothing */
	Monitor *m;
	struct { double x, y; uint32_t t; } hist[8]; /* recent samples, by event time */
	int nhist;
} finger;
/* cards thrown sideways: offset from the current card, a critically damped glide to tgt */
static struct {
	Monitor *m;
	double x0, v0, tgt, w, x;
	float t;
} glide;
static struct wlr_scene_buffer *edge_node;
static int edge_side, edge_armed; /* side: 1 right, -1 left */
static struct wlr_scene_rect *pill, *bar_bg;
static struct wl_event_source *bar_slide, *bar_timer;
static float bar_t;
static int bar_shown, bar_hover;
static int flick_side_ws[2] = {-1, -1}; /* the neighbours a flick leaves fade where they were */
static struct wlr_box flick_side[2];
static float flick_side_op[2];
static int flick_ws = -1; /* the card a flick leaves stays on the left until the overview is gone */
static float flick_dim;
static struct { uint32_t t; int paused; } pillpause;
/* recent apps as two columns that scroll up and down instead of the carousel; overview = grid in phone.conf */
static int overview_grid;
/* shortcut: one scroll and one tracked card for every monitor, fine while a phone has one */
static double grid_scroll;
static int grid_ws = -1; /* the workspace m->overview[1] is the card of */
/* grid mode: a card drawn cropped to this, with labels on this card */
static const struct wlr_box *grid_clip, *grid_card;
#define GRIDLT(M) (overview_grid && !SCROLLLT(M))
#define GRIDPANEL 3 /* grid panels are GRIDPANEL + ws, past the carousel's three */
#define GRID_GAP 12
static float pill_a; /* how much of the pill showed when the drag began */
static void barset(int shown);
static void barhover(void);
static unsigned int pillseq; /* published, the shell closes its menu when it changes */
static unsigned int menuseq; /* published, the shell opens its app menu when it changes */
static unsigned int pageseq[2]; /* published, a swipe sideways on bare home turns the home page: prev, next */
static unsigned int editseq; /* published, the shell opens the home editor when it changes */
static struct wl_event_source *home_hold;
#define HOME_HOLD_MS 500
static struct { int32_t id; double x0, y0; } homeswipe = { .id = -1 }; /* a finger on bare home, until it opens the menu */
#define HOMESWIPE_UP 60.0
#define PILL_W 124
#define PILL_H 5
#define PILL_HALO 1
#define PILL_ZONE 26 /* the bar's height when shown, and the strip under the tray */
#define BAR_ZONE 16 /* the part of the screen edge that stays ours while the bar is hidden */
#define BAR_SLIDE_MS 120
#define BAR_HIDE_MS 3000
#define PILL_PAUSE_MS 170 /* a finger this long under PILL_SLOW has paused: slowing is enough */
#define PILL_SLOW 0.25 /* px per ms */
#define PILL_PAUSE_MIN 0.12f /* progress a pause has to reach to count as a hold */
#define PILL_FLICK 1.0 /* px per ms: only a clearly fast flick leaves for the free workspace */
#define PILL_LIFT 18.0 /* px the pill rises with the finger while it fades */
#define PILL_HOLD_MS 500 /* holding still on the bar opens screen text */
#define PILL_HOLD_SLOP 8.0
#define SCREENTEXT_NAMESPACE "phone-screentext"
#define TRAY_NAMESPACE "phone-tray"
#define HOME_NAMESPACE "phone-home"
#define STATUSBAR_NAMESPACE "phone-statusbar"
#define LABELS_NAMESPACE "phone-cardlabels"
#define ICON_GHOST 56
#define LABELS_H (28 * NUMWS + ICON_GHOST)
#define LABEL_H 28 /* the icon and name in a card's top strip, one row per workspace in the shell's surface */
#define CARD_TOP 6 /* under the status bar, which stays in the overview */
#define SIDE_CARD 0.86f /* the side cards against the centre one */
#define TRAY_ROW 48 /* the top of the tray's surface: the button row, 34 high in 7 above and below */
#define CARD_HOLD_SLOP 4 /* a hold stays this close to where it landed */
/* up closes a card past this share of its height, or fast past the near one; less comes back */
#define CARD_CLOSE_FAR 0.5f
#define CARD_CLOSE_NEAR 0.25f
#define CARD_CLOSE_SPEED 1.0
static struct {
	Client *c; /* the window a finger is flinging off its card */
	float dy, from, to;
} card_close;
static struct wl_event_source *card_close_timer;
static Client *overview_drag_client;
/* an app icon carried instead of a window: its command, split by 0x1f */
static char *overview_drag_cmd, *overview_drag_dir;
static struct wlr_scene_tree *overview_land_scene;
#define OPEN_FROM_MS 5000 /* an app slower than this opens from the centre */
static uint32_t open_from_at;
static double press_x, press_y;
static struct wl_event_source *carry_edge_timer;
static int carry_dir;
/* the next window attached splits this one, on this side */
static Client *place_anchor;
static int place_side;
static const char *spawn_dir;
enum { SIDE_SWAP, SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM };
#define TILES_MAX 4
#define PLACE_MS 20000
#define CARRY_EDGE 24
#define CARRY_EDGE_MS 450
/* where a dropped icon's window goes, tied to the process it was launched as */
struct Placement {
	pid_t pid;
	Client *anchor; /* NULL: alone, on the free workspace */
	int side;
	struct timespec until;
};
static Client *overview_focus_client;
static int overview_dragging;
static double overview_press_x, overview_press_y;
static int overview_grab_x, overview_grab_y;
static struct wlr_box overview_drag_box;
/* Map from ZWLR_LAYER_SHELL_* constants to Lyr* enum */
static const int layermap[] = { LyrBg, LyrBottom, LyrTop, LyrOverlay };

typedef struct {
	struct wlr_text_input_v3 *input;
	struct wl_listener enable;
	struct wl_listener commit;
	struct wl_listener disable;
	struct wl_listener destroy;
	struct wl_list link;
} TextInput;

static struct wl_list text_inputs;
static TextInput *active_text_input;
static struct wlr_input_method_v2 *input_method;
static struct wl_listener input_method_commit;
static struct wl_listener input_method_destroy;
static void createtextinput(struct wl_listener *listener, void *data);
static void createinputmethod(struct wl_listener *listener, void *data);
static void keyboardfocuschange(struct wl_listener *listener, void *data);
static struct wl_listener new_text_input = {.notify = createtextinput};
static struct wl_listener new_input_method = {.notify = createinputmethod};
static struct wl_listener keyboard_focus_change = {.notify = keyboardfocuschange};

/* the on-screen keyboard goes above the menu whatever layer it asks for */
static pid_t spawned_pid, shell_pid, keyboard_pid;
static void spawnshell(void);
static int relock(void *data);
static void lockengage(int ms);
static void screenpower(Monitor *m, int on);
static int screendark(Monitor *m);
static void touchlift(int32_t id, uint32_t time, int cancelled);
/* the picture fades out before the panel goes dark and back in once it is lit */
#define SCREEN_FADE_MS 200
static struct {
	Monitor *m;
	struct wlr_scene_rect *rect;
	struct wl_event_source *timer;
	uint32_t at;
	int on;
} screenfade;
static void keyboardoverlock(void);

static struct wlr_scene_tree *
layertree(struct wlr_layer_surface_v1 *layer_surface, int layer)
{
	if (input_method && wl_resource_get_client(layer_surface->resource)
			== wl_resource_get_client(input_method->resource)) {
		pid_t pid;

		/* only the keyboard this compositor started goes over the lock */
		wl_client_get_credentials(wl_resource_get_client(layer_surface->resource), &pid, NULL, NULL);
		return locked && keyboard_pid > 0 && pid == keyboard_pid ? layers[LyrBlock] : layers[LyrPill];
	}
	return layers[layermap[layer]];
}
static struct wlr_renderer *drw;
static struct wlr_allocator *alloc;
static struct wlr_compositor *compositor;
static struct wlr_session *session;

static struct wlr_xdg_shell *xdg_shell;
static struct wlr_xdg_decoration_manager_v1 *xdg_decoration_mgr;
static struct wl_list clients; /* tiling order */
static struct wl_list fstack;  /* focus order */
static struct wlr_idle_notifier_v1 *idle_notifier;
static struct wlr_idle_inhibit_manager_v1 *idle_inhibit_mgr;
static struct wlr_layer_shell_v1 *layer_shell;
static struct wlr_output_manager_v1 *output_mgr;
static struct wlr_virtual_keyboard_manager_v1 *virtual_keyboard_mgr;
static struct wlr_virtual_pointer_manager_v1 *virtual_pointer_mgr;
static struct wlr_cursor_shape_manager_v1 *cursor_shape_mgr;
static struct wlr_output_power_manager_v1 *power_mgr;

static struct wlr_pointer_constraints_v1 *pointer_constraints;
static struct wlr_relative_pointer_manager_v1 *relative_pointer_mgr;
static struct wlr_pointer_constraint_v1 *active_constraint;

static struct wlr_cursor *cursor;
static struct wlr_xcursor_manager *cursor_mgr;

static struct wlr_scene_rect *root_bg;
static struct wlr_session_lock_manager_v1 *session_lock_mgr;
static struct wlr_scene_rect *locked_bg;
static struct wlr_session_lock_v1 *cur_lock;
static struct wl_event_source *relock_timer;
static int relock_tries;
static int greeter; /* the boot login: no bar, no gestures */

static struct wlr_seat *seat;
static KeyboardGroup *kb_group;
static KeyboardGroup *super_group;
static unsigned int cursor_mode;
static Client *grabc;
static int grabcx, grabcy; /* client-relative */
static double grab_startx; /* cursor x at the start of a resize or canvas pan */
static double grab_starty; /* cursor y at the start of a resize or canvas pan */
static float grab_wfrac;   /* column width when the resize started */
static Node *bsp_grabh, *bsp_grabv; /* splits a bsp drag-resize is moving */
static float bsp_grabhr, bsp_grabvr; /* their ratios when the drag started */
static Monitor *grabm;     /* monitor whose camera a canvas pan is dragging */
static double grab_camx, grab_camy; /* camera position when the pan started */
static int lt_migrating;   /* set while windows move between layouts */
static int drift_dragcluster; /* the running drag moves the whole snapped cluster */
static double drift_pinch_zoom, drift_pinch_x, drift_pinch_y;
static int drift_pinch_done;

static struct wlr_output_layout *output_layout;
static struct wlr_box sgeom;
static struct wl_list mons;
static Monitor *selmon;

/* global event handlers */
static struct wl_listener cursor_axis = {.notify = axisnotify};
static struct wl_listener cursor_button = {.notify = buttonpress};
static struct wl_listener cursor_frame = {.notify = cursorframe};
static struct wl_listener cursor_motion = {.notify = motionrelative};
static struct wl_listener cursor_motion_absolute = {.notify = motionabsolute};
static struct wl_listener cursor_pinch_begin = {.notify = pinchbeginnotify};
static struct wl_listener cursor_pinch_end = {.notify = pinchendnotify};
static struct wl_listener cursor_pinch_update = {.notify = pinchupdatenotify};
static struct wl_listener cursor_swipe_begin = {.notify = swipebeginnotify};
static struct wl_listener cursor_swipe_end = {.notify = swipeendnotify};
static struct wl_listener cursor_touch_cancel = {.notify = touchcancel};
static struct wl_listener cursor_touch_down = {.notify = touchdown};
static struct wl_listener cursor_touch_frame = {.notify = touchframe};
static struct wl_listener cursor_touch_motion = {.notify = touchmotion};
static struct wl_listener cursor_touch_up = {.notify = touchup};
static struct wl_listener cursor_swipe_update = {.notify = swipeupdatenotify};
static struct wl_listener gpu_reset = {.notify = gpureset};
static struct wl_listener layout_change = {.notify = updatemons};
static struct wl_listener new_idle_inhibitor = {.notify = createidleinhibitor};
static struct wl_listener new_input_device = {.notify = inputdevice};
static struct wl_listener new_virtual_keyboard = {.notify = virtualkeyboard};
static struct wl_listener new_virtual_pointer = {.notify = virtualpointer};
static struct wl_listener new_pointer_constraint = {.notify = createpointerconstraint};
static struct wl_listener new_output = {.notify = createmon};
static struct wl_listener new_xdg_toplevel = {.notify = createnotify};
static struct wl_listener new_xdg_popup = {.notify = createpopup};
static struct wl_listener new_xdg_decoration = {.notify = createdecoration};
static struct wl_listener new_layer_surface = {.notify = createlayersurface};
static struct wl_listener output_mgr_apply = {.notify = outputmgrapply};
static struct wl_listener output_mgr_test = {.notify = outputmgrtest};
static struct wl_listener output_power_mgr_set_mode = {.notify = powermgrsetmode};
static struct wl_listener request_cursor = {.notify = setcursor};
static struct wl_listener request_set_psel = {.notify = setpsel};
static struct wl_listener request_set_sel = {.notify = setsel};
static struct wl_listener request_set_cursor_shape = {.notify = setcursorshape};
static struct wl_listener request_start_drag = {.notify = requeststartdrag};
static struct wl_listener start_drag = {.notify = startdrag};
static struct wl_listener new_session_lock = {.notify = locksession};

#ifdef XWAYLAND
static void activatex11(struct wl_listener *listener, void *data);
static void associatex11(struct wl_listener *listener, void *data);
static void configurex11(struct wl_listener *listener, void *data);
static void createnotifyx11(struct wl_listener *listener, void *data);
static void dissociatex11(struct wl_listener *listener, void *data);
static void xwaylandready(struct wl_listener *listener, void *data);
static struct wl_listener new_xwayland_surface = {.notify = createnotifyx11};
static struct wl_listener xwayland_ready = {.notify = xwaylandready};
static struct wlr_xwayland *xwayland;
#endif

/* configuration, allows nested code to access above variables */
#include "config.h"

/* attempt to encapsulate suck into one file */
#include "client.h"
static int cfgbindcombo(char *combo, uint32_t *mods, xkb_keysym_t *sym);
#ifdef HYPR
#include "hypr.c"
#include "hyprexport.c"
#endif

/* function implementations */
static int
monunblock(void *data)
{
	/* a client sat on its configure long enough to freeze the output: come
	 * back and draw the frame without it */
	Monitor *m = data;

	if (m->wlr_output->enabled)
		wlr_output_schedule_frame(m->wlr_output);
	return 0;
}

float
animease(const float *curve, float t)
{
	/* CSS cubic-bezier(x1, y1, x2, y2): the curve runs from (0,0) to (1,1),
	 * so x(u) is solved for the wanted time and y(u) is the eased progress.
	 * Newton converges in a couple of steps for the usual control points. */
	float u = t, x, dx, mu;
	int i;

	if (t <= 0.0f)
		return 0.0f;
	if (t >= 1.0f)
		return 1.0f;
	for (i = 0; i < 8; i++) {
		mu = 1.0f - u;
		x = 3.0f * mu * mu * u * curve[0] + 3.0f * mu * u * u * curve[2]
				+ u * u * u;
		dx = 3.0f * mu * mu * curve[0]
				+ 6.0f * mu * u * (curve[2] - curve[0])
				+ 3.0f * u * u * (1.0f - curve[2]);
		if (fabsf(x - t) < 0.0005f || fabsf(dx) < 1e-5f)
			break;
		u -= (x - t) / dx;
		u = u < 0.0f ? 0.0f : u > 1.0f ? 1.0f : u;
	}
	mu = 1.0f - u;
	return 3.0f * mu * mu * u * curve[1] + 3.0f * mu * u * u * curve[3]
			+ u * u * u;
}

void
animkick(Monitor *m)
{
	if (!m)
		return;
	m->lastanimtick = now_ms();
	wlr_output_schedule_frame(m->wlr_output);
}

void
animstop(Monitor *m)
{
	Client *c;

	wl_list_for_each(c, &clients, link) {
		if (c->mon != m)
			continue;
		c->anim.active = 0;
		c->anim.fadein = 0;
		c->anim.workspace = 0;
		c->anim.hide = 0;
		c->anim.swipe = 0;
		c->anim.zoom = 0;
		clientunscale(c);
		wlr_scene_node_set_position(&c->scene->node, c->geom.x, c->geom.y);
		if (c->surfbuf)
			wlr_scene_buffer_set_opacity(c->surfbuf, clientopacity(c));
	}
}

uint32_t
now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void
logfilter(enum wlr_log_importance importance, const char *fmt, va_list args)
{
	struct timespec ts;
	/* scenefx spams this once per frame while blur is visible */
	if (strstr(fmt, "Failed to use optimized blur"))
		return;
	if (importance > wlr_log_get_verbosity())
		return;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	fprintf(stderr, "%02u:%02u:%02u.%03u ", (unsigned)(ts.tv_sec / 3600) % 100,
			(unsigned)(ts.tv_sec / 60) % 60, (unsigned)ts.tv_sec % 60,
			(unsigned)(ts.tv_nsec / 1000000));
	vfprintf(stderr, fmt, args);
	fputc('\n', stderr);
}

static void
findsurfbuf(struct wlr_scene_buffer *buffer, int sx, int sy, void *data)
{
	Client *c = data;
	struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(buffer);
	if (s && s->surface == client_surface(c))
		c->surfbuf = buffer;
}

static void
findlayerbuf(struct wlr_scene_buffer *buffer, int sx, int sy, void *data)
{
	LayerSurface *l = data;
	struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(buffer);
	if (s && s->surface == l->layer_surface->surface)
		wlr_scene_blur_set_transparency_mask_source(l->blur, buffer);
}

static float
clientopacity(Client *c)
{
	if (!opacityenabled || c->isfullscreen || c->isfakefull)
		return 1.0f;
	return win_opacity;
}

int
boxclip(struct wlr_box *b, const struct wlr_box *clip)
{
	/* shrink b to the part inside clip; 0 when nothing is left */
	return wlr_box_intersection(b, b, clip) && !wlr_box_empty(b);
}

/* place a frame piece, cut down to the part of it inside crop (frame-relative,
 * NULL for none); a piece left with nothing is parked at zero size */
static void
rectplace(struct wlr_scene_rect *rect, int x, int y, int w, int h,
		const struct wlr_box *crop)
{
	struct wlr_box b = {x, y, w, h};

	if (crop && !boxclip(&b, crop)) {
		wlr_scene_rect_set_size(rect, 0, 0);
		return;
	}
	wlr_scene_rect_set_size(rect, b.width, b.height);
	wlr_scene_node_set_position(&rect->node, b.x, b.y);
}

void
clientborders(Client *c, int width, int height, int bw, int radius,
		const struct wlr_box *crop)
{
	/* the four edges are square and the corners carry the radius, so a
	 * transparent client keeps a real rounded outline */
	int horizontal, vertical;

	if (!c->border.top)
		return;
	horizontal = MAX(0, width - 2 * radius);
	vertical = MAX(0, height - 2 * radius);

	rectplace(c->border.top, radius, 0, horizontal, bw, crop);
	rectplace(c->border.bottom, radius, MAX(0, height - bw), horizontal, bw, crop);
	rectplace(c->border.left, 0, radius, bw, vertical, crop);
	rectplace(c->border.right, MAX(0, width - bw), radius, bw, vertical, crop);

	rectplace(c->border.top_left, 0, 0, radius, radius, crop);
	rectplace(c->border.top_right, MAX(0, width - radius), 0, radius, radius, crop);
	rectplace(c->border.bottom_right, MAX(0, width - radius),
			MAX(0, height - radius), radius, radius, crop);
	rectplace(c->border.bottom_left, 0, MAX(0, height - radius),
			radius, radius, crop);

	if (c->blur) {
		struct wlr_box b = {bw, bw, MAX(0, width - 2 * bw), MAX(0, height - 2 * bw)};
		if (crop && !boxclip(&b, crop))
			b.width = b.height = 0;
		wlr_scene_blur_set_size(c->blur, b.width, b.height);
		wlr_scene_blur_set_corner_radius(c->blur, MAX(0, radius - bw));
		wlr_scene_node_set_position(&c->blur->node, b.x, b.y);
	}
}

/* a window alone on its workspace fills the screen like a phone app: square corners */
static int
cornerfor(Client *c)
{
	Client *o;
	if (c->isfullscreen || c->isfakefull)
		return 0;
	wl_list_for_each(o, &clients, link)
		if (o != c && VISIBLEON(o, c->mon) && !o->isfloating && !c->isfloating)
			return MAX(0, corner_radius);
	return c->isfloating ? MAX(0, corner_radius) : 0;
}

int
borderwanted(Client *c)
{
	/* the frame the focus state asks for, before the monitor crop */
	return !decorhidden && !c->isfullscreen && !c->isfakefull
			&& (unfocused_borders
				|| client_surface(c) == seat->keyboard_state.focused_surface);
}

/* the crop box of c's monitor, relative to the client's scene tree */
static void
clientcropbox(Client *c, struct wlr_box *crop)
{
	*crop = (struct wlr_box){
		.x = c->mon->m.x - c->scene->node.x,
		.y = c->mon->m.y - c->scene->node.y,
		.width = c->mon->m.width, .height = c->mon->m.height,
	};
}

static void
clientoffscreen(Client *c, int off)
{
	off = !!off;
	if (c->offscreen == off)
		return;
	c->offscreen = off;
	if (c->scene_surface)
		wlr_scene_node_set_enabled(&c->scene_surface->node, !off);
	client_set_border_enabled(c, !off && borderwanted(c));
	if (c->blur)
		wlr_scene_node_set_enabled(&c->blur->node, !off && blurenabled
				&& !c->isfullscreen && !c->isfakefull);
}

/* Everything a window paints stays on its own monitor.  The scroll strip and
 * the drift canvas legitimately hang past the edge, a workspace slide starts
 * a whole screen away and a retile can cross it for a few frames; without
 * this the overhang is drawn on whichever output sits next door. */
void
clientclip(Client *c)
{
	struct wlr_box clip, crop, vis;
	int bw, sx1, sy1, sx2, sy2, r;

	if (!c->mon || !c->scene || !c->scene_surface
			|| !client_surface(c)->mapped || client_is_unmanaged(c))
		return;
	/* the scaled paths (camera zoom, open animation) crop for themselves */
	if (c->bufscale != 1.0 || (c->anim.scale > 0.0f && c->anim.scale < 1.0f))
		return;
	bw = (int)c->bw;
	clientcropbox(c, &crop);
	vis = (struct wlr_box){0, 0, c->geom.width, c->geom.height};
	if (!boxclip(&vis, &crop)) {
		clientoffscreen(c, 1);
		return;
	}
	clientoffscreen(c, 0);

	client_get_clip(c, &clip);
	if (DRIFTLT(c->mon) && c->oncanvas && !c->isfloating
			&& !c->isfullscreen && !c->isfakefull) {
		clip.width = MAX(1, c->canvas.width - 2 * bw);
		clip.height = MAX(1, c->canvas.height - 2 * bw);
	}
	/* the surface sits at (bw, bw) in the frame; keep the part of it that
	 * the visible box covers.  The clip is in surface coordinates and does
	 * not move anything: wlroots parks the cropped buffer at the clip's
	 * own origin, so the tree stays where it is and the cut lands right. */
	sx1 = MAX(bw, vis.x);
	sy1 = MAX(bw, vis.y);
	sx2 = MIN(bw + clip.width, vis.x + vis.width);
	sy2 = MIN(bw + clip.height, vis.y + vis.height);
	if (sx2 <= sx1 || sy2 <= sy1) {
		wlr_scene_node_set_enabled(&c->scene_surface->node, 0);
	} else {
		clip.x += sx1 - bw;
		clip.y += sy1 - bw;
		clip.width = sx2 - sx1;
		clip.height = sy2 - sy1;
		wlr_scene_node_set_enabled(&c->scene_surface->node, 1);
		wlr_scene_subsurface_tree_set_clip(&c->scene_surface->node, &clip);
	}
	r = MIN(cornerfor(c), MIN(c->geom.width, c->geom.height) / 2);
	clientborders(c, c->geom.width, c->geom.height, bw, r, &vis);
}

void
clientplace(Client *c, int x, int y)
{
	wlr_scene_node_set_position(&c->scene->node, x, y);
	clientclip(c);
}

/* SceneFX 0.5 keeps the backdrop blur in a node of its own that is masked by
 * the buffer it belongs to, so a cloned buffer needs a cloned blur node. */
static void
cloneblur(struct wlr_scene_buffer *src, struct wlr_scene_buffer *clone,
		struct wlr_scene_tree *tree, int width, int height,
		struct fx_corner_radii corners)
{
	struct wlr_scene_blur *blur;

	if (!linked_nodes_get_sibling(&src->blur)
			|| !(blur = wlr_scene_blur_create(tree, width, height)))
		return;
	wlr_scene_blur_set_corner_radii(blur, corners);
	wlr_scene_blur_set_transparency_mask_source(blur, clone);
	wlr_scene_node_set_position(&blur->node, clone->node.x, clone->node.y);
	wlr_scene_node_place_below(&blur->node, &clone->node);
}

void
applyeffects(Client *c)
{
	int fs = c->isfullscreen || c->isfakefull;
	int r = cornerfor(c);
	int visible = !decorhidden && !fs && (unfocused_borders
			|| client_surface(c) == seat->keyboard_state.focused_surface);

	if (c->border.top) {
		client_set_border_enabled(c, visible);

		/* Edges are square; only the four outer pieces carry the radius. */
		wlr_scene_rect_set_corner_radii(c->border.top, corner_radii_none());
		wlr_scene_rect_set_corner_radii(c->border.bottom, corner_radii_none());
		wlr_scene_rect_set_corner_radii(c->border.left, corner_radii_none());
		wlr_scene_rect_set_corner_radii(c->border.right, corner_radii_none());
		wlr_scene_rect_set_corner_radii(c->border.top_left, corner_radii_new(r, 0, 0, 0));
		wlr_scene_rect_set_corner_radii(c->border.top_right, corner_radii_new(0, r, 0, 0));
		wlr_scene_rect_set_corner_radii(c->border.bottom_right, corner_radii_new(0, 0, r, 0));
		wlr_scene_rect_set_corner_radii(c->border.bottom_left, corner_radii_new(0, 0, 0, r));
	}
	if (c->surfbuf) {
		wlr_scene_buffer_set_corner_radius(c->surfbuf, MAX(0, r - (int)c->bw));
		if (!c->anim.fadein)
			wlr_scene_buffer_set_opacity(c->surfbuf, clientopacity(c));
	}
	if (c->blur) {
		/* masking the blur with the surface keeps it inside the parts the
		 * client actually paints, the way ignore_transparent used to */
		wlr_scene_blur_set_transparency_mask_source(c->blur, c->surfbuf);
		wlr_scene_node_set_enabled(&c->blur->node, blurenabled && !fs
				&& !c->offscreen);
	}
}

void
toggleopacity(const Arg *arg)
{
	Client *c;
	opacityenabled ^= 1;
	wl_list_for_each(c, &clients, link)
		applyeffects(c);
}

static bool
closeaniminput(struct wlr_scene_buffer *buffer, double *sx, double *sy)
{
	return false;
}

static void
closeanimclone(struct wlr_scene_buffer *buffer, int sx, int sy, void *data)
{
	CloseAnim *a = data;
	CloseBuffer *b;
	int width, height;

	if (!buffer->buffer)
		return;
	width = buffer->dst_width > 0 ? buffer->dst_width
			: buffer->src_box.width > 0 ? (int)round(buffer->src_box.width)
			: buffer->buffer->width;
	height = buffer->dst_height > 0 ? buffer->dst_height
			: buffer->src_box.height > 0 ? (int)round(buffer->src_box.height)
			: buffer->buffer->height;
	if (width <= 0 || height <= 0)
		return;

	b = ecalloc(1, sizeof(*b));
	b->scene = wlr_scene_buffer_create(a->tree, buffer->buffer);
	b->scene->point_accepts_input = closeaniminput;
	if (buffer->src_box.width > 0 && buffer->src_box.height > 0)
		wlr_scene_buffer_set_source_box(b->scene, &buffer->src_box);
	wlr_scene_buffer_set_transform(b->scene, buffer->transform);
	wlr_scene_buffer_set_dest_size(b->scene, width, height);
	wlr_scene_buffer_set_opacity(b->scene, buffer->opacity);
	wlr_scene_buffer_set_filter_mode(b->scene, WLR_SCALE_FILTER_BILINEAR);
	wlr_scene_buffer_set_corner_radii(b->scene, buffer->corners);
	wlr_scene_buffer_set_opaque_region(b->scene, &buffer->opaque_region);
	b->opacity = buffer->opacity;
	b->x = sx - a->x;
	b->y = sy - a->y;
	b->width = width;
	b->height = height;
	wlr_scene_node_set_position(&b->scene->node, b->x, b->y);
	cloneblur(buffer, b->scene, a->tree, width, height, buffer->corners);
	a->minx = MIN(a->minx, b->x);
	a->miny = MIN(a->miny, b->y);
	a->maxx = MAX(a->maxx, b->x + width);
	a->maxy = MAX(a->maxy, b->y + height);
	wl_list_insert(&a->buffers, &b->link);
}

static void
closeanimdestroy(CloseAnim *a)
{
	CloseBuffer *b, *tmp;

	wl_list_remove(&a->link);
	wl_list_for_each_safe(b, tmp, &a->buffers, link) {
		wl_list_remove(&b->link);
		free(b);
	}
	wlr_scene_node_destroy(&a->tree->node);
	free(a);
}

static int
closeanimstart(struct wlr_scene_node *node, struct wlr_scene_tree *parent,
		Monitor *m)
{
	CloseAnim *a;

	if (!animations || animation_type_close == AnimNone
			|| animation_duration_close <= 0 || overview_visible
			|| !node || !parent || !overviewvalid(m))
		return 0;
	a = ecalloc(1, sizeof(*a));
	if (!wlr_scene_node_coords(node, &a->x, &a->y)) {
		free(a);
		return 0;
	}
	a->tree = wlr_scene_tree_create(parent);
	a->mon = m;
	a->minx = a->miny = INT_MAX;
	a->maxx = a->maxy = INT_MIN;
	wl_list_init(&a->buffers);
	wlr_scene_node_for_each_buffer(node, closeanimclone, a);
	if (wl_list_empty(&a->buffers)) {
		wlr_scene_node_destroy(&a->tree->node);
		free(a);
		return 0;
	}
	wlr_scene_node_set_position(&a->tree->node, a->x, a->y);
	wl_list_insert(&close_anims, &a->link);
	animkick(m);
	return 1;
}

static void
clientcloseanim(Client *c)
{
	Monitor *m;
	struct wlr_scene_tree *parent;

	if (!c || !c->scene || c->anim.closing)
		return;
	m = c->mon ? c->mon : xytomon(c->geom.x + c->geom.width / 2.0,
			c->geom.y + c->geom.height / 2.0);
	parent = client_is_unmanaged(c) ? layers[LyrFloat]
			: layers[c->isfullscreen ? LyrFS : LyrFloat];
	c->anim.closing = closeanimstart(&c->scene->node, parent, m);
}

static int
closeanimadvance(Monitor *m, float dt)
{
	CloseAnim *a, *tmp;
	CloseBuffer *b;
	float e, scale;
	int cx, cy, duration, slide, pending = 0;

	duration = MAX(60, animation_duration_close);
	/* zoom collapses the window towards its own centre, slide drops it out
	 * of the way; both fade, and a plain fade holds the window still */
	slide = animation_type_close == AnimSlide
			? MAX(16, MIN(64, (m->w.height ? m->w.height : 720) / 24)) : 0;
	wl_list_for_each_safe(a, tmp, &close_anims, link) {
		if (a->mon != m)
			continue;
		a->t += duration > 0 ? dt / (float)duration : 1.0f;
		if (a->t >= 1.0f) {
			closeanimdestroy(a);
			continue;
		}
		pending = 1;
		e = animease(animation_curve_close, a->t);
		scale = animation_type_close == AnimZoom
				? 1.0f - (1.0f - zoom_end_ratio) * e : 1.0f;
		cx = (a->minx + a->maxx) / 2;
		cy = (a->miny + a->maxy) / 2;
		wlr_scene_node_set_position(&a->tree->node, a->x,
				a->y + (int)roundf(slide * e));
		wl_list_for_each(b, &a->buffers, link) {
			wlr_scene_node_set_position(&b->scene->node,
					cx + (int)roundf((b->x - cx) * scale),
					cy + (int)roundf((b->y - cy) * scale));
			wlr_scene_buffer_set_dest_size(b->scene,
					MAX(1, (int)roundf(b->width * scale)),
					MAX(1, (int)roundf(b->height * scale)));
			wlr_scene_buffer_set_opacity(b->scene, b->opacity * (1.0f - e));
		}
	}
	return pending;
}

static void
closeanimclear(Monitor *m)
{
	CloseAnim *a, *tmp;

	wl_list_for_each_safe(a, tmp, &close_anims, link)
		if (!m || a->mon == m)
			closeanimdestroy(a);
}

static void
layersetopacity(struct wlr_scene_buffer *buffer, int sx, int sy, void *data)
{
	float opacity = *(float *)data;

	wlr_scene_buffer_set_opacity(buffer, opacity);
}

static int
layeranimated(LayerSurface *l)
{
	return l->layer_surface->current.keyboard_interactive
			!= ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE
			&& l->layer_surface->current.layer >= ZWLR_LAYER_SHELL_V1_LAYER_TOP;
}

static void
layeropacity(LayerSurface *l, float opacity)
{
	wlr_scene_node_for_each_buffer(&l->scene->node, layersetopacity, &opacity);
	wlr_scene_node_for_each_buffer(&l->popups->node, layersetopacity, &opacity);
	if (l->blur)
		wlr_scene_blur_set_alpha(l->blur, opacity);
}

static void
layeranimstart(LayerSurface *l)
{
	if (!animations || animation_type_open == AnimNone
			|| animation_duration_open <= 0 || overview_visible
			|| !layeranimated(l))
		return;
	l->anim.active = 1;
	l->anim.t = 0.0f;
	l->anim.to_y = l->scene->node.y;
	l->anim.from_y = l->anim.to_y + 18;
	wlr_scene_node_set_position(&l->scene->node,
			l->scene->node.x, l->anim.from_y);
	wlr_scene_node_set_position(&l->popups->node,
			l->scene->node.x, l->anim.from_y);
	layeropacity(l, 0.0f);
	animkick(l->mon);
}

static int
layeranimadvance(Monitor *m, float dt)
{
	LayerSurface *l;
	float e, opacity;
	int i, duration, pending = 0;

	duration = MAX(60, animation_duration_open);
	for (i = 0; i < 4; i++) {
		wl_list_for_each(l, &m->layers[i], link) {
			/* the shell fades the menu out over 240 ms, OutCubic: (1 - p)^3 */
			if (l->blur && l->blurfade > 0.0f) {
				l->blurfade = MAX(0.0f, l->blurfade - dt / 240.0f);
				wlr_scene_blur_set_alpha(l->blur, l->blurfade * l->blurfade * l->blurfade);
				pending |= l->blurfade > 0.0f;
			}
			if (!l->anim.active)
				continue;
			l->anim.t += duration > 0 ? dt / (float)duration : 1.0f;
			if (l->anim.t >= 1.0f) {
				l->anim.active = 0;
				wlr_scene_node_set_position(&l->scene->node,
						l->scene->node.x, l->anim.to_y);
				wlr_scene_node_set_position(&l->popups->node,
						l->scene->node.x, l->anim.to_y);
				layeropacity(l, 1.0f);
				continue;
			}
			pending = 1;
			e = animease(animation_curve_open, l->anim.t);
			opacity = e;
			wlr_scene_node_set_position(&l->scene->node, l->scene->node.x,
					l->anim.from_y
					+ (int)roundf((l->anim.to_y - l->anim.from_y) * e));
			wlr_scene_node_set_position(&l->popups->node,
					l->scene->node.x, l->scene->node.y);
			layeropacity(l, opacity);
		}
	}
	return pending;
}

void
applybounds(Client *c, struct wlr_box *bbox)
{
	/* set minimum possible */
	c->geom.width = MAX(1 + 2 * (int)c->bw, c->geom.width);
	c->geom.height = MAX(1 + 2 * (int)c->bw, c->geom.height);

	if (c->geom.x >= bbox->x + bbox->width)
		c->geom.x = bbox->x + bbox->width - c->geom.width;
	if (c->geom.y >= bbox->y + bbox->height)
		c->geom.y = bbox->y + bbox->height - c->geom.height;
	if (c->geom.x + c->geom.width <= bbox->x)
		c->geom.x = bbox->x;
	if (c->geom.y + c->geom.height <= bbox->y)
		c->geom.y = bbox->y;
}

/* games open fullscreen; their dialogs, splashes and child windows do not */
static int
fullscreenapp(Client *c)
{
	char buf[sizeof fullscreen_apps], *t, *save = NULL;
	const char *id = client_get_appid(c);

	if (!id || !*id || client_is_unmanaged(c) || client_get_parent(c))
		return 0;
#ifdef XWAYLAND
	if (client_is_x11(c)) {
		struct wlr_xwayland_surface *s = c->surface.xwayland;
		if (s->modal
				|| wlr_xwayland_surface_has_window_type(s, WLR_XWAYLAND_NET_WM_WINDOW_TYPE_DIALOG)
				|| wlr_xwayland_surface_has_window_type(s, WLR_XWAYLAND_NET_WM_WINDOW_TYPE_SPLASH)
				|| wlr_xwayland_surface_has_window_type(s, WLR_XWAYLAND_NET_WM_WINDOW_TYPE_TOOLBAR)
				|| wlr_xwayland_surface_has_window_type(s, WLR_XWAYLAND_NET_WM_WINDOW_TYPE_UTILITY))
			return 0;
	}
#endif
	snprintf(buf, sizeof buf, "%s", fullscreen_apps);
	for (t = strtok_r(buf, " ,", &save); t; t = strtok_r(NULL, " ,", &save))
		if (!fnmatch(t, id, 0))
			return 1;
	return 0;
}

/* every app opens alone: the current workspace if empty, else the next empty
 * one, else the current one */
static int
wsoccupied(Monitor *m, unsigned int ws)
{
	Client *c;

	wl_list_for_each(c, &clients, link) {
		if (c->mon == m && c->ws == ws && !client_is_unmanaged(c))
			return 1;
	}
	return 0;
}

/* the free workspace, or the last one when all are taken: wscompact keeps the row without gaps */
static unsigned int
wslimit(Monitor *m)
{
	int ws = NUMWS - 1;

	while (ws >= 0 && !wsoccupied(m, (unsigned int)ws))
		ws--;
	return (unsigned int)MIN(ws + 1, NUMWS - 1);
}

/* the workspace one step that way, or -1 at the end of the row */
static int
wsnext(Monitor *m, int dir)
{
	unsigned int limit = wslimit(m);

	if (dir > 0)
		return m->ws < limit ? (int)m->ws + 1 : -1;
	return m->ws ? (int)MIN(m->ws - 1, limit) : -1;
}

static unsigned int
freews(Monitor *m)
{
	unsigned int limit = wslimit(m);

	return wsoccupied(m, limit) ? m->ws : limit;
}

static LayerSurface *
phonetray(Monitor *m)
{
	LayerSurface *l;

	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link) {
		if (l->mapped && !strcmp(l->layer_surface->namespace, TRAY_NAMESPACE))
			return l;
	}
	return NULL;
}

/* turned, the shell stands the tray at the right edge as a column */
static int
trayside(Monitor *m, LayerSurface *l)
{
	return m->m.width > m->m.height && (int)l->layer_surface->current.actual_width < m->m.width / 2;
}

/* the tray sits off screen and takes no touches unless the overview or an empty
 * workspace wants it; the overview's progress drives it so it follows the finger */
static void
traysync(Monitor *m)
{
	LayerSurface *l;
	float t;
	int h, x, y;

	/* the clock is for the home screen only, not the gaps between windows */
	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM], link) {
		if (!strcmp(l->layer_surface->namespace, HOME_NAMESPACE))
			wlr_scene_node_set_enabled(&l->scene->node, l->mapped && !wsoccupied(m, m->ws) && !overview_visible);
		else if (!strcmp(l->layer_surface->namespace, LABELS_NAMESPACE))
			wlr_scene_node_set_enabled(&l->scene->node, 0);
	}
	if (!(l = phonetray(m)))
		return;
	t = overview_visible ? m->overview_dim : 0.0f;
	if (!wsoccupied(m, m->ws))
		t = flick_ws >= 0 && flick_dim > 0.0f
				? 1.0f - (1.0f - flick_dim) * MIN(1.0f, m->overview_dim / flick_dim) : 1.0f;
	if (trayside(m, l)) {
		x = m->m.x + m->m.width - (int)roundf(t * l->layer_surface->current.actual_width);
		y = m->m.y;
	} else {
		x = m->m.x;
		h = (int)l->layer_surface->current.actual_height;
		y = m->m.y + m->m.height - BAR_ZONE - (int)roundf(t * h);
	}
	wlr_scene_node_set_position(&l->scene->node, x, y);
	wlr_scene_node_set_position(&l->popups->node, x, y);
	wlr_scene_node_set_enabled(&l->scene->node, t > 0.0f);
}

/* the bar takes no room: it lies over the content, for a moment */
static LayerSurface *
keyboardlayer(Monitor *m)
{
	LayerSurface *l;

	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link)
		if (l->mapped && !strcmp(l->layer_surface->namespace, "phone-keyboard"))
			return l;
	return NULL;
}

static int
keyboardshown(Monitor *m)
{
	return keyboardlayer(m) != NULL;
}

static void
pillplace(Monitor *m)
{
	float t, a;
	int x, y;

	if (!pill || m != selmon)
		return;
	/* over the keyboard's strip and in the overview it does not hide or slide */
	t = keyboardshown(m) || overview_active ? 1.0f : bar_t;
	y = m->m.y + m->m.height - (int)roundf(t * PILL_ZONE) + (PILL_ZONE - PILL_H) / 2;
	x = m->m.x + (m->m.width - PILL_W) / 2;
	/* in the overview drag it rises a little with the finger and fades */
	a = 1.0f;
	if (touch_gesture == 3 && finger.mode == 1 && finger.m == m) {
		t = pill_a;
		a = MAX(0.0f, 1.0f - pillprogress() / 0.5f);
		y = m->m.y + m->m.height - PILL_ZONE + (PILL_ZONE - PILL_H) / 2
				- (int)round(MIN(PILL_LIFT, 0.3 * MAX(0.0, finger.y0 - finger.y)));
		t *= a;
	}
	wlr_scene_rect_set_color(bar_bg, (const float[4]){0.0f, 0.0f, 0.0f, 0.3f * a});
	wlr_scene_rect_set_color(pill, (const float[4]){0.9f * a, 0.9f * a, 0.9f * a, 0.9f * a});
	wlr_scene_node_set_position(&bar_bg->node, x - PILL_HALO, y - PILL_HALO);
	wlr_scene_node_set_position(&pill->node, x, y);
	/* the keyboard lives in this same layer and mapped later */
	wlr_scene_node_raise_to_top(&bar_bg->node);
	wlr_scene_node_raise_to_top(&pill->node);
	wlr_scene_node_set_enabled(&bar_bg->node, t > 0.0f);
	wlr_scene_node_set_enabled(&pill->node, t > 0.0f);
}

static int
barslide(void *data)
{
	float step = 16.0f / BAR_SLIDE_MS;

	bar_t = bar_shown ? MIN(1.0f, bar_t + step) : MAX(0.0f, bar_t - step);
	pillplace(selmon);
	if (bar_t != (bar_shown ? 1.0f : 0.0f))
		wl_event_source_timer_update(bar_slide, 16);
	return 0;
}

static int
barexpire(void *data)
{
	barset(0);
	return 0;
}

static void
barset(int shown)
{
	if (!bar_slide)
		return;
	wl_event_source_timer_update(bar_timer, shown && !bar_hover ? BAR_HIDE_MS : 0);
	if (!shown)
		bar_hover = 0;
	if (shown == bar_shown)
		return;
	bar_shown = shown;
	if (animations && animation_duration > 0) {
		wl_event_source_timer_update(bar_slide, 1);
	} else {
		bar_t = shown ? 1.0f : 0.0f;
		pillplace(selmon);
	}
}

void
applyrules(Client *c)
{
	/* rule matching */
	const char *appid, *title;
	int i, ws = -1;
	const Rule *r;
	Monitor *mon = selmon, *m;
	Placement *pl;

	appid = client_get_appid(c);
	title = client_get_title(c);

	for (r = rules; r < END(rules); r++) {
		if ((!r->title || strstr(title, r->title))
				&& (!r->id || strstr(appid, r->id))) {
			c->isfloating = r->isfloating;
			if (r->ws > 0 && r->ws <= NUMWS)
				ws = r->ws - 1;
			i = 0;
			wl_list_for_each(m, &mons, link) {
				if (r->monitor == i++)
					mon = m;
			}
		}
	}

	c->isfloating |= client_is_float_type(c);
	/* before the first buffer only the scale matters: an app that is slow changes nothing on screen */
	if (!client_surface(c)->mapped) {
		client_set_scale(client_surface(c), mon->wlr_output->scale);
		return;
	}
	barset(0);
	if (!c->isfloating && (pl = placementfind(c))) {
		/* it was dropped somewhere: goes there, and whoever moved on stays where they are */
		place_anchor = pl->anchor;
		place_side = pl->side;
		pl->pid = 0;
		if (place_anchor) {
			c->isfullscreen = 0;
			if (place_anchor->isfullscreen)
				setfullscreen(place_anchor, 0);
		}
		mon = place_anchor ? place_anchor->mon : mon;
		setmon(c, mon, (int)(place_anchor ? place_anchor->ws : freews(mon)));
		place_anchor = NULL;
		/* the tree it joined may be on a workspace nobody is looking at */
		if (!SCROLLLT(mon) && !DRIFTLT(mon))
			tilehidden(mon);
		return;
	}
	setmon(c, mon, ws < 0 && !c->isfloating ? (int)freews(mon) : ws);
	if (c->mon == mon && !c->isfloating) {
		selmon = mon;
		openswitch(mon, c->ws);
	}
}

static int wscompact(Monitor *m);

/* the new window grows over what was there, which fades: one motion, no slide */
static void
openswitch(Monitor *m, unsigned int ws)
{
	Arg a = {.ui = ws};
	Client *w;
	int oldanim = animations, cut = animations && overview_visible && !touch_gesture;

	if (cut) {
		overview_visible = 0;
		closeanimstart(&overview_scene->node, layers[LyrBottom], m);
		overview_visible = 1;
	} else if (animations && !overview_visible && m->ws != ws) {
		wl_list_for_each(w, &clients, link)
			if (VISIBLEON(w, m) && w->scene->node.enabled && !client_is_unmanaged(w))
				closeanimstart(&w->scene->node, layers[LyrBottom], m);
		animations = 0;
	}
	viewws(&a);
	animations = oldanim;
	overviewset(0);
	if (cut) {
		m->overview_animating = 0;
		overviewfinish();
	}
}

static void
bsp_flip(Node *n)
{
	if (!n || n->leaf)
		return;
	n->horiz = !n->horiz;
	bsp_flip(n->a);
	bsp_flip(n->b);
}

static void
tilehidden(Monitor *m)
{
	Client *c;
	unsigned int ws, fs = 0;

	wl_list_for_each(c, &clients, link)
		if (c->mon == m && c->isfullscreen)
			fs |= 1u << c->ws;
	for (ws = 0; ws < NUMWS; ws++)
		if (ws != m->ws && !(fs & 1u << ws))
			bsp_tile(m->tree[ws], m->w);
}

/* a turn or a new bar height reaches the other workspaces now, not when they are shown */
static void
arrangehidden(Monitor *m)
{
	Client *c;

	if (!SCROLLLT(m) && !DRIFTLT(m))
		tilehidden(m);
	wl_list_for_each(c, &clients, link)
		if (c->mon == m && c->isfullscreen && c->ws != m->ws)
			resize(c, m->m, 0);
}

void
arrange(Monitor *m)
{
	Client *c, *fs = NULL;

	if (!m->wlr_output->enabled || m->mirroring || wscompact(m))
		return;

	/* a fullscreen client (real or fake) is shown alone on its workspace;
	 * in the scroll layout fake fullscreen leaves the strip mapped beneath
	 * so it just grows over it and shrinks back, like niri */
	wl_list_for_each(c, &clients, link) {
		if (!fs && VISIBLEON(c, m) && (c->isfullscreen || c->isfakefull))
			fs = c;
	}

	wl_list_for_each(c, &clients, link) {
		if (c->mon == m) {
			int vis = VISIBLEON(c, m) && (!fs || c == fs
					|| (SCROLLLT(m) && fs->isfakefull));
			int render = vis || (c->anim.workspace && c->anim.hide) || wsdragshows(c);
			wlr_scene_node_set_enabled(&c->scene->node, render);
			/* behind the lock nobody sees it either */
			client_set_suspended(c, !vis || locked);
			if (vis) {
				applyeffects(c); /* the corners follow how many windows share the workspace */
				clientclip(c); /* and the crop hides again the border pieces applyeffects enabled */
			}
		}
	}

	wlr_scene_node_set_enabled(&m->fullscreen_bg->node, fs && fs->isfullscreen);
	traysync(m);

	if (fs && fs->isfakefull && SCROLLLT(m) && !fs->isfloating) {
		scroll_tile(m);
		resize(fs, m->m, 0); /* cover the whole output */
	} else if (fs) {
		if (fs->isfakefull) {
			resize(fs, m->w, 0);
		} else {
			/* the field being typed in must stay above the keyboard */
			struct wlr_box full = m->m;

			if (keyboardshown(m))
				full.height = m->w.y + m->w.height - m->m.y;
			resize(fs, full, 0);
		}
	} else if (SCROLLLT(m)) {
		scroll_tile(m);
	} else if (DRIFTLT(m)) {
		drifttile(m);
	} else {
		bsp_tile(m->tree[m->ws], m->w);
		/* the other cards show their real layout too */
		if (overview_visible)
			tilehidden(m);
	}
	motionnotify(0, NULL, 0, 0, 0, 0);
	checkidleinhibitor(NULL);
	ipcnotifyall();
	if (overview_visible)
		overview_dirty = 1;
}

void
arrangelayer(Monitor *m, struct wl_list *list, struct wlr_box *usable_area, int exclusive)
{
	LayerSurface *l;
	struct wlr_box full_area = m->m;

	wl_list_for_each(l, list, link) {
		struct wlr_layer_surface_v1 *layer_surface = l->layer_surface;

		if (!layer_surface->initialized)
			continue;

		if (exclusive != (layer_surface->current.exclusive_zone > 0))
			continue;

		wlr_scene_layer_surface_v1_configure(l->scene_layer, &full_area, usable_area);
		wlr_scene_node_set_position(&l->popups->node, l->scene->node.x, l->scene->node.y);
	}
}

void
arrangelayers(Monitor *m)
{
	int i;
	struct wlr_box usable_area = m->m;
	LayerSurface *l;
	uint32_t layers_above_shell[] = {
		ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
		ZWLR_LAYER_SHELL_V1_LAYER_TOP,
	};
	if (!m->wlr_output->enabled || m->mirroring)
		return;
	/* Arrange exclusive surfaces from top->bottom */
	for (i = 3; i >= 0; i--)
		arrangelayer(m, &m->layers[i], &usable_area, 1);

	if (!wlr_box_equal(&usable_area, &m->w)) {
		m->w = usable_area;
		arrange(m);
		arrangehidden(m);
		if (overview_visible)
			overviewrelayout();
	}

	/* Arrange non-exlusive surfaces from top->bottom */
	for (i = 3; i >= 0; i--)
		arrangelayer(m, &m->layers[i], &usable_area, 0);
	traysync(m);
	pillplace(m);
	menubar(m);

	/* Find topmost keyboard interactive layer, if such a layer exists */
	for (i = 0; i < (int)LENGTH(layers_above_shell); i++) {
		wl_list_for_each_reverse(l, &m->layers[layers_above_shell[i]], link) {
			if (locked || !l->layer_surface->current.keyboard_interactive || !l->mapped)
				continue;
			/* Deactivate the focused client. */
			focusclient(NULL, 0);
			exclusive_focus = l;
			client_notify_enter(l->layer_surface->surface, wlr_seat_get_keyboard(seat));
			return;
		}
	}

	/* Nothing above the shell wants the keyboard any more. Without this the
	 * grab would stick after e.g. the overview dock closes its search box,
	 * and every later key would go to a surface that stopped asking for it. */
	if (exclusive_focus) {
		exclusive_focus = NULL;
		if (overview_visible)
			wlr_seat_keyboard_notify_clear_focus(seat);
		else
			focusclient(focustop(m), 1);
	}
}

void
axisnotify(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_axis_event *event = data;
	Monitor *m;
	double delta;
	int dir;

	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	delta = event->delta != 0.0 ? event->delta : event->delta_discrete;
	dir = delta > 0.0 ? 1 : delta < 0.0 ? -1 : 0;
	if (!locked && !overview_visible && dir
			&& DRIFTLT((m = xytomon(cursor->x, cursor->y)))) {
		struct wlr_keyboard *kb = wlr_seat_get_keyboard(seat);
		struct wlr_surface *surface = NULL;
		double amount = event->relative_direction
				== WL_POINTER_AXIS_RELATIVE_DIRECTION_INVERTED ? -delta : delta;
		double z = driftz(m, m->ws);
		int super = super_group && super_group->super_down;

		if (super && kb && (wlr_keyboard_get_modifiers(kb) & WLR_MODIFIER_SHIFT)) {
			/* Mod+Shift+wheel zooms at the pointer; plain Mod+wheel keeps
			 * changing workspace, like in the other layouts */
			super_group->super_alone = 0;
			driftzoomto(m, z * (dir > 0 ? 1.0 / drift_zoom_step : drift_zoom_step),
					cursor->x, cursor->y);
			return;
		}
		if (!super) {
			xytonode(cursor->x, cursor->y, &surface, NULL, NULL, NULL, NULL);
			if (!surface) {
				/* over bare canvas, scrolling pans it; over a window the
				 * event belongs to the client */
				if (event->source != WL_POINTER_AXIS_SOURCE_FINGER)
					amount *= 4.0;
				if (event->orientation == WL_POINTER_AXIS_HORIZONTAL_SCROLL)
					m->camx[m->ws] += amount * drift_pan_speed / z;
				else
					m->camy[m->ws] += amount * drift_pan_speed / z;
				driftarrange(m);
				return;
			}
		}
	}
	if (super_group && super_group->super_down
			&& (event->source == WL_POINTER_AXIS_SOURCE_WHEEL
				|| event->source == WL_POINTER_AXIS_SOURCE_WHEEL_TILT)) {
		struct wlr_keyboard *keeb = wlr_seat_get_keyboard(seat);

		super_group->super_alone = 0;
		/* Mod+Ctrl+wheel takes the window along to the workspace it lands on */
		if (dir)
			workspacestepcarry(dir, keeb && (wlr_keyboard_get_modifiers(keeb)
					& WLR_MODIFIER_CTRL));
		return;
	}
	/* over the shell's own surfaces the wheel belongs to them - the overview
	 * dock scrolls its app grid with it - so only steal it elsewhere */
	if (overview_visible && !overviewpassthrough()) {
		if (!overview_active)
			return;
		if (event->source == WL_POINTER_AXIS_SOURCE_WHEEL
				|| event->source == WL_POINTER_AXIS_SOURCE_WHEEL_TILT) {
			if (dir)
				workspacestep(dir);
			return;
		}
		/* two-finger scrolling stays out of workspace switching; the
		 * overview is walked with three fingers, the wheel or the keys */
		return;
	}
	wlr_seat_pointer_notify_axis(seat,
			event->time_msec, event->orientation, event->delta,
			event->delta_discrete, event->source, event->relative_direction);
}

void
swipefocus(int dir)
{
	/* directional focus from a touchpad gesture: no cursor warp */
	Arg a = {.i = dir};
	int oldwarp = warpcursor;

	warpcursor = 0;
	focusdir(&a);
	warpcursor = oldwarp;
}

static int
wsdragshows(Client *c)
{
	return wsdrag.active && wsdrag.dir && c->mon == wsdrag.m && c->ws == wsdrag.nb;
}

static Client *
wsfullscreen(Monitor *m, unsigned int ws)
{
	Client *c;

	wl_list_for_each(c, &clients, link)
		if (c->mon == m && c->ws == ws && (c->isfullscreen || c->isfakefull))
			return c;
	return NULL;
}

/* lay out a workspace that is not on screen, so it can be shown sliding in */
static void
wsdragtile(Monitor *m, unsigned int ws)
{
	unsigned int cur = m->ws;
	Client *c;

	if (!wsfullscreen(m, ws)) {
		m->ws = ws;
		if (SCROLLLT(m))
			scroll_tile(m);
		else
			bsp_tile(m->tree[ws], m->w);
		m->ws = cur;
	}
	wl_list_for_each(c, &clients, link) {
		if (c->mon != m || c->ws != ws)
			continue;
		c->anim.active = c->anim.workspace = c->anim.hide = 0;
	}
}

static int
wsdragspan(void)
{
	return wsdrag.vertical ? wsdrag.m->m.height : wsdrag.m->m.width;
}

static double
wsdragclamp(double travel)
{
	double p = travel / MAX(50, swipe_distance);

	return p < -1.0 ? -1.0 : p > 1.0 ? 1.0 : p;
}

static double
wsdragprogress(void)
{
	return wsdragclamp(wsdrag.shown);
}

static void
wsdragmove(Client *c, int off)
{
	clientplace(c, c->geom.x + (wsdrag.vertical ? 0 : off),
			c->geom.y + (wsdrag.vertical ? off : 0));
}

static void
wsdragplace(void)
{
	Monitor *m = wsdrag.m;
	Client *c, *fs;
	int span = wsdragspan(), off = (int)lround(wsdragprogress() * span);
	int dir = off < 0 ? 1 : off > 0 ? -1 : wsdrag.dir;
	int nb = dir ? wsnext(m, dir) : -1;

	if (nb < 0) { /* the end of the row resists */
		off /= 4;
		dir = 0;
	}
	if (dir != wsdrag.dir) {
		/* the other neighbour: put the old one away, lay out the new one */
		if (wsdrag.dir)
			wl_list_for_each(c, &clients, link)
				if (c->mon == m && c->ws == wsdrag.nb)
					wlr_scene_node_set_enabled(&c->scene->node, 0);
		wsdrag.dir = dir;
		if (dir) {
			wsdrag.nb = (unsigned int)nb;
			wsdragtile(m, wsdrag.nb);
		}
	}
	fs = wsfullscreen(m, wsdrag.nb);
	wl_list_for_each(c, &clients, link) {
		if (c->mon != m || client_is_unmanaged(c))
			continue;
		if (c->ws == m->ws && c->scene->node.enabled) {
			wsdragmove(c, off);
		} else if (wsdrag.dir && c->ws == wsdrag.nb && (!fs || c == fs)) {
			wlr_scene_node_set_enabled(&c->scene->node, 1);
			wsdragmove(c, off + wsdrag.dir * span);
		}
	}
}

static void
wsdragbegin(Monitor *m, int vertical, double pos)
{
	animstop(m);
	wsdrag.m = m;
	wsdrag.active = 1;
	wsdrag.vertical = vertical;
	wsdrag.dir = 0;
	wsdrag.pos = pos;
	wsdrag.shown = 0.0;
	wsdrag.hn = 0;
	wsdrag.lastframe = 0;
	wsdragplace();
	wsdragupdate(0.0);
}

static void
wsdragupdate(double d)
{
	int i = wsdrag.hn++ % LENGTH(wsdrag.hpos);

	wsdrag.pos += d;
	wsdrag.hpos[i] = wsdrag.pos;
	wsdrag.ht[i] = gesture_time;
	/* drawn on the next frame, not per event */
	wlr_output_schedule_frame(wsdrag.m->wlr_output);
}

/* finger speed over the last 100 ms, 0 if they stopped before lifting */
static double
wsdragvel(uint32_t end)
{
	int n = MIN(wsdrag.hn, (int)LENGTH(wsdrag.hpos)), k, i, j = -1;
	int last = (wsdrag.hn - 1) % LENGTH(wsdrag.hpos);

	if (n < 2 || end - wsdrag.ht[last] > 60)
		return 0.0;
	for (k = 1; k < n; k++) {
		i = (wsdrag.hn - 1 - k) % LENGTH(wsdrag.hpos);
		if (wsdrag.ht[last] - wsdrag.ht[i] > 100)
			break;
		j = i;
	}
	if (j < 0 || wsdrag.ht[last] == wsdrag.ht[j])
		return 0.0;
	return (wsdrag.hpos[last] - wsdrag.hpos[j])
			/ (double)(wsdrag.ht[last] - wsdrag.ht[j]);
}

/* ease the shown position toward the fingers, once per frame */
static int
wsdragframe(Monitor *m)
{
	uint32_t t = now_ms();
	double dt, a;

	if (!wsdrag.active || wsdrag.m != m)
		return 0;
	dt = wsdrag.lastframe ? MIN(50, t - wsdrag.lastframe) : 16.0;
	wsdrag.lastframe = t;
	a = 1.0 - exp(-dt / 22.0);
	wsdrag.shown += (wsdrag.pos - wsdrag.shown) * a;
	if (fabs(wsdrag.pos - wsdrag.shown) < 0.05)
		wsdrag.shown = wsdrag.pos;
	wsdragplace();
	return wsdrag.shown != wsdrag.pos;
}

static void
wsdraganim(Client *c, int tooff, int hide, int dur)
{
	c->anim.from.x = c->scene->node.x;
	c->anim.from.y = c->scene->node.y;
	c->anim.to.x = c->geom.x + (wsdrag.vertical ? 0 : tooff);
	c->anim.to.y = c->geom.y + (wsdrag.vertical ? tooff : 0);
	c->anim.fadein = 0;
	c->anim.zoom = 0;
	c->anim.workspace = 1;
	c->anim.hide = hide;
	c->anim.swipe = dur;
	c->anim.active = 1;
	c->anim.t = 0.0f;
}

/* let go: finish the switch when the fingers went past half way, or were
 * still moving fast enough to get there; otherwise spring back */
static void
wsdragend(int cancelled, uint32_t time)
{
	Monitor *m = wsdrag.m;
	Client *c;
	double vel = wsdragvel(time);
	double p = wsdragclamp(wsdrag.pos), shown = wsdragprogress();
	double proj = p + vel / MAX(50, swipe_distance) * 180.0;
	double left, speed;
	int span = wsdragspan(), dir = wsdrag.dir, commit, dur;
	unsigned int oldws = m->ws;

	commit = !cancelled && dir
			&& ((dir > 0 && p < 0.0 && proj <= -0.5) || (dir < 0 && p > 0.0 && proj >= 0.5));
	left = (commit ? 1.0 - fabs(shown) : fabs(shown)) * span;
	dur = (int)(MAX(180, animation_duration * 5 / 4) * left / MAX(1, span));
	/* the ease-out starts at 3x its mean speed: match the fingers */
	speed = fabs(vel) / MAX(50, swipe_distance) * span;
	if (speed > 0.05 && (commit ? vel * dir < 0.0 : vel * shown < 0.0))
		dur = MIN(dur, (int)(3.0 * left / speed));
	dur = MAX(120, dur);
	wsdrag.active = 0;

	if (!animations || animation_duration <= 0) {
		if (commit) {
			Arg a = {.ui = wsdrag.nb};
			viewws(&a);
		} else {
			animstop(m);
			arrange(m);
		}
		return;
	}
	if (commit) {
		wl_list_for_each(c, &clients, link)
			if (c->mon == m && c->ws == oldws && c->scene->node.enabled
					&& !client_is_unmanaged(c))
				wsdraganim(c, -dir * span, 1, dur);
		m->ws = wsdrag.nb;
		focusclient(focustop(m), 1);
		arrange(m);
		wl_list_for_each(c, &clients, link) {
			if (c->mon != m || !VISIBLEON(c, m) || !c->scene->node.enabled
					|| client_is_unmanaged(c))
				continue;
			c->anim.active = 0;
			wsdragmove(c, (int)lround(shown * span) + dir * span);
			wsdraganim(c, 0, 0, dur);
		}
	} else {
		wl_list_for_each(c, &clients, link) {
			if (c->mon != m || client_is_unmanaged(c) || !c->scene->node.enabled)
				continue;
			if (c->ws == oldws)
				wsdraganim(c, 0, 0, dur);
			else if (dir && c->ws == wsdrag.nb)
				wsdraganim(c, dir * span, 1, dur);
		}
		arrange(m);
	}
	animkick(m);
}

void
gesturebegin(uint32_t fingers)
{
	Monitor *m;

	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	/* three and four fingers only: two-finger scrolling belongs to the
	 * clients, and in the drift layout to the canvas */
	overview_swipe_active = !locked && !greeter && (fingers == 3 || fingers == 4);
	overview_swipe_triggered = 0;
	overview_swipe_dx = overview_swipe_dy = 0.0;
	wsdrag.refused = 0;
	if (!overview_swipe_active)
		return;
	m = xytomon(cursor->x, cursor->y);
	if (overviewvalid(m))
		selmon = m;
}

void
swipebeginnotify(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_swipe_begin_event *event = data;

	gesturebegin(event->fingers);
}

void
gestureupdate(uint32_t fingers, double dx, double dy)
{
	if (!overview_swipe_active || fingers < 3 || fingers > 4
			|| !overviewvalid(selmon))
		return;
	overview_swipe_dx += dx;
	overview_swipe_dy += dy;

	/* workspaces follow the fingers along the way they slide: sideways in
	 * BSP, up and down in the scroll layout */
	if (wsdrag.active) {
		wsdragupdate(wsdrag.vertical ? dy : dx);
		return;
	}
	if (!wsdrag.refused && !overview_swipe_triggered && !overview_visible
			&& !DRIFTLT(selmon) && swipe_distance > 0
			&& hypot(overview_swipe_dx, overview_swipe_dy) >= 8.0) {
		int vertical = SCROLLLT(selmon);
		double along = vertical ? overview_swipe_dy : overview_swipe_dx;
		double across = vertical ? overview_swipe_dx : overview_swipe_dy;

		if ((fingers == 3 || !vertical) && fabs(along) > fabs(across) * 1.2) {
			wsdragbegin(selmon, vertical, along);
			return;
		}
		wsdrag.refused = 1;
	}

	if (fingers == 4) {
		/* four fingers walk the workspaces and open the overview in every
		 * layout, which is where drift keeps them since three fingers pan */
		const double step = 120.0;

		if (fabs(overview_swipe_dx) > fabs(overview_swipe_dy) * 1.2) {
			for (; overview_swipe_dx <= -step; overview_swipe_dx += step) {
				overview_swipe_dy = 0.0;
				workspacestep(1);
			}
			for (; overview_swipe_dx >= step; overview_swipe_dx -= step) {
				overview_swipe_dy = 0.0;
				workspacestep(-1);
			}
		} else if (!overview_swipe_triggered && fabs(overview_swipe_dy) >= 64.0) {
			overview_swipe_triggered = 1;
			overviewset(overview_swipe_dy < 0.0);
		}
		return;
	}

	if (fingers == 3 && DRIFTLT(selmon) && !overview_visible) {
		/* three fingers pan the canvas, the content following the fingers */
		double z = driftz(selmon, selmon->ws);

		selmon->camx[selmon->ws] -= dx * drift_pan_speed / z;
		selmon->camy[selmon->ws] -= dy * drift_pan_speed / z;
		driftarrange(selmon);
		return;
	}

	if (SCROLLLT(selmon)) {
		/* niri-style gestures: horizontal swipes walk the windows on the
		 * strip, vertical swipes change workspace; every swipe_step
		 * pixels repeats the action so a long swipe keeps going */
		const double step = 140.0;

		if (fabs(overview_swipe_dx) > fabs(overview_swipe_dy) * 1.2) {
			for (; overview_swipe_dx <= -step; overview_swipe_dx += step) {
				overview_swipe_dy = 0.0;
				if (overview_active)
					overviewfocuscol(1);
				else if (!overview_visible)
					swipefocus(DirRight);
			}
			for (; overview_swipe_dx >= step; overview_swipe_dx -= step) {
				overview_swipe_dy = 0.0;
				if (overview_active)
					overviewfocuscol(-1);
				else if (!overview_visible)
					swipefocus(DirLeft);
			}
		} else if (fabs(overview_swipe_dy) > fabs(overview_swipe_dx) * 1.2) {
			for (; overview_swipe_dy <= -step; overview_swipe_dy += step) {
				overview_swipe_dx = 0.0;
				workspacestep(1);
			}
			for (; overview_swipe_dy >= step; overview_swipe_dy -= step) {
				overview_swipe_dx = 0.0;
				workspacestep(-1);
			}
		}
		return;
	}

	if (overview_swipe_triggered)
		return;
	if (fabs(overview_swipe_dx) >= 48.0
			&& fabs(overview_swipe_dx) > fabs(overview_swipe_dy) * 1.2) {
		overview_swipe_triggered = 1;
		workspacestep(overview_swipe_dx < 0.0 ? 1 : -1);
	} else if (fingers == 3 && fabs(overview_swipe_dy) >= 48.0
			&& fabs(overview_swipe_dy) > fabs(overview_swipe_dx) * 1.2) {
		overview_swipe_triggered = 1;
		overviewset(overview_swipe_dy < 0.0);
	}
}

void
swipeupdatenotify(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_swipe_update_event *event = data;

	gesture_time = event->time_msec;
	gestureupdate(event->fingers, event->dx, event->dy);
}

void
swipeendnotify(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_swipe_end_event *event = data;

	gestureend(event->cancelled, event->time_msec);
}

void
gestureend(int cancelled, uint32_t time)
{
	if (wsdrag.active)
		wsdragend(cancelled, time);
	overview_swipe_active = 0;
	overview_swipe_triggered = 0;
	overview_swipe_dx = overview_swipe_dy = 0.0;
}

void
pinchbeginnotify(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_pinch_begin_event *event = data;
	Monitor *m;

	drift_pinch_done = 0;
	drift_pinch_x = cursor->x;
	drift_pinch_y = cursor->y;
	gesturebegin(event->fingers);
	m = xytomon(cursor->x, cursor->y);
	if (!locked && overviewvalid(m))
		selmon = m;
	drift_pinch_zoom = DRIFTLT(selmon) ? driftz(selmon, selmon->ws) : 1.0;
}

void
pinchupdatenotify(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_pinch_update_event *event = data;

	if (locked || !overviewvalid(selmon) || event->scale <= 0.0)
		return;
	if (event->fingers >= 3) {
		/* libinput reports a three-finger swipe as a pinch as soon as the
		 * fingers drift apart a little, so the movement is fed to the swipe
		 * handler instead of the zoom - otherwise the gesture would either
		 * do nothing or zoom by accident */
		if (event->fingers >= 4 && !drift_pinch_done) {
			if (event->scale <= 0.75) {
				drift_pinch_done = 1;
				overviewset(1);
			} else if (event->scale >= 1.3) {
				drift_pinch_done = 1;
				overviewset(0);
			}
		}
		gesture_time = event->time_msec;
		gestureupdate(event->fingers, event->dx, event->dy);
		return;
	}
	if (overview_visible || !DRIFTLT(selmon))
		return;
	/* a two-finger pinch zooms the camera around the pinch centre */
	driftzoomto(selmon, drift_pinch_zoom * event->scale,
			drift_pinch_x, drift_pinch_y);
}

void
pinchendnotify(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_pinch_end_event *event = data;

	if (wsdrag.active)
		wsdragend(event->cancelled, event->time_msec);
	drift_pinch_done = 0;
	overview_swipe_active = 0;
	overview_swipe_triggered = 0;
	overview_swipe_dx = overview_swipe_dy = 0.0;
}

void
bsp_attach(Monitor *m, unsigned int ws, Client *c)
{
	Node *leaf, *t = NULL, *sp;
	Client *f;

	c->canvas.width = c->canvas.height = 0;
	c->canvassized = 0; /* the window is no longer sized by a canvas */
	leaf = ecalloc(1, sizeof(Node));
	leaf->leaf = 1;
	leaf->ratio = 0.5f;
	leaf->c = c;
	c->node = leaf;
	c->ws = ws;

	if (!m->tree[ws]) {
		m->tree[ws] = leaf;
		return;
	}

	/* split the most recently focused leaf on this workspace */
	if (place_anchor && place_anchor->mon == m && place_anchor->ws == ws)
		t = place_anchor->node;
	else wl_list_for_each(f, &fstack, flink) {
		if (f != c && f->mon == m && f->ws == ws && f->node) {
			t = f->node;
			break;
		}
	}
	if (!t)
		t = bsp_first(m->tree[ws]);

	sp = ecalloc(1, sizeof(Node));
	sp->ratio = 0.5f;
	sp->horiz = t->c->geom.width > 0 ? t->c->geom.width >= t->c->geom.height
			: m->w.width >= m->w.height;
	sp->par = t->par;
	sp->a = t;
	sp->b = leaf;
	if (place_anchor && t == place_anchor->node) {
		sp->horiz = place_side == SIDE_LEFT || place_side == SIDE_RIGHT;
		if (place_side == SIDE_LEFT || place_side == SIDE_TOP) {
			sp->a = leaf;
			sp->b = t;
		}
	}
	if (!t->par)
		m->tree[ws] = sp;
	else if (t->par->a == t)
		t->par->a = sp;
	else
		t->par->b = sp;
	t->par = sp;
	leaf->par = sp;
}

void
bsp_detach(Client *c)
{
	Node *n = c->node, *p, *sib;
	Monitor *m = c->mon;

	if (!n)
		return;
	c->node = NULL;
	/* a running drag-resize must not keep pointing at a freed split */
	if (bsp_grabh == n)
		bsp_grabh = NULL;
	if (bsp_grabv == n)
		bsp_grabv = NULL;
	if (!n->par) {
		if (m)
			m->tree[c->ws] = NULL;
		free(n);
		return;
	}
	p = n->par;
	sib = p->a == n ? p->b : p->a;
	sib->par = p->par;
	if (!p->par) {
		if (m)
			m->tree[c->ws] = sib;
	} else if (p->par->a == p) {
		p->par->a = sib;
	} else {
		p->par->b = sib;
	}
	free(p);
	free(n);
}

void
bsp_dragto(Client *c, double cx, double cy)
{
	/* bsp drag: hand the window the tile it is dragged onto instead of
	 * floating it.  arrange() can bounce back into motionnotify(), so this
	 * has to survive re-entry. */
	static int busy;
	Monitor *m = c->mon;
	Client *t, *target = NULL;
	Node *a, *b;

	if (busy || !m || !c->node || c->isfloating)
		return;
	wl_list_for_each(t, &clients, link) {
		if (t == c || !t->node || t->isfloating || t->isfullscreen
				|| !VISIBLEON(t, m))
			continue;
		if (cx >= t->geom.x && cx < t->geom.x + t->geom.width
				&& cy >= t->geom.y && cy < t->geom.y + t->geom.height) {
			target = t;
			break;
		}
	}
	if (!target)
		return;
	a = c->node;
	b = target->node;
	a->c = target;
	b->c = c;
	c->node = b;
	target->node = a;
	busy = 1;
	arrange(m);
	busy = 0;
}

Node *
bsp_findsplit(Node *n, int horiz, int after)
{
	/* Nearest ancestor split of the requested orientation whose dividing
	 * line lies after (right of / below) n, or before it when after is 0.
	 * Splits with nothing tiled on one side are skipped: bsp_tile() hands
	 * the whole box to the other side there, so their ratio does nothing.
	 * A split on the wrong side is kept as a fallback for windows that sit
	 * against the screen edge. */
	Node *p, *fallback = NULL;

	for (; n && n->par; n = n->par) {
		p = n->par;
		if (!p->horiz != !horiz || !bsp_has_tiled(p->a) || !bsp_has_tiled(p->b))
			continue;
		if ((p->a == n) == !!after)
			return p;
		if (!fallback)
			fallback = p;
	}
	return fallback;
}

Node *
bsp_first(Node *n)
{
	while (n && !n->leaf)
		n = n->a;
	return n;
}

int
bsp_has_tiled(Node *n)
{
	if (!n)
		return 0;
	if (n->leaf)
		return !n->c->isfloating;
	return bsp_has_tiled(n->a) || bsp_has_tiled(n->b);
}

Node *
bsp_nextleaf(Node *tree, Node *cur)
{
	Node *n = cur;
	if (!cur || !tree)
		return bsp_first(tree);
	while (n->par) {
		if (n->par->a == n) {
			Node *r = bsp_first(n->par->b);
			if (r)
				return r;
		}
		n = n->par;
	}
	return bsp_first(tree);
}

Node *
bsp_prevleaf(Node *tree, Node *cur)
{
	Node *prev = NULL, *n;
	if (!tree)
		return NULL;
	n = bsp_first(tree);
	while (n) {
		if (n == cur)
			break;
		prev = n;
		n = bsp_nextleaf(tree, n);
		if (n == bsp_first(tree))
			break;
	}
	if (prev)
		return prev;
	/* cur is the first leaf: wrap to the last one */
	n = bsp_first(tree);
	prev = n;
	while ((n = bsp_nextleaf(tree, prev)) && n != bsp_first(tree))
		prev = n;
	return prev;
}

void
bsp_resizeto(Client *c, double cx, double cy)
{
	/* bsp right-drag: move the split lines the grab started on, so the
	 * window resizes inside the tree and its neighbours give up the room */
	static int busy;
	float r;
	int changed = 0;

	if (busy || !c->mon || !c->node || c->isfloating)
		return;
	if (bsp_grabh && bsp_grabh->box.width > 0) {
		r = bsp_grabhr + (float)((cx - grab_startx) / bsp_grabh->box.width);
		r = r < 0.05f ? 0.05f : r > 0.95f ? 0.95f : r;
		changed |= fabsf(r - bsp_grabh->ratio) >= 0.001f;
		bsp_grabh->ratio = r;
	}
	if (bsp_grabv && bsp_grabv->box.height > 0) {
		r = bsp_grabvr + (float)((cy - grab_starty) / bsp_grabv->box.height);
		r = r < 0.05f ? 0.05f : r > 0.95f ? 0.95f : r;
		changed |= fabsf(r - bsp_grabv->ratio) >= 0.001f;
		bsp_grabv->ratio = r;
	}
	if (!changed)
		return;
	busy = 1;
	arrange(c->mon);
	busy = 0;
}

void
bsp_tile(Node *n, struct wlr_box box)
{
	/* Hiding borders is a visual choice; keep the tile spacing intact. */
	int gap = gappx;

	if (!n)
		return;
	n->box = box; /* remembered so a drag-resize can scale its own split */
	if (n->leaf) {
		if (!n->c->isfloating) {
			const struct wlr_box *w = &n->c->mon->w;
			/* a window alone touches the bars; tiles get one gap everywhere,
			 * so an inner edge takes half of it from each side */
			int g = wlr_box_equal(&box, w) ? 0 : gap;
			int l = box.x == w->x ? g : g / 2;
			int t = box.y == w->y ? g : g / 2;
			int r = box.x + box.width == w->x + w->width ? g : g - g / 2;
			int b = box.y + box.height == w->y + w->height ? g : g - g / 2;

			resize(n->c, (struct wlr_box){.x = box.x + l, .y = box.y + t,
				.width = MAX(1, box.width - l - r),
				.height = MAX(1, box.height - t - b)}, 0);
			wlr_log(WLR_DEBUG, "bsp: ws=%u %dx%d%+d%+d", n->c->ws,
					n->c->geom.width, n->c->geom.height,
					n->c->geom.x, n->c->geom.y);
		}
		return;
	}
	if (!bsp_has_tiled(n->a) && !bsp_has_tiled(n->b))
		return;
	if (!bsp_has_tiled(n->a)) {
		bsp_tile(n->b, box);
		return;
	}
	if (!bsp_has_tiled(n->b)) {
		bsp_tile(n->a, box);
		return;
	}
	if (n->horiz) {
		int wa = (int)(box.width * n->ratio);
		bsp_tile(n->a, (struct wlr_box){box.x, box.y, wa, box.height});
		bsp_tile(n->b, (struct wlr_box){box.x + wa, box.y, box.width - wa, box.height});
	} else {
		int ha = (int)(box.height * n->ratio);
		bsp_tile(n->a, (struct wlr_box){box.x, box.y, box.width, ha});
		bsp_tile(n->b, (struct wlr_box){box.x, box.y + ha, box.width, box.height - ha});
	}
}

Column *
scroll_addcol(Monitor *m, unsigned int ws, struct wl_list *pos)
{
	Column *col = ecalloc(1, sizeof(Column));

	wl_list_init(&col->clients);
	col->wfrac = scroll_colfrac;
	wl_list_insert(pos, &col->link);
	return col;
}

void
scroll_addclient(Column *col, Client *c, unsigned int ws)
{
	wl_list_insert(col->clients.prev, &c->clink);
	c->col = col;
	c->ws = ws;
}

void
scroll_attach(Monitor *m, unsigned int ws, Client *c)
{
	/* a new window opens in its own column right of the focused one, like niri */
	Column *after = NULL;
	Client *f;

	c->canvas.width = c->canvas.height = 0;
	c->canvassized = 0; /* the window is no longer sized by a canvas */

	if (lt_migrating) {
		/* rebuilding the strip from another layout: keep tiling order */
		scroll_addclient(scroll_addcol(m, ws, m->cols[ws].prev), c, ws);
		return;
	}
	wl_list_for_each(f, &fstack, flink) {
		if (f != c && f->mon == m && f->ws == ws && f->col) {
			after = f->col;
			break;
		}
	}
	scroll_addclient(scroll_addcol(m, ws,
			after ? &after->link : m->cols[ws].prev), c, ws);
}

void
scroll_detach(Client *c)
{
	Column *col = c->col;

	if (!col)
		return;
	wl_list_remove(&c->clink);
	c->col = NULL;
	if (wl_list_empty(&col->clients)) {
		wl_list_remove(&col->link);
		free(col);
	}
}

int
scroll_coltiled(Column *col)
{
	Client *c;
	int n = 0;

	wl_list_for_each(c, &col->clients, clink) {
		if (!c->isfloating)
			n++;
	}
	return n;
}

int
scroll_colwidth(Monitor *m, Column *col)
{
	int w = (int)(m->w.width * col->wfrac);

	return MAX(2 * gappx + 50, MIN(w, m->w.width));
}

Client *
wsfocused(Monitor *m, unsigned int ws)
{
	Client *c;

	wl_list_for_each(c, &fstack, flink) {
		if (c->mon == m && c->ws == ws && c->col && !c->isfloating)
			return c;
	}
	return NULL;
}

Client *
wsfocusedany(Monitor *m, unsigned int ws)
{
	Client *c;

	wl_list_for_each(c, &fstack, flink) {
		if (c->mon == m && c->ws == ws)
			return c;
	}
	return NULL;
}

void
scroll_tile(Monitor *m)
{
	Column *col, *fcol;
	Client *c, *focus = wsfocused(m, m->ws);
	int gap = gappx;
	int total = 0, x, colw, n, i, h;
	int *sx = &m->scrollx[m->ws];

	fcol = focus ? focus->col : NULL;

	/* total strip width, then scroll just enough to reveal the focused
	 * column - the columns themselves never move, only the viewport */
	wl_list_for_each(col, &m->cols[m->ws], link) {
		if (scroll_coltiled(col))
			total += scroll_colwidth(m, col);
	}
	if (total <= m->w.width) {
		*sx = 0;
	} else {
		x = 0;
		wl_list_for_each(col, &m->cols[m->ws], link) {
			if (!scroll_coltiled(col))
				continue;
			colw = scroll_colwidth(m, col);
			if (col == fcol) {
				if (x < *sx)
					*sx = x;
				else if (x + colw > *sx + m->w.width)
					*sx = x + colw - m->w.width;
				break;
			}
			x += colw;
		}
		*sx = MAX(0, MIN(*sx, total - m->w.width));
	}

	x = 0;
	wl_list_for_each(col, &m->cols[m->ws], link) {
		if (!(n = scroll_coltiled(col)))
			continue;
		colw = scroll_colwidth(m, col);
		h = m->w.height / n;
		i = 0;
		wl_list_for_each(c, &col->clients, clink) {
			if (c->isfloating)
				continue;
			resize(c, (struct wlr_box){
				.x = m->w.x + x - *sx + gap,
				.y = m->w.y + i * h + gap,
				.width = MAX(1, colw - 2 * gap),
				.height = MAX(1, (i == n - 1 ? m->w.height - i * h : h)
					- 2 * gap)}, 0);
			wlr_log(WLR_DEBUG, "scroll: ws=%u %dx%d%+d%+d sx=%d", c->ws,
					c->geom.width, c->geom.height,
					c->geom.x, c->geom.y, *sx);
			i++;
		}
		x += colw;
	}
}

Client *
scroll_next(Monitor *m, Client *sel)
{
	/* next client in strip order, wrapping like bsp_nextleaf */
	Column *col = sel->col;
	struct wl_list *cl = sel->clink.next;
	Client *c;

	for (;;) {
		if (cl != &col->clients) {
			c = wl_container_of(cl, c, clink);
			return c;
		}
		/* end of the column: hop to the next one (empty columns are freed
		 * on detach, so any wrapped-to column has at least one client) */
		col = col->link.next == &m->cols[sel->ws]
				? wl_container_of(m->cols[sel->ws].next, col, link)
				: wl_container_of(col->link.next, col, link);
		cl = col->clients.next;
	}
}

void
scroll_dragto(Client *c, double cx)
{
	/* niri-style drag: reorder the strip live under the cursor instead of
	 * floating the window */
	Monitor *m = c->mon;
	Column *col, *own, *target = NULL;
	int x = 0, colw = 0, tx = 0;
	double lx;

	if (!m || !c->col || c->isfloating)
		return;
	lx = cx - m->w.x + m->scrollx[c->ws];
	wl_list_for_each(col, &m->cols[c->ws], link) {
		if (!scroll_coltiled(col))
			continue;
		colw = scroll_colwidth(m, col);
		if (lx < x + colw) {
			target = col;
			tx = x;
			break;
		}
		x += colw;
	}
	if (target == c->col)
		return;
	/* pull the window out of a shared column first */
	if (wl_list_length(&c->col->clients) > 1) {
		own = scroll_addcol(m, c->ws, &c->col->link);
		wl_list_remove(&c->clink);
		wl_list_insert(own->clients.prev, &c->clink);
		c->col = own;
	}
	if (!target) {
		if (c->col->link.next == &m->cols[c->ws])
			return;
		wl_list_remove(&c->col->link);
		wl_list_insert(m->cols[c->ws].prev, &c->col->link);
	} else if (lx < tx + colw / 2) {
		if (c->col->link.next == &target->link)
			return;
		wl_list_remove(&c->col->link);
		wl_list_insert(target->link.prev, &c->col->link);
	} else {
		if (c->col->link.prev == &target->link)
			return;
		wl_list_remove(&c->col->link);
		wl_list_insert(&target->link, &c->col->link);
	}
	arrange(m);
}

void
scroll_maximize(Client *sel)
{
	/* niri maximize-column: make the column screen-wide, and back to the
	 * width it had before */
	Column *col = sel->col;

	if (col->wfrac < 0.995f) {
		col->prevfrac = col->wfrac;
		col->wfrac = 1.0f;
	} else {
		col->wfrac = col->prevfrac > 0.0f ? col->prevfrac : scroll_colfrac;
	}
	arrange(sel->mon);
}

void
scroll_swap(Client *sel, int dir)
{
	Column *col = sel->col;
	struct wl_list *pos;

	if (dir == DirLeft || dir == DirRight) {
		/* move the whole column across, like niri */
		pos = dir == DirLeft ? col->link.prev : col->link.next;
		if (pos == &sel->mon->cols[sel->ws])
			return;
		wl_list_remove(&col->link);
		wl_list_insert(dir == DirLeft ? pos->prev : pos, &col->link);
	} else {
		pos = dir == DirUp ? sel->clink.prev : sel->clink.next;
		if (pos == &col->clients)
			return;
		wl_list_remove(&sel->clink);
		wl_list_insert(dir == DirUp ? pos->prev : pos, &sel->clink);
	}
	arrange(sel->mon);
	warpto(sel);
}

/* ---- drift: a driftwm-style infinite canvas, one per workspace ----
 * Windows keep the size they asked for and sit at fixed canvas coordinates.
 * Every workspace owns a camera (pan + zoom) over its canvas; zooming scales
 * the rendered surfaces, so clients never learn about it and keep their
 * native size. */

double
driftz(Monitor *m, unsigned int ws)
{
	double z = m->camz[ws] > 0.0 ? m->camz[ws] : 1.0;

	return MIN((double)drift_zoom_max, MAX((double)drift_zoom_min, z));
}

int
drifttiled(Client *c, Monitor *m, unsigned int ws)
{
	return c->mon == m && c->ws == ws && c->oncanvas && !c->isfloating;
}

void
driftscreen(Monitor *m, Client *c, struct wlr_box *out)
{
	/* canvas rect -> screen rect; borders keep their pixel width at any zoom */
	double z = driftz(m, c->ws);
	int bw = 2 * (int)c->bw;

	out->x = m->w.x + (int)round((c->canvas.x - m->camx[c->ws]) * z);
	out->y = m->w.y + (int)round((c->canvas.y - m->camy[c->ws]) * z);
	out->width = MAX(1 + bw, (int)round((c->canvas.width - bw) * z) + bw);
	out->height = MAX(1 + bw, (int)round((c->canvas.height - bw) * z) + bw);
}

static int
driftoverlap(const struct wlr_box *a, const struct wlr_box *b, int margin)
{
	return a->x - margin < b->x + b->width && b->x - margin < a->x + a->width
			&& a->y - margin < b->y + b->height && b->y - margin < a->y + a->height;
}

void
driftattach(Monitor *m, unsigned int ws, Client *c)
{
	struct wlr_box box, t;
	Client *o;
	double z = driftz(m, ws);
	int bw = 2 * (int)c->bw, ring, dx, dy, stepx, stepy, taken;

	c->ws = ws;
	c->oncanvas = 1;
	if (lt_migrating && c->geom.width > 0 && c->geom.height > 0) {
		/* coming from another layout: stay exactly where the window is now */
		c->canvas.width = MAX(1 + bw, (int)round((c->geom.width - bw) / z) + bw);
		c->canvas.height = MAX(1 + bw, (int)round((c->geom.height - bw) / z) + bw);
		c->canvas.x = (int)round((c->geom.x - m->w.x) / z + m->camx[ws]);
		c->canvas.y = (int)round((c->geom.y - m->w.y) / z + m->camy[ws]);
		c->canvassized = client_surface(c)->mapped;
		return;
	}

	if (!c->canvassized || c->canvas.width <= 0 || c->canvas.height <= 0) {
		/* arriving from another layout or freshly mapped: there the
		 * geometry is the real size.  A window that already lives on a
		 * canvas keeps its own size instead - c->geom would be the
		 * zoomed screen box, which would shrink it on every move. */
		c->canvas.width = MAX(1 + bw, c->geom.width);
		c->canvas.height = MAX(1 + bw, c->geom.height);
	}
	c->canvassized = client_surface(c)->mapped;
	/* start centred in the viewport, then spiral outwards over a grid of
	 * the window's own size until the spot is free */
	stepx = c->canvas.width + MAX(1, gappx);
	stepy = c->canvas.height + MAX(1, gappx);
	box = c->canvas;
	box.x = (int)round(m->camx[ws] + (m->w.width / z - box.width) / 2.0);
	box.y = (int)round(m->camy[ws] + (m->w.height / z - box.height) / 2.0);
	for (ring = 0; ring < 8; ring++) {
		int bestscore = 0, found = 0;
		struct wlr_box best = box;

		for (dy = -ring; dy <= ring; dy++) {
			for (dx = -ring; dx <= ring; dx++) {
				int score;
				if (ring && MAX(dx < 0 ? -dx : dx, dy < 0 ? -dy : dy) != ring)
					continue;
				/* nearest to the camera wins, and right or below beats
				 * left or above, so windows grow away from the corner */
				score = 4 * ((dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy))
						+ (dx < 0) + (dy < 0);
				if (found && score >= bestscore)
					continue;
				t = box;
				t.x += dx * stepx;
				t.y += dy * stepy;
				taken = 0;
				wl_list_for_each(o, &clients, link) {
					if (o != c && drifttiled(o, m, ws)
							&& driftoverlap(&t, &o->canvas, gappx)) {
						taken = 1;
						break;
					}
				}
				if (!taken) {
					best = t;
					bestscore = score;
					found = 1;
				}
			}
		}
		if (found) {
			c->canvas.x = best.x;
			c->canvas.y = best.y;
			driftreveal(m, c); /* a new window is always brought into view */
			return;
		}
	}
	/* the canvas around the camera is packed solid: cascade instead */
	c->canvas.x = box.x + (wl_list_length(&clients) % 8) * MAX(24, gappx * 3);
	c->canvas.y = box.y + (wl_list_length(&clients) % 8) * MAX(24, gappx * 3);
	driftreveal(m, c);
}

void
driftdetach(Client *c)
{
	c->oncanvas = 0;
}

void
drifttile(Monitor *m)
{
	struct wlr_box box;
	Client *c;

	wl_list_for_each(c, &clients, link) {
		if (!drifttiled(c, m, m->ws))
			continue;
		driftscreen(m, c, &box);
		resize(c, box, 0);
		wlr_log(WLR_DEBUG, "drift: ws=%u %dx%d%+d%+d cam=%.0f,%.0f z=%.2f",
				c->ws, c->canvas.width, c->canvas.height,
				c->canvas.x, c->canvas.y, m->camx[c->ws], m->camy[c->ws],
				driftz(m, c->ws));
	}
}

void
driftbounds(Monitor *m, unsigned int ws, int withview, struct wlr_box *out)
{
	/* the canvas area in use, optionally joined with the current viewport */
	double z = driftz(m, ws);
	Client *c;
	int x1 = 0, y1 = 0, x2 = 0, y2 = 0, first = 1;

	if (withview) {
		x1 = (int)round(m->camx[ws]);
		y1 = (int)round(m->camy[ws]);
		x2 = x1 + MAX(1, (int)round(m->w.width / z));
		y2 = y1 + MAX(1, (int)round(m->w.height / z));
		first = 0;
	}
	wl_list_for_each(c, &clients, link) {
		if (!drifttiled(c, m, ws))
			continue;
		if (first) {
			x1 = c->canvas.x;
			y1 = c->canvas.y;
			x2 = c->canvas.x + c->canvas.width;
			y2 = c->canvas.y + c->canvas.height;
			first = 0;
			continue;
		}
		x1 = MIN(x1, c->canvas.x);
		y1 = MIN(y1, c->canvas.y);
		x2 = MAX(x2, c->canvas.x + c->canvas.width);
		y2 = MAX(y2, c->canvas.y + c->canvas.height);
	}
	if (first) {
		x1 = (int)round(m->camx[ws]);
		y1 = (int)round(m->camy[ws]);
		x2 = x1 + MAX(1, (int)round(m->w.width / z));
		y2 = y1 + MAX(1, (int)round(m->w.height / z));
	}
	*out = (struct wlr_box){.x = x1, .y = y1,
		.width = MAX(1, x2 - x1), .height = MAX(1, y2 - y1)};
}

static void
driftsnapedge(int lo, int size, int tlo, int tsize, int *best, int *out)
{
	/* the four ways our edges can meet theirs: aligned or butted together */
	int cand[4], i, d;

	cand[0] = tlo;
	cand[1] = tlo + tsize;
	cand[2] = tlo - size;
	cand[3] = tlo + tsize - size;
	for (i = 0; i < 4; i++) {
		d = cand[i] > lo ? cand[i] - lo : lo - cand[i];
		if (d <= drift_snap && d < *best) {
			*best = d;
			*out = cand[i];
		}
	}
}

void
driftsnap(Monitor *m, Client *c, struct wlr_box *box)
{
	/* snapping kicks in as edges approach each other, like driftwm */
	double z = driftz(m, c->ws);
	struct wlr_box view;
	Client *o;
	int x = box->x, y = box->y;
	int bestx = drift_snap + 1, besty = drift_snap + 1;

	if (drift_snap <= 0)
		return;
	view.x = (int)round(m->camx[c->ws]);
	view.y = (int)round(m->camy[c->ws]);
	view.width = MAX(1, (int)round(m->w.width / z));
	view.height = MAX(1, (int)round(m->w.height / z));
	driftsnapedge(box->x, box->width, view.x, view.width, &bestx, &x);
	driftsnapedge(box->y, box->height, view.y, view.height, &besty, &y);
	wl_list_for_each(o, &clients, link) {
		if (o == c || !drifttiled(o, m, c->ws))
			continue;
		/* only snap along an axis where the windows actually face each other */
		if (o->canvas.y - drift_snap < box->y + box->height
				&& box->y - drift_snap < o->canvas.y + o->canvas.height)
			driftsnapedge(box->x, box->width, o->canvas.x, o->canvas.width,
					&bestx, &x);
		if (o->canvas.x - drift_snap < box->x + box->width
				&& box->x - drift_snap < o->canvas.x + o->canvas.width)
			driftsnapedge(box->y, box->height, o->canvas.y, o->canvas.height,
					&besty, &y);
	}
	box->x = x;
	box->y = y;
}

int
driftcluster(Client *c, Client **out, int max)
{
	/* windows that touch, directly or through another window, form an
	 * implicit group that moves together */
	Client *o;
	int n = 1, i, added = 1;

	out[0] = c;
	while (added && n < max) {
		added = 0;
		wl_list_for_each(o, &clients, link) {
			if (o == c || !drifttiled(o, c->mon, c->ws))
				continue;
			for (i = 0; i < n; i++)
				if (out[i] == o)
					break;
			if (i < n)
				continue;
			for (i = 0; i < n; i++)
				if (driftoverlap(&o->canvas, &out[i]->canvas, MAX(1, drift_snap)))
					break;
			if (i == n)
				continue;
			out[n++] = o;
			added = 1;
			if (n == max)
				break;
		}
	}
	return n;
}

void
driftmove(Client *c, int dx, int dy, int cluster)
{
	Client *group[32];
	int i, n = 1;

	if (!dx && !dy)
		return;
	group[0] = c;
	if (cluster)
		n = driftcluster(c, group, (int)LENGTH(group));
	for (i = 0; i < n; i++) {
		group[i]->canvas.x += dx;
		group[i]->canvas.y += dy;
	}
}

void
driftreveal(Monitor *m, Client *c)
{
	/* pan just enough to bring the window into the viewport */
	double z, vw, vh, x, y;
	int margin;

	if (!DRIFTLT(m) || !c || !c->oncanvas || c->isfloating)
		return;
	z = driftz(m, c->ws);
	vw = m->w.width / z;
	vh = m->w.height / z;
	x = m->camx[c->ws];
	y = m->camy[c->ws];
	margin = MAX(8, gappx);
	if (c->canvas.x - margin < x)
		x = c->canvas.x - margin;
	else if (c->canvas.x + c->canvas.width + margin > x + vw)
		x = c->canvas.x + c->canvas.width + margin - vw;
	if (c->canvas.y - margin < y)
		y = c->canvas.y - margin;
	else if (c->canvas.y + c->canvas.height + margin > y + vh)
		y = c->canvas.y + c->canvas.height + margin - vh;
	m->camx[c->ws] = x;
	m->camy[c->ws] = y;
}

Client *
driftpick(Monitor *m, Client *from, int dir)
{
	/* nearest window in that direction on the canvas, offscreen ones
	 * included; unlike tiled layouts nothing has to line up */
	Client *c, *best = NULL;
	long bestscore = 0;
	int fx, fy;

	if (!from)
		return NULL;
	fx = from->canvas.x + from->canvas.width / 2;
	fy = from->canvas.y + from->canvas.height / 2;
	wl_list_for_each(c, &clients, link) {
		long primary, perp, score;
		int dx, dy;
		if (c == from || !drifttiled(c, m, m->ws))
			continue;
		dx = c->canvas.x + c->canvas.width / 2 - fx;
		dy = c->canvas.y + c->canvas.height / 2 - fy;
		if (dir == DirLeft || dir == DirRight) {
			primary = dir == DirLeft ? -dx : dx;
			perp = dy < 0 ? -dy : dy;
		} else {
			primary = dir == DirUp ? -dy : dy;
			perp = dx < 0 ? -dx : dx;
		}
		if (primary <= 0 || perp > primary * 2)
			continue;
		score = primary + perp / 2;
		if (!best || score < bestscore) {
			best = c;
			bestscore = score;
		}
	}
	return best;
}

void
driftzoomto(Monitor *m, double z, double ax, double ay)
{
	/* zoom around a screen anchor: the canvas point under it stays put */
	unsigned int ws;
	double old, cx, cy;

	if (!DRIFTLT(m) || m->w.width <= 0 || m->w.height <= 0)
		return;
	ws = m->ws;
	old = driftz(m, ws);
	z = MIN((double)drift_zoom_max, MAX((double)drift_zoom_min, z));
	if (fabs(z - old) < 0.0005)
		return;
	cx = m->camx[ws] + (ax - m->w.x) / old;
	cy = m->camy[ws] + (ay - m->w.y) / old;
	m->camz[ws] = z;
	m->camx[ws] = cx - (ax - m->w.x) / z;
	m->camy[ws] = cy - (ay - m->w.y) / z;
	driftarrange(m);
}

void
driftzoomkey(const Arg *arg)
{
	Monitor *m = selmon;

	double ax, ay;

	if (!DRIFTLT(m))
		return;
	/* zoom around the middle of the viewport: positive zooms in, negative
	 * out, zero goes back to 1:1 */
	ax = m->w.x + m->w.width / 2.0;
	ay = m->w.y + m->w.height / 2.0;
	if (arg->f == 0.0f)
		driftzoomto(m, 1.0, ax, ay);
	else
		driftzoomto(m, driftz(m, m->ws) * (arg->f > 0.0f
				? drift_zoom_step : 1.0f / drift_zoom_step), ax, ay);
}

void
driftfit(const Arg *arg)
{
	/* zoom to fit every window on the workspace, like driftwm's overview */
	Monitor *m = selmon;
	struct wlr_box b;
	double z;
	int margin;

	if (!DRIFTLT(m) || m->w.width <= 0 || m->w.height <= 0)
		return;
	driftbounds(m, m->ws, 0, &b);
	margin = MAX(16, gappx * 2);
	b.x -= margin;
	b.y -= margin;
	b.width += 2 * margin;
	b.height += 2 * margin;
	z = MIN((double)m->w.width / b.width, (double)m->w.height / b.height);
	z = MIN((double)drift_zoom_max, MAX((double)drift_zoom_min, z));
	m->camz[m->ws] = z;
	m->camx[m->ws] = b.x + b.width / 2.0 - m->w.width / (2.0 * z);
	m->camy[m->ws] = b.y + b.height / 2.0 - m->w.height / (2.0 * z);
	driftarrange(m);
}

void
driftpankey(const Arg *arg)
{
	/* Mod+Alt+arrow pans the camera; the other layouts keep swapping windows */
	Monitor *m = selmon;
	double z, stepx, stepy;

	if (!DRIFTLT(m)) {
		swapdir(arg);
		return;
	}
	z = driftz(m, m->ws);
	stepx = m->w.width / z / 4.0;
	stepy = m->w.height / z / 4.0;
	m->camx[m->ws] += arg->i == DirLeft ? -stepx : arg->i == DirRight ? stepx : 0;
	m->camy[m->ws] += arg->i == DirUp ? -stepy : arg->i == DirDown ? stepy : 0;
	driftarrange(m);
}

void
driftpan(const Arg *arg)
{
	/* Mod+Shift+drag grabs the canvas itself and pulls it under the cursor.
	 * The wheel only pans over bare canvas and the three-finger swipe needs a
	 * touchpad, so this is how a plain mouse gets around a covered canvas. */
	Monitor *m = xytomon(cursor->x, cursor->y);

	if (cursor_mode != CurNormal && cursor_mode != CurPressed)
		return;
	if (!DRIFTLT(m))
		return;
	grabc = NULL;
	grabm = m;
	grab_startx = cursor->x;
	grab_starty = cursor->y;
	grab_camx = m->camx[m->ws];
	grab_camy = m->camy[m->ws];
	cursor_mode = CurDriftPan;
	wlr_cursor_set_xcursor(cursor, cursor_mgr, "grabbing");
}

void
driftpanto(double cx, double cy)
{
	/* driftarrange() calls motionnotify() again, so keep this re-entrant
	 * safe and quiet when the camera did not actually move */
	static int busy;
	Monitor *m = grabm;
	double z, camx, camy;

	if (busy || !DRIFTLT(m) || m->w.width <= 0 || m->w.height <= 0)
		return;
	z = driftz(m, m->ws);
	camx = grab_camx - (cx - grab_startx) / z;
	camy = grab_camy - (cy - grab_starty) / z;
	if (camx == m->camx[m->ws] && camy == m->camy[m->ws])
		return;
	m->camx[m->ws] = camx;
	m->camy[m->ws] = camy;
	busy = 1;
	driftarrange(m);
	busy = 0;
}

void
driftnudge(const Arg *arg)
{
	/* Mod+Shift+arrow nudges the window; snapping still applies */
	Client *sel = focustop(selmon);
	struct wlr_box box;

	if (!sel || !drifttiled(sel, selmon, selmon->ws))
		return;
	/* no snapping here: the keyboard is how you place a window precisely,
	 * and a snap wider than the step would swallow every nudge */
	box = sel->canvas;
	box.x += arg->i == DirLeft ? -drift_nudge : arg->i == DirRight ? drift_nudge : 0;
	box.y += arg->i == DirUp ? -drift_nudge : arg->i == DirDown ? drift_nudge : 0;
	driftmove(sel, box.x - sel->canvas.x, box.y - sel->canvas.y, 0);
	driftreveal(selmon, sel);
	arrange(selmon);
}

void
driftdragto(Client *c, double cx, double cy)
{
	/* drag on the canvas: snap to the neighbours and auto-pan at the edges.
	 * arrange() calls motionnotify() again, so this has to be re-entrant
	 * safe and quiet when nothing actually moved */
	static int busy;
	Monitor *m = c->mon;
	struct wlr_box box;
	double z, edge, oldcamx, oldcamy;

	if (busy || !m || !c->oncanvas || c->isfloating)
		return;
	z = driftz(m, c->ws);
	oldcamx = m->camx[c->ws];
	oldcamy = m->camy[c->ws];
	edge = MAX(16.0, MIN(48.0, m->w.width / 24.0));
	if (cx < m->w.x + edge)
		m->camx[c->ws] -= (m->w.x + edge - cx) / z;
	else if (cx > m->w.x + m->w.width - edge)
		m->camx[c->ws] += (cx - (m->w.x + m->w.width - edge)) / z;
	if (cy < m->w.y + edge)
		m->camy[c->ws] -= (m->w.y + edge - cy) / z;
	else if (cy > m->w.y + m->w.height - edge)
		m->camy[c->ws] += (cy - (m->w.y + m->w.height - edge)) / z;

	box = c->canvas;
	box.x = (int)round((cx - grabcx - m->w.x) / z + m->camx[c->ws]);
	box.y = (int)round((cy - grabcy - m->w.y) / z + m->camy[c->ws]);
	driftsnap(m, c, &box);
	if (box.x == c->canvas.x && box.y == c->canvas.y
			&& m->camx[c->ws] == oldcamx && m->camy[c->ws] == oldcamy)
		return;
	driftmove(c, box.x - c->canvas.x, box.y - c->canvas.y, drift_dragcluster);
	busy = 1;
	driftarrange(m);
	busy = 0;
}

void
driftresizeto(Client *c, double cx, double cy)
{
	static int busy;
	Monitor *m = c->mon;
	double z;
	int bw, w, h;

	if (busy || !m || !c->oncanvas || c->isfloating)
		return;
	z = driftz(m, c->ws);
	bw = 2 * (int)c->bw;
	w = MAX(1 + bw, (int)round((cx - c->geom.x - bw) / z) + bw);
	h = MAX(1 + bw, (int)round((cy - c->geom.y - bw) / z) + bw);
	if (w == c->canvas.width && h == c->canvas.height)
		return;
	c->canvas.width = w;
	c->canvas.height = h;
	busy = 1;
	driftarrange(m);
	busy = 0;
}

/* --- rendering the camera zoom ---
 * wlroots has no scale on a scene tree, so the zoom is applied to the client's
 * buffers: the destination size is scaled while the source box wlroots
 * computed is left alone.  Every value below is derived from protocol state,
 * so re-running this over an already scaled tree is a no-op - which is what
 * lets it run again after each commit and on every frame. */
typedef struct {
	struct wlr_surface *surface;
	int x, y;
} DriftSurface;

typedef struct {
	DriftSurface list[24];
	int n;
	double z;
	int ox, oy;          /* where the clip origin lands on screen */
	struct wlr_box clip; /* unscaled, in surface-local coordinates */
	const struct wlr_box *crop; /* monitor box in the same space as ox/oy */
} DriftScale;

static void
driftcollect(struct wlr_surface *surface, int sx, int sy, void *data)
{
	DriftScale *ds = data;

	if (ds->n < (int)LENGTH(ds->list)) {
		ds->list[ds->n].surface = surface;
		ds->list[ds->n].x = sx;
		ds->list[ds->n].y = sy;
		ds->n++;
	}
}

/* the hit test wlroots installs on a scene surface, kept so the clip it
 * applies keeps being applied after the scale correction below */
static wlr_scene_buffer_point_accepts_input_func_t wlr_point_accepts_input;

static bool
driftpointinput(struct wlr_scene_buffer *buffer, double *sx, double *sy)
{
	/* wlroots hit-tests a buffer in destination pixels and hands the result
	 * to the client as surface coordinates, which only agree while nothing
	 * is scaled.  A scaled buffer therefore needs the scale divided back
	 * out first, otherwise every click lands zoom times too far into the
	 * window and the input region covers the wrong part of it. */
	struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(buffer);
	struct wlr_scene_node *n;
	Client *c = NULL;
	double z = 1.0;

	if (!s)
		return false;
	for (n = &buffer->node; n && !c; n = n->parent ? &n->parent->node : NULL)
		c = n->data;
	if (c && c->type != LayerShell && c->bufscale > 0.0)
		z = c->bufscale;
	*sx /= z;
	*sy /= z;
	return wlr_point_accepts_input ? wlr_point_accepts_input(buffer, sx, sy)
			: wlr_surface_point_accepts_input(s->surface, *sx, *sy);
}

static void
driftscalebuf(struct wlr_scene_buffer *buffer, int sx, int sy, void *data)
{
	DriftScale *ds = data;
	struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(buffer);
	struct wlr_box dst, vis;
	int i, x1, y1, x2, y2, tx, ty;

	if (!s)
		return;
	/* every buffer this pass touches gets the scale-aware hit test, and
	 * keeps it: at 1:1 it behaves exactly like the one wlroots installs */
	if (buffer->point_accepts_input
			&& buffer->point_accepts_input != driftpointinput)
		wlr_point_accepts_input = buffer->point_accepts_input;
	buffer->point_accepts_input = driftpointinput;
	for (i = 0; i < ds->n && ds->list[i].surface != s->surface; i++);
	if (i == ds->n)
		return;
	/* the part of this surface that survives the clip, unscaled */
	x1 = MAX(ds->list[i].x, ds->clip.x);
	y1 = MAX(ds->list[i].y, ds->clip.y);
	x2 = MIN(ds->list[i].x + s->surface->current.width,
			ds->clip.x + ds->clip.width);
	y2 = MIN(ds->list[i].y + s->surface->current.height,
			ds->clip.y + ds->clip.height);
	if (x2 <= x1 || y2 <= y1)
		return;
	tx = ds->ox + (int)round((x1 - ds->clip.x) * ds->z);
	ty = ds->oy + (int)round((y1 - ds->clip.y) * ds->z);
	dst = (struct wlr_box){tx, ty, MAX(1, (int)round((x2 - x1) * ds->z)),
			MAX(1, (int)round((y2 - y1) * ds->z))};
	vis = dst;
	if (ds->crop && !boxclip(&vis, ds->crop)) {
		/* entirely past the monitor edge; wlroots re-enables it on the
		 * next map, and the next pass does when it comes back */
		wlr_scene_node_set_enabled(&buffer->node, 0);
		return;
	}
	wlr_scene_node_set_enabled(&buffer->node, 1);
	/* a CSD shadow outside the window geometry is cut by the clip too */
	if (vis.x != dst.x || vis.y != dst.y || vis.width != dst.width
			|| vis.height != dst.height || x1 != ds->list[i].x
			|| y1 != ds->list[i].y
			|| x2 != ds->list[i].x + s->surface->current.width
			|| y2 != ds->list[i].y + s->surface->current.height) {
		/* only the visible part is drawn: pick that part of the buffer
		 * and shrink the destination to match */
		struct wlr_fbox src;
		double bx = buffer->buffer ? (double)buffer->buffer->width
				/ MAX(1, s->surface->current.width) : 1.0;
		double by = buffer->buffer ? (double)buffer->buffer->height
				/ MAX(1, s->surface->current.height) : 1.0;
		src.x = (x1 - ds->list[i].x + (vis.x - dst.x) / ds->z) * bx;
		src.y = (y1 - ds->list[i].y + (vis.y - dst.y) / ds->z) * by;
		src.width = vis.width / ds->z * bx;
		src.height = vis.height / ds->z * by;
		wlr_scene_buffer_set_source_box(buffer, &src);
	} else {
		/* back to what the surface state says, in case a crop was set */
		wlr_scene_buffer_set_source_box(buffer, NULL);
	}
	wlr_scene_buffer_set_dest_size(buffer, vis.width, vis.height);
	wlr_scene_buffer_set_filter_mode(buffer, WLR_SCALE_FILTER_BILINEAR);
	wlr_scene_node_set_position(&buffer->node,
			buffer->node.x + vis.x - sx, buffer->node.y + vis.y - sy);
}

static void
driftscalesurface(struct wlr_scene_tree *tree, struct wlr_surface *surface,
		double z, int ox, int oy, const struct wlr_box *clip,
		const struct wlr_box *crop)
{
	DriftScale ds = {.n = 0, .z = z, .ox = ox, .oy = oy, .clip = *clip,
		.crop = crop};

	wlr_surface_for_each_surface(surface, driftcollect, &ds);
	wlr_scene_node_for_each_buffer(&tree->node, driftscalebuf, &ds);
}

static void
driftscalepopups(struct wl_list *popups, double z, int ox, int oy)
{
	/* popups hang off the client's tree, so they are scaled separately;
	 * their position comes from the protocol, never from the scene.
	 * ox/oy is the parent's geometry origin inside the tree the popup is
	 * parented to, which is (border, border) for a toplevel's popups and
	 * (0, 0) for a popup of a popup. */
	struct wlr_xdg_popup *p;
	struct wlr_scene_tree *tree;
	struct wlr_box clip;
	int tx, ty;

	wl_list_for_each(p, popups, link) {
		if (!(tree = p->base->surface->data))
			continue;
		clip = p->base->geometry;
		if (clip.width <= 0 || clip.height <= 0)
			continue;
		tx = ox + (int)round(p->current.geometry.x * z);
		ty = oy + (int)round(p->current.geometry.y * z);
		wlr_scene_node_set_position(&tree->node, tx, ty);
		driftscalesurface(tree, p->base->surface, z, tx, ty, &clip, NULL);
		driftscalepopups(&p->base->popups, z, 0, 0);
	}
}

void
driftscaleclient(Client *c, double z)
{
	/* wlr_scene_node_for_each_buffer() counts from the parent of the node it
	 * is given, so everything here is relative to the client's scene tree -
	 * which also keeps the open and retile animations working */
	struct wlr_box clip, crop, vis;
	int bw = (int)c->bw, r;

	if (!c->scene || !c->scene_surface || !client_surface(c)->mapped)
		return;
	client_get_clip(c, &clip);
	/* the clip is the size the client was configured with, borders excluded */
	clip.width = c->fit < 1.0 ? c->fitw : MAX(1, c->canvas.width - 2 * bw);
	clip.height = c->fit < 1.0 ? c->fith : MAX(1, c->canvas.height - 2 * bw);
	c->bufscale = z;
	clientcropbox(c, &crop);
	vis = (struct wlr_box){0, 0, c->geom.width, c->geom.height};
	/* a fitted window fills its area: only its open animation moves it, and the
	 * last pass of that must not leave a subsurface cut off with no frame to follow */
	if (c->fit >= 1.0 && !boxclip(&vis, &crop)) {
		clientoffscreen(c, 1);
		return;
	}
	clientoffscreen(c, 0);
	r = (c->isfullscreen || c->isfakefull) ? 0
			: MIN(MAX(0, corner_radius), MIN(c->geom.width, c->geom.height) / 2);
	clientborders(c, c->geom.width, c->geom.height, bw, r, &vis);
	driftscalesurface(c->scene_surface, client_surface(c), z, bw, bw, &clip,
			c->fit < 1.0 ? NULL : &crop);
#ifdef XWAYLAND
	if (c->type != XDGShell)
		return;
#endif
	driftscalepopups(&c->surface.xdg->popups, z, bw, bw);
}

/* --- scaling a live window for the open animation ---
 * The same trick as the camera zoom: the frame is drawn at the animated size
 * and the buffers are stretched to match, so the client never sees a resize
 * and keeps painting real content while it grows. */
void
clientscale(Client *c, float z)
{
	/* popups are left alone: a window that just mapped has none, and one
	 * that shows up mid-animation is better placed than half scaled */
	struct wlr_box clip, crop, vis;
	int bw, w, h, r;

	if (!c->scene || !c->scene_surface || !client_surface(c)->mapped)
		return;
	if (z >= 1.0f) {
		clientunscale(c);
		return;
	}
	/* shortcut: a shrunk window opens without the zoom, multiply the two scales if it is ever missed */
	if (c->fit < 1.0)
		return;
	bw = (int)roundf(c->bw * z);
	w = MAX(1 + 2 * bw, (int)roundf(c->geom.width * z));
	h = MAX(1 + 2 * bw, (int)roundf(c->geom.height * z));
	r = (c->isfullscreen || c->isfakefull) ? 0
			: MIN(MAX(0, (int)roundf(corner_radius * z)), MIN(w, h) / 2);
	c->anim.scale = z;
	c->bufscale = z;
	clientcropbox(c, &crop);
	vis = (struct wlr_box){0, 0, w, h};
	if (!boxclip(&vis, &crop)) {
		clientoffscreen(c, 1);
		return;
	}
	clientoffscreen(c, 0);
	clientborders(c, w, h, bw, r, &vis);
	client_get_clip(c, &clip);
	driftscalesurface(c->scene_surface, client_surface(c), z, bw, bw, &clip,
			&crop);
}

void
clientunscale(Client *c)
{
	/* one pass at 1:1 puts every buffer back on the size and position
	 * wlroots computed for it, the same way the camera zoom returns */
	struct wlr_box clip;
	int bw = (int)c->bw, r;

	if (c->fit < 1.0) {
		c->anim.scale = 1.0f;
		driftscaleclient(c, c->fit);
		return;
	}
	if ((c->anim.scale == 0.0f || c->anim.scale >= 1.0f) && c->bufscale == 1.0)
		return;
	c->anim.scale = 1.0f;
	c->bufscale = 1.0;
	if (!c->scene || !c->scene_surface || !client_surface(c)->mapped)
		return;
	r = (c->isfullscreen || c->isfakefull) ? 0
			: MIN(MAX(0, corner_radius),
					MIN(c->geom.width, c->geom.height) / 2);
	clientborders(c, c->geom.width, c->geom.height, bw, r, NULL);
	client_get_clip(c, &clip);
	driftscalesurface(c->scene_surface, client_surface(c), 1.0, bw, bw, &clip,
			NULL);
	clientclip(c);
}

void
driftapply(Monitor *m)
{
	/* wlroots resets buffer sizes whenever a client commits, so the camera
	 * zoom is re-applied once per frame, before anything reads the buffers */
	Client *c;
	double z;

	/* every workspace: the cards copy these buffers at their painted size */
	wl_list_for_each(c, &clients, link)
		if (c->mon == m && c->fit < 1.0)
			driftscaleclient(c, c->fit);
	if (!DRIFTLT(m))
		return;
	z = driftz(m, m->ws);
	/* at 1:1 the scene graph is already right, except for the one pass that
	 * puts the buffers back after a zoom */
	if (z == 1.0 && !m->driftscaled)
		return;
	wl_list_for_each(c, &clients, link) {
		if (!drifttiled(c, m, m->ws) || !VISIBLEON(c, m)
				|| c->isfullscreen || c->isfakefull)
			continue;
		driftscaleclient(c, z);
	}
	m->driftscaled = z != 1.0;
}

static void
driftarrange(Monitor *m)
{
	/* camera moves are direct manipulation: retile without easing */
	int oldanim = animations;

	animations = 0;
	arrange(m);
	animations = oldanim;
}

void
attachclient(Monitor *m, unsigned int ws, Client *c)
{
	if (SCROLLLT(m))
		scroll_attach(m, ws, c);
	else if (DRIFTLT(m))
		driftattach(m, ws, c);
	else
		bsp_attach(m, ws, c);
}

void
detachclient(Client *c)
{
	/* detach from whichever layout currently holds the client */
	if (c->oncanvas)
		driftdetach(c);
	else if (c->col)
		scroll_detach(c);
	else
		bsp_detach(c);
}

void
setlayout(Monitor *m, unsigned int lt)
{
	/* move every window of every workspace into the new layout, keeping the
	 * order they are in now */
	Client *c, *sel;
	unsigned int ws;

	if (!m || lt >= LtLast || m->lt == lt)
		return;
	sel = focustop(m);
	for (ws = 0; ws < NUMWS; ws++) {
		wl_list_for_each(c, &clients, link) {
			if (LTMIGRATE(c, m, ws) && (c->node || c->col || c->oncanvas))
				detachclient(c);
		}
		m->scrollx[ws] = 0;
		m->camx[ws] = m->camy[ws] = 0.0;
		m->camz[ws] = 1.0;
	}
	m->lt = lt;
	savelayoutstate(lt);
	/* windows are re-attached in tiling order, and the canvas starts out as
	 * a copy of the screen, so nothing jumps around */
	lt_migrating = 1;
	for (ws = 0; ws < NUMWS; ws++) {
		wl_list_for_each(c, &clients, link) {
			if (LTMIGRATE(c, m, ws))
				attachclient(m, ws, c);
		}
	}
	lt_migrating = 0;
	arrange(m);
	ipcnotifyall();
	if (sel) {
		focusclient(sel, 1);
		warpto(sel);
	}
}

void
togglelayout(const Arg *arg)
{
	if (selmon)
		setlayout(selmon, (selmon->lt + 1) % LtLast);
}

void
setlayoutarg(const Arg *arg)
{
	if (selmon)
		setlayout(selmon, arg->ui);
}

void
consumewin(const Arg *arg)
{
	/* pull the first window of the next column into this one (niri consume) */
	Client *sel = focustop(selmon), *t;
	Column *next;

	if (!SCROLLLT(selmon) || !sel || !sel->col)
		return;
	if (sel->col->link.next == &selmon->cols[sel->ws])
		return;
	next = wl_container_of(sel->col->link.next, next, link);
	t = wl_container_of(next->clients.next, t, clink);
	scroll_detach(t);
	scroll_addclient(sel->col, t, sel->ws);
	arrange(selmon);
	warpto(sel);
}

void
expelwin(const Arg *arg)
{
	/* push the focused window out into its own column to the right (niri expel) */
	Client *sel = focustop(selmon);
	Column *col;

	if (!SCROLLLT(selmon) || !sel || !sel->col
			|| wl_list_length(&sel->col->clients) < 2)
		return;
	col = sel->col;
	wl_list_remove(&sel->clink);
	sel->col = NULL;
	scroll_addclient(scroll_addcol(selmon, sel->ws, &col->link), sel, sel->ws);
	arrange(selmon);
	warpto(sel);
}

/* laptop test mode: the mouse is one finger, four while F4 is held */
static int mouse_four, mouse_fingers;
static double mouse_x, mouse_y;
static struct wlr_touch mouse_touch;
static const struct wlr_touch_impl mouse_touch_impl = { .name = "mouse-finger" };

static void
mousetouch(uint32_t time, int pressed, int released)
{
	int i;

	for (i = 0; i < mouse_fingers; i++) {
		double x = MAX(0.0, MIN(1.0, mouse_x + (i - (mouse_fingers - 1) / 2.0) * 0.05));

		if (pressed) {
			struct wlr_touch_down_event e = { &mouse_touch, time, i, x, mouse_y };
			wl_signal_emit_mutable(&mouse_touch.events.down, &e);
		} else if (released) {
			struct wlr_touch_up_event e = { &mouse_touch, time, i };
			wl_signal_emit_mutable(&mouse_touch.events.up, &e);
		} else {
			struct wlr_touch_motion_event e = { &mouse_touch, time, i, x, mouse_y };
			wl_signal_emit_mutable(&mouse_touch.events.motion, &e);
		}
	}
	if (mouse_fingers)
		wl_signal_emit_mutable(&mouse_touch.events.frame, NULL);
	if (released)
		mouse_fingers = 0;
}

static void
mousefingersetup(void)
{
	if (!(mouse_finger = !!getenv("PHONEGLUEWC_MOUSE_FINGER")))
		return;
	wlr_touch_init(&mouse_touch, &mouse_touch_impl, "mouse-finger");
	inputdevice(NULL, &mouse_touch.base);
}

void
buttonpress(struct wl_listener *listener, void *data)
{
	struct wlr_pointer_button_event *event = data;
	struct wlr_keyboard *keyboard;
	uint32_t mods;
	Client *c;
	const Button *b;

	/* touchbutton passes no listener: that press comes from a finger already */
	if (mouse_finger && listener && event->button == BTN_LEFT) {
		if (event->state == WL_POINTER_BUTTON_STATE_PRESSED) {
			mouse_fingers = mouse_four ? 4 : 1;
			mousetouch(event->time_msec, 1, 0);
		} else {
			mousetouch(event->time_msec, 0, 1);
		}
		return;
	}
	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	/* clicking while Super is held is not a bare Super tap */
	if (super_group && super_group->super_down
			&& event->state == WL_POINTER_BUTTON_STATE_PRESSED)
		super_group->super_alone = 0;
	/* a fresh press over the shell's dock belongs to the dock, not the
	 * overview; once a gesture is under way the overview keeps it */
	if ((overview_visible || overview_button_swallow)
			&& !(!overview_button_swallow && overviewpassthrough())) {
		overviewbutton(event);
		return;
	}

	switch (event->state) {
	case WL_POINTER_BUTTON_STATE_PRESSED:
		cursor_mode = CurPressed;
		selmon = xytomon(cursor->x, cursor->y);
		if (locked)
			break;

		/* Change focus if the button was _pressed_ over a client */
		xytonode(cursor->x, cursor->y, NULL, &c, NULL, NULL, NULL);
		if (c && (!client_is_unmanaged(c) || client_wants_focus(c)))
			focusclient(c, 1);

		keyboard = wlr_seat_get_keyboard(seat);
		mods = keyboard ? wlr_keyboard_get_modifiers(keyboard) : 0;
		for (b = buttons; b < END(buttons); b++) {
			/* Alt bindings exist for driftwm muscle memory; outside the
			 * drift layout Alt+click belongs to the application */
			if ((b->mod & WLR_MODIFIER_ALT) && !DRIFTLT(selmon))
				continue;
			/* there is no camera to pan in the other layouts, so let the
			 * click through instead of swallowing it */
			if (b->func == driftpan && !DRIFTLT(selmon))
				continue;
			if (CLEANMASK(mods) == CLEANMASK(b->mod) &&
					event->button == b->button && b->func) {
				b->func(&b->arg);
				return;
			}
		}
		break;
	case WL_POINTER_BUTTON_STATE_RELEASED:
		/* If you released any buttons, we exit interactive move/resize mode. */
		/* TODO: should reset to the pointer focus's current setcursor */
		if (!locked && cursor_mode != CurNormal && cursor_mode != CurPressed) {
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "default");
			if (cursor_mode == CurMove || cursor_mode == CurResize) {
				/* Drop the window off on its new monitor */
				selmon = xytomon(cursor->x, cursor->y);
				setmon(grabc, selmon, -1);
			} else if ((cursor_mode == CurDragTile
					|| cursor_mode == CurBSPMove
					|| cursor_mode == CurDriftMove
					|| cursor_mode == CurDriftResize) && grabc) {
				Monitor *dropmon = xytomon(cursor->x, cursor->y);
				if (dropmon && dropmon != grabc->mon) {
					/* a canvas window keeps the spot it was dropped on,
					 * translated onto the other monitor's canvas */
					lt_migrating = DRIFTLT(dropmon) && grabc->oncanvas;
					setmon(grabc, dropmon, -1);
					lt_migrating = 0;
				}
			}
			cursor_mode = CurNormal;
			grabc = NULL;
			grabm = NULL;
			bsp_grabh = bsp_grabv = NULL;
			return;
		}
		cursor_mode = CurNormal;
		break;
	}
	/* If the event wasn't handled by the compositor, notify the client with
	 * pointer focus that a button press has occurred */
	wlr_seat_pointer_notify_button(seat,
			event->time_msec, event->button, event->state);
}

void
chvt(const Arg *arg)
{
	wlr_session_change_vt(session, arg->ui);
}

void
checkidleinhibitor(struct wlr_surface *exclude)
{
	int inhibited = 0, unused_lx, unused_ly;
	struct wlr_idle_inhibitor_v1 *inhibitor;
	Client *c;

	if (idle_inhibit_fullscreen) {
		wl_list_for_each(c, &clients, link) {
			if (c->isfullscreen && c->mon && c->mon->wlr_output->enabled
					&& VISIBLEON(c, c->mon) && client_surface(c) != exclude) {
				wlr_idle_notifier_v1_set_inhibited(idle_notifier, 1);
				return;
			}
		}
	}
	wl_list_for_each(inhibitor, &idle_inhibit_mgr->inhibitors, link) {
		struct wlr_surface *surface = wlr_surface_get_root_surface(inhibitor->surface);
		struct wlr_scene_tree *tree = surface->data;
		if (exclude != surface && (bypass_surface_visibility || (!tree
				|| wlr_scene_node_coords(&tree->node, &unused_lx, &unused_ly)))) {
			inhibited = 1;
			break;
		}
	}

	wlr_idle_notifier_v1_set_inhibited(idle_notifier, inhibited);
}

void
cleanup(void)
{
	/* the helper and the monitor-sensor it started share its process group */
	if (sensor_pid > 0)
		kill(-sensor_pid, SIGTERM);
	xsatcleanup();
#ifdef HYPR
	hyprcleanup();
#endif
	cleanuplisteners();
#ifdef XWAYLAND
	wlr_xwayland_destroy(xwayland);
	xwayland = NULL;
#endif
	wl_display_destroy_clients(dpy);
	closeanimclear(NULL);
	if (child_pid > 0) {
		kill(-child_pid, SIGTERM);
		waitpid(child_pid, NULL, 0);
	}
	wlr_xcursor_manager_destroy(cursor_mgr);

	destroykeyboardgroup(&kb_group->destroy, NULL);

	/* If it's not destroyed manually, it will cause a use-after-free of wlr_seat.
	 * Destroy it until it's fixed on the wlroots side */
	wlr_backend_destroy(backend);

	wl_display_destroy(dpy);
	/* Destroy after the wayland display (when the monitors are already destroyed)
	   to avoid destroying them with an invalid scene output. */
	wlr_scene_node_destroy(&scene->tree.node);
}

void
cleanupmon(struct wl_listener *listener, void *data)
{
	Monitor *m = wl_container_of(listener, m, destroy);
	LayerSurface *l, *tmp;
	IpcOutput *io;
	size_t i;

	wl_list_for_each(io, &ipc_outputs, link)
		if (io->mon == m)
			io->mon = NULL;

	/* m->layers[i] are intentionally not unlinked */
	for (i = 0; i < LENGTH(m->layers); i++) {
		wl_list_for_each_safe(l, tmp, &m->layers[i], link)
			wlr_layer_surface_v1_destroy(l->layer_surface);
	}

	if (wsdrag.m == m) {
		wsdrag.active = 0;
		wsdrag.m = NULL;
	}

	if (grabm == m) {
		grabm = NULL;
		if (cursor_mode == CurDriftPan)
			cursor_mode = CurNormal;
	}

	if (m->unblock) {
		wl_event_source_remove(m->unblock);
		m->unblock = NULL;
	}
	if (screenfade.m == m) {
		screenfade.m = NULL;
		wlr_scene_node_destroy(&screenfade.rect->node);
	}

	wl_list_remove(&m->destroy.link);
	wl_list_remove(&m->frame.link);
	wl_list_remove(&m->link);
	wl_list_remove(&m->request_state.link);
	if (m->lock_surface)
		destroylocksurface(&m->destroy_lock_surface, NULL);
	m->wlr_output->data = NULL;
	wlr_output_layout_remove(output_layout, m->wlr_output);
	wlr_scene_output_destroy(m->scene_output);

	closemon(m);
	closeanimclear(m);
	wlr_scene_node_destroy(&m->fullscreen_bg->node);
	free(m);
	saveoutputstate();
}

void
cleanuplisteners(void)
{
	wl_list_remove(&keyboard_focus_change.link);
	wl_list_remove(&new_text_input.link);
	wl_list_remove(&new_input_method.link);
	wl_list_remove(&cursor_axis.link);
	wl_list_remove(&cursor_button.link);
	wl_list_remove(&cursor_frame.link);
	wl_list_remove(&cursor_motion.link);
	wl_list_remove(&cursor_motion_absolute.link);
	wl_list_remove(&cursor_swipe_begin.link);
	wl_list_remove(&cursor_swipe_end.link);
	wl_list_remove(&cursor_swipe_update.link);
	wl_list_remove(&cursor_touch_cancel.link);
	wl_list_remove(&cursor_touch_down.link);
	wl_list_remove(&cursor_touch_frame.link);
	wl_list_remove(&cursor_touch_motion.link);
	wl_list_remove(&cursor_touch_up.link);
	wl_list_remove(&cursor_pinch_begin.link);
	wl_list_remove(&cursor_pinch_update.link);
	wl_list_remove(&cursor_pinch_end.link);
	wl_list_remove(&gpu_reset.link);
	wl_list_remove(&new_idle_inhibitor.link);
	wl_list_remove(&layout_change.link);
	wl_list_remove(&new_input_device.link);
	wl_list_remove(&new_virtual_keyboard.link);
	wl_list_remove(&new_virtual_pointer.link);
	wl_list_remove(&new_pointer_constraint.link);
	wl_list_remove(&new_output.link);
	wl_list_remove(&new_xdg_toplevel.link);
	wl_list_remove(&new_xdg_decoration.link);
	wl_list_remove(&new_xdg_popup.link);
	wl_list_remove(&new_layer_surface.link);
	wl_list_remove(&output_mgr_apply.link);
	wl_list_remove(&output_mgr_test.link);
	wl_list_remove(&output_power_mgr_set_mode.link);
	wl_list_remove(&request_cursor.link);
	wl_list_remove(&request_set_psel.link);
	wl_list_remove(&request_set_sel.link);
	wl_list_remove(&request_set_cursor_shape.link);
	wl_list_remove(&request_start_drag.link);
	wl_list_remove(&start_drag.link);
	wl_list_remove(&new_session_lock.link);
#ifdef XWAYLAND
	wl_list_remove(&new_xwayland_surface.link);
	wl_list_remove(&xwayland_ready.link);
#endif
}

void
closemon(Monitor *m)
{
	/* update selmon if needed and
	 * move closed monitor's clients to the focused one */
	Client *c;
	Monitor *n;
	if (m == selmon) {
		/* the first monitor that is on and shows something of its own */
		selmon = NULL;
		wl_list_for_each(n, &mons, link) {
			if (n != m && n->wlr_output->enabled && !n->mirroring) {
				selmon = n;
				break;
			}
		}
	}

	wl_list_for_each(c, &clients, link) {
		if (c->isfloating && c->geom.x > m->m.width)
			resize(c, (struct wlr_box){.x = c->geom.x - m->w.width, .y = c->geom.y,
					.width = c->geom.width, .height = c->geom.height}, 0);
		if (c->mon == m)
			setmon(c, selmon, c->ws);
	}
	focusclient(focustop(selmon), 1);
}

void
commitlayersurfacenotify(struct wl_listener *listener, void *data)
{
	LayerSurface *l = wl_container_of(listener, l, surface_commit);
	struct wlr_layer_surface_v1 *layer_surface = l->layer_surface;
	struct wlr_scene_tree *scene_layer = layertree(layer_surface, layer_surface->current.layer);
	struct wlr_layer_surface_v1_state old_state;
	int wasmapped;

	/* the cards copy this surface, and it is hidden so nothing damages them */
	if (overview_visible && layer_surface->namespace
			&& !strcmp(layer_surface->namespace, LABELS_NAMESPACE)) {
		overview_dirty = 1;
		wlr_output_schedule_frame(l->mon->wlr_output);
	}
	if (l->layer_surface->initial_commit) {
		client_set_scale(layer_surface->surface, l->mon->wlr_output->scale);

		/* Temporarily set the layer's current state to pending
		 * so that we can easily arrange it */
		old_state = l->layer_surface->current;
		l->layer_surface->current = l->layer_surface->pending;
		arrangelayers(l->mon);
		l->layer_surface->current = old_state;
		return;
	}

	/* before the early return: a turn resizes the buffer with nothing else committed; no wallpaper, nothing to blur */
	if (l->blur) {
		wlr_scene_blur_set_size(l->blur, layer_surface->surface->current.width,
				layer_surface->surface->current.height);
		wlr_scene_node_set_enabled(&l->blur->node,
				!wl_list_empty(&l->mon->layers[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND]));
		if (!wlr_scene_blur_get_transparency_mask_source(l->blur))
			wlr_scene_node_for_each_buffer(&l->scene->node, findlayerbuf, l);
	}
	/* the commit that takes an acked size has no committed bits: the tray's spot depends on that size */
	if (l->mapped && l == phonetray(l->mon))
		traysync(l->mon);
	if (layer_surface->current.committed == 0 && l->mapped == layer_surface->surface->mapped)
		return;
	wasmapped = l->mapped;
	l->mapped = layer_surface->surface->mapped;

	if (scene_layer != l->scene->node.parent) {
		wlr_scene_node_reparent(&l->scene->node, scene_layer);
		wl_list_remove(&l->link);
		wl_list_insert(&l->mon->layers[layer_surface->current.layer], &l->link);
		wlr_scene_node_reparent(&l->popups->node, (layer_surface->current.layer
				< ZWLR_LAYER_SHELL_V1_LAYER_TOP ? layers[LyrTop] : scene_layer));
	}

	arrangelayers(l->mon);
	if (!wasmapped && l->mapped)
		layeranimstart(l);
	if (wasmapped != l->mapped)
		rotsoon(1);
	/* the cards carry the wallpaper, so a new one shows up in them too */
	if (overview_visible && layer_surface->current.layer
			== ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND) {
		overview_dirty = 1;
		wlr_output_schedule_frame(l->mon->wlr_output);
	}
}

void
commitnotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, commit);

	if (c->surface.xdg->initial_commit) {
		/*
		 * Get the monitor this client will be rendered on
		 * Note that if the user set a rule in which the client is placed on
		 * a different monitor based on its title, this will likely select
		 * a wrong monitor.
		 */
		applyrules(c);
		if (c->mon) {
			client_set_scale(client_surface(c), c->mon->wlr_output->scale);
		}
		setmon(c, NULL, 0); /* Make sure to reapply rules in mapnotify() */

		wlr_xdg_toplevel_set_wm_capabilities(c->surface.xdg->toplevel,
				WLR_XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN);
		if (c->decoration)
			requestdecorationmode(&c->set_decoration_mode, c->decoration);
		/* so the first buffer is already the right size for the open animation */
		if (selmon && !client_get_parent(c) && !client_is_float_type(c))
			wlr_xdg_toplevel_set_size(c->surface.xdg->toplevel, selmon->w.width, selmon->w.height);
		else
			wlr_xdg_toplevel_set_size(c->surface.xdg->toplevel, 0, 0);
		return;
	}

	if (selmon && c == focustop(selmon))
		topcolorsoon();

	if (DRIFTLT(c->mon) && c->oncanvas && !c->isfloating && !c->isfullscreen
			&& !c->isfakefull) {
		/* on the canvas the client owns its size: follow whatever it asked
		 * for, then place that box under the camera again */
		struct wlr_box geo, box;
		int w, h;
		client_get_geometry(c, &geo);
		/* a client that never acks a configure would otherwise hold the
		 * canvas at a size it is not painting at, for as long as it lives */
		if (c->resize && now_ms() - c->resizeat > RESIZEWAIT)
			c->resize = 0;
		if (!c->resize && geo.width > 0 && geo.height > 0) {
			w = geo.width + 2 * (int)c->bw;
			h = geo.height + 2 * (int)c->bw;
			/* Growing to its real size is the first thing a client like a
			 * browser does after mapping, and it would walk out of the
			 * centre it was placed in.  Resizing around the middle keeps
			 * it where it was put, wherever that is. */
			if (c->canvassized) {
				c->canvas.x -= (w - c->canvas.width) / 2;
				c->canvas.y -= (h - c->canvas.height) / 2;
			}
			c->canvas.width = w;
			c->canvas.height = h;
			c->canvassized = 1;
		}
		driftscreen(c->mon, c, &box);
		resize(c, box, 0);
	} else {
		resize(c, c->geom, (c->isfloating && !c->isfullscreen));
	}

	/* mark a pending resize as completed */
	if (c->resize && c->resize <= c->surface.xdg->current.configure_serial)
		c->resize = 0;
	clientfitlearn(c);
	overviewtouch(c);
}

static void
precommitnotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, precommit);
	struct wlr_surface *surface = client_surface(c);

	if (surface->mapped
			&& (surface->pending.committed & WLR_SURFACE_STATE_BUFFER)
			&& !surface->pending.buffer)
		clientcloseanim(c);
}

static void
precommitlayersurfacenotify(struct wl_listener *listener, void *data)
{
	LayerSurface *l = wl_container_of(listener, l, surface_precommit);
	struct wlr_surface *surface = l->layer_surface->surface;

	if (!l->anim.closing && surface->mapped && layeranimated(l)
			&& (surface->pending.committed & WLR_SURFACE_STATE_BUFFER)
			&& !surface->pending.buffer)
		l->anim.closing = closeanimstart(&l->scene->node,
				layers[layermap[l->layer_surface->current.layer]], l->mon);
}

void
commitpopup(struct wl_listener *listener, void *data)
{
	struct wlr_surface *surface = data;
	struct wlr_xdg_popup *popup = wlr_xdg_popup_try_from_wlr_surface(surface);
	LayerSurface *l = NULL;
	Client *c = NULL;
	struct wlr_box box;
	int type = -1;

	if (!popup->base->initial_commit)
		return;

	type = toplevel_from_wlr_surface(popup->base->surface, &c, &l);
	if (!popup->parent || type < 0)
		return;
	popup->base->surface->data = wlr_scene_xdg_surface_create(
			popup->parent->data, popup->base);
	if ((l && !l->mon) || (c && !c->mon)) {
		wlr_xdg_popup_destroy(popup);
		return;
	}
	box = type == LayerShell ? l->mon->m : c->mon->w;
	box.x -= (type == LayerShell ? l->scene->node.x : c->geom.x);
	box.y -= (type == LayerShell ? l->scene->node.y : c->geom.y);
	if (c && c->fit < 1.0) {
		/* the client places it in its own, larger, coordinates */
		box.x = (int)floor(box.x / c->fit);
		box.y = (int)floor(box.y / c->fit);
		box.width = (int)floor(box.width / c->fit);
		box.height = (int)floor(box.height / c->fit);
	}
	wlr_xdg_popup_unconstrain_from_box(popup, &box);
	wl_list_remove(&listener->link);
	free(listener);
}

void
createdecoration(struct wl_listener *listener, void *data)
{
	struct wlr_xdg_toplevel_decoration_v1 *deco = data;
	Client *c = deco->toplevel->base->data;
	c->decoration = deco;

	LISTEN(&deco->events.request_mode, &c->set_decoration_mode, requestdecorationmode);
	LISTEN(&deco->events.destroy, &c->destroy_decoration, destroydecoration);

	requestdecorationmode(&c->set_decoration_mode, deco);
}

void
createidleinhibitor(struct wl_listener *listener, void *data)
{
	struct wlr_idle_inhibitor_v1 *idle_inhibitor = data;
	LISTEN_STATIC(&idle_inhibitor->events.destroy, destroyidleinhibitor);

	checkidleinhibitor(NULL);
}

void
createkeyboard(struct wlr_keyboard *keyboard)
{
	/* Set the keymap to match the group keymap */
	wlr_keyboard_set_keymap(keyboard, kb_group->wlr_group->keyboard.keymap);

	/* Add the new keyboard to the group */
	wlr_keyboard_group_add_keyboard(kb_group->wlr_group, keyboard);
}

KeyboardGroup *
createkeyboardgroup(void)
{
	KeyboardGroup *group = ecalloc(1, sizeof(*group));
	struct xkb_context *context;
	struct xkb_keymap *keymap;

	group->wlr_group = wlr_keyboard_group_create();
	group->wlr_group->data = group;

	/* Prepare an XKB keymap and assign it to the keyboard group. */
	context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (!(keymap = xkb_keymap_new_from_names(context, &xkb_rules,
				XKB_KEYMAP_COMPILE_NO_FLAGS)))
		die("failed to compile keymap");

	wlr_keyboard_set_keymap(&group->wlr_group->keyboard, keymap);
	xkb_keymap_unref(keymap);
	xkb_context_unref(context);

	wlr_keyboard_set_repeat_info(&group->wlr_group->keyboard, repeat_rate, repeat_delay);

	/* Set up listeners for keyboard events */
	LISTEN(&group->wlr_group->keyboard.events.key, &group->key, keypress);
	LISTEN(&group->wlr_group->keyboard.events.modifiers, &group->modifiers, keypressmod);

	group->key_repeat_source = wl_event_loop_add_timer(event_loop, keyrepeat, group);

	/* A seat can only have one keyboard, but this is a limitation of the
	 * Wayland protocol - not wlroots. We assign all connected keyboards to the
	 * same wlr_keyboard_group, which provides a single wlr_keyboard interface for
	 * all of them. Set this combined wlr_keyboard as the seat keyboard.
	 */
	wlr_seat_set_keyboard(seat, &group->wlr_group->keyboard);
	return group;
}

void
createlayersurface(struct wl_listener *listener, void *data)
{
	struct wlr_layer_surface_v1 *layer_surface = data;
	LayerSurface *l;
	struct wlr_surface *surface = layer_surface->surface;
	struct wlr_scene_tree *scene_layer = layertree(layer_surface, layer_surface->pending.layer);

	if (!layer_surface->output
			&& !(layer_surface->output = selmon ? selmon->wlr_output : NULL)) {
		wlr_layer_surface_v1_destroy(layer_surface);
		return;
	}
	/* a mirror shows the source's bar already */
	if (layer_surface->output->data
			&& ((Monitor *)layer_surface->output->data)->mirroring) {
		wlr_layer_surface_v1_destroy(layer_surface);
		return;
	}

	l = layer_surface->data = ecalloc(1, sizeof(*l));
	l->type = LayerShell;
	LISTEN(&surface->events.client_commit, &l->surface_precommit,
			precommitlayersurfacenotify);
	LISTEN(&surface->events.commit, &l->surface_commit, commitlayersurfacenotify);
	LISTEN(&surface->events.unmap, &l->unmap, unmaplayersurfacenotify);
	LISTEN(&layer_surface->events.destroy, &l->destroy, destroylayersurfacenotify);

	l->layer_surface = layer_surface;
	l->mon = layer_surface->output->data;
	l->scene_layer = wlr_scene_layer_surface_v1_create(scene_layer, layer_surface);
	l->scene = l->scene_layer->tree;
	l->popups = surface->data = wlr_scene_tree_create(layer_surface->current.layer
			< ZWLR_LAYER_SHELL_V1_LAYER_TOP ? layers[LyrTop] : scene_layer);
	l->scene->node.data = l->popups->node.data = l;
	if (layer_surface->namespace && (!strcmp(layer_surface->namespace, "phone-menu")
			|| !strcmp(layer_surface->namespace, "phone-panel"))
			&& (l->blur = wlr_scene_blur_create(l->scene, 0, 0)))
		wlr_scene_node_lower_to_bottom(&l->blur->node);

	wl_list_insert(&l->mon->layers[layer_surface->pending.layer],&l->link);
	wlr_surface_send_enter(surface, layer_surface->output);
}

void
createlocksurface(struct wl_listener *listener, void *data)
{
	SessionLock *lock = wl_container_of(listener, lock, new_surface);
	struct wlr_session_lock_surface_v1 *lock_surface = data;
	Monitor *m = lock_surface->output->data;
	struct wlr_scene_tree *scene_tree = lock_surface->surface->data
			= wlr_scene_subsurface_tree_create(lock->scene, lock_surface->surface);
	m->lock_surface = lock_surface;

	wlr_scene_node_set_position(&scene_tree->node, m->m.x, m->m.y);
	wlr_session_lock_surface_v1_configure(lock_surface, m->m.width, m->m.height);

	LISTEN(&lock_surface->events.destroy, &m->destroy_lock_surface, destroylocksurface);
	keyboardoverlock();

	if (m == selmon)
		client_notify_enter(lock_surface->surface, wlr_seat_get_keyboard(seat));
}

const char *
transformname(enum wl_output_transform t)
{
	switch (t) {
	case WL_OUTPUT_TRANSFORM_90: return "90";
	case WL_OUTPUT_TRANSFORM_180: return "180";
	case WL_OUTPUT_TRANSFORM_270: return "270";
	case WL_OUTPUT_TRANSFORM_FLIPPED: return "flipped";
	case WL_OUTPUT_TRANSFORM_FLIPPED_90: return "flipped-90";
	case WL_OUTPUT_TRANSFORM_FLIPPED_180: return "flipped-180";
	case WL_OUTPUT_TRANSFORM_FLIPPED_270: return "flipped-270";
	default: return "normal";
	}
}

static int
parsetransform(const char *s, enum wl_output_transform *t)
{
	static const struct { const char *name; enum wl_output_transform t; } map[] = {
		{"normal", WL_OUTPUT_TRANSFORM_NORMAL}, {"90", WL_OUTPUT_TRANSFORM_90},
		{"180", WL_OUTPUT_TRANSFORM_180}, {"270", WL_OUTPUT_TRANSFORM_270},
		{"flipped", WL_OUTPUT_TRANSFORM_FLIPPED},
		{"flipped-90", WL_OUTPUT_TRANSFORM_FLIPPED_90},
		{"flipped-180", WL_OUTPUT_TRANSFORM_FLIPPED_180},
		{"flipped-270", WL_OUTPUT_TRANSFORM_FLIPPED_270},
	};
	size_t i;

	for (i = 0; i < LENGTH(map); i++) {
		if (!strcmp(s, map[i].name)) {
			*t = map[i].t;
			return 1;
		}
	}
	return 0;
}

static int
parsebool(const char *s)
{
	return !strcmp(s, "true") || !strcmp(s, "1") || !strcmp(s, "on")
			|| !strcmp(s, "yes");
}

static OutputCfg *
outcfgentry(const char *name)
{
	size_t i;

	for (i = 0; i < noutcfgs; i++)
		if (!strcmp(outcfgs[i].name, name))
			return &outcfgs[i];
	if (!(outcfgs = realloc(outcfgs, (noutcfgs + 1) * sizeof(*outcfgs))))
		die("config: realloc:");
	memset(&outcfgs[noutcfgs], 0, sizeof(*outcfgs));
	snprintf(outcfgs[noutcfgs].name, sizeof outcfgs[noutcfgs].name, "%s", name);
	return &outcfgs[noutcfgs++];
}

void
cfgoutput(char *v)
{
	OutputCfg *o;
	char *tok, *eq, *save = NULL;

	if (!(tok = strtok_r(v, " \t", &save))) {
		cfgerror("output needs a name");
		return;
	}
	o = outcfgentry(tok);
	o->line = cfg_curline;
	while ((tok = strtok_r(NULL, " \t", &save))) {
		if (!(eq = strchr(tok, '='))) {
			cfgerror("output %s: expected key=value, got '%s'", o->name, tok);
			continue;
		}
		*eq++ = '\0';
		if (!strcmp(tok, "mode")) {
			int w, h;
			float hz = 0;
			if (!strcmp(eq, "preferred")) {
				o->has_mode = 1;
				o->mw = o->mh = o->mhz = 0;
			} else if (sscanf(eq, "%dx%d@%f", &w, &h, &hz) >= 2 && w > 0 && h > 0) {
				o->has_mode = 1;
				o->mw = w;
				o->mh = h;
				o->mhz = (int)(hz * 1000.0f + 0.5f);
			} else {
				cfgerror("output %s: bad mode '%s'", o->name, eq);
			}
		} else if (!strcmp(tok, "pos")) {
			int x, y;
			if (!strcmp(eq, "auto")) {
				o->has_pos = 1;
				o->pos_auto = 1;
			} else if (sscanf(eq, "%d,%d", &x, &y) == 2) {
				o->has_pos = 1;
				o->pos_auto = 0;
				o->x = x;
				o->y = y;
			} else {
				cfgerror("output %s: bad pos '%s'", o->name, eq);
			}
		} else if (!strcmp(tok, "scale")) {
			float s = strtof(eq, NULL);
			if (s < 0.1f || s > 10.0f) {
				cfgerror("output %s: bad scale '%s'", o->name, eq);
			} else {
				o->has_scale = 1;
				o->scale = s;
			}
		} else if (!strcmp(tok, "transform")) {
			if (parsetransform(eq, &o->transform))
				o->has_transform = 1;
			else
				cfgerror("output %s: bad transform '%s'", o->name, eq);
		} else if (!strcmp(tok, "enabled")) {
			o->has_enabled = 1;
			o->enabled = parsebool(eq);
		} else if (!strcmp(tok, "mirror")) {
			o->has_mirror = 1;
			snprintf(o->mirror, sizeof o->mirror, "%s",
					strcmp(eq, "none") ? eq : "");
		} else if (!strcmp(tok, "adaptive_sync")) {
			o->has_vrr = 1;
			o->vrr = parsebool(eq);
		} else {
			cfgerror("output %s: unknown key '%s'", o->name, tok);
		}
	}
}

/* a mirror shows a real monitor: itself and another mirror are refused */
void
cfgoutputcheck(void)
{
	size_t i, j;

	for (i = 0; i < noutcfgs; i++) {
		OutputCfg *o = &outcfgs[i];
		if (!o->mirror[0] || !strcmp(o->name, "*"))
			continue;
		cfg_curline = o->line;
		if (!strcmp(o->mirror, o->name)) {
			cfgerror("output %s cannot mirror itself", o->name);
			o->mirror[0] = '\0';
			continue;
		}
		for (j = 0; j < noutcfgs; j++) {
			if (j != i && !strcmp(outcfgs[j].name, o->mirror)
					&& outcfgs[j].mirror[0]) {
				cfgerror("output %s mirrors %s, which is a mirror itself",
						o->name, o->mirror);
				o->mirror[0] = '\0';
				break;
			}
		}
	}
}

static void
outcfgoverlay(const OutputCfg *from, OutputCfg *out)
{
	if (from->has_mode) {
		out->mw = from->mw;
		out->mh = from->mh;
		out->mhz = from->mhz;
	}
	if (from->has_pos) {
		out->pos_auto = from->pos_auto;
		out->x = from->x;
		out->y = from->y;
	}
	if (from->has_scale)
		out->scale = from->scale;
	if (from->has_transform)
		out->transform = from->transform;
	if (from->has_enabled)
		out->enabled = from->enabled;
	if (from->has_mirror)
		snprintf(out->mirror, sizeof out->mirror, "%s", from->mirror);
	if (from->has_vrr)
		out->vrr = from->vrr;
}

/* the compiled monrules, then "*", then the output's own line */
void
outcfgmerged(const char *name, OutputCfg *out)
{
	const MonitorRule *r;
	size_t i;

	memset(out, 0, sizeof(*out));
	snprintf(out->name, sizeof out->name, "%s", name);
	out->scale = 1.0f;
	out->transform = WL_OUTPUT_TRANSFORM_NORMAL;
	out->enabled = 1;
	out->pos_auto = 1;
	for (r = monrules; r < END(monrules); r++) {
		if (!r->name || strstr(name, r->name)) {
			out->scale = r->scale;
			out->transform = r->rr;
			if (r->x != -1 || r->y != -1) {
				out->pos_auto = 0;
				out->x = r->x;
				out->y = r->y;
			}
			break;
		}
	}
	for (i = 0; i < noutcfgs; i++)
		if (!strcmp(outcfgs[i].name, "*"))
			outcfgoverlay(&outcfgs[i], out);
	for (i = 0; i < noutcfgs; i++)
		if (!strcmp(outcfgs[i].name, name))
			outcfgoverlay(&outcfgs[i], out);
	/* "* mirror=X" is how every other screen copies X; X itself stays */
	if (!strcmp(out->mirror, name))
		out->mirror[0] = '\0';
}

/* a source keeps the spot its mirror was fitted to, see mirrorfit() */
static int
ismirrorsource(Monitor *m)
{
	Monitor *o;

	wl_list_for_each(o, &mons, link)
		if (o->mirroring && o->mirror_src == m)
			return 1;
	return 0;
}

Monitor *
monbyname(const char *name)
{
	Monitor *m;

	wl_list_for_each(m, &mons, link)
		if (!strcmp(m->wlr_output->name, name))
			return m;
	return NULL;
}

/* the monitor this one copies right now: its configured source, if that
 * one is here, on, and not a mirror itself */
Monitor *
mirrorsource(Monitor *m)
{
	Monitor *src;

	if (!m->mirror_of[0] || !m->wlr_output->enabled)
		return NULL;
	if (!(src = monbyname(m->mirror_of)) || src == m
			|| !src->wlr_output->enabled || src->mirror_of[0])
		return NULL;
	return src;
}

void
mirrorstart(Monitor *m)
{
	LayerSurface *l, *tmp;
	size_t i;

	m->mirroring = 1;
	/* the bar on the source is what the mirror shows; its own would sit
	 * on top of it */
	for (i = 0; i < LENGTH(m->layers); i++) {
		wl_list_for_each_safe(l, tmp, &m->layers[i], link)
			wlr_layer_surface_v1_destroy(l->layer_surface);
	}
	if (wsdrag.m == m) {
		wsdrag.active = 0;
		wsdrag.m = NULL;
	}

	if (grabm == m) {
		grabm = NULL;
		if (cursor_mode == CurDriftPan)
			cursor_mode = CurNormal;
	}
	closemon(m);
}

void
mirrorstop(Monitor *m)
{
	OutputCfg c;
	Monitor *src = m->mirror_src;
	struct wlr_output *o = m->wlr_output;
	struct wlr_output_state st;

	m->mirroring = 0;
	m->mirror_src = NULL;
	/* the source was pinned for the mirror; let it float again */
	if (src && src->wlr_output->enabled && !ismirrorsource(src)) {
		outcfgmerged(src->wlr_output->name, &c);
		if (c.pos_auto)
			wlr_output_layout_add_auto(output_layout, src->wlr_output);
	}
	if (!o->enabled)
		return;
	outcfgmerged(o->name, &c);
	if (fabsf(o->scale - c.scale) > 0.001f) {
		wlr_output_state_init(&st);
		wlr_output_state_set_scale(&st, c.scale);
		wlr_output_commit_state(o, &st);
		wlr_output_state_finish(&st);
	}
	if (c.pos_auto)
		wlr_output_layout_add_auto(output_layout, o);
	else
		wlr_output_layout_add(output_layout, o, c.x, c.y);
}

/* the whole logical area of the source, scaled to fit and centred: the
 * mirror sits on the same spot of the one scene at its own scale */
void
mirrorfit(Monitor *m, Monitor *src)
{
	struct wlr_output *o = m->wlr_output;
	struct wlr_output_layout_output *lo;
	struct wlr_box sb;
	struct wlr_output_state st;
	int pw, ph, lw, lh, x, y;
	float scale;

	m->mirror_src = src;
	wlr_output_layout_get_box(output_layout, src->wlr_output, &sb);
	if (sb.width <= 0 || sb.height <= 0)
		return;
	/* an auto-placed source would be pushed right of its own mirror by
	 * the layout, and the mirror would follow it forever: pin it */
	lo = wlr_output_layout_get(output_layout, src->wlr_output);
	if (lo && lo->auto_configured)
		wlr_output_layout_add(output_layout, src->wlr_output, sb.x, sb.y);
	wlr_output_transformed_resolution(o, &pw, &ph);
	scale = MIN((float)pw / (float)sb.width, (float)ph / (float)sb.height);
	/* the logical size is truncated, keep it from landing one pixel short */
	scale *= 0.99999f;
	if (scale <= 0.0f)
		return;
	if (fabsf(o->scale - scale) > 0.0001f) {
		wlr_output_state_init(&st);
		wlr_output_state_set_scale(&st, scale);
		if (!wlr_output_commit_state(o, &st))
			wlr_log(WLR_ERROR, "%s: cannot scale to mirror %s", o->name,
					src->wlr_output->name);
		wlr_output_state_finish(&st);
	}
	wlr_output_effective_resolution(o, &lw, &lh);
	x = sb.x - (lw - sb.width) / 2;
	y = sb.y - (lh - sb.height) / 2;
	lo = wlr_output_layout_get(output_layout, o);
	if (!lo || lo->x != x || lo->y != y || lo->auto_configured)
		wlr_output_layout_add(output_layout, o, x, y);
}

/* from updatemons: start, stop and place every mirror.  The commits and
 * layout moves in here re-enter updatemons, so the nested call skips this. */
void
placemirrors(void)
{
	static int busy;
	Monitor *m, *src;

	if (busy)
		return;
	busy = 1;
	wl_list_for_each(m, &mons, link) {
		src = mirrorsource(m);
		if (src && !m->mirroring)
			mirrorstart(m);
		else if (!src && m->mirroring)
			mirrorstop(m);
		if (src)
			mirrorfit(m, src);
	}
	busy = 0;
}

static struct wl_event_source *outcfg_retry;
static int outcfg_tries;

static int
outcfgretry(void *data)
{
	applyoutputcfgs();
	return 0;
}

/* bring one output to what the config says, committing only what differs */
void
applyoutputcfg(Monitor *m)
{
	OutputCfg c;
	struct wlr_output *o = m->wlr_output;
	struct wlr_output_state st;
	struct wlr_output_layout_output *lo;
	struct wlr_output_mode *mode, *want = NULL;

	outcfgmerged(o->name, &c);
	snprintf(m->mirror_of, sizeof m->mirror_of, "%s", c.mirror);
	if (m == rotmon() && c.transform <= WL_OUTPUT_TRANSFORM_270)
		c.transform = (c.transform + rot) % 4;

	wlr_output_state_init(&st);
	/* a screen put to sleep by power management is off, not disabled */
	if (o->enabled != c.enabled && !(m->asleep && c.enabled))
		wlr_output_state_set_enabled(&st, c.enabled);
	if (c.enabled) {
		if (c.mw) {
			wl_list_for_each(mode, &o->modes, link) {
				if (mode->width != c.mw || mode->height != c.mh)
					continue;
				if (!c.mhz) {
					if (!want)
						want = mode;
				} else if (abs(mode->refresh - c.mhz) <= 500 && (!want
						|| abs(mode->refresh - c.mhz) < abs(want->refresh - c.mhz))) {
					want = mode;
				}
			}
			if (want) {
				if (o->current_mode != want)
					wlr_output_state_set_mode(&st, want);
			} else if (o->width != c.mw || o->height != c.mh
					|| (c.mhz && o->refresh != c.mhz)) {
				wlr_output_state_set_custom_mode(&st, c.mw, c.mh, c.mhz);
			}
		} else if ((want = wlr_output_preferred_mode(o)) && o->current_mode != want) {
			wlr_output_state_set_mode(&st, want);
		}
		if (!m->mirroring && fabsf(o->scale - c.scale) > 0.001f)
			wlr_output_state_set_scale(&st, c.scale);
		if (o->transform != c.transform)
			wlr_output_state_set_transform(&st, c.transform);
		if (c.vrr != (o->adaptive_sync_status == WLR_OUTPUT_ADAPTIVE_SYNC_ENABLED))
			wlr_output_state_set_adaptive_sync_enabled(&st, c.vrr);
	}
	if (st.committed) {
		/* not every output does VRR; keep the rest of the change */
		if ((st.committed & WLR_OUTPUT_STATE_ADAPTIVE_SYNC_ENABLED)
				&& !wlr_output_test_state(o, &st))
			st.committed &= ~WLR_OUTPUT_STATE_ADAPTIVE_SYNC_ENABLED;
		if (!wlr_output_commit_state(o, &st)) {
			wlr_log(WLR_ERROR, "%s: output configuration rejected", o->name);
			/* a panel busy with its first frames refuses once: without this it stays at scale 1 */
			if (!outcfg_retry)
				outcfg_retry = wl_event_loop_add_timer(event_loop, outcfgretry, NULL);
			if (outcfg_tries++ < 20)
				wl_event_source_timer_update(outcfg_retry, 100);
		} else if (c.enabled) {
			m->asleep = 0;
			outcfg_tries = 0;
		}
	}
	wlr_output_state_finish(&st);

	if (!o->enabled || mirrorsource(m))
		return;
	lo = wlr_output_layout_get(output_layout, o);
	if (c.pos_auto) {
		if (!lo || (!lo->auto_configured && !ismirrorsource(m)))
			wlr_output_layout_add_auto(output_layout, o);
	} else if (!lo || lo->x != c.x || lo->y != c.y || lo->auto_configured) {
		wlr_output_layout_add(output_layout, o, c.x, c.y);
	}
}

void
applyoutputcfgs(void)
{
	Monitor *m;

	wl_list_for_each(m, &mons, link)
		applyoutputcfg(m);
	updatemons(NULL, NULL);
}

static void
fputfield(FILE *f, const char *s)
{
	if (!s || !*s) {
		fputs("none", f);
		return;
	}
	for (; *s; s++)
		fputc(*s == '\t' || *s == '\n' || *s == '\r' ? ' ' : *s, f);
}

/* every output, on or off, one tab-separated line each: what the monitor
 * settings page reads and what a script can parse with cut -f */
void
saveoutputstate(void)
{
	char path[600], dir[512];
	Monitor *m;
	struct wlr_output_mode *mode, *pref;
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	{
		char *slash = strrchr(dir, '/');
		if (slash) {
			*slash = '\0';
			mkdir(dir, 0700);
			*slash = '/';
		}
	}
	mkdir(dir, 0700);
	snprintf(path, sizeof path, "%s/outputs", dir);
	if (!(f = fopen(path, "w")))
		return;
	wl_list_for_each(m, &mons, link) {
		struct wlr_output *o = m->wlr_output;
		struct wlr_box b = {0};
		int first = 1;

		if (o->enabled)
			wlr_output_layout_get_box(output_layout, o, &b);
		pref = wlr_output_preferred_mode(o);
		fprintf(f, "name=%s\tenabled=%d\tx=%d\ty=%d\tw=%d\th=%d\tpw=%d\tph=%d"
				"\thz=%.2f\tscale=%.2f\ttransform=%s\tmirror=%s\tfocused=%d\tmake=",
				o->name, o->enabled ? 1 : 0, b.x, b.y, b.width, b.height,
				o->width, o->height, o->refresh / 1000.0, o->scale,
				transformname(o->transform),
				m->mirroring && m->mirror_src ? m->mirror_src->wlr_output->name : "none",
				m == selmon);
		fputfield(f, o->make);
		fputs("\tmodel=", f);
		fputfield(f, o->model);
		fputs("\tserial=", f);
		fputfield(f, o->serial);
		if (pref)
			fprintf(f, "\tpreferred=%dx%d@%.2f", pref->width, pref->height,
					pref->refresh / 1000.0);
		else
			fputs("\tpreferred=none", f);
		fputs("\tmodes=", f);
		wl_list_for_each(mode, &o->modes, link) {
			fprintf(f, "%s%dx%d@%.2f", first ? "" : ",", mode->width,
					mode->height, mode->refresh / 1000.0);
			first = 0;
		}
		fputc('\n', f);
	}
	fclose(f);
}

void
createmon(struct wl_listener *listener, void *data)
{
	/* This event is raised by the backend when a new output (aka a display or
	 * monitor) becomes available. */
	struct wlr_output *wlr_output = data;
	size_t i;
	Monitor *m;

	if (!wlr_output_init_render(wlr_output, alloc, drw))
		return;

	m = wlr_output->data = ecalloc(1, sizeof(*m));
	m->wlr_output = wlr_output;

	for (i = 0; i < LENGTH(m->layers); i++)
		wl_list_init(&m->layers[i]);
	for (i = 0; i < NUMWS; i++) {
		wl_list_init(&m->cols[i]);
		m->camz[i] = 1.0;
	}
	m->lt = default_layout >= 0 && default_layout < LtLast
			? (unsigned int)default_layout : LtBSP;

	m->unblock = wl_event_loop_add_timer(event_loop, monunblock, m);

	/* Set up event listeners */
	LISTEN(&wlr_output->events.frame, &m->frame, rendermon);
	LISTEN(&wlr_output->events.destroy, &m->destroy, cleanupmon);
	LISTEN(&wlr_output->events.request_state, &m->request_state, requestmonstate);

	wl_list_insert(&mons, &m->link);

	/* The xdg-protocol specifies:
	 *
	 * If the fullscreened surface is not opaque, the compositor must make
	 * sure that other screen content not part of the same surface tree (made
	 * up of subsurfaces, popups or similarly coupled surfaces) are not
	 * visible below the fullscreened surface.
	 *
	 */
	/* updatemons() will resize and set correct position */
	m->fullscreen_bg = wlr_scene_rect_create(layers[LyrFS], 0, 0, fullscreen_bg);
	wlr_scene_node_set_enabled(&m->fullscreen_bg->node, 0);

	/* Adds this to the output layout in the order it was configured.
	 *
	 * The output layout utility automatically adds a wl_output global to the
	 * display, which Wayland clients can see to find out information about the
	 * output (such as DPI, scale factor, manufacturer, etc).
	 */
	m->scene_output = wlr_scene_output_create(scene, wlr_output);
	/* the config decides mode, scale, transform, position and whether it
	 * comes up at all.  Joining the layout runs updatemons(); a mirror or
	 * a disabled output does not join it, so run it for them here. */
	applyoutputcfg(m);
	if (!wlr_output_layout_get(output_layout, wlr_output))
		updatemons(NULL, NULL);
}

void
createnotify(struct wl_listener *listener, void *data)
{
	/* This event is raised when a client creates a new toplevel (application window). */
	struct wlr_xdg_toplevel *toplevel = data;
	Client *c = NULL;

	/* Allocate a Client for this surface */
	c = toplevel->base->data = ecalloc(1, sizeof(*c));
	c->surface.xdg = toplevel->base;
	c->bw = borderpx;
	c->bufscale = 1.0;
	c->fit = 1.0;

	LISTEN(&toplevel->base->surface->events.client_commit, &c->precommit,
			precommitnotify);
	LISTEN(&toplevel->base->surface->events.commit, &c->commit, commitnotify);
	LISTEN(&toplevel->base->surface->events.map, &c->map, mapnotify);
	LISTEN(&toplevel->base->surface->events.unmap, &c->unmap, unmapnotify);
	LISTEN(&toplevel->events.destroy, &c->destroy, destroynotify);
	LISTEN(&toplevel->events.request_fullscreen, &c->fullscreen, fullscreennotify);
	LISTEN(&toplevel->events.request_maximize, &c->maximize, maximizenotify);
	LISTEN(&toplevel->events.set_title, &c->set_title, updatetitle);
	LISTEN(&toplevel->events.set_app_id, &c->set_app_id, updateappid);
}

void
createpointer(struct wlr_pointer *pointer)
{
	struct libinput_device *device;
	if (wlr_input_device_is_libinput(&pointer->base)
			&& (device = wlr_libinput_get_device_handle(&pointer->base))) {

		if (libinput_device_config_tap_get_finger_count(device)) {
			libinput_device_config_tap_set_enabled(device, tap_to_click);
			libinput_device_config_tap_set_drag_enabled(device, tap_and_drag);
			libinput_device_config_tap_set_drag_lock_enabled(device, drag_lock);
			libinput_device_config_tap_set_button_map(device, button_map);
		}

		if (libinput_device_config_scroll_has_natural_scroll(device))
			libinput_device_config_scroll_set_natural_scroll_enabled(device, natural_scrolling);

		if (libinput_device_config_dwt_is_available(device))
			libinput_device_config_dwt_set_enabled(device, disable_while_typing);

		if (libinput_device_config_left_handed_is_available(device))
			libinput_device_config_left_handed_set(device, left_handed);

		if (libinput_device_config_middle_emulation_is_available(device))
			libinput_device_config_middle_emulation_set_enabled(device, middle_button_emulation);

		if (libinput_device_config_scroll_get_methods(device) != LIBINPUT_CONFIG_SCROLL_NO_SCROLL)
			libinput_device_config_scroll_set_method(device, scroll_method);

		if (libinput_device_config_click_get_methods(device) != LIBINPUT_CONFIG_CLICK_METHOD_NONE)
			libinput_device_config_click_set_method(device, click_method);

		if (libinput_device_config_send_events_get_modes(device))
			libinput_device_config_send_events_set_mode(device, send_events_mode);

		if (libinput_device_config_accel_is_available(device)) {
			libinput_device_config_accel_set_profile(device, accel_profile);
			libinput_device_config_accel_set_speed(device, accel_speed);
		}
	}

	wlr_cursor_attach_input_device(cursor, &pointer->base);
}

void
createpointerconstraint(struct wl_listener *listener, void *data)
{
	PointerConstraint *pointer_constraint = ecalloc(1, sizeof(*pointer_constraint));
	pointer_constraint->constraint = data;
	LISTEN(&pointer_constraint->constraint->events.destroy,
			&pointer_constraint->destroy, destroypointerconstraint);
}

void
createpopup(struct wl_listener *listener, void *data)
{
	/* This event is raised when a client (either xdg-shell or layer-shell)
	 * creates a new popup. */
	struct wlr_xdg_popup *popup = data;
	LISTEN_STATIC(&popup->base->surface->events.commit, commitpopup);
}

void
cursorconstrain(struct wlr_pointer_constraint_v1 *constraint)
{
	if (active_constraint == constraint)
		return;

	if (active_constraint)
		wlr_pointer_constraint_v1_send_deactivated(active_constraint);

	active_constraint = constraint;
	wlr_pointer_constraint_v1_send_activated(constraint);
}

void
cursorframe(struct wl_listener *listener, void *data)
{
	/* This event is forwarded by the cursor when a pointer emits a frame
	 * event. Frame events are sent after regular pointer events to group
	 * multiple events together. For instance, two axis events may happen at the
	 * same time, in which case a frame event won't be sent in between. */
	/* Notify the client with pointer focus of the frame event. */
	wlr_seat_pointer_notify_frame(seat);
}

void
cursorwarptohint(void)
{
	Client *c = NULL;
	double sx = active_constraint->current.cursor_hint.x;
	double sy = active_constraint->current.cursor_hint.y;

	toplevel_from_wlr_surface(active_constraint->surface, &c, NULL);
	if (c && active_constraint->current.cursor_hint.enabled) {
		wlr_cursor_warp(cursor, NULL, sx + c->geom.x + c->bw, sy + c->geom.y + c->bw);
		wlr_seat_pointer_warp(active_constraint->seat, sx, sy);
	}
}

void
destroydecoration(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, destroy_decoration);

	wl_list_remove(&c->destroy_decoration.link);
	wl_list_remove(&c->set_decoration_mode.link);
}

void
destroydragicon(struct wl_listener *listener, void *data)
{
	/* Focus enter isn't sent during drag, so refocus the focused node. */
	focusclient(focustop(selmon), 1);
	motionnotify(0, NULL, 0, 0, 0, 0);
	wl_list_remove(&listener->link);
	free(listener);
}

void
destroyidleinhibitor(struct wl_listener *listener, void *data)
{
	/* `data` is the wlr_surface of the idle inhibitor being destroyed,
	 * at this point the idle inhibitor is still in the list of the manager */
	checkidleinhibitor(wlr_surface_get_root_surface(data));
	wl_list_remove(&listener->link);
	free(listener);
}

void
destroylayersurfacenotify(struct wl_listener *listener, void *data)
{
	LayerSurface *l = wl_container_of(listener, l, destroy);

	wl_list_remove(&l->link);
	wl_list_remove(&l->destroy.link);
	wl_list_remove(&l->unmap.link);
	wl_list_remove(&l->surface_precommit.link);
	wl_list_remove(&l->surface_commit.link);
	wlr_scene_node_destroy(&l->scene->node);
	wlr_scene_node_destroy(&l->popups->node);
	free(l);
}

void
destroylock(SessionLock *lock, int unlock)
{
	Monitor *m;

	wlr_seat_keyboard_notify_clear_focus(seat);
	topcolorsoon();
	rotsoon(1);
	if ((locked = !unlock)) {
		wl_event_source_timer_update(relock_timer, 1000);
		goto destroy;
	}

	relock_tries = 0;
	keyboardoverlock();
	wlr_scene_node_set_enabled(&locked_bg->node, 0);
	/* the apps draw again */
	wl_list_for_each(m, &mons, link)
		arrange(m);

	focusclient(focustop(selmon), 0);
	motionnotify(0, NULL, 0, 0, 0, 0);

destroy:
	wl_list_remove(&lock->new_surface.link);
	wl_list_remove(&lock->unlock.link);
	wl_list_remove(&lock->destroy.link);

	wlr_scene_node_destroy(&lock->scene->node);
	cur_lock = NULL;
	free(lock);
}

void
destroylocksurface(struct wl_listener *listener, void *data)
{
	Monitor *m = wl_container_of(listener, m, destroy_lock_surface);
	struct wlr_session_lock_surface_v1 *surface, *lock_surface = m->lock_surface;

	m->lock_surface = NULL;
	wl_list_remove(&m->destroy_lock_surface.link);

	if (lock_surface->surface != seat->keyboard_state.focused_surface)
		return;

	if (locked && cur_lock && !wl_list_empty(&cur_lock->surfaces)) {
		surface = wl_container_of(cur_lock->surfaces.next, surface, link);
		client_notify_enter(surface->surface, wlr_seat_get_keyboard(seat));
	} else if (!locked) {
		focusclient(focustop(selmon), 1);
	} else {
		wlr_seat_keyboard_clear_focus(seat);
	}
}

void
destroynotify(struct wl_listener *listener, void *data)
{
	/* Called when the xdg_toplevel is destroyed. */
	Client *c = wl_container_of(listener, c, destroy);
#ifdef HYPR
	exportforget(c);
#endif
	wl_list_remove(&c->destroy.link);
	wl_list_remove(&c->set_title.link);
	wl_list_remove(&c->fullscreen.link);
#ifdef XWAYLAND
	if (c->type != XDGShell) {
		wl_list_remove(&c->activate.link);
		wl_list_remove(&c->associate.link);
		wl_list_remove(&c->configure.link);
		wl_list_remove(&c->dissociate.link);
	} else
#endif
	{
		wl_list_remove(&c->precommit.link);
		wl_list_remove(&c->commit.link);
		wl_list_remove(&c->map.link);
		wl_list_remove(&c->unmap.link);
		wl_list_remove(&c->maximize.link);
		wl_list_remove(&c->set_app_id.link);
	}
	free(c);
}

void
destroypointerconstraint(struct wl_listener *listener, void *data)
{
	PointerConstraint *pointer_constraint = wl_container_of(listener, pointer_constraint, destroy);

	if (active_constraint == pointer_constraint->constraint) {
		cursorwarptohint();
		active_constraint = NULL;
	}

	wl_list_remove(&pointer_constraint->destroy.link);
	free(pointer_constraint);
}

void
destroysessionlock(struct wl_listener *listener, void *data)
{
	SessionLock *lock = wl_container_of(listener, lock, destroy);
	destroylock(lock, 0);
}

void
destroykeyboardgroup(struct wl_listener *listener, void *data)
{
	KeyboardGroup *group = wl_container_of(listener, group, destroy);
	if (super_group == group)
		super_group = NULL;
	wl_event_source_remove(group->key_repeat_source);
	wl_list_remove(&group->key.link);
	wl_list_remove(&group->modifiers.link);
	wl_list_remove(&group->destroy.link);
	wlr_keyboard_group_destroy(group->wlr_group);
	free(group);
}

Client *
dirpick(Monitor *m, Client *from, int dir)
{
	Client *n, *best = NULL;
	long best_primary = 0, best_dist = 0;
	int fx1, fy1, fx2, fy2, fcx, fcy;

	if (!from)
		return NULL;
	if (DRIFTLT(m) && from->oncanvas && !from->isfloating)
		return driftpick(m, from, dir);
	fx1 = from->geom.x;
	fy1 = from->geom.y;
	fx2 = from->geom.x + from->geom.width;
	fy2 = from->geom.y + from->geom.height;
	fcx = from->geom.x + from->geom.width / 2;
	fcy = from->geom.y + from->geom.height / 2;

	wl_list_for_each(n, &clients, link) {
		int ncx, ncy, dx, dy, primary, o1, o2, overlap, valid;
		long dist;
		if (n == from || !VISIBLEON(n, m) || n->isfloating)
			continue;
		ncx = n->geom.x + n->geom.width / 2;
		ncy = n->geom.y + n->geom.height / 2;
		dx = ncx - fcx;
		dy = ncy - fcy;

		if (dir == DirLeft || dir == DirRight) {
			valid = dir == DirLeft ? dx < 0 : dx > 0;
			primary = dx < 0 ? -dx : dx;
			o1 = MAX(fy1, n->geom.y);
			o2 = MIN(fy2, n->geom.y + n->geom.height);
		} else {
			valid = dir == DirUp ? dy < 0 : dy > 0;
			primary = dy < 0 ? -dy : dy;
			o1 = MAX(fx1, n->geom.x);
			o2 = MIN(fx2, n->geom.x + n->geom.width);
		}
		overlap = o2 - o1;

		if (!valid || overlap <= 0)
			continue;
		dist = (long)dx * dx + (long)dy * dy;
		if (!best || primary < best_primary ||
				(primary == best_primary && dist < best_dist)) {
			best = n;
			best_primary = primary;
			best_dist = dist;
		}
	}
	return best;
}

void
entermode(const Arg *arg)
{
	Client *sel;
	inputmode = arg->i;
	wlr_log(WLR_DEBUG, "mode: %s", inputmode == ModeNormal ? "normal" : "insert");
	if ((sel = focustop(selmon)))
		client_set_border_color(sel, focuscolorfor());
}

const float *
focuscolorfor(void)
{
	return inputmode == ModeNormal ? normalmodecolor : focuscolor;
}

void
focusclient(Client *c, int lift)
{
	struct wlr_surface *old = seat->keyboard_state.focused_surface;
	int unused_lx, unused_ly, old_client_type;
	Client *old_c = NULL;
	LayerSurface *old_l = NULL;

	topcolorsoon();
	rotsoon(1);
	if (locked)
		return;

	/* Raise client in stacking order if requested */
	if (c && lift)
		wlr_scene_node_raise_to_top(&c->scene->node);

	if (c && client_surface(c) == old)
		return;

	if ((old_client_type = toplevel_from_wlr_surface(old, &old_c, &old_l)) == XDGShell) {
		struct wlr_xdg_popup *popup, *tmp;
		wl_list_for_each_safe(popup, tmp, &old_c->surface.xdg->popups, link)
			wlr_xdg_popup_destroy(popup);
	}

	/* Put the new client atop the focus stack and select its monitor */
	if (c && !client_is_unmanaged(c)) {
		wl_list_remove(&c->flink);
		wl_list_insert(&fstack, &c->flink);
		selmon = c->mon;
		if (c->ftl)
			wlr_foreign_toplevel_handle_v1_set_activated(c->ftl, 1);

		/* Don't change border color if there is an exclusive focus or we are
		 * handling a drag operation */
		if (!exclusive_focus && !seat->drag)
			client_set_border_color(c, focuscolorfor());
		if (!exclusive_focus && !seat->drag)
			client_set_border_enabled(c, !decorhidden && !c->isfullscreen
					&& !c->isfakefull);
	}

	/* Deactivate old client if focus is changing */
	if (old && (!c || client_surface(c) != old)) {
		/* If an overlay is focused, don't focus or activate the client,
		 * but only update its position in fstack to render its border with focuscolor
		 * and focus it after the overlay is closed. */
		if (old_client_type == LayerShell && wlr_scene_node_coords(
					&old_l->scene->node, &unused_lx, &unused_ly)
				&& old_l->layer_surface->current.layer >= ZWLR_LAYER_SHELL_V1_LAYER_TOP) {
			return;
		} else if (old_c && old_c == exclusive_focus && client_wants_focus(old_c)) {
			return;
		/* Don't deactivate old client if the new one wants focus, as this causes issues with winecfg
		 * and probably other clients */
		} else if (old_c && !client_is_unmanaged(old_c) && (!c || !client_wants_focus(c))) {
			client_set_border_color(old_c, bordercolor);
			client_set_border_enabled(old_c, !decorhidden && unfocused_borders
					&& !old_c->isfullscreen && !old_c->isfakefull);
			if (old_c->ftl)
				wlr_foreign_toplevel_handle_v1_set_activated(old_c->ftl, 0);

			client_activate_surface(old, 0);
		}
	}
	ipcnotifyall();

	if (!c) {
		/* With no client, all we have left is to clear focus */
		wlr_seat_keyboard_notify_clear_focus(seat);
		return;
	}

	/* Change cursor surface */
	motionnotify(0, NULL, 0, 0, 0, 0);

	/* Have a client, so focus its top-level wlr_surface */
	client_notify_enter(client_surface(c), wlr_seat_get_keyboard(seat));

	/* Activate the new client */
	client_activate_surface(client_surface(c), 1);
}

void
focusdir(const Arg *arg)
{
	Client *sel = focustop(selmon), *c;
	if (SCROLLLT(selmon) && sel
			&& (sel->isfullscreen || sel->isfakefull)) {
		/* niri: moving focus out of fullscreen just resizes the window
		 * back into its column, then the move proceeds */
		if (sel->isfullscreen)
			setfullscreen(sel, 0);
		if (sel->isfakefull) {
			sel->isfakefull = 0;
			applyeffects(sel);
			applyfakefull(sel);
			arrange(selmon);
		}
	}
	if (selmon && (!sel || sel->isfullscreen || sel->isfakefull
			|| !(c = dirpick(selmon, sel, arg->i)))) {
		/* nothing in that direction: step to the neighbouring workspace.
		 * The scroll layout stacks workspaces vertically like niri, so
		 * there the vertical axis changes workspace instead. */
		if (SCROLLLT(selmon)
				? (arg->i == DirUp || arg->i == DirDown)
				: (arg->i == DirLeft || arg->i == DirRight)) {
			Arg a = {.i = (arg->i == DirLeft || arg->i == DirUp) ? -1 : +1};
			wsstep(&a);
		}
		return;
	}
	if (!selmon)
		return;
	focusclient(c, 1);
	if (SCROLLLT(selmon)) {
		arrange(selmon); /* scroll the focused column into view */
	} else if (DRIFTLT(selmon)) {
		driftreveal(selmon, c); /* pan the camera onto the new window */
		driftarrange(selmon);
	}
	warpto(c);
}

void
focusnext(const Arg *arg)
{
	Client *sel = focustop(selmon), *c;
	Node *n;
	if (!sel || sel->isfullscreen || sel->isfakefull || !selmon
			|| (!sel->node && !sel->col && !sel->oncanvas))
		return;
	if (sel->oncanvas) {
		/* walk the windows of this canvas in tiling order */
		struct wl_list *pos = sel->link.next;
		for (;;) {
			if (pos == &clients) {
				pos = clients.next;
				continue;
			}
			c = wl_container_of(pos, c, link);
			if (c == sel)
				return;
			if (drifttiled(c, selmon, selmon->ws))
				break;
			pos = pos->next;
		}
		focusclient(c, 1);
		driftreveal(selmon, c);
		driftarrange(selmon);
		warpto(c);
		return;
	}
	if (sel->col) {
		c = scroll_next(selmon, sel);
		if (c != sel) {
			focusclient(c, 1);
			arrange(selmon);
			warpto(c);
		}
		return;
	}
	n = bsp_nextleaf(selmon->tree[sel->ws], sel->node);
	if (n && n->c != sel) {
		focusclient(n->c, 1);
		warpto(n->c);
	}
}

/* We probably should change the name of this: it sounds like it
 * will focus the topmost client of this mon, when actually will
 * only return that client */
Client *
focustop(Monitor *m)
{
	Client *c;
	wl_list_for_each(c, &fstack, flink) {
		if (VISIBLEON(c, m))
			return c;
	}
	return NULL;
}

void
ftlactivatenotify(struct wl_listener *listener, void *data)
{
	/* A taskbar/dock asked to focus this window */
	Client *c = wl_container_of(listener, c, ftl_activate);
	if (c->mon)
		clientraise(c);
}

static void
clientraise(Client *c)
{
	Arg a = {.ui = c->ws};

	/* the overview hides every window, so a dock click there would focus
	 * something the user cannot see: step out of it first */
	overviewset(0);
	selmon = c->mon;
	viewws(&a);
	focusclient(c, 1);
}

/* the polite close is asynchronous: leave the overview once they have gone, stay if one refuses */
static int
closeallcheck(void *data)
{
	Client *c;

	wl_list_for_each(c, &clients, link) {
		if (client_is_unmanaged(c))
			continue;
		if (--closeall_ticks > 0)
			wl_event_source_timer_update(closeall_timer, CLOSEALL_TICK_MS);
		if (overview_active && selmon && !wsoccupied(selmon, freews(selmon)))
			overviewnavigate(freews(selmon), 1);
		return 0;
	}
	overviewset(0);
	return 0;
}

static void
closeall(void)
{
	Client *c, *tmp;

	if (!selmon)
		return;
	wl_list_for_each_safe(c, tmp, &clients, link) {
		if (!client_is_unmanaged(c))
			client_send_close(c);
	}
	if (!closeall_timer)
		closeall_timer = wl_event_loop_add_timer(event_loop, closeallcheck, NULL);
	closeall_ticks = CLOSEALL_TICKS;
	wl_event_source_timer_update(closeall_timer, CLOSEALL_TICK_MS);
	if (overview_active && !wsoccupied(selmon, freews(selmon)))
		overviewnavigate(freews(selmon), 1);
}

void
ftlclosenotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, ftl_close);
	clientcloseanim(c);
	client_send_close(c);
}

void
fullscreennotify(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, fullscreen);
	setfullscreen(c, client_wants_fullscreen(c));
}

/* NVIDIA spin-waits on the GPU unless told to sleep; read once at EGL init, so clients don't inherit it */
static struct wlr_renderer *
createrenderer(void)
{
	struct wlr_renderer *r;
	int set = !getenv("__GL_YIELD");

	if (set)
		setenv("__GL_YIELD", "USLEEP", 1);
	r = fx_renderer_create(backend);
	if (set)
		unsetenv("__GL_YIELD");
	return r;
}

void
gpureset(struct wl_listener *listener, void *data)
{
	struct wlr_renderer *old_drw = drw;
	struct wlr_allocator *old_alloc = alloc;
	struct Monitor *m;
	if (!(drw = createrenderer()))
		die("couldn't recreate renderer");

	if (!(alloc = wlr_allocator_autocreate(backend, drw)))
		die("couldn't recreate allocator");

	wl_list_remove(&gpu_reset.link);
	wl_signal_add(&drw->events.lost, &gpu_reset);

	wlr_compositor_set_renderer(compositor, drw);

	wl_list_for_each(m, &mons, link) {
		wlr_output_init_render(m->wlr_output, alloc, drw);
	}

	wlr_allocator_destroy(old_alloc);
	wlr_renderer_destroy(old_drw);
}

void
handlesig(int signo)
{
	if (signo == SIGCHLD) {
		pid_t pid;

		while ((pid = waitpid(-1, NULL, WNOHANG)) > 0)
			if (pid == shell_pid)
				shell_pid = 0;
			else if (pid == keyboard_pid)
				keyboard_pid = 0;
			else if (pid == sensor_pid)
				sensor_pid = 0;
	} else if (signo == SIGINT || signo == SIGTERM) {
		/* The session wrapper records the clean exit.  wlr_log() is not
		 * async-signal-safe, so it must not be called from this handler. */
		quit(NULL);
	}
}

static void
handlecrash(int signo)
{
	/* A signal can interrupt malloc/stdio/libwayland.  Do not call into any
	 * of those from here: write(), signal() and raise() are async-signal-safe.
	 * The session wrapper records the resulting exit status, while the reset
	 * disposition below lets the kernel produce the actual core dump. */
	static const char msg[] = "phonegluewc: fatal signal; core dump follows\n";
	if (write(STDERR_FILENO, msg, sizeof(msg) - 1) < 0)
		{}
	signal(signo, SIG_DFL);
	raise(signo);
}

void
inputdevice(struct wl_listener *listener, void *data)
{
	/* This event is raised by the backend when a new input device becomes
	 * available. */
	struct wlr_input_device *device = data;
	uint32_t caps;

	switch (device->type) {
	case WLR_INPUT_DEVICE_KEYBOARD:
		createkeyboard(wlr_keyboard_from_input_device(device));
		break;
	case WLR_INPUT_DEVICE_POINTER:
		createpointer(wlr_pointer_from_input_device(device));
		break;
	case WLR_INPUT_DEVICE_TOUCH:
		createtouch(wlr_touch_from_input_device(device));
		break;
	default:
		/* TODO handle other input device types */
		break;
	}

	/* We need to let the wlr_seat know what our capabilities are, which is
	 * communiciated to the client. In phonegluewc we always have a cursor, even if
	 * there are no pointer devices, so we always include that capability. */
	/* TODO do we actually require a cursor? */
	/* a phone has no keyboard device, but apps only take text focus on a seat that has one */
	caps = WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD;
	if (device->type == WLR_INPUT_DEVICE_TOUCH || (seat->capabilities & WL_SEAT_CAPABILITY_TOUCH))
		caps |= WL_SEAT_CAPABILITY_TOUCH;
	wlr_seat_set_capabilities(seat, caps);
}

/* --- on-screen keyboards: text_input_v3 on one side, input_method_v2 on the other --- */
/* shortcut: no input method keyboard grab or popups, squeekboard needs neither; add them for IMEs with candidate windows */
static void
imsendstate(TextInput *ti)
{
	struct wlr_text_input_v3 *t = ti->input;

	if (t->active_features & WLR_TEXT_INPUT_V3_FEATURE_SURROUNDING_TEXT)
		wlr_input_method_v2_send_surrounding_text(input_method,
				t->current.surrounding.text ? t->current.surrounding.text : "",
				t->current.surrounding.cursor, t->current.surrounding.anchor);
	wlr_input_method_v2_send_text_change_cause(input_method, t->current.text_change_cause);
	/* the keyboard must never offer learned words on these screens, hints or not */
	if (locked || greeter)
		wlr_input_method_v2_send_content_type(input_method,
				t->current.content_type.hint | 0x40 /* hidden_text */
				| 0x80 /* sensitive_data */,
				8 /* password */);
	else if (t->active_features & WLR_TEXT_INPUT_V3_FEATURE_CONTENT_TYPE)
		wlr_input_method_v2_send_content_type(input_method,
				t->current.content_type.hint, t->current.content_type.purpose);
	wlr_input_method_v2_send_done(input_method);
}

static void
imactivate(TextInput *ti)
{
	active_text_input = ti;
	if (!input_method)
		return;
	wlr_input_method_v2_send_activate(input_method);
	imsendstate(ti);
}

static void
imdeactivate(TextInput *ti)
{
	if (active_text_input != ti)
		return;
	active_text_input = NULL;
	if (!input_method)
		return;
	wlr_input_method_v2_send_deactivate(input_method);
	wlr_input_method_v2_send_done(input_method);
}

static void
textinputenable(struct wl_listener *listener, void *data)
{
	TextInput *ti = wl_container_of(listener, ti, enable);

	imactivate(ti);
}

static void
textinputcommit(struct wl_listener *listener, void *data)
{
	TextInput *ti = wl_container_of(listener, ti, commit);

	if (active_text_input == ti && input_method)
		imsendstate(ti);
}

static void
textinputdisable(struct wl_listener *listener, void *data)
{
	TextInput *ti = wl_container_of(listener, ti, disable);

	imdeactivate(ti);
}

static void
textinputdestroy(struct wl_listener *listener, void *data)
{
	TextInput *ti = wl_container_of(listener, ti, destroy);

	imdeactivate(ti);
	wl_list_remove(&ti->enable.link);
	wl_list_remove(&ti->commit.link);
	wl_list_remove(&ti->disable.link);
	wl_list_remove(&ti->destroy.link);
	wl_list_remove(&ti->link);
	free(ti);
}

static void
textinputfocus(TextInput *ti, struct wlr_surface *surface)
{
	struct wlr_text_input_v3 *t = ti->input;

	/* wlroots drops a destroyed focused surface without a disable (a shell reload): deactivate anyway */
	if (t->focused_surface != surface)
		imdeactivate(ti);
	if (t->focused_surface && t->focused_surface != surface)
		wlr_text_input_v3_send_leave(t);
	if (surface && !t->focused_surface
			&& wl_resource_get_client(t->resource) == wl_resource_get_client(surface->resource))
		wlr_text_input_v3_send_enter(t, surface);
}

static void
createtextinput(struct wl_listener *listener, void *data)
{
	struct wlr_text_input_v3 *input = data;
	TextInput *ti;

	if (input->seat != seat)
		return;
	ti = ecalloc(1, sizeof(*ti));
	ti->input = input;
	LISTEN(&input->events.enable, &ti->enable, textinputenable);
	LISTEN(&input->events.commit, &ti->commit, textinputcommit);
	LISTEN(&input->events.disable, &ti->disable, textinputdisable);
	LISTEN(&input->events.destroy, &ti->destroy, textinputdestroy);
	wl_list_insert(&text_inputs, &ti->link);
	textinputfocus(ti, seat->keyboard_state.focused_surface);
}

static void
keyboardfocuschange(struct wl_listener *listener, void *data)
{
	struct wlr_seat_keyboard_focus_change_event *event = data;
	TextInput *ti;

	wl_list_for_each(ti, &text_inputs, link)
		textinputfocus(ti, event->new_surface);
}

static void
inputmethodcommit(struct wl_listener *listener, void *data)
{
	struct wlr_input_method_v2 *im = input_method;
	struct wlr_text_input_v3 *t;

	if (!active_text_input)
		return;
	t = active_text_input->input;
	if (im->current.preedit.text)
		wlr_text_input_v3_send_preedit_string(t, im->current.preedit.text,
				im->current.preedit.cursor_begin, im->current.preedit.cursor_end);
	if (im->current.delete.before_length || im->current.delete.after_length)
		wlr_text_input_v3_send_delete_surrounding_text(t,
				im->current.delete.before_length, im->current.delete.after_length);
	if (im->current.commit_text)
		wlr_text_input_v3_send_commit_string(t, im->current.commit_text);
	wlr_text_input_v3_send_done(t);
}

static void
inputmethoddestroy(struct wl_listener *listener, void *data)
{
	wl_list_remove(&input_method_commit.link);
	wl_list_remove(&input_method_destroy.link);
	input_method = NULL;
}

static void
createinputmethod(struct wl_listener *listener, void *data)
{
	struct wlr_input_method_v2 *im = data;

	if (input_method || im->seat != seat) {
		wlr_input_method_v2_send_unavailable(im);
		return;
	}
	input_method = im;
	LISTEN(&im->events.commit, &input_method_commit, inputmethodcommit);
	LISTEN(&im->events.destroy, &input_method_destroy, inputmethoddestroy);
	if (active_text_input)
		imactivate(active_text_input);
}

/* --- dwl-ipc-unstable-v2: status/tag info for bars (mmsg, waybar) --- */
static void
ipcoutputdestroy(struct wl_resource *resource)
{
	IpcOutput *io = wl_resource_get_user_data(resource);
	if (io) {
		wl_list_remove(&io->link);
		free(io);
	}
}

static void
ipcrelease(struct wl_client *client, struct wl_resource *resource)
{
	wl_resource_destroy(resource);
}

static void
ipcsettags(struct wl_client *client, struct wl_resource *resource,
		uint32_t tagmask, uint32_t toggle_tagset)
{
	IpcOutput *io = wl_resource_get_user_data(resource);
	Arg a;
	int i;
	if (!io || !io->mon || !tagmask)
		return;
	for (i = 0; i < NUMWS && !(tagmask & (1u << i)); i++);
	if (i >= NUMWS)
		return;
	selmon = io->mon;
	a.ui = (uint32_t)i;
	if (overview_active)
		overviewnavigate(a.ui, (a.ui + NUMWS - selmon->ws) % NUMWS <= NUMWS / 2 ? 1 : -1);
	else
		viewws(&a);
}

static void
ipcsetclienttags(struct wl_client *client, struct wl_resource *resource,
		uint32_t and_tags, uint32_t xor_tags)
{
	IpcOutput *io = wl_resource_get_user_data(resource);
	Client *sel;
	uint32_t newtags;
	Arg a;
	int i;
	if (!io || !io->mon)
		return;
	selmon = io->mon;
	if (!(sel = focustop(selmon)))
		return;
	newtags = ((1u << sel->ws) & and_tags) ^ xor_tags;
	if (!newtags)
		return;
	for (i = 0; i < NUMWS && !(newtags & (1u << i)); i++);
	if (i >= NUMWS)
		return;
	a.ui = (uint32_t)i;
	movetows(&a);
}

static void
ipcsetlayout(struct wl_client *client, struct wl_resource *resource, uint32_t index)
{
	IpcOutput *io = wl_resource_get_user_data(resource);

	if (io && io->mon && index < LtLast)
		setlayout(io->mon, index);
}

static void
ipcquit(struct wl_client *client, struct wl_resource *resource)
{
	pid_t pid = 0;
	wl_client_get_credentials(client, &pid, NULL, NULL);
	wlr_log(WLR_ERROR, "exiting: ipc quit from client pid %d", pid);
	quit(NULL);
}

static void
ipcdispatch(struct wl_client *client, struct wl_resource *resource,
		const char *dispatch, const char *arg1, const char *arg2,
		const char *arg3, const char *arg4, const char *arg5)
{
	Client *c;
	Monitor *m;
	LayerSurface *l;
	enum wl_output_transform t;

	/* the sensor keeps reporting behind the lock, so the phone turns the moment it opens */
	if (!strcmp(dispatch, "orientation")) {
		rotorientation(arg1);
		return;
	}
	if (locked || greeter)
		return;
	if (!strcmp(dispatch, "rotate")) {
		if (parsetransform(arg1, &t) && t <= WL_OUTPUT_TRANSFORM_270) {
			rot_pick = t;
			rotsoon(1);
		}
	} else if (!strcmp(dispatch, "closeall")) {
		closeall();
	} else if (!strcmp(dispatch, "icondrag")) {
		icondragstart(arg1, arg2);
	} else if (!strcmp(dispatch, "openfrom")) {
		open_from_at = animations ? now_ms() : 0;
	} else if (!strcmp(dispatch, "menuclose")) {
		wl_list_for_each(m, &mons, link)
			wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link)
				if (l->blur && !strcmp(l->layer_surface->namespace, "phone-menu")) {
					l->blurfade = 1.0f;
					animkick(m);
				}
	} else if (!strcmp(dispatch, "animations")) {
		animations = !!strcmp(arg1, "off");
	} else if (!strcmp(dispatch, "homerotate")) {
		home_upright = !strcmp(arg1, "off");
		rotsoon(1);
	} else if (!strcmp(dispatch, "overviewmode")) {
		overview_grid = !strcmp(arg1, "grid");
		grid_ws = -1;
		if (selmon && GRIDLT(selmon))
			gridreveal(selmon);
		overviewrelayout();
	} else if (!strcmp(dispatch, "raise")) {
		/* fstack is most recently used first */
		wl_list_for_each(c, &fstack, flink) {
			if (!client_is_unmanaged(c) && c->mon && !strcmp(client_get_appid(c), arg1)) {
				clientraise(c);
				return;
			}
		}
	}
}

static const struct zdwl_ipc_output_v2_interface ipc_output_impl = {
	.release = ipcrelease,
	.set_tags = ipcsettags,
	.set_client_tags = ipcsetclienttags,
	.set_layout = ipcsetlayout,
	.quit = ipcquit,
	.dispatch = ipcdispatch,
};

void
ipcstatus(IpcOutput *io)
{
	Monitor *m = io->mon;
	Client *c, *sel;
	uint32_t wscnt[NUMWS] = {0};
	const char *title, *appid;
	int i, version;

	if (!m)
		return;
	version = wl_resource_get_version(io->resource);
	sel = focustop(m);
	wl_list_for_each(c, &clients, link) {
		if (c->mon == m && c->ws < NUMWS)
			wscnt[c->ws]++;
	}

	zdwl_ipc_output_v2_send_active(io->resource, m == selmon);
	for (i = 0; i < NUMWS; i++) {
		zdwl_ipc_output_v2_send_tag(io->resource, (uint32_t)i,
				(unsigned int)i == m->ws ? ZDWL_IPC_OUTPUT_V2_TAG_STATE_ACTIVE
						: ZDWL_IPC_OUTPUT_V2_TAG_STATE_NONE,
				wscnt[i], sel && sel->ws == (unsigned int)i);
	}
	zdwl_ipc_output_v2_send_layout(io->resource, m->lt);
	title = sel ? client_get_title(sel) : NULL;
	appid = sel ? client_get_appid(sel) : NULL;
	zdwl_ipc_output_v2_send_title(io->resource, title ? title : "");
	if (version >= ZDWL_IPC_OUTPUT_V2_APPID_SINCE_VERSION)
		zdwl_ipc_output_v2_send_appid(io->resource, appid ? appid : "");
	if (version >= ZDWL_IPC_OUTPUT_V2_LAYOUT_SYMBOL_SINCE_VERSION)
		zdwl_ipc_output_v2_send_layout_symbol(io->resource,
				m->lt == LtScroll ? "scroll" : m->lt == LtDrift ? "drift" : "bsp");
	if (version >= ZDWL_IPC_OUTPUT_V2_FULLSCREEN_SINCE_VERSION)
		zdwl_ipc_output_v2_send_fullscreen(io->resource,
				sel && (sel->isfullscreen || sel->isfakefull));
	if (version >= ZDWL_IPC_OUTPUT_V2_FLOATING_SINCE_VERSION)
		zdwl_ipc_output_v2_send_floating(io->resource, sel && sel->isfloating);
	zdwl_ipc_output_v2_send_frame(io->resource);
}

/* The same picture the dwl-ipc bars get, as a file any shell can watch:
 * one line per output, "name active workspace count,count,... layout".
 * Workspaces and counts are 1-based on the wire and 0-based here. */
/* pid and app id of each mapped window, for the panel's list of active apps */
static void
savewindowstate(void)
{
	char path[600], dir[512];
	Client *c;
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	mkdir(dir, 0700);
	snprintf(path, sizeof path, "%s/windows", dir);
	/* in place, a file watcher keeps following the inode */
	if (!(f = fopen(path, "w")))
		return;
	wl_list_for_each(c, &clients, link) {
		const char *id;
		pid_t pid;

		if (client_is_unmanaged(c) || c->type != XDGShell)
			continue;
		id = c->surface.xdg->toplevel->app_id;
		wl_client_get_credentials(c->surface.xdg->client->client, &pid, NULL, NULL);
		fprintf(f, "%d\t", pid);
		for (; id && *id; id++)
			if (*id != '\t' && *id != '\n')
				fputc(*id, f);
		fputc('\n', f);
	}
	fclose(f);
}

static void
saveworkspacestate(void)
{
	char path[600], dir[512];
	Monitor *m;
	Client *c;
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	mkdir(dir, 0700);
	snprintf(path, sizeof path, "%s/workspaces", dir);
	/* written in place, like the overview file: a rename would swap the
	 * inode out from under a file watcher and it would stop noticing */
	if (!(f = fopen(path, "w")))
		return;
	wl_list_for_each(m, &mons, link) {
		uint32_t wscnt[NUMWS] = {0};
		int i;
		if (!m->wlr_output->enabled || m->mirroring)
			continue;
		wl_list_for_each(c, &clients, link) {
			if (c->mon == m && c->ws < NUMWS && !client_is_unmanaged(c))
				wscnt[c->ws]++;
		}
		fprintf(f, "%s %d %u ", m->wlr_output->name, m == selmon, m->ws);
		for (i = 0; i < NUMWS; i++)
			fprintf(f, "%s%u", i ? "," : "", wscnt[i]);
		fprintf(f, " %s ", layoutname(m->lt));
		/* the app on top of each workspace, for the name above its card */
		for (i = 0; i < NUMWS; i++) {
			const char *id = NULL;

			wl_list_for_each(c, &fstack, flink) {
				if (c->mon == m && c->ws == (unsigned int)i && !client_is_unmanaged(c)) {
					id = client_get_appid(c);
					break;
				}
			}
			fprintf(f, "%s", i ? "," : "");
			for (; id && *id; id++)
				if (!isspace((unsigned char)*id) && *id != ',')
					fputc(*id, f);
		}
		fputc('\n', f);
	}
	fclose(f);
}

#ifdef HYPR
static void
hyprsyncidle(void *data)
{
	hypr_idle = NULL;
	hyprsync();
}
#endif

void
ipcnotifyall(void)
{
	IpcOutput *io;
	wl_list_for_each(io, &ipc_outputs, link)
		ipcstatus(io);
	saveworkspacestate();
#ifdef HYPR
	/* Hyprland events go out once per loop iteration */
	if (!hypr_idle)
		hypr_idle = wl_event_loop_add_idle(wl_display_get_event_loop(dpy),
				hyprsyncidle, NULL);
#endif
}

static void
ipcgetoutput(struct wl_client *client, struct wl_resource *resource,
		uint32_t id, struct wl_resource *output)
{
	struct wlr_output *wlr_output = wlr_output_from_resource(output);
	struct wl_resource *res;
	IpcOutput *io;

	res = wl_resource_create(client, &zdwl_ipc_output_v2_interface,
			wl_resource_get_version(resource), id);
	if (!res) {
		wl_client_post_no_memory(client);
		return;
	}
	io = ecalloc(1, sizeof(*io));
	io->resource = res;
	io->mon = wlr_output ? wlr_output->data : NULL;
	wl_resource_set_implementation(res, &ipc_output_impl, io, ipcoutputdestroy);
	wl_list_insert(&ipc_outputs, &io->link);
	ipcstatus(io);
}

static const struct zdwl_ipc_manager_v2_interface ipc_manager_impl = {
	.release = ipcrelease,
	.get_output = ipcgetoutput,
};

void
ipcmgrbind(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
	struct wl_resource *res = wl_resource_create(client,
			&zdwl_ipc_manager_v2_interface, (int)version, id);
	if (!res) {
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_implementation(res, &ipc_manager_impl, NULL, NULL);
	zdwl_ipc_manager_v2_send_tags(res, NUMWS);
	zdwl_ipc_manager_v2_send_layout(res, "bsp");
	zdwl_ipc_manager_v2_send_layout(res, "scroll");
	zdwl_ipc_manager_v2_send_layout(res, "drift");
}
/* --- end dwl-ipc --- */

/* the corners a box keeps once it is cut down to vis: a cut side goes square */
static struct fx_corner_radii
cutradii(struct fx_corner_radii r, const struct wlr_box *full,
		const struct wlr_box *vis)
{
	int l = vis->x > full->x, t = vis->y > full->y;
	int rt = vis->x + vis->width < full->x + full->width;
	int b = vis->y + vis->height < full->y + full->height;

	return corner_radii_new(l || t ? 0 : r.top_left, rt || t ? 0 : r.top_right,
			rt || b ? 0 : r.bottom_right, l || b ? 0 : r.bottom_left);
}

/* a rounded rect of the overview, cut to the monitor it belongs to */
static struct wlr_scene_rect *
overviewrect(struct wlr_scene_tree *tree, struct wlr_box box, int radius,
		const float color[static 4], const struct wlr_box *clip)
{
	struct wlr_box vis = box;
	struct wlr_scene_rect *rect;

	if (!boxclip(&vis, clip))
		return NULL;
	rect = wlr_scene_rect_create(tree, vis.width, vis.height, color);
	wlr_scene_rect_set_corner_radii(rect,
			cutradii(corner_radii_all(radius), &box, &vis));
	wlr_scene_node_set_position(&rect->node, vis.x, vis.y);
	return rect;
}

/* The overview shows the windows themselves, not a snapshot: whenever one
 * of them paints, its card is rebuilt on the next frame. */
static void
overviewtouch(Client *c)
{
	if (!overview_visible || !c || !c->mon)
		return;
	overview_dirty = 1;
	wlr_output_schedule_frame(c->mon->wlr_output);
}

static LayerSurface *
cardlabels(Monitor *m)
{
	LayerSurface *l;

	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM], link)
		if (l->mapped && !strcmp(l->layer_surface->namespace, LABELS_NAMESPACE))
			return l;
	return NULL;
}

static void
overviewframedone(struct wlr_surface *surface, int sx, int sy, void *data)
{
	wlr_surface_send_frame_done(surface, data);
}

/* The tiling layers are switched off while the overview is up, and wlroots
 * only sends frame callbacks to what it draws, so the windows would stop
 * painting: a video freezes, a terminal stops scrolling.  Tell them a frame
 * went by ourselves. */
static void
overviewframes(Monitor *m, struct timespec *now)
{
	LayerSurface *l;
	Client *c;

	/* a hidden window with a resize pending (turned) draws its new size for the cards and the slide */
	wl_list_for_each(c, &clients, link) {
		if (c->mon == m && client_surface(c)->mapped
				&& (VISIBLEON(c, m) ? overview_visible : c->resize != 0))
			wlr_surface_for_each_surface(client_surface(c),
					overviewframedone, now);
	}
	if (overview_visible && (l = cardlabels(m)))
		wlr_surface_for_each_surface(l->layer_surface->surface, overviewframedone, now);
}

static void
overviewclear(void)
{
	struct wlr_scene_node *node, *tmp;
	wl_list_for_each_safe(node, tmp, &overview_dim_scene->children, link)
		wlr_scene_node_destroy(node);
	wl_list_for_each_safe(node, tmp, &overview_panels_scene->children, link)
		wlr_scene_node_destroy(node);
}

static void
overviewdragclear(void)
{
	struct wlr_scene_node *node, *tmp;

	wl_list_for_each_safe(node, tmp, &overview_drag_scene->children, link)
		wlr_scene_node_destroy(node);
	wl_list_for_each_safe(node, tmp, &overview_land_scene->children, link)
		wlr_scene_node_destroy(node);
	wlr_scene_node_set_position(&overview_drag_scene->node, 0, 0);
}

void
overviewclone(struct wlr_scene_buffer *buffer, int sx, int sy, void *data)
{
	OverviewClone *oc = data;
	struct wlr_scene_buffer *clone;
	struct wlr_scene_buffer_set_buffer_options options;
	struct fx_corner_radii corners;
	struct wlr_box dst, vis;
	float scale;
	int width, height, dstw, dsth;

	if (!buffer->buffer)
		return;
	width = buffer->dst_width > 0 ? buffer->dst_width
			: buffer->src_box.width > 0 ? (int)round(buffer->src_box.width)
			: buffer->buffer->width;
	height = buffer->dst_height > 0 ? buffer->dst_height
			: buffer->src_box.height > 0 ? (int)round(buffer->src_box.height)
			: buffer->buffer->height;
	if (width <= 0 || height <= 0)
		return;

	options = (struct wlr_scene_buffer_set_buffer_options){
		.wait_timeline = buffer->WLR_PRIVATE.wait_timeline,
		.wait_point = buffer->WLR_PRIVATE.wait_point,
	};
	clone = wlr_scene_buffer_create(oc->tree, NULL);
	wlr_scene_buffer_set_buffer_with_options(clone, buffer->buffer, &options);
	if (buffer->src_box.width > 0 && buffer->src_box.height > 0)
		wlr_scene_buffer_set_source_box(clone, &buffer->src_box);
	wlr_scene_buffer_set_transform(clone, buffer->transform);
	dstw = MAX(1, (int)roundf(width * oc->scalex));
	dsth = MAX(1, (int)roundf(height * oc->scaley));
	wlr_scene_buffer_set_dest_size(clone, dstw, dsth);
	wlr_scene_buffer_set_opacity(clone, buffer->opacity * oc->opacity);
	wlr_scene_buffer_set_filter_mode(clone, WLR_SCALE_FILTER_BILINEAR);
	scale = MIN(oc->scalex, oc->scaley);
	corners = oc->radius >= 0 ? corner_radii_all(oc->radius)
			: corner_radii_new((int)roundf(buffer->corners.top_left * scale),
				(int)roundf(buffer->corners.top_right * scale),
				(int)roundf(buffer->corners.bottom_right * scale),
				(int)roundf(buffer->corners.bottom_left * scale));
	dst = (struct wlr_box){
		oc->x + (int)roundf((sx - oc->srcx) * oc->scalex),
		oc->y + (int)roundf((sy - oc->srcy) * oc->scaley), dstw, dsth};
	/* only what reaches a corner of the card is rounded: a subsurface stays square */
	if (oc->radius >= 0) {
		int l = dst.x <= oc->card.x + 2, t = dst.y <= oc->card.y + 2;
		int r = dst.x + dst.width >= oc->card.x + oc->card.width - 2;
		int b = dst.y + dst.height >= oc->card.y + oc->card.height - 2;
		corners = corner_radii_new(l && t ? oc->radius : 0, r && t ? oc->radius : 0,
				r && b ? oc->radius : 0, l && b ? oc->radius : 0);
	}
	vis = dst;
	if (!boxclip(&vis, &oc->clip)) {
		wlr_scene_node_destroy(&clone->node);
		return;
	}
	if (vis.x != dst.x || vis.y != dst.y || vis.width != dst.width
			|| vis.height != dst.height) {
		/* a panel sliding in from past the edge: draw the part of the
		 * buffer that is on this monitor, and only that */
		struct wlr_fbox src = buffer->src_box;
		double fx, fy;
		if (src.width <= 0 || src.height <= 0)
			src = (struct wlr_fbox){0, 0, buffer->buffer->width,
					buffer->buffer->height};
		fx = src.width / dst.width;
		fy = src.height / dst.height;
		src.x += (vis.x - dst.x) * fx;
		src.y += (vis.y - dst.y) * fy;
		src.width = vis.width * fx;
		src.height = vis.height * fy;
		wlr_scene_buffer_set_source_box(clone, &src);
		corners = cutradii(corners, &dst, &vis);
		dstw = vis.width;
		dsth = vis.height;
		wlr_scene_buffer_set_dest_size(clone, dstw, dsth);
	}
	wlr_scene_buffer_set_corner_radii(clone, corners);
	wlr_scene_buffer_set_opaque_region(clone, &buffer->opaque_region);
	wlr_scene_node_set_position(&clone->node, vis.x, vis.y);
	cloneblur(buffer, clone, oc->tree, dstw, dsth, corners);
	oc->count++;
}

static struct wlr_box
overviewwindowbox(Monitor *m, Client *c, const struct wlr_box *panel)
{
	struct wlr_box geo = (c->isfullscreen || c->isfakefull) ? c->prev : c->geom;
	/* the card is the whole screen in small, bars included */
	float scalex = (float)panel->width / m->m.width;
	float scaley = (float)panel->height / m->m.height;

	/* a window still sliding into place is drawn where it is right now,
	 * so the card moves the way the window does */
	if (c->anim.active && !c->anim.workspace && !c->anim.hide && !c->anim.zoom
			&& c->scene && !c->isfullscreen && !c->isfakefull) {
		geo.x = c->scene->node.x;
		geo.y = c->scene->node.y;
	}

	if (DRIFTLT(m) && c->oncanvas && !c->isfloating
			&& !c->isfullscreen && !c->isfakefull) {
		/* the card shows the whole canvas, not just the viewport */
		struct wlr_box b;
		float scale;

		driftbounds(m, c->ws, 1, &b);
		scale = MIN((float)panel->width / MAX(1, b.width),
				(float)panel->height / MAX(1, b.height));
		return (struct wlr_box){
			.x = panel->x + (panel->width - (int)roundf(b.width * scale)) / 2
					+ (int)roundf((c->canvas.x - b.x) * scale),
			.y = panel->y + (panel->height - (int)roundf(b.height * scale)) / 2
					+ (int)roundf((c->canvas.y - b.y) * scale),
			.width = MAX(4, (int)roundf(c->canvas.width * scale)),
			.height = MAX(4, (int)roundf(c->canvas.height * scale)),
		};
	}
	if (geo.width <= 0 || geo.height <= 0)
		geo = m->w;
	return (struct wlr_box){
		.x = panel->x + (int)roundf((geo.x - m->m.x) * scalex)
				+ (c == card_close.c && GRIDLT(m) ? (int)roundf(card_close.dy) : 0),
		.y = panel->y + (int)roundf((geo.y - m->m.y) * scaley)
				+ (c == card_close.c && !GRIDLT(m) ? (int)roundf(card_close.dy) : 0),
		.width = MAX(4, (int)roundf(geo.width * scalex)),
		.height = MAX(4, (int)roundf(geo.height * scaley)),
	};
}

/* rounded as a card, square again as it grows to full screen */
static int
cardradius(float scale)
{
	return (int)roundf(32.0f * scale * MAX(0.0f, MIN(1.0f, (1.0f - scale) * 3.2f)));
}

static void
overviewwindowdraw(struct wlr_scene_tree *tree, Client *c,
		const struct wlr_box *box, float opacity, int focused,
		const struct wlr_box *clip, const struct wlr_box *card)
{
	float windowcolor[] = {0.055f * opacity, 0.055f * opacity,
		0.065f * opacity, 0.96f * opacity};
	struct wlr_scene_tree *content;
	struct wlr_scene_rect *back;
	OverviewClone oc;
	float scale;
	int enabled, radius;

	if (opacity <= 0.0f)
		return;
	scale = MIN((float)box->width / MAX(1, c->geom.width),
			(float)box->height / MAX(1, c->geom.height));
	radius = cardradius(scale);
	if (focused && !decorhidden && borderpx > 0) {
		/* focus ring behind the clone, like the live focus border */
		const float *fc = focuscolorfor();
		float bcolor[] = {fc[0] * opacity, fc[1] * opacity,
			fc[2] * opacity, fc[3] * opacity};
		int fbw = MAX(2, (int)roundf(borderpx * scale) + 1);
		overviewrect(tree, (struct wlr_box){box->x - fbw, box->y - fbw,
				box->width + 2 * fbw, box->height + 2 * fbw},
				radius + fbw, bcolor, clip);
	}
	content = wlr_scene_tree_create(tree);
	back = overviewrect(content, *box, radius, windowcolor, clip);

	if (!c->scene)
		return;
	oc = (OverviewClone){
		.tree = content,
		.scalex = (float)box->width / MAX(1, c->geom.width),
		.scaley = (float)box->height / MAX(1, c->geom.height),
		.opacity = opacity,
		.srcx = c->scene->node.x, .srcy = c->scene->node.y,
		.x = box->x, .y = box->y,
		.radius = radius,
		.clip = *clip,
		/* only corners on the card's own corners round: under the title bar it stays square */
		.card = *card,
	};
	enabled = c->scene->node.enabled;
	if (!enabled)
		wlr_scene_node_set_enabled(&c->scene->node, 1);
	/* a window cut by the monitor edge is cloned whole; the crop above is
	 * only for what is drawn on screen */
	if (c->scene_surface && (c->offscreen || !c->scene_surface->node.enabled))
		wlr_scene_node_set_enabled(&c->scene_surface->node, 1);
	wlr_scene_node_for_each_buffer(&c->scene->node, overviewclone, &oc);
	if (c->scene_surface && c->offscreen)
		wlr_scene_node_set_enabled(&c->scene_surface->node, 0);
	else if (c->scene_surface && !enabled)
		clientclip(c);
	if (!enabled)
		wlr_scene_node_set_enabled(&c->scene->node, 0);
	if (oc.count && back)
		wlr_scene_node_destroy(&back->node);
}

static void
overviewwindow(struct wlr_scene_tree *tree, Monitor *m, Client *c,
		const struct wlr_box *panel, float opacity, int focused, const struct wlr_box *clip)
{
	struct wlr_box box = overviewwindowbox(m, c, panel);

	if (c == card_close.c)
		opacity *= MAX(0.0f, 1.0f - fabsf(card_close.dy)
				/ (GRIDLT(m) ? (grid_card ? grid_card->width : panel->width) : panel->height));
	overviewwindowdraw(tree, c, &box, opacity, focused, clip, panel);
}

typedef struct {
	struct wlr_scene_tree *tree;
	int surfw, ws, cardw, x, y;
	float opacity;
} CardLabel;

/* shortcut: not cropped to the monitor, only one output on a phone, crop like overviewclone for more */
static void
overviewlabel(struct wlr_scene_buffer *buffer, int sx, int sy, void *data)
{
	CardLabel *cl = data;
	struct wlr_scene_buffer *clone;
	struct wlr_fbox src = buffer->src_box;
	int w = MIN(cl->surfw, cl->cardw);

	if (!buffer->buffer || cl->surfw <= 0)
		return;
	if (src.width <= 0 || src.height <= 0)
		src = (struct wlr_fbox){0, 0, buffer->buffer->width, buffer->buffer->height};
	/* nine rows of 28, then the carried icon: see CardLabels.qml */
	if (cl->ws < 0) {
		src.y += src.height * 28 * NUMWS / LABELS_H;
		src.height *= (double)ICON_GHOST / LABELS_H;
		src.width *= (double)ICON_GHOST / cl->surfw;
		w = ICON_GHOST;
	} else {
		src.height *= 28.0 / LABELS_H;
		src.y += cl->ws * src.height;
		src.width *= (double)w / cl->surfw;
	}
	clone = wlr_scene_buffer_create(cl->tree, buffer->buffer);
	wlr_scene_buffer_set_source_box(clone, &src);
	wlr_scene_buffer_set_dest_size(clone, w, cl->ws < 0 ? ICON_GHOST : LABEL_H);
	wlr_scene_buffer_set_opacity(clone, cl->opacity);
	wlr_scene_node_set_position(&clone->node, cl->x, cl->y);
}

static void
overviewpanel(Monitor *m, unsigned int ws, const struct wlr_box *box, float opacity)
{
	/* black at the gesture's start like the screen under it, so the card does not flash in */
	float shade = 0.085f * m->overview_dim;
	/* a leaving card drops its own copy of the wallpaper first, or it shows through the fading window */
	float under = (int)ws == flick_ws ? MAX(0.0f, 1.0f - (1.0f - opacity) * 4.0f) : opacity;
	float panelcolor[] = {shade * under, shade * under,
		shade * under, under};
	struct wlr_scene_tree *tree;
	LayerSurface *l;
	Client *c, *focus = NULL;
	OverviewClone oc;
	struct wlr_box clip = grid_clip ? *grid_clip : m->m, card = grid_card ? *grid_card : *box;

	if (opacity <= 0.0f)
		return;
	/* the focus ring marks the window the strip is parked on, which only
	 * means something in the scroll layout */
	if (ws == m->ws && SCROLLLT(m))
		focus = overview_focus_client && overview_focus_client->mon == m
				&& overview_focus_client->ws == ws
				? overview_focus_client : wsfocusedany(m, ws);
	tree = wlr_scene_tree_create(overview_panels_scene);
	oc = (OverviewClone){
		.tree = tree,
		.scalex = (float)box->width / m->m.width,
		.scaley = (float)box->height / m->m.height,
		.opacity = under,
		.srcx = m->m.x, .srcy = m->m.y,
		.x = box->x, .y = box->y,
		.radius = cardradius((float)box->width / m->m.width),
		.clip = clip,
		.card = *box,
	};

	if (under > 0.0f)
		overviewrect(tree, *box, oc.radius, panelcolor, &clip);

	/* under the windows too, so a translucent one shows it; the label strip stays dark */
	if (wsoccupied(m, ws)) {
		int top = m->m.y + m->m.height;

		wl_list_for_each(c, &clients, link)
			if (c->mon == m && c->ws == ws)
				top = MIN(top, c->geom.y);
		oc.clip.y = MAX(clip.y, box->y + (int)floorf((top - m->m.y) * oc.scaley));
		oc.clip.height = clip.y + clip.height - oc.clip.y;
	}
	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND], link) {
		if (l->mapped && under > 0.0f)
			wlr_scene_node_for_each_buffer(&l->scene->node, overviewclone, &oc);
	}
	oc.clip = clip;

	wl_list_for_each_reverse(c, &clients, link) {
		if (c->mon == m && c->ws == ws
				&& (!overview_dragging || c != overview_drag_client))
			overviewwindow(tree, m, c, box, opacity, c == focus, &clip);
	}
	/* the clock leaves with the gesture and is on no finished card */
	if (ws == m->ws && !wsoccupied(m, ws) && m->overview_dim < 1.0f) {
		wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM], link) {
			if (!l->mapped || strcmp(l->layer_surface->namespace, HOME_NAMESPACE))
				continue;
			oc.opacity = opacity * (1.0f - m->overview_dim);
			wlr_scene_node_set_enabled(&l->scene->node, 1);
			wlr_scene_node_for_each_buffer(&l->scene->node, overviewclone, &oc);
			wlr_scene_node_set_enabled(&l->scene->node, 0);
		}
	}
	/* a grid card scrolled under the bar keeps no label: it would sit on the bar */
	if ((l = cardlabels(m)) && wsoccupied(m, ws) && card.y >= clip.y) {
		CardLabel cl = {tree, (int)l->layer_surface->current.actual_width, (int)ws,
			card.width, card.x + (card.width - (int)l->layer_surface->current.actual_width) / 2,
			card.y + 1, opacity * m->overview_dim};

		wlr_scene_node_set_enabled(&l->scene->node, 1);
		wlr_scene_node_for_each_buffer(&l->scene->node, overviewlabel, &cl);
		wlr_scene_node_set_enabled(&l->scene->node, 0);
	}
}

static int
overviewvalid(Monitor *m)
{
	return m && m->wlr_output->enabled && !m->mirroring
			&& m->m.width > 0 && m->m.height > 0
			&& m->w.width > 0 && m->w.height > 0;
}

/* where cards go: under the bar, over the tray or beside one standing at a side */
static struct wlr_box
overviewarea(Monitor *m)
{
	LayerSurface *l;
	int top, bottom, trayh = 0, trayw = 0, trayleft = 0;
	int wide = !SCROLLLT(m) && m->m.width > m->m.height;

	if ((l = phonetray(m))) {
		/* a tray standing at a side takes width, one along the bottom height */
		if (wide && trayside(m, l)) {
			trayw = (int)l->layer_surface->current.actual_width;
			trayleft = (l->layer_surface->current.anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT)
					&& !(l->layer_surface->current.anchor & ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
		} else {
			trayh = (int)l->layer_surface->current.actual_height;
		}
	}
	/* between the bar and the tray: never from the keyboard's share of the screen */
	top = m->m.y + (SCROLLLT(m) ? 0 : CARD_TOP);
	if (!SCROLLLT(m))
		wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_TOP], link)
			if (l->mapped && !strcmp(l->layer_surface->namespace, STATUSBAR_NAMESPACE))
				top += (int)l->layer_surface->current.actual_height;
	bottom = m->m.y + m->m.height - BAR_ZONE - trayh;
	return (struct wlr_box){m->m.x + (trayleft ? trayw : 0), top, m->m.width - trayw, bottom - top};
}

/* the cards with the row shifted by off; a card shrinks to SIDE_CARD as it leaves the centre */
static void
overviewlayout(Monitor *m, struct wlr_box boxes[3], double off)
{
	struct wlr_box *center = &boxes[1], area = overviewarea(m);
	float scale;
	int gap, margin, width, height, i;
	int top = area.y, bottom = area.y + area.height, trayw = m->m.width - area.width, trayleft = area.x > m->m.x;
	/* turned: wide cards, the side ones half off the edges */
	int wide = !SCROLLLT(m) && m->m.width > m->m.height;

	margin = MAX(24, MIN(m->m.width, m->m.height) / 18);
	margin = MIN(64, margin);
	gap = 8;
	if (SCROLLLT(m)) {
		/* niri stacks workspaces vertically: prev above, next below */
		scale = MIN((m->m.width - 2.0f * margin) / m->m.width,
				((bottom - top) * 0.72f) / m->m.height);
	} else if (wide) {
		scale = MIN((bottom - top) / (float)m->m.height,
				(m->m.width - trayw - 2.0f * (margin + gap)) / (m->m.width * (1.0f + SIDE_CARD)));
	} else {
		scale = (bottom - top) / (float)m->m.height;
	}
	scale = MAX(0.20f, scale);
	width = MAX(1, (int)roundf(m->m.width * scale));
	height = MAX(1, (int)roundf(m->m.height * scale));
	*center = (struct wlr_box){
		.x = m->m.x + (trayleft ? trayw : 0) + (m->m.width - trayw - width) / 2,
		.y = SCROLLLT(m) || wide ? top + (bottom - top - height) / 2 : top,
		.width = width, .height = height,
	};
	if (SCROLLLT(m)) {
		boxes[0] = boxes[2] = *center;
		boxes[0].y = center->y - height - gap;
		boxes[2].y = center->y + height + gap;
		return;
	}
	{
		double span = (width + width * SIDE_CARD) / 2.0 + gap, cx = center->x + width / 2.0;
		struct wlr_box c = *center;

		for (i = 0; i < 3; i++) {
			double d = (i - 1) * span + off;
			float s = 1.0f - (1.0f - SIDE_CARD) * (float)MIN(1.0, fabs(d) / span);
			int w = MAX(1, (int)roundf(width * s)), h = MAX(1, (int)roundf(height * s));

			boxes[i] = (struct wlr_box){ .x = (int)lround(cx + d - w / 2.0),
					.y = c.y + (c.height - h) / 2, .width = w, .height = h };
		}
	}
}

/* a workspace holding a fullscreen_apps window gets a card as wide as both columns */
static int
gridwide(Monitor *m, unsigned int ws)
{
	Client *c;

	wl_list_for_each(c, &clients, link)
		if (c->mon == m && c->ws == ws && !client_is_unmanaged(c) && fullscreenapp(c))
			return 1;
	return 0;
}

/* the grid's cards, scrolled, width 0 for none; two rows fill the view; returns the furthest scroll */
static double
gridlayout(Monitor *m, struct wlr_box cards[NUMWS], struct wlr_box *view)
{
	struct wlr_box area = overviewarea(m);
	unsigned int ws, limit = wslimit(m);
	int cw, ch, x0, y = 0, col = 0, wide2, wideh, end;

	ch = (area.height - GRID_GAP) / 2;
	cw = (int)roundf((float)ch * m->m.width / m->m.height);
	if (2 * cw + 3 * GRID_GAP > area.width) {
		cw = (area.width - 3 * GRID_GAP) / 2;
		ch = (int)roundf((float)cw * m->m.height / m->m.width);
	}
	cw = MAX(1, cw);
	ch = MAX(1, ch);
	wide2 = 2 * cw + GRID_GAP;
	wideh = MIN(ch, (int)roundf((float)wide2 * MIN(m->m.width, m->m.height) / MAX(m->m.width, m->m.height)));
	x0 = area.x + (area.width - wide2) / 2;
	for (ws = 0; ws < NUMWS; ws++) {
		cards[ws] = (struct wlr_box){0};
		/* the free one only while something is carried, to drop it there */
		if (ws > limit || (!wsoccupied(m, ws) && !(ws == limit && overview_dragging)))
			continue;
		if (gridwide(m, ws)) {
			if (col)
				y += ch + GRID_GAP;
			cards[ws] = (struct wlr_box){x0, area.y + y, wide2, wideh};
			y += wideh + GRID_GAP;
			col = 0;
			continue;
		}
		cards[ws] = (struct wlr_box){x0 + col * (cw + GRID_GAP), area.y + y, cw, ch};
		if (++col == 2) {
			col = 0;
			y += ch + GRID_GAP;
		}
	}
	end = (col ? y + ch : y - GRID_GAP);
	for (ws = 0; ws < NUMWS; ws++)
		cards[ws].y -= (int)lround(grid_scroll);
	if (view)
		*view = area;
	return MAX(0, end - area.height);
}

/* a workspace's card in the grid, the open one wherever its animation has it; 0 when it has none */
static int
gridcard(Monitor *m, unsigned int ws, struct wlr_box *card)
{
	struct wlr_box cards[NUMWS];

	if (ws >= NUMWS)
		return 0;
	gridlayout(m, cards, NULL);
	if (cards[ws].width <= 0)
		return 0;
	*card = ws == m->ws && wsoccupied(m, ws) ? m->overview[1] : cards[ws];
	return 1;
}

/* m->overview[1] follows the open workspace's card; settle: also when nothing else moves it */
static void
gridsync(Monitor *m, int settle)
{
	struct wlr_box cards[NUMWS];

	if (!GRIDLT(m))
		return;
	if (grid_ws == (int)m->ws && !(settle && overview_active && !m->overview_animating && touch_gesture != 3))
		return;
	grid_ws = (int)m->ws;
	gridlayout(m, cards, NULL);
	if (cards[m->ws].width <= 0)
		return;
	m->overview[1] = cards[m->ws];
	/* a new current card mid-move, say after its neighbour closed: it is already in place */
	if (m->overview_animating && overview_active)
		m->overview_from[1] = m->overview_to[1] = cards[m->ws];
}

static void
gridplace(Monitor *m, double scroll)
{
	grid_scroll = scroll;
	grid_ws = -1;
	gridsync(m, 0);
}

/* past either end the grid follows the finger at a quarter */
static double
gridrubber(Monitor *m, double s)
{
	double max = gridlayout(m, (struct wlr_box[NUMWS]){0}, NULL);

	return s < 0 ? s * 0.25 : s > max ? max + (s - max) * 0.25 : s;
}

static double
gridclamp(Monitor *m, double s)
{
	return MAX(0.0, MIN(gridlayout(m, (struct wlr_box[NUMWS]){0}, NULL), s));
}

/* the view: the whole screen while the overview is on its way in or out, under the bar and over the tray once up */
static struct wlr_box
gridview(Monitor *m)
{
	struct wlr_box view;

	gridlayout(m, (struct wlr_box[NUMWS]){0}, &view);
	view.y -= CARD_TOP;
	view.height += CARD_TOP;
	return overviewboxlerp(&m->m, &view, MIN(1.0f, m->overview_dim));
}

/* the whole screen in small, scaled to cover the card, so a wide card shows its middle */
static void
gridpanel(Monitor *m, unsigned int ws, const struct wlr_box *card, float opacity)
{
	float s = MAX((float)card->width / m->m.width, (float)card->height / m->m.height);
	struct wlr_box view = gridview(m), clip = *card, box;

	if (!boxclip(&clip, &view))
		return;
	box.width = MAX(1, (int)roundf(m->m.width * s));
	box.height = MAX(1, (int)roundf(m->m.height * s));
	box.x = card->x + (card->width - box.width) / 2;
	box.y = card->y + (card->height - box.height) / 2;
	grid_clip = &clip;
	grid_card = card;
	overviewpanel(m, ws, &box, opacity);
	grid_clip = grid_card = NULL;
}

/* what is drawn for a card: the box for windows, the card for edges */
static struct wlr_box
overviewpanelcard(Monitor *m, int panel)
{
	struct wlr_box card = m->overview[panel < GRIDPANEL ? panel : 1];

	if (panel >= GRIDPANEL)
		gridcard(m, (unsigned int)(panel - GRIDPANEL), &card);
	return card;
}

static struct wlr_box
overviewpanelbox(Monitor *m, int panel)
{
	struct wlr_box card = overviewpanelcard(m, panel), box = card;
	float s = MAX((float)card.width / m->m.width, (float)card.height / m->m.height);

	if (panel < GRIDPANEL)
		return card;
	box.width = MAX(1, (int)roundf(m->m.width * s));
	box.height = MAX(1, (int)roundf(m->m.height * s));
	box.x = card.x + (card.width - box.width) / 2;
	box.y = card.y + (card.height - box.height) / 2;
	return box;
}

/* the open card from where the scroll shows it; from home the newest ones */
static void
gridreveal(Monitor *m)
{
	struct wlr_box cards[NUMWS], view;
	double max;

	grid_scroll = 0.0;
	max = gridlayout(m, cards, &view);
	if (!wsoccupied(m, m->ws) || cards[m->ws].width <= 0)
		grid_scroll = max;
	else if (cards[m->ws].y + cards[m->ws].height > view.y + view.height)
		grid_scroll = MIN(max, (double)(cards[m->ws].y + cards[m->ws].height - view.y - view.height));
}

static void
overviewtargets(Monitor *m, struct wlr_box boxes[3])
{
	struct wlr_box cards[NUMWS];

	if (!GRIDLT(m)) {
		overviewlayout(m, boxes, 0.0);
		return;
	}
	gridlayout(m, cards, NULL);
	/* from home there is no card of its own to shrink into */
	boxes[1] = wsoccupied(m, m->ws) && cards[m->ws].width > 0 ? cards[m->ws] : m->m;
	boxes[0] = boxes[2] = boxes[1];
}

static struct wlr_box
overviewboxlerp(const struct wlr_box *from, const struct wlr_box *to, float t)
{
	return (struct wlr_box){
		.x = from->x + (int)roundf((to->x - from->x) * t),
		.y = from->y + (int)roundf((to->y - from->y) * t),
		.width = MAX(1, from->width + (int)roundf((to->width - from->width) * t)),
		.height = MAX(1, from->height + (int)roundf((to->height - from->height) * t)),
	};
}

static void
overviewtransition(Monitor *m, const struct wlr_box boxes[3],
		const float opacity[3], float dim)
{
	int i;

	gridsync(m, 0);
	for (i = 0; i < 3; i++) {
		m->overview_from[i] = m->overview[i];
		m->overview_to[i] = boxes[i];
		m->overview_opacity_from[i] = m->overview_opacity[i];
		m->overview_opacity_to[i] = opacity[i];
	}
	m->overview_dim_from = m->overview_dim;
	m->overview_dim_to = dim;
	if (glide.m == m)
		glide.m = NULL;
	if (animations && animation_duration > 0) {
		m->overview_anim_t = 0.0f;
		m->overview_anim_v = 0.0f;
		m->overview_animating = 1;
		animkick(m);
	} else {
		for (i = 0; i < 3; i++) {
			m->overview[i] = boxes[i];
			m->overview_opacity[i] = opacity[i];
		}
		m->overview_dim = dim;
		m->overview_animating = 0;
	}
}

#define OVERVIEW_SETTLE_MS 340
#define OVERVIEW_SPRING 8.5f /* per settle: 0.2% of the way is left at the end */

static int
overviewadvance(Monitor *m, float dt)
{
	float e, v, dur;
	int i;

	if (!overview_visible || !m->overview_animating)
		return 0;
	if (glide.m == m)
		return glideadvance(m, dt);
	/* a critically damped spring: it starts at the finger's speed and cannot
	 * overshoot while that speed stays under the spring's own */
	dur = (float)MAX(OVERVIEW_SETTLE_MS, animation_duration * 3 / 2);
	v = MAX(0.0f, MIN(OVERVIEW_SPRING, m->overview_anim_v * dur));
	m->overview_anim_t += dt / dur;
	if (m->overview_anim_t >= 1.0f) {
		m->overview_anim_t = 1.0f;
		m->overview_animating = 0;
	}
	e = !m->overview_animating ? 1.0f : 1.0f - (1.0f + (OVERVIEW_SPRING - v)
			* m->overview_anim_t) * expf(-OVERVIEW_SPRING * m->overview_anim_t);
	if (card_close.c)
		card_close.dy = card_close.from + (card_close.to - card_close.from) * e;
	if (card_close.c && !m->overview_animating && card_close.to == 0.0f)
		card_close.c = NULL;
	for (i = 0; i < 3; i++) {
		m->overview[i] = overviewboxlerp(&m->overview_from[i],
				&m->overview_to[i], e);
		m->overview_opacity[i] = m->overview_opacity_from[i]
				+ (m->overview_opacity_to[i] - m->overview_opacity_from[i]) * e;
	}
	m->overview_dim = m->overview_dim_from
			+ (m->overview_dim_to - m->overview_dim_from) * e;
	return 1;
}

static int
overviewwatchdog(void *data)
{
	/* While the overview is up the tiling layers are switched off and only
	 * overviewfinish() turns them back on, so a closing transition that
	 * never reaches its last frame - an output that stopped sending them,
	 * a failed commit - would leave the screen without a single window on
	 * it, nothing to click and nothing to type into.  Never wait forever. */
	Monitor *m;

	if (overview_active || !overview_visible)
		return 0;
	wlr_log(WLR_ERROR, "overview close stalled; closing it by hand");
	wl_list_for_each(m, &mons, link)
		m->overview_animating = 0;
	overviewfinish();
	wl_list_for_each(m, &mons, link)
		if (m->wlr_output->enabled)
			wlr_output_schedule_frame(m->wlr_output);
	return 0;
}

static int
overviewallidle(void)
{
	Monitor *m;

	wl_list_for_each(m, &mons, link) {
		if (overviewvalid(m) && m->overview_animating)
			return 0;
	}
	return 1;
}

static void
overviewfinish(void)
{
	Client *c, *focus = NULL;
	Monitor *m;

	if (overview_active || !overview_visible || !overviewallidle())
		return;
	if (overview_watchdog)
		wl_event_source_timer_update(overview_watchdog, 0);
	overview_visible = 0;
	flick_ws = -1;
	rotsoon(1);
	wlr_scene_node_set_enabled(&overview_scene->node, 0);
	wlr_scene_node_set_enabled(&overview_dim_scene->node, 0);
	wlr_scene_node_set_enabled(&layers[LyrTile]->node, 1);
	wlr_scene_node_set_enabled(&layers[LyrFloat]->node, 1);
	wlr_scene_node_set_enabled(&layers[LyrFS]->node, 1);
	wl_list_for_each(m, &mons, link)
		arrange(m);
	if (overview_focus_client) {
		wl_list_for_each(c, &clients, link) {
			if (c == overview_focus_client && VISIBLEON(c, selmon)) {
				focus = c;
				break;
			}
		}
	}
	if (!focus)
		focus = focustop(selmon);
	overview_focus_client = NULL;
	focusclient(focus, 1);
	motionnotify(0, NULL, 0, 0, 0, 0);
}

#define BACKDROP_ZOOM 0.05f
#define BACKDROP_SHADE 0.35f
/* what the card uncovers: the wallpaper zoomed, blurred and shaded with the gesture, normal when it is gone */
static void
overviewbackdrop(Monitor *m)
{
	float dim = MIN(1.0f, m->overview_dim), zoom = 1.0f + BACKDROP_ZOOM * dim;
	float color[] = {0.0f, 0.0f, 0.0f, dim * BACKDROP_SHADE};
	struct wlr_box box;
	struct wlr_scene_tree *tree;
	struct wlr_scene_blur *blur;
	OverviewClone oc;
	LayerSurface *l;

	box.width = (int)roundf(m->m.width * zoom);
	box.height = (int)roundf(m->m.height * zoom);
	box.x = m->m.x - (box.width - m->m.width) / 2;
	box.y = m->m.y - (box.height - m->m.height) / 2;
	tree = wlr_scene_tree_create(overview_panels_scene);
	oc = (OverviewClone){
		.tree = tree,
		.scalex = (float)box.width / m->m.width,
		.scaley = (float)box.height / m->m.height,
		.opacity = 1.0f,
		.srcx = m->m.x, .srcy = m->m.y,
		.x = box.x, .y = box.y,
		.clip = m->m,
	};
	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND], link) {
		if (l->mapped)
			wlr_scene_node_for_each_buffer(&l->scene->node, overviewclone, &oc);
	}
	/* only over a copy: with no wallpaper it would blur the windows under the overview */
	if (dim > 0.0f && !wl_list_empty(&tree->children)
			&& (blur = wlr_scene_blur_create(tree, m->m.width, m->m.height))) {
		wlr_scene_node_set_position(&blur->node, m->m.x, m->m.y);
		wlr_scene_blur_set_strength(blur, dim);
		wlr_scene_blur_set_alpha(blur, dim);
	}
	/* the free workspace's own clock comes up with it, from nothing at the release */
	if (flick_ws >= 0 && m == selmon) {
		oc.opacity = flick_dim > 0.0f ? MAX(0.0f, 1.0f - dim / flick_dim) : 1.0f;
		wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM], link) {
			if (!l->mapped || strcmp(l->layer_surface->namespace, HOME_NAMESPACE))
				continue;
			wlr_scene_node_set_enabled(&l->scene->node, 1);
			wlr_scene_node_for_each_buffer(&l->scene->node, overviewclone, &oc);
			wlr_scene_node_set_enabled(&l->scene->node, 0);
		}
	}
	overviewrect(tree, m->m, 0, color, &m->m);
}

void
overviewbuild(void)
{
	Monitor *m;

	overviewclear();
	wl_list_for_each(m, &mons, link) {
		/* opaque: the home screen would show between the cards at full size */
		float dimcolor[] = {0.0f, 0.0f, 0.0f, m->overview_dim};
		struct wlr_scene_rect *dim;

		if (!overviewvalid(m))
			continue;
		dim = wlr_scene_rect_create(overview_dim_scene,
				m->m.width, m->m.height, dimcolor);
		wlr_scene_node_set_position(&dim->node, m->m.x, m->m.y);
		overviewbackdrop(m);
		if (flick_ws >= 0 && m == selmon) {
			float fade = flick_dim > 0.0f ? m->overview_dim / flick_dim : 0.0f;
			int i;

			for (i = 0; i < 2; i++)
				if (flick_side_ws[i] >= 0)
					overviewpanel(m, (unsigned int)flick_side_ws[i], &flick_side[i],
							flick_side_op[i] * fade);
			overviewpanel(m, (unsigned int)flick_ws,
					&m->overview[0], m->overview_opacity[0]);
		} else if (GRIDLT(m)) {
			struct wlr_box card;
			unsigned int ws;

			gridsync(m, 1);
			for (ws = 0; ws < NUMWS; ws++)
				if (ws != m->ws && gridcard(m, ws, &card))
					gridpanel(m, ws, &card, MIN(1.0f, m->overview_dim));
			/* on top, so it is over the others on its way in and out */
			if (gridcard(m, m->ws, &card))
				gridpanel(m, m->ws, &card, wsoccupied(m, m->ws)
						? m->overview_opacity[1] : MIN(1.0f, m->overview_dim));
		} else {
			if (wsnext(m, -1) >= 0)
				overviewpanel(m, (unsigned int)wsnext(m, -1),
						&m->overview[0], m->overview_opacity[0]);
			if (wsnext(m, 1) >= 0)
				overviewpanel(m, (unsigned int)wsnext(m, 1),
						&m->overview[2], m->overview_opacity[2]);
			overviewpanel(m, m->ws, &m->overview[1], m->overview_opacity[1]);
		}
		traysync(m);
		wlr_output_schedule_frame(m->wlr_output);
	}
	if (overview_dragging)
		carryland();
}

static void
overviewrelayout(void)
{
	struct wlr_box target[3];
	Monitor *m;
	int i;

	if (!overview_visible)
		return;
	wl_list_for_each(m, &mons, link) {
		if (!overviewvalid(m))
			continue;
		overviewtargets(m, target);
		for (i = 0; i < 3; i++) {
			m->overview[i] = target[i];
			m->overview_opacity[i] = 1.0f;
		}
		m->overview_dim = 1.0f;
		m->overview_animating = 0;
	}
	overviewbuild();
}

static int
overviewpanelat(Monitor *m, double x, double y)
{
	int i = -1;

	if (GRIDLT(m)) {
		struct wlr_box card, view = gridview(m);
		unsigned int ws;

		if (!wlr_box_contains_point(&view, x, y))
			return -1;
		for (ws = 0; ws < NUMWS; ws++)
			if (gridcard(m, ws, &card) && wlr_box_contains_point(&card, x, y))
				return GRIDPANEL + (int)ws;
		return -1;
	}
	if (wlr_box_contains_point(&m->overview[1], x, y))
		return 1;
	if (wlr_box_contains_point(&m->overview[0], x, y))
		i = 0;
	else if (wlr_box_contains_point(&m->overview[2], x, y))
		i = 2;
	/* the gap counts as the neighbour, for a strip a finger can hit */
	else if (!SCROLLLT(m) && y >= m->overview[1].y && y < m->overview[1].y + m->overview[1].height)
		i = x < m->overview[1].x ? 0 : x >= m->overview[1].x + m->overview[1].width ? 2 : -1;
	return i >= 0 && wsnext(m, i - 1) >= 0 ? i : -1;
}

static unsigned int
overviewpanelws(Monitor *m, int panel)
{
	if (panel >= GRIDPANEL)
		return (unsigned int)(panel - GRIDPANEL);
	return panel == 1 ? m->ws : (unsigned int)wsnext(m, panel - 1);
}

static Client *
overviewclientat(Monitor *m, double x, double y, int *panel,
		struct wlr_box *box)
{
	Client *c;
	unsigned int ws;
	int p = overviewpanelat(m, x, y);
	struct wlr_box panelbox;

	if (p < 0)
		return NULL;

	ws = overviewpanelws(m, p);
	panelbox = overviewpanelbox(m, p);
	wl_list_for_each(c, &clients, link) {
		struct wlr_box b;
		if (c->mon != m || c->ws != ws)
			continue;
		b = overviewwindowbox(m, c, &panelbox);
		if (!wlr_box_contains_point(&b, x, y))
			continue;
		if (panel)
			*panel = p;
		if (box)
			*box = b;
		return c;
	}
	return NULL;
}

static void
overviewmovetows(Client *c, Monitor *m, unsigned int ws)
{
	if (c->mon != m) {
		setmon(c, m, (int)ws);
	} else if (c->ws != ws) {
		detachclient(c);
		attachclient(m, ws, c);
		arrange(m);
	}
}

typedef struct {
	unsigned int ws;
	Client *tile; /* what the drop splits or swaps with */
	int side;
	struct wlr_box box; /* what the preview covers; empty when nothing would change */
} DropSpot;

/* what a carried thing would do if let go here; 0 when that is nothing at all */
static int
dropspot(Monitor *m, double x, double y, Client *skip, DropSpot *d)
{
	Client *c, *near = NULL;
	struct wlr_box nearbox = {0};
	double neard = 1e9;
	int aside = 0, panel = overviewvalid(m) ? overviewpanelat(m, x, y) : -1;
	struct wlr_box panelbox;

	if (panel < 0)
		return 0;
	panelbox = overviewpanelbox(m, panel);
	d->ws = overviewpanelws(m, panel);
	d->tile = NULL;
	d->side = SIDE_SWAP;
	d->box = overviewpanelcard(m, panel);
	wl_list_for_each(c, &clients, link) {
		struct wlr_box b;
		double dist;

		if (c == skip || c->mon != m || c->ws != d->ws || c->isfloating)
			continue;
		b = overviewwindowbox(m, c, &panelbox);
		dist = hypot(MAX(0.0, MAX(b.x - x, x - (b.x + b.width))),
				MAX(0.0, MAX(b.y - y, y - (b.y + b.height))));
		if (dist < neard) {
			neard = dist;
			near = c;
			nearbox = b;
		}
		if (wlr_box_contains_point(&b, x, y))
			break;
	}
	/* in a gap or on the bar strip of its own card: the nearest tile, by the side the finger is on */
	if (near && (neard <= 0.0 || (skip && skip->ws == d->ws))) {
		double u = MAX(-0.5, MIN(0.5, (x - nearbox.x) / nearbox.width - 0.5));
		double v = MAX(-0.5, MIN(0.5, (y - nearbox.y) / nearbox.height - 0.5));

		d->tile = near;
		d->box = nearbox;
		if (fabs(u) >= 0.25 || fabs(v) >= 0.25)
			d->side = fabs(u) >= fabs(v) ? (u < 0 ? SIDE_LEFT : SIDE_RIGHT)
					: (v < 0 ? SIDE_TOP : SIDE_BOTTOM);
	}
	if (!d->tile && skip && skip->ws == d->ws) {
		d->box.width = 0;
		return 1;
	}
	if (!d->tile) {
		/* on a card, but off its windows: beside the one last used */
		wl_list_for_each(c, &fstack, flink) {
			if (c != skip && c->mon == m && c->ws == d->ws && !c->isfloating) {
				d->tile = c;
				d->box = overviewwindowbox(m, c, &panelbox);
				aside = 1;
				break;
			}
		}
	}
	/* only the middle of a window swaps; an icon has nothing to swap: the long side splits, as a new window does */
	if (d->tile && d->side == SIDE_SWAP && (!skip || aside || d->box.width <= 0))
		d->side = d->box.width >= d->box.height ? SIDE_RIGHT : SIDE_BOTTOM;
	return 1;
}

static int
tilecount(Monitor *m, unsigned int ws)
{
	Client *c;
	int n = 0;

	wl_list_for_each(c, &clients, link)
		n += c->mon == m && c->ws == ws && !c->isfloating;
	return n;
}

/* shows where the carried thing lands: half a tile, a whole one to swap, a whole free card */
static void
carryland(void)
{
	static const float color[] = {0.3f, 0.3f, 0.3f, 0.3f};
	struct wlr_scene_node *node, *tmp;
	Monitor *m = xytomon(cursor->x, cursor->y);
	Client *skip = overview_drag_client;
	DropSpot d;

	wl_list_for_each_safe(node, tmp, &overview_land_scene->children, link)
		wlr_scene_node_destroy(node);
	/* over a carried window, which covers it otherwise; under a carried icon */
	wlr_scene_node_raise_to_top(skip ? &overview_land_scene->node : &overview_drag_scene->node);
	if (!overview_dragging || !dropspot(m, cursor->x, cursor->y, skip, &d) || d.box.width <= 0
			|| (d.tile && (!skip || skip->ws != d.ws) && d.side != SIDE_SWAP
				&& tilecount(m, d.ws) >= TILES_MAX))
		return;
	if (d.tile && d.side != SIDE_SWAP) {
		if (d.side == SIDE_LEFT || d.side == SIDE_RIGHT)
			d.box.width /= 2;
		else
			d.box.height /= 2;
		if (d.side == SIDE_RIGHT)
			d.box.x += d.box.width;
		else if (d.side == SIDE_BOTTOM)
			d.box.y += d.box.height;
	}
	overviewrect(overview_land_scene, d.box, 10, color, &m->m);
}

static void
carrydrop(Client *c, Monitor *m, const DropSpot *d)
{
	Client *t = d->tile;

	if (c->mon != m || !t || !c->node || !t->node) {
		/* shortcut: the scroll and drift layouts only move between cards, phones use the tree */
		overviewmovetows(c, m, d->ws);
		return;
	}
	if (t->isfullscreen)
		setfullscreen(t, 0);
	if (c->isfullscreen)
		setfullscreen(c, 0);
	if (d->side == SIDE_SWAP) {
		Node *a = c->node, *b = t->node;
		unsigned int ws = c->ws;

		a->c = t;
		b->c = c;
		c->node = b;
		t->node = a;
		c->ws = t->ws;
		t->ws = ws;
	} else {
		if (c->ws != d->ws && tilecount(m, d->ws) >= TILES_MAX) {
			buttonsend("tilefull");
			return;
		}
		detachclient(c);
		place_anchor = t;
		place_side = d->side;
		attachclient(m, d->ws, c);
		place_anchor = NULL;
	}
	arrange(m);
}

static struct Placement placements[8];

static void
placementadd(pid_t pid, Client *anchor, int side)
{
	Placement *p = placements;
	size_t i;

	for (i = 0; i < LENGTH(placements); i++)
		if (!placements[i].pid) {
			p = &placements[i];
			break;
		}
	p->pid = pid;
	p->anchor = anchor;
	p->side = side;
	clock_gettime(CLOCK_MONOTONIC, &p->until);
	p->until.tv_sec += PLACE_MS / 1000;
}

/* shortcut: follows the parent chain, an app that daemonizes first or an X11 one gets normal placement */
static Placement *
placementfind(Client *c)
{
	struct timespec now;
	pid_t pid;
	size_t i;
	int depth;

	if (c->type != XDGShell)
		return NULL;
	wl_client_get_credentials(c->surface.xdg->client->client, &pid, NULL, NULL);
	clock_gettime(CLOCK_MONOTONIC, &now);
	for (depth = 0; pid > 1 && depth < 16; depth++) {
		char path[32], buf[512], *paren;
		ssize_t n;
		int fd;

		for (i = 0; i < LENGTH(placements); i++) {
			if (placements[i].pid && now.tv_sec >= placements[i].until.tv_sec)
				placements[i].pid = 0;
			else if (placements[i].pid == pid)
				return &placements[i];
		}
		snprintf(path, sizeof path, "/proc/%d/stat", pid);
		if ((fd = open(path, O_RDONLY | O_CLOEXEC)) < 0)
			return NULL;
		n = read(fd, buf, sizeof buf - 1);
		close(fd);
		if (n <= 0)
			return NULL;
		buf[n] = '\0';
		/* the name in brackets can hold anything */
		if (!(paren = strrchr(buf, ')')) || sscanf(paren + 1, " %*c %d", &pid) != 1)
			return NULL;
	}
	return NULL;
}

static void
icondrop(void)
{
	Monitor *m = xytomon(cursor->x, cursor->y);
	char *argv[32], *cmd = overview_drag_cmd, *dir = overview_drag_dir;
	int n = 0;
	DropSpot d;
	Arg a = {.v = argv};

	overview_drag_cmd = overview_drag_dir = NULL;
	overview_dragging = 0;
	overviewdragclear();
	if (dropspot(m, cursor->x, cursor->y, NULL, &d)) {
		if (wsoccupied(m, wslimit(m))) {
			buttonsend("nofree");
		} else if (d.tile && tilecount(m, d.ws) >= TILES_MAX) {
			buttonsend("tilefull");
		} else {
			for (argv[n] = strtok(cmd, "\x1f"); argv[n] && n < (int)LENGTH(argv) - 1;
					argv[++n] = strtok(NULL, "\x1f"))
				;
			argv[n] = NULL;
			if (n) {
				spawn_dir = dir && *dir ? dir : NULL;
				spawn(&a);
				spawn_dir = NULL;
				if (spawned_pid > 0)
					placementadd(spawned_pid, d.tile, d.side);
			}
			/* the free one or a neighbour comes to the middle, to watch it arrive */
			if (d.ws != m->ws)
				overviewnavigate(d.ws, d.ws > m->ws ? 1 : -1);
		}
	}
	free(cmd);
	free(dir);
}

/* a carried thing resting at a side of the screen turns the cards */
static int
carryedge(void *data)
{
	if ((overview_drag_client || overview_drag_cmd) && overview_dragging && carry_dir && GRIDLT(selmon)) {
		struct wlr_box view = gridview(selmon);

		glideto(selmon, grid_scroll, 0.0, gridclamp(selmon, grid_scroll + carry_dir * view.height / 2.0));
		wl_event_source_timer_update(carry_edge_timer, CARRY_EDGE_MS);
	} else if ((overview_drag_client || overview_drag_cmd) && overview_dragging && carry_dir) {
		overviewstep(carry_dir);
		wl_event_source_timer_update(carry_edge_timer, CARRY_EDGE_MS);
	}
	return 0;
}

static void
carryedgewatch(Monitor *m)
{
	int dir = cursor->x < m->m.x + CARRY_EDGE ? -1
			: cursor->x >= m->m.x + m->m.width - CARRY_EDGE ? 1 : 0;

	if (GRIDLT(m)) {
		struct wlr_box view = gridview(m);

		/* inside the view only: an icon starts its trip in the tray, below it */
		dir = cursor->y >= view.y && cursor->y < view.y + CARRY_EDGE ? -1
				: cursor->y < view.y + view.height && cursor->y >= view.y + view.height - CARRY_EDGE ? 1 : 0;
	}

	if (dir != carry_dir) {
		carry_dir = dir;
		wl_event_source_timer_update(carry_edge_timer, dir ? CARRY_EDGE_MS : 0);
	}
}

static void
overviewbutton(struct wlr_pointer_button_event *event)
{
	Monitor *m;
	Client *c;
	struct wlr_box box;
	int panel;

	if (event->state == WL_POINTER_BUTTON_STATE_PRESSED) {
		overview_button_swallow = 1;
		if (!overview_active || event->button != BTN_LEFT)
			return;
		m = xytomon(cursor->x, cursor->y);
		if (!overviewvalid(m) || m->overview_animating)
			return;
		selmon = m;
		c = overviewclientat(m, cursor->x, cursor->y, &panel, &box);
		if (c) {
			overview_drag_client = c;
			overview_drag_box = box;
			overview_press_x = cursor->x;
			overview_press_y = cursor->y;
			overview_grab_x = (int)round(cursor->x) - box.x;
			overview_grab_y = (int)round(cursor->y) - box.y;
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "grab");
			return;
		}
		panel = overviewpanelat(m, cursor->x, cursor->y);
		if (panel >= GRIDPANEL) {
			Arg a = {.ui = (unsigned int)(panel - GRIDPANEL)};

			if (!wsoccupied(m, a.ui))
				return;
			viewws(&a);
			overviewset(0);
		} else if (panel == 0)
			overviewstep(-1);
		else if (panel == 2)
			overviewstep(1);
		else if (panel == 1)
			overviewset(0);
		return;
	}

	carry_dir = 0;
	wl_event_source_timer_update(carry_edge_timer, 0);
	if (overview_drag_cmd) {
		icondrop();
		if (overview_active)
			overviewbuild();
	} else if (overview_drag_client) {
		DropSpot d;

		c = overview_drag_client;
		m = xytomon(cursor->x, cursor->y);
		if (overview_dragging && dropspot(m, cursor->x, cursor->y, c, &d))
			carrydrop(c, m, &d);
		if (!overview_dragging) {
			selmon = c->mon;
			if (selmon->ws != c->ws) {
				Arg a = {.ui = c->ws};
				viewws(&a);
			}
			overview_focus_client = c;
		}
		overview_drag_client = NULL;
		overview_dragging = 0;
		overviewdragclear();
		wlr_cursor_set_xcursor(cursor, cursor_mgr, "default");
		if (overview_active) {
			overviewbuild();
			if (overview_focus_client)
				overviewset(0);
		}
	}
	overview_button_swallow = 0;
}

static int
overviewpassthrough(void)
{
	/* The shell puts its overview dock on a layer surface. While the pointer
	 * is over one, the overview stops swallowing input so the dock can be
	 * hovered and clicked; everywhere else the overview keeps the pointer. */
	struct wlr_surface *surface = NULL;
	LayerSurface *l = NULL;
	Client *c = NULL;

	if (!overview_visible || overview_drag_client || overview_drag_cmd)
		return 0;
	/* xytonode's own pl output walks one node too far up and comes back
	 * empty, so resolve the toplevel from the surface instead */
	xytonode(cursor->x, cursor->y, &surface, NULL, NULL, NULL, NULL);
	return surface && toplevel_from_wlr_surface(surface, &c, &l) == LayerShell;
}

static int
overviewkeypassthrough(void)
{
	/* A layer surface holds the keyboard - the overview dock's search box
	 * asking for it - so the keys are its to consume, not the overview's. */
	struct wlr_surface *focus;
	LayerSurface *l = NULL;
	Client *c = NULL;

	if (!overview_visible)
		return 0;
	focus = seat->keyboard_state.focused_surface;
	return focus && toplevel_from_wlr_surface(focus, &c, &l) == LayerShell;
}

static void
icondraw(void)
{
	Monitor *m = xytomon(cursor->x, cursor->y);
	LayerSurface *l = overviewvalid(m) ? cardlabels(m) : NULL;

	overviewdragclear();
	if (l) {
		CardLabel cl = {overview_drag_scene, (int)l->layer_surface->current.actual_width,
			-1, ICON_GHOST, 0, 0, 1.0f};

		wlr_scene_node_set_enabled(&l->scene->node, 1);
		wlr_scene_node_for_each_buffer(&l->scene->node, overviewlabel, &cl);
		wlr_scene_node_set_enabled(&l->scene->node, 0);
	}
	wlr_scene_node_set_position(&overview_drag_scene->node,
			(int)round(cursor->x) - ICON_GHOST / 2, (int)round(cursor->y) - ICON_GHOST / 2);
	carryland();
	if (overviewvalid(m))
		carryedgewatch(m);
}

static int
overviewmotion(void)
{
	Monitor *m;
	Client *c;

	if (!overview_visible)
		return 0;
	if (!overview_active)
		return 1;
	if (overview_drag_client) {
		if (!overview_dragging && (fabs(cursor->x - overview_press_x) >= 7.0
				|| fabs(cursor->y - overview_press_y) >= 7.0)) {
			overview_dragging = 1;
			overviewdragclear();
			overview_drag_box.x = overview_drag_box.y = 0;
			/* the ghost follows the cursor across monitors, so it is
			 * the one thing that is not cut to one */
			overviewwindowdraw(overview_drag_scene, overview_drag_client,
					&overview_drag_box, 0.96f, 0,
					&(struct wlr_box){-(1 << 20), -(1 << 20), 1 << 21, 1 << 21},
					&overview_drag_box);
			overviewbuild();
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "grabbing");
		}
		if (overview_dragging) {
			wlr_scene_node_set_position(&overview_drag_scene->node,
					(int)round(cursor->x) - overview_grab_x,
					(int)round(cursor->y) - overview_grab_y);
			carryland();
			if (overviewvalid(m = xytomon(cursor->x, cursor->y)))
				carryedgewatch(m);
		}
		return 1;
	}
	if (overview_drag_cmd) {
		icondraw();
		return 1;
	}
	m = xytomon(cursor->x, cursor->y);
	c = overviewvalid(m) && !m->overview_animating
			? overviewclientat(m, cursor->x, cursor->y, NULL, NULL) : NULL;
	wlr_cursor_set_xcursor(cursor, cursor_mgr, c ? "grab" : "default");
	return 1;
}

void
overviewset(int active)
{
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	static const float closing[] = {0.0f, 1.0f, 0.0f};
	struct wlr_box target[3], end[3];
	Monitor *m;
	int i;

	active = !!active;
	if (active == overview_active || (active && (locked || greeter || !selmon)))
		return;
	overview_active = active;
	saveoverviewstate(active);
	if (active) {
		flick_ws = -1;
		barset(0);
		wl_list_for_each(m, &mons, link)
			keyboardforce(m, 0);
	}
	overview_swipe_active = overview_swipe_triggered = 0;
	overview_swipe_dx = overview_swipe_dy = 0.0;
	if (active) {
		overview_focus_client = NULL;
		if (!overview_visible) {
			overview_visible = 1;
			/* the previews clone the live buffers, so nothing may be
			 * caught halfway through an open animation */
			wl_list_for_each(m, &mons, link)
				animstop(m);
			focusclient(NULL, 0);
			wlr_seat_pointer_notify_clear_focus(seat);
			wlr_scene_node_set_enabled(&layers[LyrTile]->node, 0);
			wlr_scene_node_set_enabled(&layers[LyrFloat]->node, 0);
			wlr_scene_node_set_enabled(&layers[LyrFS]->node, 0);
			wlr_scene_node_set_enabled(&overview_dim_scene->node, 1);
			wlr_scene_node_set_enabled(&overview_scene->node, 1);
			wl_list_for_each(m, &mons, link) {
				if (!overviewvalid(m))
					continue;
				if (GRIDLT(m)) {
					grid_ws = (int)m->ws;
					gridreveal(m);
				}
				overviewtargets(m, target);
				m->overview[0] = target[0];
				m->overview[1] = m->m;
				m->overview[2] = target[2];
				if (SCROLLLT(m)) {
					m->overview[0].y -= m->m.height;
					m->overview[2].y += m->m.height;
				} else {
					m->overview[0].x -= m->m.width;
					m->overview[2].x += m->m.width;
				}
				m->overview_opacity[0] = 0.0f;
				m->overview_opacity[1] = 1.0f;
				m->overview_opacity[2] = 0.0f;
				m->overview_dim = 0.0f;
				overviewtransition(m, target, shown, 1.0f);
			}
		} else {
			wl_list_for_each(m, &mons, link) {
				if (!overviewvalid(m))
					continue;
				overviewtargets(m, target);
				overviewtransition(m, target, shown, 1.0f);
			}
		}
	} else {
		overview_drag_client = NULL;
		overview_dragging = 0;
		free(overview_drag_cmd);
		free(overview_drag_dir);
		overview_drag_cmd = overview_drag_dir = NULL;
		card_close.c = NULL;
		wl_event_source_timer_update(card_close_timer, 0);
		overviewdragclear();
		/* the windows stay hidden until the closing transition ends, so
		 * put a deadline on it */
		if (overview_watchdog)
			wl_event_source_timer_update(overview_watchdog,
					MAX(500, animation_duration * 4));
		wl_list_for_each(m, &mons, link) {
			if (!overviewvalid(m))
				continue;
			for (i = 0; i < 3; i++)
				end[i] = m->overview[i];
			if (SCROLLLT(m)) {
				end[0].y -= m->m.height;
				end[2].y += m->m.height;
			} else {
				end[0].x -= m->m.width;
				end[2].x += m->m.width;
			}
			end[1] = m->m;
			overviewtransition(m, end, closing, 0.0f);
		}
	}
	overviewbuild();
	overviewfinish();
	pillplace(selmon);
}

void
overviewtoggle(const Arg *arg)
{
	overviewset(!overview_active);
}

static int
startoverview(void *data)
{
	if (selmon && overviewvalid(selmon) && !overview_visible)
		overviewset(1);
	return 0;
}

static void
workspacestep(int dir)
{
	workspacestepcarry(dir, 0);
}

/* carry takes the focused window along, the way Mod+Ctrl+arrow does */
static void
workspacestepcarry(int dir, int carry)
{
	Arg a = {.i = dir};
	Monitor *m = xytomon(cursor->x, cursor->y);

	if (overviewvalid(m))
		selmon = m;
	if (!overviewvalid(selmon) || !dir)
		return;
	if (overview_active)
		overviewstep(dir);
	else if (!overview_visible && carry)
		movewsstep(&a);
	else if (!overview_visible)
		wsstep(&a);
}

static void
overviewstep(int dir)
{
	int ws = wsnext(selmon, dir);

	if (ws >= 0)
		overviewnavigate((unsigned int)ws, dir);
}

static void
overviewnavigate(unsigned int ws, int dir)
{
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	struct wlr_box old[3], target[3];
	float oldopacity[3];
	Arg a = {.ui = ws};
	Monitor *m = selmon;
	int i, distance, adjacent;

	if (!overview_active || !overviewvalid(m) || m->ws == ws || ws > wslimit(m))
		return;
	if (GRIDLT(m)) {
		viewws(&a);
		overviewbuild();
		return;
	}
	adjacent = wsnext(m, dir);
	for (i = 0; i < 3; i++) {
		old[i] = m->overview[i];
		oldopacity[i] = m->overview_opacity[i];
	}
	viewws(&a);
	overviewtargets(m, target);
	if ((int)ws != adjacent) {
		for (i = 0; i < 3; i++) {
			m->overview[i] = target[i];
			m->overview_opacity[i] = 0.0f;
		}
		overviewtransition(m, target, shown, 1.0f);
		overviewbuild();
		return;
	}
	if (dir > 0) {
		m->overview[0] = old[1];
		m->overview[1] = old[2];
		m->overview[2] = target[2];
		if (SCROLLLT(m)) {
			distance = old[2].y - old[1].y;
			m->overview[2].y = old[2].y + distance;
		} else {
			distance = old[2].x - old[1].x;
			m->overview[2].x = old[2].x + distance;
		}
		m->overview_opacity[0] = oldopacity[1];
		m->overview_opacity[1] = oldopacity[2];
		m->overview_opacity[2] = 0.0f;
	} else {
		m->overview[2] = old[1];
		m->overview[1] = old[0];
		m->overview[0] = target[0];
		if (SCROLLLT(m)) {
			distance = old[1].y - old[0].y;
			m->overview[0].y = old[0].y - distance;
		} else {
			distance = old[1].x - old[0].x;
			m->overview[0].x = old[0].x - distance;
		}
		m->overview_opacity[2] = oldopacity[1];
		m->overview_opacity[1] = oldopacity[0];
		m->overview_opacity[0] = 0.0f;
	}
	overviewtransition(m, target, shown, 1.0f);
	overviewbuild();
}

void
overviewfocuscol(int dir)
{
	/* walk the focus along the strip inside the overview, like niri: the
	 * center panel pans to follow the newly focused column */
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	struct wlr_box target[3];
	Monitor *m = selmon;
	Client *sel, *t = NULL, *cc;
	Column *cand = NULL, *it;
	struct wl_list *pos;

	if (!overview_active || !overviewvalid(m) || !SCROLLLT(m))
		return;
	if (!(sel = wsfocused(m, m->ws)))
		return;
	if (!sel->col) {
		/* a floating window has no column; walk from the first one */
		Column *first;
		if (wl_list_empty(&m->cols[m->ws]))
			return;
		first = wl_container_of(m->cols[m->ws].next, first, link);
		wl_list_for_each(cc, &first->clients, clink) {
			if (!cc->isfloating) {
				sel = cc;
				break;
			}
		}
		if (!sel->col)
			return;
	}
	for (pos = dir > 0 ? sel->col->link.next : sel->col->link.prev;
			pos != &m->cols[m->ws];
			pos = dir > 0 ? pos->next : pos->prev) {
		it = wl_container_of(pos, it, link);
		if (scroll_coltiled(it)) {
			cand = it;
			break;
		}
	}
	if (!cand)
		return;
	wl_list_for_each(cc, &cand->clients, clink) {
		if (!cc->isfloating) {
			t = cc;
			break;
		}
	}
	if (!t)
		return;
	wl_list_remove(&t->flink);
	wl_list_insert(&fstack, &t->flink);
	overview_focus_client = t;
	arrange(m); /* pans the strip to the new column */
	overviewtargets(m, target);
	/* a (no-move) transition forces the clones to rebuild every frame, so
	 * the pan animation shows inside the panel */
	overviewtransition(m, target, shown, 1.0f);
	overviewbuild();
}

/* Keys inside the overview.  Bare keys walk it (arrows, hjkl, 1-9, Escape,
 * Return); anything with a modifier is the normal binding, so a terminal
 * can be opened, a window closed or moved, a layout switched, all with the
 * overview staying up and its cards following.  The bindings that would
 * switch workspaces underneath it are turned into overview moves instead. */
static int
overviewkeybinding(uint32_t mods, xkb_keysym_t sym)
{
	const Bind *b;

	if (!CLEANMASK(mods) || inputmode == ModeNormal)
		return overviewkey(sym);
	for (b = runkeys; b < runkeys + nrunkeys; b++) {
		if (CLEANMASK(mods) != CLEANMASK(b->mod)
				|| xkb_keysym_to_lower(sym) != xkb_keysym_to_lower(b->keysym)
				|| !b->func)
			continue;
		if (b->func == viewws) {
			overviewnavigate(b->arg.ui, b->arg.ui > selmon->ws ? 1 : -1);
		} else if (b->func == wsstep) {
			overviewstep(b->arg.i);
		} else if (b->func == focusdir) {
			overviewkey(b->arg.i == DirLeft ? XKB_KEY_Left
					: b->arg.i == DirRight ? XKB_KEY_Right
					: b->arg.i == DirUp ? XKB_KEY_Up : XKB_KEY_Down);
		} else if (b->func == overviewtoggle) {
			overviewset(0);
		} else {
			b->func(&b->arg);
		}
		return 1;
	}
	return 1;
}

int
overviewkey(xkb_keysym_t sym)
{
	int scroll = SCROLLLT(selmon);

	sym = xkb_keysym_to_lower(sym);
	if (sym == XKB_KEY_Escape || sym == XKB_KEY_Return) {
		overviewset(0);
	} else if (sym == XKB_KEY_Left || sym == XKB_KEY_h) {
		if (scroll)
			overviewfocuscol(-1);
		else
			overviewstep(-1);
	} else if (sym == XKB_KEY_Right || sym == XKB_KEY_l) {
		if (scroll)
			overviewfocuscol(1);
		else
			overviewstep(1);
	} else if (sym == XKB_KEY_Up || sym == XKB_KEY_k) {
		overviewstep(-1);
	} else if (sym == XKB_KEY_Down || sym == XKB_KEY_j) {
		overviewstep(1);
	} else if (sym >= XKB_KEY_1 && sym <= XKB_KEY_9) {
		unsigned int ws = (uint32_t)(sym - XKB_KEY_1);
		overviewnavigate(ws, ws > selmon->ws ? 1 : -1);
	}
	return 1;
}

/* hardware buttons: this only counts presses, the shell decides what each one means */
#define POWER_WINDOW_MS 300
static struct wl_event_source *power_timer, *vol_timer;
static int power_down, power_chord, power_presses, power_woke, voldown_down, voldown_eaten;
static uint32_t vol_key;
static int vol_stepped;

static void
buttonsend(const char *event)
{
	static unsigned seq;
	char path[600], tmp[610], dir[512];
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	{
		char *slash = strrchr(dir, '/');
		if (slash) {
			*slash = '\0';
			mkdir(dir, 0700);
			*slash = '/';
		}
	}
	mkdir(dir, 0700);
	snprintf(path, sizeof path, "%s/button", dir);
	snprintf(tmp, sizeof tmp, "%s.tmp", path);
	if (!(f = fopen(tmp, "w")))
		return;
	fprintf(f, "%u %s\n", seq++, event);
	fclose(f);
	rename(tmp, path);
}

static int
powerexpire(void *data)
{
	/* the press that lit the screen does not turn it off again */
	if (power_presses > 1 || (power_presses == 1 && !power_woke))
		buttonsend(power_presses == 1 ? "single" : power_presses == 2 ? "double" : "triple");
	power_presses = power_woke = 0;
	return 0;
}

/* a held volume key keeps stepping */
static int
volrepeat(void *data)
{
	if (!vol_key)
		return 0;
	vol_stepped = 1;
	buttonsend(vol_key == KEY_VOLUMEUP ? "volup" : "voldown");
	wl_event_source_timer_update(vol_timer, 90);
	return 0;
}

/* returns 1 when the key stops here. Both keys down is the screenshot, in either order;
 * a single press waits out the window so a double or triple never blanks the screen first */
static int
buttonkey(KeyboardGroup *group, uint32_t code, int pressed)
{
	Monitor *m;

	if (!power_timer) {
		power_timer = wl_event_loop_add_timer(event_loop, powerexpire, NULL);
		vol_timer = wl_event_loop_add_timer(event_loop, volrepeat, NULL);
	}
	if (code == KEY_VOLUMEDOWN) {
		voldown_down = pressed;
		if (pressed && power_down) {
			power_chord = voldown_eaten = 1;
			buttonsend("chord");
			return 1;
		}
		if (!pressed && voldown_eaten) {
			voldown_eaten = 0;
			return 1;
		}
	}
	/* the shell steps the volume and shows it, locked or not; the laptop's F5 is only the chord */
	if (code == KEY_VOLUMEDOWN || code == KEY_VOLUMEUP) {
		if (!group)
			return 0;
		if (pressed) {
			/* down steps at its release: it may be the first half of the screenshot chord */
			if ((vol_stepped = code == KEY_VOLUMEUP))
				buttonsend("volup");
			vol_key = code;
			wl_event_source_timer_update(vol_timer, 400);
		} else if (vol_key == code) {
			if (!vol_stepped)
				buttonsend("voldown");
			vol_key = 0;
			wl_event_source_timer_update(vol_timer, 0);
		}
		return 1;
	}
	if (code != KEY_POWER)
		return 0;
	if (pressed) {
		power_down = 1;
		wl_event_source_timer_update(power_timer, 0);
		/* a dark screen lights at the press itself, not after the wait for a second one */
		if (!power_presses)
			wl_list_for_each(m, &mons, link)
				if (screendark(m)) {
					screenpower(m, 1);
					power_woke = 1;
				}
		power_presses++;
		if (voldown_down) {
			power_chord = 1;
			vol_key = 0;
			if (group)
				wl_event_source_timer_update(group->key_repeat_source, 0);
			buttonsend("chord");
		}
		return 1;
	}
	power_down = 0;
	if (power_chord) {
		power_chord = power_presses = power_woke = 0;
		return 1;
	}
	wl_event_source_timer_update(power_timer, POWER_WINDOW_MS);
	return 1;
}

int
keybinding(uint32_t mods, xkb_keysym_t sym)
{
	/*
	 * Here we handle compositor keybindings. This is when the compositor is
	 * processing keys, rather than passing them on to the client for its own
	 * processing.
	 */
	int handled = 0;
	const Bind *b;
	for (b = runkeys; b < runkeys + nrunkeys; b++) {
		if (CLEANMASK(mods) == CLEANMASK(b->mod)
				&& xkb_keysym_to_lower(sym) == xkb_keysym_to_lower(b->keysym)
				&& b->func) {
			b->func(&b->arg);
			handled = 1;
			break;
		}
	}
	if (inputmode == ModeNormal) {
		if (!handled) {
			for (b = runnormalkeys; b < runnormalkeys + nrunnormalkeys; b++) {
				if (sym == b->keysym && b->func) {
					b->func(&b->arg);
					break;
				}
			}
		}
		return 1; /* normal mode swallows everything, like nvwm's keyboard grab */
	}
	return handled;
}

void
keypress(struct wl_listener *listener, void *data)
{
	int i, super, macrohandled = 0;
	/* This event is raised when a key is pressed or released. */
	KeyboardGroup *group = wl_container_of(listener, group, key);
	struct wlr_keyboard_key_event *event = data;

	/* Translate libinput keycode -> xkbcommon */
	uint32_t keycode = event->keycode + 8;
	/* Get a list of keysyms based on the keymap for this keyboard */
	const xkb_keysym_t *syms;
	int nsyms = xkb_state_key_get_syms(
			group->wlr_group->keyboard.xkb_state, keycode, &syms);

	int handled = 0;
	uint32_t mods = wlr_keyboard_get_modifiers(&group->wlr_group->keyboard);
	super = event->keycode == KEY_LEFTMETA || event->keycode == KEY_RIGHTMETA;

	if (mouse_finger && event->keycode == KEY_F4) {
		mouse_four = event->state == WL_KEYBOARD_KEY_STATE_PRESSED;
		return;
	}
	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	/* the laptop window has no such buttons, and must not change the real volume */
	/* the laptop has no accelerometer: F7 turns the pretend one a quarter, through the file the sensor helper reads */
	if (mouse_finger && event->keycode == KEY_F7) {
		const char *fake = getenv("FAKE_STATE"), *next[] = {"left-up", "bottom-up", "right-up", "normal"};
		char path[600];
		FILE *f;

		if (fake && event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
			snprintf(path, sizeof path, "%s/orientation", fake);
			if ((f = fopen(path, "w"))) {
				fprintf(f, "%s\n", next[rot_sensor <= WL_OUTPUT_TRANSFORM_270 ? rot_sensor : 3]);
				fclose(f);
			}
		}
		return;
	}
	if (mouse_finger && (event->keycode == KEY_F5 || event->keycode == KEY_F6)) {
		buttonkey(NULL, event->keycode == KEY_F5 ? KEY_VOLUMEDOWN : KEY_POWER,
				event->state == WL_KEYBOARD_KEY_STATE_PRESSED);
		return;
	}
	if (buttonkey(group, event->keycode, event->state == WL_KEYBOARD_KEY_STATE_PRESSED))
		return;
	if (!locked && event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		if (super) {
			group->super_down = group->super_alone = 1;
			super_group = group;
			handled = 1;
		} else if (group->super_down) {
			group->super_alone = 0;
		}
	} else if (!locked && event->state == WL_KEYBOARD_KEY_STATE_RELEASED
			&& super && group->super_down) {
		if (group->super_alone)
			overviewtoggle(NULL);
		group->super_down = group->super_alone = 0;
		if (super_group == group)
			super_group = NULL;
		handled = 1;
	}

	/* Macro triggers need both edges: hold macros stop on release and every
	 * trigger release is swallowed so clients never receive an orphaned key. */
	if (!locked && !greeter && !super && !overviewkeypassthrough()) {
		for (i = 0; i < nsyms && !macrohandled; i++)
			macrohandled = macrohandle(mods, syms[i], event->keycode, event->state);
		handled = macrohandled || handled;
	}

	/* On _press_ if there is no active screen locker,
	 * attempt to process a compositor keybinding. */
	if (!macrohandled && !locked && !greeter && event->state == WL_KEYBOARD_KEY_STATE_PRESSED && !super
			&& !overviewkeypassthrough()) {
		if (overview_visible)
			group->overview_keycode = event->keycode;
		for (i = 0; i < nsyms; i++)
			handled = (overview_visible ? (overview_active
						? overviewkeybinding(mods, syms[i]) : 1)
					: keybinding(mods, syms[i])) || handled;
	}
	if (event->state == WL_KEYBOARD_KEY_STATE_RELEASED && !overviewkeypassthrough()
			&& (overview_visible || event->keycode == group->overview_keycode)) {
		handled = 1;
		if (event->keycode == group->overview_keycode)
			group->overview_keycode = 0;
	}

	if (handled && !macrohandled && !super && !group->overview_keycode
			&& group->wlr_group->keyboard.repeat_info.delay > 0) {
		group->mods = mods;
		group->keysyms = syms;
		group->nsyms = nsyms;
		wl_event_source_timer_update(group->key_repeat_source,
				group->wlr_group->keyboard.repeat_info.delay);
	} else {
		group->nsyms = 0;
		wl_event_source_timer_update(group->key_repeat_source, 0);
	}

	if (handled)
		return;

	wlr_seat_set_keyboard(seat, &group->wlr_group->keyboard);
	/* Pass unhandled keycodes along to the client. */
	wlr_seat_keyboard_notify_key(seat, event->time_msec,
			event->keycode, event->state);
}

void
keypressmod(struct wl_listener *listener, void *data)
{
	/* This event is raised when a modifier key, such as shift or alt, is
	 * pressed. We simply communicate this to the client. */
	KeyboardGroup *group = wl_container_of(listener, group, modifiers);

	wlr_seat_set_keyboard(seat, &group->wlr_group->keyboard);
	/* Send modifiers to the client. */
	wlr_seat_keyboard_notify_modifiers(seat,
			&group->wlr_group->keyboard.modifiers);
}

int
keyrepeat(void *data)
{
	KeyboardGroup *group = data;
	int i;
	if (!group->nsyms || group->wlr_group->keyboard.repeat_info.rate <= 0)
		return 0;

	wl_event_source_timer_update(group->key_repeat_source,
			1000 / group->wlr_group->keyboard.repeat_info.rate);

	for (i = 0; i < group->nsyms; i++)
		keybinding(group->mods, group->keysyms[i]);

	return 0;
}

void
killclient(const Arg *arg)
{
	Client *sel = focustop(selmon);
	if (sel) {
		clientcloseanim(sel);
		client_send_close(sel);
	}
}

void
locksession(struct wl_listener *listener, void *data)
{
	struct wlr_session_lock_v1 *session_lock = data;
	SessionLock *lock;
	Monitor *m;
	macrostopall();
	overviewset(0);
	barset(0);
	wlr_scene_node_set_enabled(&locked_bg->node, 1);
	if (cur_lock) {
		wlr_session_lock_v1_destroy(session_lock);
		return;
	}
	lock = session_lock->data = ecalloc(1, sizeof(*lock));
	focusclient(NULL, 0);

	lock->scene = wlr_scene_tree_create(layers[LyrBlock]);
	cur_lock = lock->lock = session_lock;
	wl_list_for_each(m, &mons, link)
		keyboardforce(m, 0);
	locked = 1;
	/* a lock with the screen still lit suspends the apps too */
	wl_list_for_each(m, &mons, link)
		arrange(m);
	topcolorsoon();
	rotsoon(1);
	keyboardoverlock();

	LISTEN(&session_lock->events.new_surface, &lock->new_surface, createlocksurface);
	LISTEN(&session_lock->events.destroy, &lock->destroy, destroysessionlock);
	LISTEN(&session_lock->events.unlock, &lock->unlock, unlocksession);

	wlr_session_lock_v1_send_locked(session_lock);
}

/* the menu's blur runs on under the bar, so the bar goes over the menu while it is up */
void
menubar(Monitor *m)
{
	LayerSurface *l, *bar = NULL;
	int menu = 0, panel = 0;

	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_TOP], link)
		if (!strcmp(l->layer_surface->namespace, "phone-statusbar"))
			bar = l;
	if (!bar)
		return;
	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link) {
		menu |= l->mapped && !strcmp(l->layer_surface->namespace, "phone-menu");
		panel |= l->mapped && !strcmp(l->layer_surface->namespace, "phone-panel");
	}
	/* a pulled panel maps on top: the bar goes back under it */
	if (menu && !panel) {
		wlr_scene_node_reparent(&bar->scene->node, layers[LyrOverlay]);
		wlr_scene_node_raise_to_top(&bar->scene->node);
	} else if (bar->scene->node.parent == layers[LyrOverlay]) {
		wlr_scene_node_reparent(&bar->scene->node, layers[LyrTop]);
	}
}

void
mapnotify(struct wl_listener *listener, void *data)
{
	/* Called when the surface is mapped, or ready to display on-screen. */
	Client *p = NULL;
	Client *w, *c = wl_container_of(listener, c, map);
	Monitor *m;

	/* Create scene tree for this client and its border */
	c->scene = client_surface(c)->data = wlr_scene_tree_create(layers[LyrTile]);
	/* Enabled later by a call to arrange() */
	wlr_scene_node_set_enabled(&c->scene->node, client_is_unmanaged(c));
	c->scene_surface = c->type == XDGShell
			? wlr_scene_xdg_surface_create(c->scene, c->surface.xdg)
			: wlr_scene_subsurface_tree_create(c->scene, client_surface(c));
	c->scene->node.data = c->scene_surface->node.data = c;

	client_get_geometry(c, &c->geom);

	/* Handle unmanaged clients first so we can return prior create borders */
	if (client_is_unmanaged(c)) {
		/* Unmanaged clients always are floating */
		wlr_scene_node_reparent(&c->scene->node, layers[LyrFloat]);
		wlr_scene_node_set_position(&c->scene->node, c->geom.x, c->geom.y);
		client_set_size(c, c->geom.width, c->geom.height);
		if (client_wants_focus(c)) {
			focusclient(c, 1);
			exclusive_focus = c;
		}
		goto unset_fullscreen;
	}

	/* Draw an edge-only frame.  Separate corner pieces make a real rounded
	 * outer edge without painting a full rectangle behind transparent clients. */
	c->border.top = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.bottom = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.left = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.right = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.top_left = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.top_right = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.bottom_right = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.bottom_left = wlr_scene_rect_create(c->scene, 0, 0, bordercolor);
	c->border.top->node.data = c;
	c->border.bottom->node.data = c;
	c->border.left->node.data = c;
	c->border.right->node.data = c;
	c->border.top_left->node.data = c;
	c->border.top_right->node.data = c;
	c->border.bottom_right->node.data = c;
	c->border.bottom_left->node.data = c;
	wlr_scene_node_lower_to_bottom(&c->border.top->node);
	wlr_scene_node_lower_to_bottom(&c->border.bottom->node);
	wlr_scene_node_lower_to_bottom(&c->border.left->node);
	wlr_scene_node_lower_to_bottom(&c->border.right->node);
	wlr_scene_node_lower_to_bottom(&c->border.top_left->node);
	wlr_scene_node_lower_to_bottom(&c->border.top_right->node);
	wlr_scene_node_lower_to_bottom(&c->border.bottom_right->node);
	wlr_scene_node_lower_to_bottom(&c->border.bottom_left->node);

	/* The blur goes under the frame and the surface, so it paints what is
	 * behind the whole window. */
	if ((c->blur = wlr_scene_blur_create(c->scene, 0, 0))) {
		c->blur->node.data = c;
		wlr_scene_node_lower_to_bottom(&c->blur->node);
	}

	/* Find the main surface buffer for rounded corners/blur/fade */
	wlr_scene_node_for_each_buffer(&c->scene_surface->node, findsurfbuf, c);
	applyeffects(c);

	/* Initialize client geometry with room for border */
	client_set_tiled(c, WLR_EDGE_TOP | WLR_EDGE_BOTTOM | WLR_EDGE_LEFT | WLR_EDGE_RIGHT);
	c->geom.width += 2 * c->bw;
	c->geom.height += 2 * c->bw;

	/* Insert this client into client lists. */
	wl_list_insert(&clients, &c->link);
	wl_list_insert(&fstack, &c->flink);

	if ((c->ftl = wlr_foreign_toplevel_handle_v1_create(ftl_mgr))) {
		const char *title = client_get_title(c), *appid = client_get_appid(c);
		if (title)
			wlr_foreign_toplevel_handle_v1_set_title(c->ftl, title);
		if (appid)
			wlr_foreign_toplevel_handle_v1_set_app_id(c->ftl, appid);
		LISTEN(&c->ftl->events.request_activate, &c->ftl_activate, ftlactivatenotify);
		LISTEN(&c->ftl->events.request_close, &c->ftl_close, ftlclosenotify);
	}
	savewindowstate();

	/* Set initial monitor, tags, floating status, and focus:
	 * we always consider floating, clients that have parent and thus
	 * we set the same tags and monitor as its parent.
	 * If there is no parent, apply rules */
	if ((p = client_get_parent(c))) {
		c->isfloating = 1;
		setmon(c, p->mon, p->ws);
	} else {
		c->isfullscreen |= fullscreenapp(c);
		applyrules(c);
	}

	/* Wayland windows carry no position and an X11 one often asks for the
	 * corner: a floating window opening there sits over the bar. Dialogs
	 * go to the centre of their parent, the rest to the window area. */
	if (c->isfloating && c->mon && !c->isfullscreen
			&& (!client_is_x11(c)
				|| (c->geom.x - c->mon->m.x < 48 && c->geom.y - c->mon->m.y < 48))) {
		struct wlr_box area = c->mon->w;
		if (p && p->mon == c->mon)
			area = p->geom;
		c->geom.x = area.x + (area.width - c->geom.width) / 2;
		c->geom.y = area.y + (area.height - c->geom.height) / 2;
		c->geom.x = MAX(c->mon->w.x, MIN(c->geom.x,
				c->mon->w.x + c->mon->w.width - c->geom.width));
		c->geom.y = MAX(c->mon->w.y, MIN(c->geom.y,
				c->mon->w.y + c->mon->w.height - c->geom.height));
		resize(c, c->geom, 0);
	}

	/* Pop the new window in */
	if (animations && animation_type_open != AnimNone && animation_duration_open > 0
			&& c->mon && VISIBLEON(c, c->mon)) {
		/* the drift camera owns the buffer scale of the windows it holds,
		 * so a window opening on that canvas only slides and fades */
		c->anim.zoom = animation_type_open == AnimZoom && !DRIFTLT(c->mon);
		c->anim.from.x = c->geom.x;
		c->anim.from.y = c->geom.y + (animation_type_open == AnimSlide
				? MAX(14, MIN(32, c->geom.height / 18)) : 0);
		c->anim.zoomfrom = zoom_initial_ratio;
		if (c->anim.zoom) {
			c->anim.from.x += (int)roundf(c->geom.width * (1.0f - zoom_initial_ratio) / 2.0f);
			c->anim.from.y += (int)roundf(c->geom.height * (1.0f - zoom_initial_ratio) / 2.0f);
			/* from the icon just tapped, if it asked for this window */
			if (open_from_at && !c->isfloating && now_ms() - open_from_at < OPEN_FROM_MS) {
				c->anim.zoomfrom = MAX(0.1f, (float)ICON_GHOST / MAX(1, c->geom.width));
				c->anim.from.x = (int)round(press_x - c->geom.width * c->anim.zoomfrom / 2.0f);
				c->anim.from.y = (int)round(press_y - c->geom.height * c->anim.zoomfrom / 2.0f);
			}
		}
		if (!c->isfloating)
			open_from_at = 0;
		c->anim.fadein = 1;
		c->anim.workspace = 0;
		c->anim.hide = 0;
		c->anim.active = 1;
		c->anim.t = 0;
		if (c->anim.zoom) {
			wlr_scene_node_set_position(&c->scene->node, c->anim.from.x, c->anim.from.y);
			clientscale(c, c->anim.zoomfrom);
		} else {
			wlr_scene_node_set_position(&c->scene->node,
					c->anim.from.x, c->anim.from.y);
		}
		if (c->surfbuf)
			wlr_scene_buffer_set_opacity(c->surfbuf, 0);
		animkick(c->mon);
	}

unset_fullscreen:
	m = c->mon ? c->mon : xytomon(c->geom.x, c->geom.y);
	wl_list_for_each(w, &clients, link) {
		if (w != c && w != p && m == w->mon && w->ws == c->ws) {
			if (w->isfullscreen)
				setfullscreen(w, 0);
			if (w->isfakefull) {
				w->isfakefull = 0;
				applyfakefull(w);
				arrange(m);
			}
		}
	}
	if (overview_visible)
		overviewbuild();
}

void
maximizenotify(struct wl_listener *listener, void *data)
{
	/* This event is raised when a client would like to maximize itself,
	 * typically because the user clicked on the maximize button on
	 * client-side decorations. phonegluewc does not support maximization, but
	 * to conform to xdg-shell protocol we still must send a configure.
	 * Since xdg-shell protocol v5 we should ignore request of unsupported
	 * capabilities, just schedule a empty configure when the client uses <5
	 * protocol version
	 * wlr_xdg_surface_schedule_configure() is used to send an empty reply. */
	Client *c = wl_container_of(listener, c, maximize);
	if (c->surface.xdg->initialized
			&& wl_resource_get_version(c->surface.xdg->toplevel->resource)
					< XDG_TOPLEVEL_WM_CAPABILITIES_SINCE_VERSION)
		wlr_xdg_surface_schedule_configure(c->surface.xdg);
}

void
motionabsolute(struct wl_listener *listener, void *data)
{
	/* This event is forwarded by the cursor when a pointer emits an _absolute_
	 * motion event, from 0..1 on each axis. This happens, for example, when
	 * wlroots is running under a Wayland window rather than KMS+DRM, and you
	 * move the mouse over the window. You could enter the window from any edge,
	 * so we have to warp the mouse there. Also, some hardware emits these events. */
	struct wlr_pointer_motion_absolute_event *event = data;
	double lx, ly, dx, dy;

	if (mouse_finger) {
		mouse_x = event->x;
		mouse_y = event->y;
		wlr_cursor_warp_absolute(cursor, &event->pointer->base, event->x, event->y);
		mousetouch(event->time_msec, 0, 0);
		barhover();
		return;
	}
	if (!event->time_msec) /* this is 0 with virtual pointers */
		wlr_cursor_warp_absolute(cursor, &event->pointer->base, event->x, event->y);

	wlr_cursor_absolute_to_layout_coords(cursor, &event->pointer->base, event->x, event->y, &lx, &ly);
	dx = lx - cursor->x;
	dy = ly - cursor->y;
	motionnotify(event->time_msec, &event->pointer->base, dx, dy, dx, dy);
}

void
motionnotify(uint32_t time, struct wlr_input_device *device, double dx, double dy,
		double dx_unaccel, double dy_unaccel)
{
	double sx = 0, sy = 0, sx_confined, sy_confined;
	Client *c = NULL, *w = NULL, *cc = NULL;
	LayerSurface *l = NULL;
	struct wlr_surface *surface = NULL;
	struct wlr_pointer_constraint_v1 *constraint;

	if (device)
		barhover();
	/* Find the client under the pointer and send the event along. */
	xytonode(cursor->x, cursor->y, &surface, &c, NULL, &sx, &sy);

	if (cursor_mode == CurPressed && !seat->drag
			&& surface != seat->pointer_state.focused_surface
			&& toplevel_from_wlr_surface(seat->pointer_state.focused_surface, &w, &l) >= 0) {
		c = w;
		surface = seat->pointer_state.focused_surface;
		sx = cursor->x - (l ? l->scene->node.x : w->geom.x);
		sy = cursor->y - (l ? l->scene->node.y : w->geom.y);
	}

	/* time is 0 in internal calls meant to restore pointer focus. */
	if (time) {
		wlr_relative_pointer_manager_v1_send_relative_motion(
				relative_pointer_mgr, seat, (uint64_t)time * 1000,
				dx, dy, dx_unaccel, dy_unaccel);

		wl_list_for_each(constraint, &pointer_constraints->constraints, link)
			cursorconstrain(constraint);

		if (active_constraint && cursor_mode != CurResize && cursor_mode != CurMove
				&& cursor_mode != CurDragTile && cursor_mode != CurResizeCol
				&& cursor_mode != CurBSPMove && cursor_mode != CurBSPResize
				&& cursor_mode != CurDriftMove && cursor_mode != CurDriftResize
				&& cursor_mode != CurDriftPan) {
			/* its own variable: c still has to be the client under the pointer */
			toplevel_from_wlr_surface(active_constraint->surface, &cc, NULL);
			if (cc && active_constraint->surface == seat->pointer_state.focused_surface) {
				sx = cursor->x - cc->geom.x - cc->bw;
				sy = cursor->y - cc->geom.y - cc->bw;
				if (wlr_region_confine(&active_constraint->region, sx, sy,
						sx + dx, sy + dy, &sx_confined, &sy_confined)) {
					dx = sx_confined - sx;
					dy = sy_confined - sy;
				}

				if (active_constraint->type == WLR_POINTER_CONSTRAINT_V1_LOCKED)
					return;
			}
		}

		wlr_cursor_move(cursor, device, dx, dy);
		wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);

		/* Update selmon (even while dragging a window) */
		if (sloppyfocus)
			selmon = xytomon(cursor->x, cursor->y);
	}
	if (!overviewpassthrough() && overviewmotion())
		return;

	/* Update drag icon's position */
	wlr_scene_node_set_position(&drag_icon->node, (int)round(cursor->x), (int)round(cursor->y));

	/* If we are currently grabbing the mouse, handle and return */
	if (cursor_mode == CurMove) {
		/* Move the grabbed client to the new position. */
		resize(grabc, (struct wlr_box){.x = (int)round(cursor->x) - grabcx, .y = (int)round(cursor->y) - grabcy,
			.width = grabc->geom.width, .height = grabc->geom.height}, 1);
		return;
	} else if (cursor_mode == CurResize) {
		resize(grabc, (struct wlr_box){.x = grabc->geom.x, .y = grabc->geom.y,
			.width = (int)round(cursor->x) - grabc->geom.x, .height = (int)round(cursor->y) - grabc->geom.y}, 1);
		return;
	} else if (cursor_mode == CurDragTile) {
		if (grabc)
			scroll_dragto(grabc, cursor->x);
		return;
	} else if (cursor_mode == CurBSPMove) {
		if (grabc)
			bsp_dragto(grabc, cursor->x, cursor->y);
		return;
	} else if (cursor_mode == CurBSPResize) {
		if (grabc)
			bsp_resizeto(grabc, cursor->x, cursor->y);
		return;
	} else if (cursor_mode == CurDriftMove) {
		if (grabc)
			driftdragto(grabc, cursor->x, cursor->y);
		return;
	} else if (cursor_mode == CurDriftResize) {
		if (grabc)
			driftresizeto(grabc, cursor->x, cursor->y);
		return;
	} else if (cursor_mode == CurDriftPan) {
		driftpanto(cursor->x, cursor->y);
		return;
	} else if (cursor_mode == CurResizeCol) {
		if (grabc && grabc->col && grabc->mon && grabc->mon->w.width > 0) {
			float f = grab_wfrac + (float)((cursor->x - grab_startx)
					/ grabc->mon->w.width);
			f = f < 0.15f ? 0.15f : f > 1.0f ? 1.0f : f;
			if (fabsf(f - grabc->col->wfrac) >= 0.003f) {
				/* direct manipulation: retile without easing */
				int oldanim = animations;
				grabc->col->wfrac = f;
				animations = 0;
				arrange(grabc->mon);
				animations = oldanim;
			}
		}
		return;
	}

	/* If there's no client surface under the cursor, set the cursor image to a
	 * default. This is what makes the cursor image appear when you move it
	 * off of a client or over its border. */
	if (!surface && !seat->drag)
		wlr_cursor_set_xcursor(cursor, cursor_mgr, "default");

	pointerfocus(c, surface, sx, sy, time);
}

void
motionrelative(struct wl_listener *listener, void *data)
{
	/* This event is forwarded by the cursor when a pointer emits a _relative_
	 * pointer motion event (i.e. a delta) */
	struct wlr_pointer_motion_event *event = data;
	/* The cursor doesn't move unless we tell it to. The cursor automatically
	 * handles constraining the motion to the output layout, as well as any
	 * special configuration applied for the specific input device which
	 * generated the event. You can pass NULL for the device if you want to move
	 * the cursor around without any input. */
	motionnotify(event->time_msec, &event->pointer->base, event->delta_x, event->delta_y,
			event->unaccel_dx, event->unaccel_dy);
}

void
moveresize(const Arg *arg)
{
	if (cursor_mode != CurNormal && cursor_mode != CurPressed)
		return;
	xytonode(cursor->x, cursor->y, NULL, &grabc, NULL, NULL, NULL);
	if (!grabc || client_is_unmanaged(grabc) || grabc->isfullscreen)
		return;

	if (DRIFTLT(grabc->mon) && grabc->oncanvas && !grabc->isfloating
			&& !grabc->isfakefull) {
		/* driftwm-style direct manipulation: drag moves the window across
		 * the canvas, right-drag resizes it for real */
		grabcx = (int)round(cursor->x) - grabc->geom.x;
		grabcy = (int)round(cursor->y) - grabc->geom.y;
		drift_dragcluster = arg->ui == CurDriftMove;
		if (arg->ui == CurResize) {
			cursor_mode = CurDriftResize;
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "se-resize");
		} else {
			cursor_mode = CurDriftMove;
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "grabbing");
		}
		return;
	}

	if (SCROLLLT(grabc->mon) && grabc->col && !grabc->isfloating
			&& !grabc->isfakefull) {
		/* niri-style direct manipulation: drag reorders the strip and
		 * right-drag resizes the column - the window never floats */
		if (arg->ui == CurMove) {
			cursor_mode = CurDragTile;
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "grabbing");
		} else {
			cursor_mode = CurResizeCol;
			grab_startx = cursor->x;
			grab_wfrac = grabc->col->wfrac;
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "ew-resize");
		}
		return;
	}

	if (grabc->node && !grabc->isfloating && !grabc->isfakefull) {
		/* bsp direct manipulation: drag swaps the window with the tile
		 * under the cursor and right-drag moves the splits it sits
		 * between - neither makes the window float */
		if (arg->ui == CurResize) {
			/* the grab picks the edges the click is nearest, so
			 * dragging away from the window always grows it */
			bsp_grabh = bsp_findsplit(grabc->node, 1,
					cursor->x >= grabc->geom.x + grabc->geom.width / 2.0);
			bsp_grabv = bsp_findsplit(grabc->node, 0,
					cursor->y >= grabc->geom.y + grabc->geom.height / 2.0);
			if (!bsp_grabh && !bsp_grabv)
				return; /* the only window on the workspace */
			bsp_grabhr = bsp_grabh ? bsp_grabh->ratio : 0.5f;
			bsp_grabvr = bsp_grabv ? bsp_grabv->ratio : 0.5f;
			grab_startx = cursor->x;
			grab_starty = cursor->y;
			cursor_mode = CurBSPResize;
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "se-resize");
		} else {
			cursor_mode = CurBSPMove;
			wlr_cursor_set_xcursor(cursor, cursor_mgr, "grabbing");
		}
		return;
	}

	/* Float the window and tell motionnotify to grab it */
	setfloating(grabc, 1);
	switch (cursor_mode = (arg->ui == CurDriftMove ? CurMove : arg->ui)) {
	case CurMove:
		grabcx = (int)round(cursor->x) - grabc->geom.x;
		grabcy = (int)round(cursor->y) - grabc->geom.y;
		wlr_cursor_set_xcursor(cursor, cursor_mgr, "all-scroll");
		break;
	case CurResize:
		/* Doesn't work for X11 output - the next absolute motion event
		 * returns the cursor to where it started */
		wlr_cursor_warp_closest(cursor, NULL,
				grabc->geom.x + grabc->geom.width,
				grabc->geom.y + grabc->geom.height);
		wlr_cursor_set_xcursor(cursor, cursor_mgr, "se-resize");
		break;
	}
}

void
outputmgrapply(struct wl_listener *listener, void *data)
{
	struct wlr_output_configuration_v1 *config = data;
	outputmgrapplyortest(config, 0);
}

void
outputmgrapplyortest(struct wlr_output_configuration_v1 *config, int test)
{
	/*
	 * Called when a client such as wlr-randr requests a change in output
	 * configuration. This is only one way that the layout can be changed,
	 * so any Monitor information should be updated by updatemons() after an
	 * output_layout.change event, not here.
	 */
	struct wlr_output_configuration_head_v1 *config_head;
	int ok = 1;

	wl_list_for_each(config_head, &config->heads, link) {
		struct wlr_output *wlr_output = config_head->state.output;
		Monitor *m = wlr_output->data;
		struct wlr_output_state state;

		/* Ensure displays previously disabled by wlr-output-power-management-v1
		 * are properly handled*/
		m->asleep = 0;

		wlr_output_state_init(&state);
		wlr_output_state_set_enabled(&state, config_head->state.enabled);
		if (!config_head->state.enabled)
			goto apply_or_test;

		if (config_head->state.mode)
			wlr_output_state_set_mode(&state, config_head->state.mode);
		else
			wlr_output_state_set_custom_mode(&state,
					config_head->state.custom_mode.width,
					config_head->state.custom_mode.height,
					config_head->state.custom_mode.refresh);

		wlr_output_state_set_transform(&state, config_head->state.transform);
		wlr_output_state_set_scale(&state, config_head->state.scale);
		wlr_output_state_set_adaptive_sync_enabled(&state,
				config_head->state.adaptive_sync_enabled);

apply_or_test:
		ok &= test ? wlr_output_test_state(wlr_output, &state)
				: wlr_output_commit_state(wlr_output, &state);

		/* Don't move monitors if position wouldn't change. This avoids
		 * wlroots marking the output as manually configured.
		 * wlr_output_layout_add does not like disabled outputs */
		if (!test && wlr_output->enabled && (m->m.x != config_head->state.x || m->m.y != config_head->state.y))
			wlr_output_layout_add(output_layout, wlr_output,
					config_head->state.x, config_head->state.y);

		wlr_output_state_finish(&state);
	}

	if (ok)
		wlr_output_configuration_v1_send_succeeded(config);
	else
		wlr_output_configuration_v1_send_failed(config);
	wlr_output_configuration_v1_destroy(config);

	/* https://codeberg.org/dwl/dwl/issues/577 */
	updatemons(NULL, NULL);
}

void
outputmgrtest(struct wl_listener *listener, void *data)
{
	struct wlr_output_configuration_v1 *config = data;
	outputmgrapplyortest(config, 1);
}

void
pointerfocus(Client *c, struct wlr_surface *surface, double sx, double sy,
		uint32_t time)
{
	struct timespec now;

	/* Following the pointer only on a change of pointer focus leaves the
	 * keyboard stranded whenever focus was dropped without the cursor
	 * moving off the window (a workspace switch onto an empty workspace, a
	 * client that closed elsewhere, a launcher that took the keyboard and
	 * went away): the window under the cursor is already the pointer focus,
	 * so nothing hands it the keyboard back and typing goes nowhere.  When
	 * nothing holds the keyboard at all, moving the mouse gives it to the
	 * window under it.  Focus set from the keyboard is left alone. */
	if (sloppyfocus && time && c && !client_is_unmanaged(c)
			&& (surface != seat->pointer_state.focused_surface
				|| (!exclusive_focus && !seat->drag
					&& !seat->keyboard_state.focused_surface)))
		focusclient(c, 0);

	/* If surface is NULL, clear pointer focus */
	if (!surface) {
		wlr_seat_pointer_notify_clear_focus(seat);
		return;
	}

	if (!time) {
		clock_gettime(CLOCK_MONOTONIC, &now);
		time = now.tv_sec * 1000 + now.tv_nsec / 1000000;
	}

	/* Let the client know that the mouse cursor has entered one
	 * of its surfaces, and make keyboard focus follow if desired.
	 * wlroots makes this a no-op if surface is already focused */
	wlr_seat_pointer_notify_enter(seat, surface, sx, sy);
	wlr_seat_pointer_notify_motion(seat, time, sx, sy);
}

void
powermgrsetmode(struct wl_listener *listener, void *data)
{
	struct wlr_output_power_v1_set_mode_event *event = data;
	Monitor *m = event->output->data;

	if (m)
		screenpower(m, event->mode);
}

/* locked from here on, before the shell has drawn anything: it follows the screen file
 * or its environment, and is replaced if no lock comes in time */
static void
lockengage(int ms)
{
	if (greeter || locked || shell_pid <= 0)
		return;
	locked = 1;
	wlr_scene_node_set_enabled(&locked_bg->node, 1);
	wl_event_source_timer_update(relock_timer, ms);
}

static int
screendark(Monitor *m)
{
	return m->asleep || (screenfade.m == m && !screenfade.on);
}

static void
screenset(Monitor *m, int on)
{
	struct wlr_output_state state = {0};
	Client *c;

	m->gamma_lut_changed = 1; /* Reapply gamma LUT when re-enabling the ouput */
	wlr_output_state_set_enabled(&state, on);
	wlr_output_commit_state(m->wlr_output, &state);

	m->asleep = !on;
	if (m->asleep)
		keyboardforce(m, 0);
	updatemons(NULL, NULL);
	savescreenstate();
	if (!m->asleep)
		return;
	/* nobody sees them: apps stop drawing until arrange() says otherwise at the wake */
	wl_list_for_each(c, &clients, link)
		if (c->mon == m)
			client_set_suspended(c, 1);
	/* dark means locked, so the next wake has no frame of what was open */
	lockengage(5000);
}

static void
screenfadeend(void)
{
	Monitor *m = screenfade.m;

	if (!m)
		return;
	screenfade.m = NULL;
	wlr_scene_node_destroy(&screenfade.rect->node);
	if (!screenfade.on)
		screenset(m, 0);
}

static int
screenfadestep(void *data)
{
	float t = (float)(now_ms() - screenfade.at) / SCREEN_FADE_MS;

	if (!screenfade.m)
		return 0;
	if (t >= 1.0f) {
		screenfadeend();
		return 0;
	}
	t = t * t * (3.0f - 2.0f * t);
	wlr_scene_node_raise_to_top(&screenfade.rect->node);
	wlr_scene_rect_set_color(screenfade.rect, (float[4]){0, 0, 0, screenfade.on ? 1.0f - t : t});
	wl_event_source_timer_update(screenfade.timer, 8);
	return 0;
}

static void
screenpower(Monitor *m, int on)
{
	uint32_t now = now_ms();

	if (screenfade.m == m && screenfade.on != on) {
		/* turned round mid-fade: on from the same darkness */
		screenfade.at = now - (SCREEN_FADE_MS - MIN(SCREEN_FADE_MS, now - screenfade.at));
		screenfade.on = on;
		return;
	}
	if (screenfade.m == m || m->asleep == !on)
		return;
	/* shortcut: one output fades at a time, a phone has one; another's fade ends at once */
	screenfadeend();
	/* no press outlives the screen */
	while (!on && touch_n)
		touchlift(touch_pts[0].id, now, 1);
	if (!animations) {
		screenset(m, on);
		return;
	}
	if (!screenfade.timer)
		screenfade.timer = wl_event_loop_add_timer(event_loop, screenfadestep, NULL);
	screenfade.rect = wlr_scene_rect_create(layers[LyrBlock], m->m.width, m->m.height, (float[4]){0, 0, 0, on});
	wlr_scene_node_set_position(&screenfade.rect->node, m->m.x, m->m.y);
	wlr_scene_node_raise_to_top(&screenfade.rect->node);
	if (on)
		screenset(m, 1);
	screenfade.m = m;
	screenfade.on = on;
	/* after the panel is lit: the fade is not spent while it powers up */
	screenfade.at = now_ms();
	wl_event_source_timer_update(screenfade.timer, 8);
}

void
quit(const Arg *arg)
{
	wl_display_terminate(dpy);
}

void
rendermon(struct wl_listener *listener, void *data)
{
	/* This function is called every time an output is ready to display a frame,
	 * generally at the output's refresh rate (e.g. 60Hz). */
	Monitor *m = wl_container_of(listener, m, frame);
	Client *c;
	struct wlr_output_state pending = {0};
	struct timespec now;
	int animpending = 0, pointerrefresh = 0, skipframe = 0, relayout = 0;
	int blockwait = 0;

	/* a mirror repaints the scene where its source is; the source's frame
	 * drives every animation */
	if (m->mirroring) {
		wlr_scene_output_commit(m->scene_output, NULL);
		clock_gettime(CLOCK_MONOTONIC, &now);
		wlr_scene_output_send_frame_done(m->scene_output, &now);
		return;
	}

	/* Render if no XDG clients have an outstanding resize and are visible on
	 * this monitor.  A client that never acks must not hold the output
	 * hostage: past RESIZEWAIT it is drawn at whatever size it has, or the
	 * whole screen would stay frozen on the last frame - with an animation
	 * caught halfway, windows parked off screen and nothing focusable. */
	wl_list_for_each(c, &clients, link) {
		if (c->resize && !c->isfloating && client_is_rendered_on_mon(c, m)
				&& !client_is_stopped(c)) {
			uint32_t waited = now_ms() - c->resizeat;
			if (waited >= RESIZEWAIT)
				continue;
			skipframe = 1;
			blockwait = MAX(blockwait, (int)(RESIZEWAIT - waited));
		}
	}

	/* Animations advance only on frames that actually render, and only
	 * schedule further frames while one is active. */
	/* The overview clones the live buffers, so the camera zoom has to be on
	 * them before anything is built from them this frame. */
	driftapply(m);
	if (!skipframe)
		animpending |= wsdragframe(m);

	if (overview_visible && overview_dirty && !skipframe) {
		overview_dirty = 0;
		overviewbuild();
	}
	if (animations || overview_visible) {
		uint32_t t_now = now_ms();
		float dt = m->lastanimtick && t_now > m->lastanimtick
				? (float)(t_now - m->lastanimtick) : 0.0f;
		if (dt > 34.0f)
			dt = 34.0f;
		m->lastanimtick = t_now;
		if (animations) {
			wl_list_for_each(c, &clients, link) {
				float e;
				int duration, targetx, targety;
				if (c->mon != m || !c->anim.active)
					continue;
				animpending = 1;
				if (skipframe)
					continue;
				/* the cards follow a window that is on the move (the
				 * strip panning to a column, a retile), so the
				 * overview is redrawn every frame it runs */
				overview_dirty |= overview_visible;
				duration = c->anim.workspace && c->anim.swipe
						? c->anim.swipe
						: c->anim.workspace
						? MAX(180, animation_duration * 5 / 4)
						: c->anim.fadein
						? MAX(60, animation_duration_open)
						: animation_duration;
				targetx = c->anim.workspace ? c->anim.to.x : c->geom.x;
				targety = c->anim.workspace ? c->anim.to.y : c->geom.y;
				c->anim.t += duration > 0 ? dt / (float)duration : 1.0f;
				if (c->anim.t >= 1.0f) {
					c->anim.active = 0;
					if (c->anim.zoom) {
						c->anim.zoom = 0;
						clientunscale(c);
					}
					clientplace(c, c->anim.hide ? c->geom.x : targetx,
							c->anim.hide ? c->geom.y : targety);
					if (c->anim.hide) {
						/* the workspace can have come back while this
						 * ran: hiding it then would leave a window of
						 * the current workspace invisible and unfocusable */
						if (VISIBLEON(c, m)) {
							relayout = 1;
						} else {
							wlr_scene_node_set_enabled(&c->scene->node, 0);
							pointerrefresh = 1;
						}
					}
					c->anim.workspace = 0;
					c->anim.hide = 0;
					c->anim.swipe = 0;
					if (c->anim.fadein) {
						c->anim.fadein = 0;
						if (c->surfbuf)
							wlr_scene_buffer_set_opacity(c->surfbuf, clientopacity(c));
					}
					continue;
				}
				e = c->anim.workspace && c->anim.swipe
						? 1.0f - powf(1.0f - c->anim.t, 3.0f)
						: c->anim.workspace
						? c->anim.t * c->anim.t * (3.0f - 2.0f * c->anim.t)
						: c->anim.fadein
						? animease(animation_curve_open, c->anim.t)
						: 1.0f - powf(2.0f, -10.0f * c->anim.t);
				if (c->anim.zoom) {
					/* grow the whole frame from where it started */
					float z = c->anim.zoomfrom + (1.0f - c->anim.zoomfrom) * e;
					/* position first: the scale pass crops against the
					 * monitor from where the frame is */
					wlr_scene_node_set_position(&c->scene->node,
							c->anim.from.x + (int)roundf((targetx - c->anim.from.x) * e),
							c->anim.from.y + (int)roundf((targety - c->anim.from.y) * e));
					clientscale(c, z);
				} else {
					clientplace(c,
							c->anim.from.x + (int)((float)(targetx - c->anim.from.x) * e),
							c->anim.from.y + (int)((float)(targety - c->anim.from.y) * e));
				}
				if (c->anim.fadein && c->surfbuf)
					wlr_scene_buffer_set_opacity(c->surfbuf,
							e * clientopacity(c));
			}
			if (!skipframe) {
				animpending |= layeranimadvance(m, dt);
				animpending |= closeanimadvance(m, dt);
			}
			/* a hide that finished on a window the current workspace owns
			 * again: let arrange() settle visibility from the real state */
			if (relayout)
				arrange(m);
		}
		if (pointerrefresh)
			motionnotify(0, NULL, 0, 0, 0, 0);
		if (overviewadvance(m, dt)) {
			overviewbuild();
			overview_dirty = 0;
			animpending |= m->overview_animating;
		} else if (overview_visible && overview_dirty) {
			overviewbuild();
			overview_dirty = 0;
		}
	}
	overviewfinish();

	if (skipframe)
		goto skip;

	wlr_scene_output_commit(m->scene_output, NULL);

skip:
	/* Let clients know a frame has been rendered */
	clock_gettime(CLOCK_MONOTONIC, &now);
	wlr_scene_output_send_frame_done(m->scene_output, &now);
	overviewframes(m, &now);
	wlr_output_state_finish(&pending);
	/* scheduling a frame without a commit fires immediately and would spin
	 * the event loop; while a resize is pending the client's next commit
	 * damages the scene and restarts the animation on its own.  If it never
	 * commits, the timer below brings the output back once the wait is up. */
	if (animpending && !skipframe)
		wlr_output_schedule_frame(m->wlr_output);
	else if (skipframe && m->unblock)
		wl_event_source_timer_update(m->unblock, MAX(1, blockwait));
}

void
requestdecorationmode(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, set_decoration_mode);
	if (c->surface.xdg->initialized)
		wlr_xdg_toplevel_decoration_v1_set_mode(c->decoration,
				WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
}

void
requeststartdrag(struct wl_listener *listener, void *data)
{
	struct wlr_seat_request_start_drag_event *event = data;

	if (wlr_seat_validate_pointer_grab_serial(seat, event->origin,
			event->serial))
		wlr_seat_start_pointer_drag(seat, event->drag, event->serial);
	else
		wlr_data_source_destroy(event->drag->source);
}

void
requestmonstate(struct wl_listener *listener, void *data)
{
	struct wlr_output_event_request_state *event = data;
	/* the phone window keeps its shape whatever the desktop's tiling asks for */
	if (mouse_finger)
		return;
	wlr_output_commit_state(event->output, event->state);
	updatemons(NULL, NULL);
}

/* A window wider than its box is drawn smaller, uniformly, and asked for the
 * height that then fills the box.  False leaves it at scale 1. */
static int
clientfit(Client *c)
{
	int w = c->geom.width - 2 * (int)c->bw, h = c->geom.height - 2 * (int)c->bw, minw;

	if (c->type != XDGShell || w <= 0 || h <= 0)
		return 0;
	/* rotated or tiled anew: ask again what it really needs */
	if (c->fitbox != w)
		c->minw = 0;
	c->fitbox = w;
	minw = MAX(c->minw, c->surface.xdg->toplevel->current.min_width);
	c->fit = minw > w ? (double)w / minw : 1.0;
	c->fitw = c->fit < 1.0 ? minw : w;
	c->fith = c->fit < 1.0 ? (int)ceil(h / c->fit) : h;
	return c->fit < 1.0;
}

/* a client that did not declare its minimum shows it by staying wider than asked */
static void
clientfitlearn(Client *c)
{
	struct wlr_box geo;

	if (c->resize || c->type != XDGShell || !client_surface(c)->mapped || !c->mon
			|| c->isfloating || !c->fitbox || (DRIFTLT(c->mon) && c->oncanvas))
		return;
	client_get_geometry(c, &geo);
	/* shortcut: right after a configure a wider commit is ignored as lag, so a client that then never commits again stays cropped, add a timer if one shows up */
	if (geo.width <= c->fitw || now_ms() - c->resizeat < 100)
		return;
	c->minw = geo.width;
	resize(c, c->geom, 0);
}

void
resize(Client *c, struct wlr_box geo, int interact)
{
	struct wlr_box *bbox;
	struct wlr_box clip;
	int oldx = c->geom.x, oldy = c->geom.y;
	int drifted, fitted;
	uint32_t serial;

	if (!c->mon || !client_surface(c)->mapped)
		return;

	bbox = interact ? &sgeom : &c->mon->w;
	drifted = DRIFTLT(c->mon) && c->oncanvas && !c->isfloating && !interact
			&& !c->isfullscreen && !c->isfakefull;

	client_set_bounds(c, geo.width, geo.height);
	c->geom = geo;
	if ((SCROLLLT(c->mon) || drifted) && !c->isfloating && !interact) {
		/* scroll columns and canvas windows legitimately extend past the
		 * viewport, so only enforce the minimum size */
		c->geom.width = MAX(1 + 2 * (int)c->bw, c->geom.width);
		c->geom.height = MAX(1 + 2 * (int)c->bw, c->geom.height);
	} else {
		applybounds(c, bbox);
	}

	/* animate position changes of visible clients */
	if (animations && !interact && !c->anim.fadein
			&& (c->geom.x != oldx || c->geom.y != oldy)
			&& VISIBLEON(c, c->mon)) {
		c->anim.from.x = c->scene->node.x;
		c->anim.from.y = c->scene->node.y;
		c->anim.workspace = 0;
		c->anim.hide = 0;
		c->anim.active = 1;
		c->anim.t = 0;
		animkick(c->mon);
	}

	/* Update scene-graph, including the border */
	if (!c->anim.active)
		wlr_scene_node_set_position(&c->scene->node, c->geom.x, c->geom.y);
	wlr_scene_node_set_position(&c->scene_surface->node, c->bw, c->bw);

	/* a window that left the canvas keeps its scaled buffers until it next
	 * commits, which is long enough to click on the wrong place */
	fitted = !drifted && !interact && clientfit(c);
	if (!drifted && !fitted)
		c->fit = 1.0;
	if (!drifted && !fitted && c->bufscale != 1.0 && !c->anim.active)
		clientunscale(c);

	/* this is a no-op if size hasn't changed */
	if (drifted) {
		/* the client is sized in canvas pixels; the camera zoom is applied
		 * to its buffers instead, so it never sees a resize */
		serial = client_set_size(c,
				MAX(1, c->canvas.width - 2 * (int)c->bw),
				MAX(1, c->canvas.height - 2 * (int)c->bw));
	} else if (fitted) {
		serial = client_set_size(c, c->fitw, c->fith);
	} else {
		serial = client_set_size(c, c->geom.width - 2 * c->bw,
				c->geom.height - 2 * c->bw);
	}
	if (serial && serial != c->resize)
		c->resizeat = now_ms();
	c->resize = serial;
	client_get_clip(c, &clip);
	if (drifted) {
		clip.width = MAX(1, c->canvas.width - 2 * (int)c->bw);
		clip.height = MAX(1, c->canvas.height - 2 * (int)c->bw);
	} else if (fitted) {
		clip.width = c->fitw;
		clip.height = c->fith;
	}
	wlr_scene_subsurface_tree_set_clip(&c->scene_surface->node, &clip);
	if (fitted)
		driftscaleclient(c, c->fit);
	if (drifted && (driftz(c->mon, c->ws) != 1.0 || c->mon->driftscaled))
		driftscaleclient(c, driftz(c->mon, c->ws));
	/* the frame and the crop to the monitor, for whatever is not scaled */
	clientclip(c);
}

static int xsatlisten(int fd, uint32_t mask, void *data);
/* unistd.h hides it under _POSIX_C_SOURCE; same prototype in glibc and musl */
long syscall(long number, ...);

static void
xsatwatch(void)
{
	int i;

	for (i = 0; i < 2; i++)
		xsat_src[i] = wl_event_loop_add_fd(event_loop, xsat_fd[i], WL_EVENT_READABLE, xsatlisten, NULL);
}

static void
xsatcleanup(void)
{
	char p[64];
	int i;

	if (xsat_pid > 0)
		kill(-xsat_pid, SIGTERM);
	xsat_pid = 0;
	if (xsat_exit)
		wl_event_source_remove(xsat_exit);
	xsat_exit = NULL;
	for (i = 0; i < 2; i++) {
		if (xsat_src[i])
			wl_event_source_remove(xsat_src[i]);
		if (xsat_fd[i] >= 0)
			close(xsat_fd[i]);
		xsat_src[i] = NULL;
		xsat_fd[i] = -1;
	}
	if (xsat_disp < 0)
		return;
	snprintf(p, sizeof(p), "/tmp/.X11-unix/X%d", xsat_disp);
	unlink(p);
	snprintf(p, sizeof(p), "/tmp/.X%d-lock", xsat_disp);
	unlink(p);
	xsat_disp = -1;
}

static int
xsatexited(int fd, uint32_t mask, void *data)
{
	wl_event_source_remove(xsat_exit);
	xsat_exit = NULL;
	close(fd);
	xsat_pid = 0;
	/* one that dies at once would be started again for the same waiting client forever */
	if (now_ms() - xsat_started < 2000) {
		wlr_log(WLR_ERROR, "xwayland-satellite exited at once: X11 apps are off until restart");
		xsatcleanup();
		return 0;
	}
	wlr_log(WLR_INFO, "xwayland-satellite exited: started again on the next X11 client");
	xsatwatch();
	return 0;
}

/* the first X11 client is waiting: hand both listening sockets to a new satellite */
static int
xsatlisten(int fd, uint32_t mask, void *data)
{
	char disp[16], a[2][12];
	int i, pidfd;

	for (i = 0; i < 2; i++) {
		wl_event_source_remove(xsat_src[i]);
		xsat_src[i] = NULL;
		snprintf(a[i], sizeof(a[i]), "%d", xsat_fd[i]);
	}
	snprintf(disp, sizeof(disp), ":%d", xsat_disp);
	xsat_started = now_ms();
	if ((xsat_pid = fork()) == 0) {
		dup2(STDERR_FILENO, STDOUT_FILENO);
		setsid();
		for (i = 0; i < 2; i++)
			fcntl(xsat_fd[i], F_SETFD, 0);
		execlp("xwayland-satellite", "xwayland-satellite", disp,
				"-listenfd", a[0], "-listenfd", a[1], NULL);
		childdie("execlp", "xwayland-satellite");
	}
	wlr_log(WLR_INFO, "X11 client on %s: started xwayland-satellite, pid %d", disp, xsat_pid);
	/* the pidfd turns readable when it exits, SIGCHLD only reaps */
	pidfd = xsat_pid > 0 ? (int)syscall(SYS_pidfd_open, xsat_pid, 0) : -1;
	if (pidfd < 0) {
		wlr_log(WLR_ERROR, "xwayland-satellite did not start: X11 apps are off until restart");
		xsatcleanup();
		return 0;
	}
	xsat_exit = wl_event_loop_add_fd(event_loop, pidfd, WL_EVENT_READABLE, xsatexited, NULL);
	return 0;
}

static int
xsatbind(int fd, const char *path, int abstract)
{
	struct sockaddr_un a = {.sun_family = AF_UNIX};
	socklen_t len;

	snprintf(a.sun_path + abstract, sizeof(a.sun_path) - 1, "%s", path);
	len = offsetof(struct sockaddr_un, sun_path) + abstract + strlen(path) + !abstract;
	return bind(fd, (struct sockaddr *)&a, len) == 0 && listen(fd, 16) == 0 ? 0 : -1;
}

/* the X socket opens now, the X server only when a client connects (as niri does) */
static void
xsatsetup(void)
{
	char lock[32], path[64], *p, *dir, *save;
	int n, fd, found = 0;
	FILE *f;

	if (!xwayland_on)
		return;
	if ((p = getenv("PATH")) && (p = strdup(p))) {
		for (dir = strtok_r(p, ":", &save); dir && !found; dir = strtok_r(NULL, ":", &save)) {
			snprintf(path, sizeof(path), "%s/xwayland-satellite", dir);
			found = access(path, X_OK) == 0;
		}
		free(p);
	}
	if (!found) {
		wlr_log(WLR_INFO, "no xwayland-satellite on PATH: X11 apps are off");
		return;
	}
	if (mkdir("/tmp/.X11-unix", 01777) == 0)
		chmod("/tmp/.X11-unix", 01777);
	/* :0 is left to a real X server */
	for (n = 1; n < 64; n++) {
		snprintf(lock, sizeof(lock), "/tmp/.X%d-lock", n);
		if ((fd = open(lock, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0444)) < 0) {
			int owner = 0;
			/* a lock whose server is gone is free: once, then the next number */
			if (errno == EEXIST && (f = fopen(lock, "r"))) {
				if (fscanf(f, "%d", &owner) != 1)
					owner = 0;
				fclose(f);
				if (owner > 0 && kill(owner, 0) < 0 && errno == ESRCH && unlink(lock) == 0)
					fd = open(lock, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0444);
			}
			if (fd < 0)
				continue;
		}
		dprintf(fd, "%10d\n", (int)getpid());
		close(fd);
		snprintf(path, sizeof(path), "/tmp/.X11-unix/X%d", n);
		xsat_fd[0] = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
		xsat_fd[1] = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
		unlink(path);
		xsat_disp = n;
		if (xsat_fd[0] >= 0 && xsat_fd[1] >= 0 && xsatbind(xsat_fd[0], path, 1) == 0
				&& xsatbind(xsat_fd[1], path, 0) == 0)
			break;
		/* the abstract name is taken by a server this lock check cannot see */
		xsatcleanup();
	}
	if (xsat_disp < 0) {
		wlr_log(WLR_ERROR, "no free X display: X11 apps are off");
		return;
	}
	snprintf(path, sizeof(path), ":%d", xsat_disp);
	setenv("DISPLAY", path, 1);
	wlr_log(WLR_INFO, "X11 apps on DISPLAY %s through xwayland-satellite, started on the first client", path);
	xsatwatch();
}

void
run(char *startup_cmd)
{
	/* Add a Unix socket to the Wayland display. */
	const char *socket = wl_display_add_socket_auto(dpy);
	if (!socket)
		die("startup: display_add_socket_auto");
	setenv("WAYLAND_DISPLAY", socket, 1);
	xsatsetup();
#ifdef HYPR
	hyprsetup(socket);
#endif
	wlr_log(WLR_INFO, "Running compositor on wayland display '%s'", socket);

	/* Start the backend. This will enumerate outputs and inputs, become the DRM
	 * master, etc */
	if (!wlr_backend_start(backend))
		die("startup: backend_start");

	/* a config that was already broken at login is worth saying out loud */
	cfgerrorshow();

	/* Now that the socket exists and the backend is started, run the startup command */
	if (startup_cmd) {
		int piperw[2];
		if (pipe(piperw) < 0)
			die("startup: pipe:");
		if ((child_pid = fork()) < 0)
			die("startup: fork:");
		if (child_pid == 0) {
			setsid();
			dup2(piperw[0], STDIN_FILENO);
			close(piperw[0]);
			close(piperw[1]);
			execl("/bin/sh", "/bin/sh", "-c", startup_cmd, NULL);
			childdie("startup execl", "/bin/sh");
		}
		dup2(piperw[1], STDOUT_FILENO);
		close(piperw[1]);
		close(piperw[0]);
	}

	/* Mark stdout as non-blocking to avoid the startup script
	 * causing phonegluewc to freeze when a user neither closes stdin
	 * nor consumes standard input in his startup script */

	if (fd_set_nonblock(STDOUT_FILENO) < 0)
		close(STDOUT_FILENO);

	/* let bus-activated services (xdg-desktop-portal) see the compositor */
	{
		Arg a = {.v = (const char *[]){ "/bin/sh", "-c",
			"command -v dbus-update-activation-environment >/dev/null 2>&1 "
			"&& exec dbus-update-activation-environment --systemd --all", NULL }};
		spawn(&a);
	}

	/* the session can open on the overview, so the first thing seen is
	 * every workspace and the dash rather than an empty desktop */
	if (start_in_overview) {
		struct wl_event_source *t = wl_event_loop_add_timer(
				wl_display_get_event_loop(dpy), startoverview, NULL);
		wl_event_source_timer_update(t, 300);
	}

	/* Run the autostart commands from the config file */
	{
		size_t i;
		for (i = 0; i < nautostarts; i++) {
			Arg a = {.v = (const char *[]){ "/bin/sh", "-c", autostarts[i], NULL }};
			spawn(&a);
		}
	}
	mousefingersetup();
	savepillstate(); /* exists before the shell starts watching it */
	savescreenstate();
	saveseq("menu", menuseq);
	saveseq("edit", editseq);
	saveseq("page-prev", pageseq[0]);
	saveseq("page-next", pageseq[1]);
	/* the tray, the home screen and the app menu; set it empty for no shell */
	{
		const char *lockstart;

		setenv("QT_QPA_PLATFORM", "wayland", 0);
		setenv("QT_IM_MODULE", "wayland", 1);
		greeter = getenv("PHONEGLUEWC_GREETER") != NULL;
		buttonsend("none");
		relock_timer = wl_event_loop_add_timer(event_loop, relock, NULL);
		/* a real session opens locked, like a phone just switched on; qs is slow at boot */
		if ((lockstart = getenv("PHONEGLUEWC_LOCK_START")) && *lockstart && !greeter)
			setenv("PHONEGLUEWC_RELOCK", "1", 1);
		spawnshell();
		if (getenv("PHONEGLUEWC_RELOCK")) {
			unsetenv("PHONEGLUEWC_RELOCK");
			lockengage(20000);
		}
	}
	pill_hold = wl_event_loop_add_timer(event_loop, pillhold, NULL);
	home_hold = wl_event_loop_add_timer(event_loop, homehold, NULL);
	bar_slide = wl_event_loop_add_timer(event_loop, barslide, NULL);
	bar_timer = wl_event_loop_add_timer(event_loop, barexpire, NULL);
	topcolor_timer = wl_event_loop_add_timer(event_loop, topcolorsample, NULL);
	/* a colour left from the last session must not tint the first home screen */
	topcolorsoon();
	rot_timer = wl_event_loop_add_timer(event_loop, rotupdate, NULL);
	rot_fade_timer = wl_event_loop_add_timer(event_loop, rotfadestep, NULL);
	/* the file tells the shell this desktop can turn, its tile shows from then on */
	rotwrite("orientation", transformname(rot));
	{
		const char *sensor = getenv("PHONEGLUEWC_SENSOR");
		Arg a = {.v = (const char *[]){ sensor ? sensor : "phonegluewc-sensor", NULL }};

		if (!sensor || *sensor) {
			spawn(&a);
			sensor_pid = spawned_pid;
		}
	}
	/* the on-screen keyboard; set it empty for none */
	{
		const char *kbd = getenv("PHONEGLUEWC_KEYBOARD");
		Arg a = {.v = (const char *[]){ kbd ? kbd : "phonekbd", NULL }};

		if (!kbd || *kbd) {
			spawn(&a);
			keyboard_pid = spawned_pid;
		}
	}

	/* At this point the outputs are initialized, choose initial selmon based on
	 * cursor position, and set default cursor image */
	selmon = xytomon(cursor->x, cursor->y);

	/* TODO hack to get cursor to display in its initial location (100, 100)
	 * instead of (0, 0) and then jumping. Still may not be fully
	 * initialized, as the image/coordinates are not transformed for the
	 * monitor when displayed here */
	wlr_cursor_warp_closest(cursor, NULL, cursor->x, cursor->y);
	wlr_cursor_set_xcursor(cursor, cursor_mgr, "default");

	/* Run the Wayland event loop. This does not return until you exit the
	 * compositor. Starting the backend rigged up all of the necessary event
	 * loop configuration to listen to libinput events, DRM events, generate
	 * frame events at the refresh rate, and so on. */
	wl_display_run(dpy);
}

void
setcursor(struct wl_listener *listener, void *data)
{
	/* This event is raised by the seat when a client provides a cursor image */
	struct wlr_seat_pointer_request_set_cursor_event *event = data;
	/* If we're "grabbing" the cursor, don't use the client's image, we will
	 * restore it after "grabbing" sending a leave event, followed by a enter
	 * event, which will result in the client requesting set the cursor surface */
	if (cursor_mode != CurNormal && cursor_mode != CurPressed)
		return;
	/* This can be sent by any client, so we check to make sure this one
	 * actually has pointer focus first. If so, we can tell the cursor to
	 * use the provided surface as the cursor image. It will set the
	 * hardware cursor on the output that it's currently on and continue to
	 * do so as the cursor moves between outputs. */
	if (!mouse_finger && event->seat_client == seat->pointer_state.focused_client)
		wlr_cursor_unset_image(cursor);
}

void
setcursorshape(struct wl_listener *listener, void *data)
{
	struct wlr_cursor_shape_manager_v1_request_set_shape_event *event = data;
	if (cursor_mode != CurNormal && cursor_mode != CurPressed)
		return;
	/* This can be sent by any client, so we check to make sure this one
	 * actually has pointer focus first. If so, we can tell the cursor to
	 * use the provided cursor shape. */
	if (event->seat_client == seat->pointer_state.focused_client)
		wlr_cursor_set_xcursor(cursor, cursor_mgr,
				wlr_cursor_shape_v1_name(event->shape));
}

void
setfloating(Client *c, int floating)
{
	Client *p = client_get_parent(c);
	c->isfloating = floating;
	if (!c->mon || !client_surface(c)->mapped)
		return;
	if (DRIFTLT(c->mon) && c->oncanvas && !floating && c->geom.width > 0) {
		/* dropped back onto the canvas: keep it where the user left it */
		double z = driftz(c->mon, c->ws);
		int bw = 2 * (int)c->bw;
		c->canvas.width = MAX(1 + bw, (int)round((c->geom.width - bw) / z) + bw);
		c->canvas.height = MAX(1 + bw, (int)round((c->geom.height - bw) / z) + bw);
		c->canvas.x = (int)round((c->geom.x - c->mon->w.x) / z + c->mon->camx[c->ws]);
		c->canvas.y = (int)round((c->geom.y - c->mon->w.y) / z + c->mon->camy[c->ws]);
		c->canvassized = 1;
	}
	wlr_scene_node_reparent(&c->scene->node, layers[c->isfullscreen ||
			(p && p->isfullscreen) ? LyrFS
			: c->isfloating ? LyrFloat : LyrTile]);
	arrange(c->mon);
}

void
setfullscreen(Client *c, int fullscreen)
{
	c->isfullscreen = fullscreen;
	if (c->ftl)
		wlr_foreign_toplevel_handle_v1_set_fullscreen(c->ftl, fullscreen);
	if (fullscreen)
		c->isfakefull = 0;
	if (!c->mon || !client_surface(c)->mapped)
		return;
	c->bw = (fullscreen || decorhidden) ? 0 : borderpx;
	client_set_fullscreen(c, fullscreen);
	applyeffects(c);
	wlr_scene_node_reparent(&c->scene->node, layers[c->isfullscreen
			? LyrFS : c->isfloating ? LyrFloat : LyrTile]);

	if (fullscreen) {
		c->prev = c->geom;
		resize(c, c->mon->m, 0);
	} else {
		/* restore previous size instead of arrange for floating windows since
		 * client positions are set by the user and cannot be recalculated */
		resize(c, c->prev, 0);
	}
	arrange(c->mon);
}

void
setmon(Client *c, Monitor *m, int ws)
{
	Monitor *oldmon = c->mon;

	/* nothing lives on a mirror */
	if (m && m->mirroring)
		m = m->mirror_src ? m->mirror_src : selmon;
	if (oldmon == m)
		return;
	if (oldmon) {
		animstop(oldmon);
		detachclient(c);
	}
	if (c->ftl && oldmon)
		wlr_foreign_toplevel_handle_v1_output_leave(c->ftl, oldmon->wlr_output);
	if (c->ftl && m)
		wlr_foreign_toplevel_handle_v1_output_enter(c->ftl, m->wlr_output);
	c->mon = m;
	c->prev = c->geom;

	/* Scene graph sends surface leave/enter events on move and resize */
	if (oldmon)
		arrange(oldmon);
	if (m) {
		attachclient(m, (ws >= 0 && ws < NUMWS) ? (unsigned int)ws : m->ws, c);
		/* Make sure window actually overlaps with the monitor */
		resize(c, c->geom, 0);
		setfullscreen(c, c->isfullscreen); /* This will call arrange(c->mon) */
		setfloating(c, c->isfloating);
	}
	focusclient(focustop(selmon), 1);
}

void
setpsel(struct wl_listener *listener, void *data)
{
	/* This event is raised by the seat when a client wants to set the selection,
	 * usually when the user copies something. wlroots allows compositors to
	 * ignore such requests if they so choose, but in phonegluewc we always honor them
	 */
	struct wlr_seat_request_set_primary_selection_event *event = data;
	wlr_seat_set_primary_selection(seat, event->source, event->serial);
}

void
setsel(struct wl_listener *listener, void *data)
{
	/* This event is raised by the seat when a client wants to set the selection,
	 * usually when the user copies something. wlroots allows compositors to
	 * ignore such requests if they so choose, but in phonegluewc we always honor them
	 */
	struct wlr_seat_request_set_selection_event *event = data;
	wlr_seat_set_selection(seat, event->source, event->serial);
}

static char *
cfgtrim(char *s)
{
	char *e;
	while (*s == ' ' || *s == '\t')
		s++;
	e = s + strlen(s);
	while (e > s && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\n' || e[-1] == '\r'))
		*--e = '\0';
	return s;
}

static int
cfgcolor(const char *s, float out[4])
{
	unsigned int v;
	if (sscanf(s, "%x", &v) != 1)
		return 0;
	if (strlen(s) <= 6)
		v = (v << 8) | 0xff;
	out[0] = ((v >> 24) & 0xff) / 255.0f;
	out[1] = ((v >> 16) & 0xff) / 255.0f;
	out[2] = ((v >> 8) & 0xff) / 255.0f;
	out[3] = (v & 0xff) / 255.0f;
	return 1;
}

static int
cfganimtype(const char *s)
{
	if (!strcmp(s, "zoom") || !strcmp(s, "pop"))
		return AnimZoom;
	if (!strcmp(s, "slide"))
		return AnimSlide;
	if (!strcmp(s, "fade"))
		return AnimFade;
	if (!strcmp(s, "none") || !strcmp(s, "false"))
		return AnimNone;
	cfgerror("unknown animation type '%s'", s);
	return AnimZoom;
}

static int
cfgcurve(const char *s, float out[4])
{
	/* x1,y1,x2,y2 - the x values are clamped, as CSS does, so the curve
	 * stays a function of time; the y values may overshoot on purpose */
	float c[4];

	if (sscanf(s, "%f , %f , %f , %f", &c[0], &c[1], &c[2], &c[3]) != 4) {
		cfgerror("bad curve '%s', want x1,y1,x2,y2", s);
		return 0;
	}
	out[0] = MIN(1.0f, MAX(0.0f, c[0]));
	out[1] = c[1];
	out[2] = MIN(1.0f, MAX(0.0f, c[2]));
	out[3] = c[3];
	return 1;
}

static int
cfgbindcombo(char *combo, uint32_t *mods, xkb_keysym_t *sym)
{
	char *tok, *save = NULL, *last = NULL;
	*mods = 0;
	for (tok = strtok_r(combo, "+", &save); tok; tok = strtok_r(NULL, "+", &save)) {
		if (last) {
			if (!strcmp(last, "mod") || !strcmp(last, "super") || !strcmp(last, "logo"))
				*mods |= WLR_MODIFIER_LOGO;
			else if (!strcmp(last, "shift"))
				*mods |= WLR_MODIFIER_SHIFT;
			else if (!strcmp(last, "ctrl") || !strcmp(last, "control"))
				*mods |= WLR_MODIFIER_CTRL;
			else if (!strcmp(last, "alt"))
				*mods |= WLR_MODIFIER_ALT;
			else
				return 0;
		}
		last = tok;
	}
	if (!last)
		return 0;
	*sym = xkb_keysym_from_name(last, XKB_KEYSYM_NO_FLAGS);
	if (*sym == XKB_KEY_NoSymbol)
		*sym = xkb_keysym_from_name(last, XKB_KEYSYM_CASE_INSENSITIVE);
	return *sym != XKB_KEY_NoSymbol;
}

static uint32_t
macrobutton(const char *name)
{
	if (!strcmp(name, "right"))
		return BTN_RIGHT;
	if (!strcmp(name, "middle"))
		return BTN_MIDDLE;
	return BTN_LEFT;
}

static void
macroaddstep(Macro *m, MacroStep step)
{
	if (!(m->steps = realloc(m->steps, (m->nsteps + 1) * sizeof(*m->steps))))
		die("config: realloc:");
	m->steps[m->nsteps++] = step;
}

static void
cfgmacro(char *value)
{
	Macro m = { .type = MacroSequence, .mode = MacroHold, .interval = 80,
		.press_ms = 10, .cps = 10, .button = BTN_LEFT };
	char *tok, *eq, *save = NULL, *sequence = NULL;
	char trigger[96] = {0};
	size_t i;

	if (!(tok = strtok_r(value, " \t", &save))) {
		cfgerror("macro needs a name");
		return;
	}
	snprintf(m.name, sizeof m.name, "%s", tok);
	while ((tok = strtok_r(NULL, " \t", &save))) {
		if (!(eq = strchr(tok, '='))) {
			cfgerror("macro %s: expected key=value, got '%s'", m.name, tok);
			goto bad;
		}
		*eq++ = '\0';
		if (!strcmp(tok, "trigger"))
			snprintf(trigger, sizeof trigger, "%s", eq);
		else if (!strcmp(tok, "type"))
			m.type = !strcmp(eq, "click") ? MacroClick : MacroSequence;
		else if (!strcmp(tok, "mode"))
			m.mode = !strcmp(eq, "once") ? MacroOnce
					: !strcmp(eq, "toggle") ? MacroToggle : MacroHold;
		else if (!strcmp(tok, "button"))
			m.button = macrobutton(eq);
		else if (!strcmp(tok, "cps"))
			m.cps = MIN(200, MAX(1, atoi(eq)));
		else if (!strcmp(tok, "interval"))
			m.interval = MIN(600000, MAX(0, atoi(eq)));
		else if (!strcmp(tok, "press"))
			m.press_ms = MIN(1000, MAX(1, atoi(eq)));
		else if (!strcmp(tok, "sequence"))
			sequence = strdup(eq);
		else {
			cfgerror("macro %s: unknown option '%s'", m.name, tok);
			goto bad;
		}
	}
	if (!*trigger || !cfgbindcombo(trigger, &m.trigger_mods, &m.trigger_sym)) {
		cfgerror("macro %s: bad or missing trigger", m.name);
		goto bad;
	}
	if (m.type == MacroSequence) {
		char *part, *ssave = NULL;
		if (!sequence || !*sequence) {
			cfgerror("macro %s: sequence is empty", m.name);
			goto bad;
		}
		for (part = strtok_r(sequence, ",", &ssave); part;
				part = strtok_r(NULL, ",", &ssave)) {
			MacroStep step = {0};
			char combo[96];
			part = cfgtrim(part);
			if (!strncmp(part, "wait:", 5)) {
				step.type = MacroStepWait;
				step.delay = MIN(600000, MAX(1, atoi(part + 5)));
			} else if (!strncmp(part, "click:", 6)) {
				step.type = MacroStepClick;
				step.button = macrobutton(part + 6);
			} else {
				step.type = MacroStepKey;
				snprintf(combo, sizeof combo, "%s", part);
				if (!cfgbindcombo(combo, &step.mods, &step.keysym)) {
					cfgerror("macro %s: bad step '%s'", m.name, part);
					goto bad;
				}
			}
			macroaddstep(&m, step);
		}
	}
	for (i = 0; i < nmacros; i++) {
		if (!strcmp(macros[i].name, m.name)) {
			cfgerror("duplicate macro name '%s'", m.name);
			goto bad;
		}
		if (macros[i].trigger_mods == m.trigger_mods
				&& xkb_keysym_to_lower(macros[i].trigger_sym)
				== xkb_keysym_to_lower(m.trigger_sym)) {
			cfgerror("macro %s: trigger is already used by %s", m.name,
					macros[i].name);
			goto bad;
		}
	}
	if (!(macros = realloc(macros, (nmacros + 1) * sizeof(*macros))))
		die("config: realloc:");
	macros[nmacros++] = m;
	free(sequence);
	return;
bad:
	free(sequence);
	free(m.steps);
}

static uint32_t
macromodmask(struct xkb_keymap *keymap, uint32_t mods)
{
	static const struct { uint32_t bit; const char *name; } map[] = {
		{ WLR_MODIFIER_SHIFT, XKB_MOD_NAME_SHIFT },
		{ WLR_MODIFIER_CTRL, XKB_MOD_NAME_CTRL },
		{ WLR_MODIFIER_ALT, XKB_MOD_NAME_ALT },
		{ WLR_MODIFIER_LOGO, XKB_MOD_NAME_LOGO },
	};
	uint32_t mask = 0;
	size_t i;
	for (i = 0; i < LENGTH(map); i++) {
		xkb_mod_index_t index;
		if (!(mods & map[i].bit))
			continue;
		index = xkb_keymap_mod_get_index(keymap, map[i].name);
		if (index != XKB_MOD_INVALID && index < 32)
			mask |= 1u << index;
	}
	return mask;
}

static uint32_t
macrokeycode(xkb_keysym_t wanted)
{
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(seat);
	struct xkb_keymap *keymap = keyboard ? keyboard->keymap : NULL;
	xkb_keycode_t code, min, max;
	const xkb_keysym_t *syms;
	int n, layout;

	if (!keymap)
		return 0;
	wanted = xkb_keysym_to_lower(wanted);
	min = xkb_keymap_min_keycode(keymap);
	max = xkb_keymap_max_keycode(keymap);
	for (code = min; code <= max; code++) {
		for (layout = 0; layout < (int)xkb_keymap_num_layouts_for_key(keymap, code);
				layout++) {
			n = xkb_keymap_key_get_syms_by_level(keymap, code, layout, 0, &syms);
			if (n > 0 && xkb_keysym_to_lower(syms[0]) == wanted)
				return code >= 8 ? code - 8 : code;
		}
	}
	return 0;
}

static void
macromodifiers(uint32_t mods)
{
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(seat);
	struct wlr_keyboard_modifiers synthetic = {0};
	if (!keyboard || !keyboard->keymap)
		return;
	synthetic.depressed = macromodmask(keyboard->keymap, mods);
	wlr_seat_keyboard_notify_modifiers(seat, &synthetic);
}

static void
macrorestoremodifiers(void)
{
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(seat);
	if (keyboard)
		wlr_seat_keyboard_notify_modifiers(seat, &keyboard->modifiers);
}

static void
macrorelease(Macro *m)
{
	if (!m->down_type)
		return;
	if (m->down_type == MacroStepKey) {
		wlr_seat_keyboard_notify_key(seat, now_ms(), m->down_code,
				WL_KEYBOARD_KEY_STATE_RELEASED);
		macrorestoremodifiers();
	} else {
		wlr_seat_pointer_notify_button(seat, now_ms(), m->down_code,
				WL_POINTER_BUTTON_STATE_RELEASED);
		wlr_seat_pointer_notify_frame(seat);
	}
	m->down_type = 0;
}

static void
macrostop(Macro *m)
{
	macrorelease(m);
	m->running = 0;
	m->pos = 0;
	if (m->timer)
		wl_event_source_timer_update(m->timer, 0);
}

static int
macrotick(void *data)
{
	Macro *m = data;
	MacroStep *step;
	int delay;
	uint32_t code;

	if (!m->running || locked)
		return 0;
	if (m->type == MacroClick) {
		int held;
		delay = MAX(1, 1000 / MAX(1, m->cps));
		held = MIN(m->press_ms, MAX(1, delay - 1));
		if (m->down_type) {
			macrorelease(m);
			if (m->mode == MacroOnce) {
				macrostop(m);
				return 0;
			}
			wl_event_source_timer_update(m->timer, MAX(1, delay - held));
		} else {
			wlr_seat_pointer_notify_button(seat, now_ms(), m->button,
					WL_POINTER_BUTTON_STATE_PRESSED);
			wlr_seat_pointer_notify_frame(seat);
			m->down_type = MacroStepClick;
			m->down_code = m->button;
			wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
			wl_event_source_timer_update(m->timer, held);
		}
		return 0;
	}

	if (m->down_type) {
		macrorelease(m);
		m->pos++;
		if (m->pos >= m->nsteps) {
			if (m->mode == MacroOnce) {
				macrostop(m);
				return 0;
			}
			m->pos = 0;
		}
		wl_event_source_timer_update(m->timer, MAX(1, m->interval));
		return 0;
	}
	if (!m->nsteps) {
		macrostop(m);
		return 0;
	}
	if (m->pos >= m->nsteps) {
		if (m->mode == MacroOnce) {
			macrostop(m);
			return 0;
		}
		m->pos = 0;
	}
	step = &m->steps[m->pos];
	if (step->type == MacroStepWait) {
		m->pos++;
		wl_event_source_timer_update(m->timer, step->delay);
		return 0;
	}
	if (step->type == MacroStepClick) {
		wlr_seat_pointer_notify_button(seat, now_ms(), step->button,
				WL_POINTER_BUTTON_STATE_PRESSED);
		wlr_seat_pointer_notify_frame(seat);
		m->down_type = MacroStepClick;
		m->down_code = step->button;
	} else {
		if (!(code = macrokeycode(step->keysym))) {
			m->pos++;
			wl_event_source_timer_update(m->timer, 1);
			return 0;
		}
		macromodifiers(step->mods);
		wlr_seat_keyboard_notify_key(seat, now_ms(), code,
				WL_KEYBOARD_KEY_STATE_PRESSED);
		m->down_type = MacroStepKey;
		m->down_code = code;
		m->down_mods = step->mods;
	}
	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	wl_event_source_timer_update(m->timer, m->press_ms);
	return 0;
}

static void
macrostart(Macro *m)
{
	if (m->running)
		macrostop(m);
	m->running = 1;
	m->pos = 0;
	if (!m->timer)
		m->timer = wl_event_loop_add_timer(event_loop, macrotick, m);
	if (!m->timer) {
		m->running = 0;
		return;
	}
	macrotick(m);
}

static int
macrohandle(uint32_t mods, xkb_keysym_t sym, uint32_t keycode,
		enum wl_keyboard_key_state state)
{
	Macro *m;
	size_t i;

	if (state == WL_KEYBOARD_KEY_STATE_RELEASED) {
		for (i = 0; i < nmacros; i++) {
			m = &macros[i];
			if (!m->trigger_down || m->trigger_keycode != keycode)
				continue;
			m->trigger_down = 0;
			if (m->mode == MacroHold)
				macrostop(m);
			return 1;
		}
		return 0;
	}
	for (i = 0; i < nmacros; i++) {
		m = &macros[i];
		if (CLEANMASK(mods) != CLEANMASK(m->trigger_mods)
				|| xkb_keysym_to_lower(sym) != xkb_keysym_to_lower(m->trigger_sym))
			continue;
		if (m->trigger_down)
			return 1;
		m->trigger_down = 1;
		m->trigger_keycode = keycode;
		if (m->mode == MacroToggle && m->running)
			macrostop(m);
		else
			macrostart(m);
		return 1;
	}
	return 0;
}

static void
macrostopall(void)
{
	size_t i;
	for (i = 0; i < nmacros; i++)
		macrostop(&macros[i]);
}

static void
macrostopaction(const Arg *arg)
{
	macrostopall();
}

static void
macrofreeall(void)
{
	size_t i;
	macrostopall();
	for (i = 0; i < nmacros; i++) {
		if (macros[i].timer)
			wl_event_source_remove(macros[i].timer);
		free(macros[i].steps);
	}
	free(macros);
	macros = NULL;
	nmacros = 0;
}

static int
cfgaction(const char *act, void (**func)(const Arg *), Arg *arg)
{
	static const struct {
		const char *name;
		void (*func)(const Arg *);
		Arg arg;
	} acts[] = {
		{ "macro:stop_all",            macrostopaction,      {0} },
		{ "wm:quit",                  quit,                 {0} },
		{ "wm:reload",                reloadconfig,         {0} },
		{ "wm:restart",               reloadconfig,         {0} },
		{ "wm:overview",              overviewtoggle,       {0} },
		{ "wm:toggle_opacity",        toggleopacity,        {0} },
		{ "wm:kill",                  killclient,           {0} },
		{ "wm:mode:insert",           entermode,            {.i = ModeInsert} },
		{ "wm:mode:normal",           entermode,            {.i = ModeNormal} },
		{ "wm:focus_left",            focusdir,             {.i = DirLeft} },
		{ "wm:focus_right",           focusdir,             {.i = DirRight} },
		{ "wm:focus_up",              focusdir,             {.i = DirUp} },
		{ "wm:focus_down",            focusdir,             {.i = DirDown} },
		{ "wm:focus_next",            focusnext,            {0} },
		{ "wm:swap_left",             swapdir,              {.i = DirLeft} },
		{ "wm:swap_right",            swapdir,              {.i = DirRight} },
		{ "wm:swap_up",               swapdir,              {.i = DirUp} },
		{ "wm:swap_down",             swapdir,              {.i = DirDown} },
		{ "wm:swap_prev",             swapstack,            {.i = -1} },
		{ "wm:swap_next",             swapstack,            {.i = +1} },
		{ "wm:toggle_split",          togglesplit,          {0} },
		{ "wm:toggle_layout",         togglelayout,         {0} },
		{ "wm:layout:bsp",            setlayoutarg,         {.ui = LtBSP} },
		{ "wm:layout:scroll",         setlayoutarg,         {.ui = LtScroll} },
		{ "wm:layout:drift",          setlayoutarg,         {.ui = LtDrift} },
		{ "wm:pan_left",              driftpankey,          {.i = DirLeft} },
		{ "wm:pan_right",             driftpankey,          {.i = DirRight} },
		{ "wm:pan_up",                driftpankey,          {.i = DirUp} },
		{ "wm:pan_down",              driftpankey,          {.i = DirDown} },
		{ "wm:zoom_in",               driftzoomkey,         {.f = 1.0f} },
		{ "wm:zoom_out",              driftzoomkey,         {.f = -1.0f} },
		{ "wm:zoom_reset",            driftzoomkey,         {.f = 0.0f} },
		{ "wm:zoom_fit",              driftfit,             {0} },
		{ "wm:consume",               consumewin,           {0} },
		{ "wm:expel",                 expelwin,             {0} },
		{ "wm:toggle_fullscreen",     togglefakefullscreen, {0} },
		{ "wm:toggle_real_fullscreen",togglefullscreen,     {0} },
		{ "wm:toggle_float",          togglefloating,       {0} },
		{ "wm:toggle_float_centered", togglefloating,       {0} },
		{ "wm:toggle_decorations",    toggledecor,          {0} },
		{ "wm:workspace_prev",        wsstep,               {.i = -1} },
		{ "wm:workspace_next",        wsstep,               {.i = +1} },
		{ "wm:move_to_workspace_prev", movewsstep,          {.i = -1} },
		{ "wm:move_to_workspace_next", movewsstep,          {.i = +1} },
		{ "wm:move_to_workspace_left", movewsdir,           {.i = DirLeft} },
		{ "wm:move_to_workspace_right", movewsdir,          {.i = DirRight} },
		{ "wm:move_to_workspace_up",  movewsdir,            {.i = DirUp} },
		{ "wm:move_to_workspace_down", movewsdir,           {.i = DirDown} },
		{ "wm:move_left",             movedir,              {.i = DirLeft} },
		{ "wm:move_right",            movedir,              {.i = DirRight} },
		{ "wm:move_up",               movedir,              {.i = DirUp} },
		{ "wm:move_down",             movedir,              {.i = DirDown} },
	};
	size_t i;
	int n;

	if (!strncmp(act, "spawn:", 6)) {
		const char **argv = ecalloc(4, sizeof(char *));
		argv[0] = "/bin/sh";
		argv[1] = "-c";
		argv[2] = strdup(act + 6);
		argv[3] = NULL;
		*func = spawn;
		arg->v = argv;
		return 1;
	}
	for (i = 0; i < LENGTH(acts); i++) {
		if (!strcmp(act, acts[i].name)) {
			*func = acts[i].func;
			*arg = acts[i].arg;
			return 1;
		}
	}
	if (!strncmp(act, "wm:ratio:", 9)) {
		*func = setratio;
		arg->f = strtof(act + 9, NULL);
		return 1;
	}
	if (sscanf(act, "wm:workspace:%d", &n) == 1 && n >= 1 && n <= NUMWS) {
		*func = viewws;
		arg->ui = n - 1;
		return 1;
	}
	if (sscanf(act, "wm:move_to_workspace_follow:%d", &n) == 1 && n >= 1 && n <= NUMWS) {
		*func = movetowsfollow;
		arg->ui = n - 1;
		return 1;
	}
	if (sscanf(act, "wm:move_to_workspace:%d", &n) == 1 && n >= 1 && n <= NUMWS) {
		*func = movetows;
		arg->ui = n - 1;
		return 1;
	}
	return 0;
}

static void
cfgaddbind(Bind **arr, size_t *n, uint32_t mods, xkb_keysym_t sym,
		void (*func)(const Arg *), Arg arg)
{
	size_t i;
	for (i = 0; i < *n; i++)
		if ((*arr)[i].mod == mods && (*arr)[i].keysym == sym)
			break;
	if (i == *n) {
		if (!(*arr = realloc(*arr, (*n + 1) * sizeof(Bind))))
			die("config: realloc:");
		(*n)++;
	}
	(*arr)[i].mod = mods;
	(*arr)[i].keysym = sym;
	(*arr)[i].func = func;
	(*arr)[i].arg = arg;
}

void
cfgerror(const char *fmt, ...)
{
	/* the first complaint is the one worth showing: after a typo the rest
	 * is usually the same mistake repeated */
	va_list ap;
	char msg[160];
	size_t i;

	va_start(ap, fmt);
	vsnprintf(msg, sizeof msg, fmt, ap);
	va_end(ap);
	wlr_log(WLR_ERROR, "config:%d: %s", cfg_curline, msg);
	if (cfg_nerrors++)
		return;
	/* the message ends up inside a shell command below */
	for (i = 0; msg[i]; i++)
		if (msg[i] == '\'' || msg[i] == '\\' || msg[i] == '\n')
			msg[i] = ' ';
	cfg_errline = cfg_curline;
	snprintf(cfg_errmsg, sizeof cfg_errmsg, "%s", msg);
}

int
cfgerrorhide(void *data)
{
	if (cfg_errbar) {
		wlr_scene_node_destroy(&cfg_errbar->node);
		cfg_errbar = NULL;
	}
	return 0;
}

void
cfgerrorshow(void)
{
	/* There is no text renderer here, so the compositor cannot spell the
	 * problem out on screen itself: it raises a red strip, which needs
	 * nothing installed and is impossible to miss, and passes the message
	 * to notify-send when a notification daemon is running.  The log line
	 * above has the details either way. */
	const float red[] = {0.85f, 0.15f, 0.18f, 0.9f};
	Monitor *m = selmon;
	char cmd[512];
	const char *argv[] = {"/bin/sh", "-c", cmd, NULL};
	Arg a = {.v = argv};

	if (!cfg_nerrors)
		return;
	if (!m && !wl_list_empty(&mons))
		m = wl_container_of(mons.next, m, link);
	if (m && m->w.width > 0) {
		cfgerrorhide(NULL);
		if ((cfg_errbar = wlr_scene_rect_create(layers[LyrOverlay],
				m->w.width, MAX(3, m->w.height / 96), red))) {
			wlr_scene_node_set_position(&cfg_errbar->node, m->w.x, m->w.y);
			if (!cfg_errbar_timer)
				cfg_errbar_timer = wl_event_loop_add_timer(event_loop,
						cfgerrorhide, NULL);
			if (cfg_errbar_timer)
				wl_event_source_timer_update(cfg_errbar_timer, 5000);
		}
	}
	snprintf(cmd, sizeof cmd, "command -v notify-send >/dev/null 2>&1 && "
			"notify-send -u critical 'phonegluewc: %d config error%s' "
			"'line %d: %s'", cfg_nerrors, cfg_nerrors > 1 ? "s" : "",
			cfg_errline, cfg_errmsg);
	spawn(&a);
}

int
cfgwatchfire(void *data)
{
	reloadconfig(NULL);
	return 0;
}

int
cfgwatchevent(int fd, uint32_t mask, void *data)
{
	union {
		struct inotify_event ev;
		char buf[4096];
	} u;
	const struct inotify_event *ev;
	const char *name = strrchr(cfg_path, '/');
	ssize_t len;
	char *pos;
	int hit = 0, gone = 0;

	name = name ? name + 1 : cfg_path;
	while ((len = read(fd, u.buf, sizeof u.buf)) > 0) {
		for (pos = u.buf; pos < u.buf + len; pos += sizeof(*ev) + ev->len) {
			ev = (const struct inotify_event *)pos;
			if (ev->len && !strcmp(ev->name, name)) {
				hit = 1;
			} else if (!ev->len && (ev->mask & (IN_MOVE_SELF | IN_DELETE_SELF))) {
				/* the directory was replaced under us: follow it.
				 * Nameless events are otherwise the watch's own
				 * bookkeeping - IN_IGNORED after a rearm above all -
				 * and reloading on those never stops. */
				gone = 1;
			}
		}
	}
	if (gone) {
		cfg_wd = -1;
		cfgwatch();
	}
	if (!hit)
		return 0;
	/* editors touch the file several times in a row; one reload once the
	 * dust settles is enough, and it never runs from inside the read */
	if (!cfg_watch_delay)
		cfg_watch_delay = wl_event_loop_add_timer(event_loop, cfgwatchfire, NULL);
	if (cfg_watch_delay)
		wl_event_source_timer_update(cfg_watch_delay, 150);
	return 0;
}

void
cfgwatch(void)
{
	/* Watching the directory rather than the file is what makes this work
	 * with editors at all: most of them write a temporary file and rename
	 * it over the config, which drops any watch on the file itself. */
	static int fd = -1;
	static char watched[512];
	char dir[512], *slash;

	if (!event_loop || !*cfg_path)
		return;
	snprintf(dir, sizeof dir, "%s", cfg_path);
	if (!(slash = strrchr(dir, '/')))
		return;
	*slash = '\0';
	/* rearming an intact watch only produces another event to react to */
	if (cfg_wd >= 0 && !strcmp(watched, dir))
		return;
	if (fd < 0 && (fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC)) < 0) {
		wlr_log(WLR_ERROR, "config: inotify_init1:");
		return;
	}
	if (cfg_wd >= 0)
		inotify_rm_watch(fd, cfg_wd);
	if ((cfg_wd = inotify_add_watch(fd, dir, IN_CLOSE_WRITE | IN_MOVED_TO
			| IN_CREATE | IN_MOVE_SELF | IN_DELETE_SELF)) < 0) {
		wlr_log(WLR_ERROR, "config: cannot watch %s", dir);
		return;
	}
	snprintf(watched, sizeof watched, "%s", dir);
	if (!cfg_watch_src)
		cfg_watch_src = wl_event_loop_add_fd(event_loop, fd,
				WL_EVENT_READABLE, cfgwatchevent, NULL);
}

static const char *
layoutname(unsigned int lt)
{
	return lt == LtScroll ? "scroll" : lt == LtDrift ? "drift" : "bsp";
}

int
layoutstatepath(char *buf, size_t size)
{
	/* the layout the session was left in, kept out of the config file */
	const char *env;

	if ((env = getenv("XDG_STATE_HOME")) && *env)
		snprintf(buf, size, "%s/phonegluewc", env);
	else if ((env = getenv("HOME")) && *env)
		snprintf(buf, size, "%s/.local/state/phonegluewc", env);
	else
		return 0;
	return 1;
}

void
loadlayoutstate(void)
{
	char path[512], name[32] = {0};
	FILE *f;

	if (!remember_layout || !layoutstatepath(path, sizeof path - 8))
		return;
	strncat(path, "/layout", sizeof path - strlen(path) - 1);
	if (!(f = fopen(path, "r")))
		return;
	if (fscanf(f, "%31s", name) == 1) {
		if (!strcmp(name, "scroll"))
			default_layout = LtScroll;
		else if (!strcmp(name, "drift"))
			default_layout = LtDrift;
		else if (!strcmp(name, "bsp"))
			default_layout = LtBSP;
	}
	fclose(f);
}

void
savelayoutstate(unsigned int lt)
{
	char path[600], dir[512];
	FILE *f;

	if (!remember_layout || !layoutstatepath(dir, sizeof dir))
		return;
	/* the parent of the state dir usually exists already; create both anyway */
	{
		char *slash = strrchr(dir, '/');
		if (slash) {
			*slash = '\0';
			mkdir(dir, 0700);
			*slash = '/';
		}
	}
	mkdir(dir, 0700);
	snprintf(path, sizeof path, "%s/layout", dir);
	if (!(f = fopen(path, "w")))
		return;
	fprintf(f, "%s\n", layoutname(lt));
	fclose(f);
}

void
saveoverviewstate(int active)
{
	/* published so the shell can put a dock on screen while the overview is
	 * up; no other compositor writes this, so the dock stays phonegluewc-only */
	char path[600], dir[512];
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	{
		char *slash = strrchr(dir, '/');
		if (slash) {
			*slash = '\0';
			mkdir(dir, 0700);
			*slash = '/';
		}
	}
	mkdir(dir, 0700);
	snprintf(path, sizeof path, "%s/overview", dir);
	if (!(f = fopen(path, "w")))
		return;
	fprintf(f, "%d\n", active ? 1 : 0);
	fclose(f);
}

/* 1 while any output is lit, for what should stop drawing when nobody can see it */
static void
savescreenstate(void)
{
	char path[600], tmp[620], dir[512];
	FILE *f;
	Monitor *m;
	int on = 0;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	wl_list_for_each(m, &mons, link)
		on |= !m->asleep;
	snprintf(path, sizeof path, "%s/screen", dir);
	/* renamed in: a reader never finds it empty and takes the screen for lit */
	snprintf(tmp, sizeof tmp, "%s.tmp", path);
	if (!(f = fopen(tmp, "w")))
		return;
	fprintf(f, "%d\n", on);
	fclose(f);
	rename(tmp, path);
}

/* the shell closes its menu when this number changes */
static void
savepillstate(void)
{
	char path[600], dir[512];
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	snprintf(path, sizeof path, "%s/pill", dir);
	if (!(f = fopen(path, "w")))
		return;
	fprintf(f, "%u\n", pillseq);
	fclose(f);
}

/* written whole then renamed: the shell never reads half a number */
static void
saveseq(const char *name, unsigned int seq)
{
	char path[600], tmp[610], dir[512];
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	snprintf(path, sizeof path, "%s/%s", dir, name);
	snprintf(tmp, sizeof tmp, "%s.tmp", path);
	if (!(f = fopen(tmp, "w")))
		return;
	fprintf(f, "%u\n", seq);
	if (fclose(f) == 0)
		rename(tmp, path);
}

/* the colour of the top rows of the app in front, for the status bar behind them */
static void
topcolorwrite(const char *v)
{
	static char last[16];
	char path[600], tmp[610], dir[512];
	FILE *f;

	if (!strcmp(last, v) || !layoutstatepath(dir, sizeof dir))
		return;
	snprintf(path, sizeof path, "%s/topcolor", dir);
	snprintf(tmp, sizeof tmp, "%s.tmp", path);
	if (!(f = fopen(tmp, "w")))
		return;
	fprintf(f, "%s\n", v);
	if (fclose(f) == 0 && rename(tmp, path) == 0)
		snprintf(last, sizeof last, "%s", v);
}

/* shortcut: reads the focused window, a split whose top half is another app shows the focused one's colour */
static int
topcolorsample(void *data)
{
	Client *c = selmon && !locked ? focustop(selmon) : NULL;
	struct wlr_surface *surface;
	struct wlr_texture *tex;
	struct wlr_box geo;
	uint32_t px[15], l[15], t;
	int i, j, n = 0, s, x, y;
	char hex[16];

	topcolor_at = now_ms();
	if (!c || !(surface = client_surface(c)) || !surface->mapped) {
		topcolorwrite("none");
		return 0;
	}
	client_get_geometry(c, &geo);
	s = surface->current.scale > 0 ? surface->current.scale : 1;
	if ((tex = wlr_surface_get_texture(surface)) && geo.width > 0) {
		for (i = 0; i < 5; i++) {
			x = (geo.x + geo.width * (2 * i + 1) / 10) * s;
			for (j = 0; j < 3; j++) {
				y = (geo.y + j) * s;
				if (x < 0 || y < 0 || x >= (int)tex->width || y >= (int)tex->height)
					continue;
				if (wlr_texture_read_pixels(tex, &(struct wlr_texture_read_pixels_options){
						.data = &px[n], .format = DRM_FORMAT_ARGB8888, .stride = 4,
						.src_box = { x, y, 1, 1 } }))
					n++;
			}
		}
	}
	/* the buffer could not be read (a dmabuf readback can fail): the shell paints Phone.black */
	if (!n) {
		topcolorwrite("unknown");
		return 0;
	}
	/* the median by brightness keeps a real pixel: a lone icon or letter in the row cannot tint it */
	for (i = 0; i < n; i++)
		l[i] = 2 * ((px[i] >> 16) & 255) + 5 * ((px[i] >> 8) & 255) + (px[i] & 255);
	for (i = 1; i < n; i++)
		for (j = i; j > 0 && l[j - 1] > l[j]; j--) {
			t = l[j]; l[j] = l[j - 1]; l[j - 1] = t;
			t = px[j]; px[j] = px[j - 1]; px[j - 1] = t;
		}
	snprintf(hex, sizeof hex, "#%06x", px[n / 2] & 0xffffff);
	topcolorwrite(hex);
	return 0;
}

/* at most one sample every TOPCOLOR_MS; the last commit in a burst is still read */
static void
topcolorsoon(void)
{
	uint32_t since = now_ms() - topcolor_at;

	if (topcolor_timer)
		wl_event_source_timer_update(topcolor_timer, since >= TOPCOLOR_MS ? 1 : (int)(TOPCOLOR_MS - since));
}

static void
rotwrite(const char *name, const char *v)
{
	char path[600], tmp[610], dir[512];
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return;
	snprintf(path, sizeof path, "%s/%s", dir, name);
	snprintf(tmp, sizeof tmp, "%s.tmp", path);
	if (!(f = fopen(tmp, "w")))
		return;
	fprintf(f, "%s\n", v);
	if (fclose(f) == 0)
		rename(tmp, path);
}

/* the flag the Rotation lock tile writes */
static int
rotlocked(void)
{
	char path[600], dir[512], v = 0;
	FILE *f;

	if (!layoutstatepath(dir, sizeof dir))
		return 0;
	snprintf(path, sizeof path, "%s/rotation-lock", dir);
	if (!(f = fopen(path, "r")))
		return 0;
	v = (char)fgetc(f);
	fclose(f);
	return v == '1';
}

/* shortcut: only the first output turns, the phone has one; pick by name if a dock ever adds a second */
static Monitor *
rotmon(void)
{
	Monitor *m;

	return wl_list_empty(&mons) ? NULL : wl_container_of(mons.next, m, link);
}

/* everything turns but the lock and the greeter; with home_rotate = off also home, its menu and its editor */
static int
rotfront(Monitor *m)
{
	LayerSurface *l;

	if (!m || locked || greeter)
		return 0;
	if (!home_upright)
		return 1;
	if (!wsoccupied(m, m->ws))
		return 0;
	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link)
		if (l->mapped && (!strcmp(l->layer_surface->namespace, "phone-menu")
				|| !strcmp(l->layer_surface->namespace, "phone-screens")))
			return 0;
	return 1;
}

static int
rotfadestep(void *data)
{
	float t = (float)(now_ms() - rot_fade_at) / ROT_FADE_MS;

	if (!rot_fade)
		return 0;
	if (t >= 1.0f) {
		wlr_scene_node_destroy(&rot_fade->node);
		rot_fade = NULL;
		return 0;
	}
	wlr_scene_rect_set_color(rot_fade, (float[4]){0, 0, 0, 1.0f - t});
	wl_event_source_timer_update(rot_fade_timer, 16);
	return 0;
}

/* the turned picture comes up out of black */
static void
rotfadestart(Monitor *m)
{
	int side = MAX(m->wlr_output->width, m->wlr_output->height);

	if (!animations)
		return;
	if (!rot_fade)
		rot_fade = wlr_scene_rect_create(layers[LyrBlock], side, side, (float[4]){0, 0, 0, 1});
	wlr_scene_rect_set_size(rot_fade, side, side);
	wlr_scene_node_set_position(&rot_fade->node, m->m.x, m->m.y);
	wlr_scene_node_raise_to_top(&rot_fade->node);
	wlr_scene_rect_set_color(rot_fade, (float[4]){0, 0, 0, 1});
	rot_fade_at = now_ms();
	wl_event_source_timer_update(rot_fade_timer, 16);
}

static int
rotupdate(void *data)
{
	Monitor *m = rotmon();
	enum wl_output_transform want = WL_OUTPUT_TRANSFORM_NORMAL;
	int front;

	if (!m || !m->wlr_output->enabled)
		return 0;
	/* never under a finger or the cards: the overview keeps the turn it opened with */
	if (touch_gesture || overview_visible) {
		rotsoon(300);
		return 0;
	}
	if (!(front = rotfront(m)))
		rot_pick = WL_OUTPUT_TRANSFORM_NORMAL;
	else
		want = rotlocked() ? rot_pick : rot_sensor;
	if (want != rot) {
		/* a split runs along the long side: stacked upright, side by side turned */
		if ((want ^ rot) & 1)
			for (unsigned int ws = 0; ws < NUMWS; ws++)
				bsp_flip(m->tree[ws]);
		rot = want;
		rotfadestart(m);
		applyoutputcfg(m);
		rotwrite("orientation", transformname(rot));
	}
	/* shortcut: the lock tile only writes its file, polled each second while turned or held turned; watch it with inotify if those wakeups show */
	if (front && (rot_sensor != rot || rot != WL_OUTPUT_TRANSFORM_NORMAL))
		rotsoon(1000);
	return 0;
}

static void
rotsoon(int ms)
{
	if (rot_timer)
		wl_event_source_timer_update(rot_timer, ms);
}

/* from phonegluewc-sensor, in iio-sensor-proxy's names */
static void
rotorientation(const char *name)
{
	static const struct { const char *name; enum wl_output_transform t; } map[] = {
		{"normal", WL_OUTPUT_TRANSFORM_NORMAL}, {"left-up", WL_OUTPUT_TRANSFORM_90},
		{"bottom-up", WL_OUTPUT_TRANSFORM_180}, {"right-up", WL_OUTPUT_TRANSFORM_270},
	};
	char offer[32];
	size_t i;

	for (i = 0; i < LENGTH(map) && strcmp(name, map[i].name); i++);
	if (i == LENGTH(map) || map[i].t == rot_sensor)
		return;
	rot_sensor = map[i].t;
	/* locked: the shell offers the turn as a button for a few seconds */
	if (rot_sensor != rot && rotlocked() && rotfront(rotmon())) {
		snprintf(offer, sizeof offer, "%u %s", ++rot_offers, transformname(rot_sensor));
		rotwrite("rotate-offer", offer);
	}
	rotsoon(1);
}

void
readconfig(void)
{
	char path[512], *line = NULL, *k, *v, *v2;
	const char *env;
	size_t i, lsz = 0;
	FILE *f;

	/* start from the built-in binds; the config upserts over them */
	for (i = 0; i < LENGTH(keys); i++)
		cfgaddbind(&runkeys, &nrunkeys, keys[i].mod, keys[i].keysym,
				keys[i].func, keys[i].arg);
	for (i = 0; i < LENGTH(normalkeys); i++)
		cfgaddbind(&runnormalkeys, &nrunnormalkeys, normalkeys[i].mod,
				normalkeys[i].keysym, normalkeys[i].func, normalkeys[i].arg);

	cfg_nerrors = 0;
	cfg_curline = 0;
	cfg_errline = 0;
	cfg_errmsg[0] = '\0';
	free(outcfgs);
	outcfgs = NULL;
	noutcfgs = 0;

	if ((env = getenv("XDG_CONFIG_HOME")))
		snprintf(path, sizeof path, "%s/phonegluewc/config.conf", env);
	else if ((env = getenv("HOME")))
		snprintf(path, sizeof path, "%s/.config/phonegluewc/config.conf", env);
	else
		return;
	snprintf(cfg_path, sizeof cfg_path, "%s", path);
	/* watch even when there is no config yet: writing one applies it */
	cfgwatch();
	if (!(f = fopen(path, "r"))) {
		loadlayoutstate();
		return;
	}

	while (getline(&line, &lsz, f) != -1) {
		cfg_curline++;
		k = cfgtrim(line);
		if (!*k || *k == '#')
			continue;
		if (!(v = strchr(k, '=')))
			continue;
		*v++ = '\0';
		k = cfgtrim(k);
		v = cfgtrim(v);
		if (!strcmp(k, "macro")) {
			cfgmacro(v);
		} else if (!strcmp(k, "bind_insert") || !strcmp(k, "bind_normal")) {
			uint32_t mods;
			xkb_keysym_t sym;
			void (*func)(const Arg *);
			Arg arg = {0};
			char combo[96];
			if (!(v2 = strchr(v, '=')))
				continue;
			*v2++ = '\0';
			v = cfgtrim(v);
			v2 = cfgtrim(v2);
			/* cfgbindcombo() tokenises in place, so the error below
			 * would otherwise report only up to the first plus */
			snprintf(combo, sizeof combo, "%s", v);
			if (!cfgbindcombo(v, &mods, &sym) || !cfgaction(v2, &func, &arg)) {
				cfgerror("bad bind '%s = %s'", combo, v2);
				continue;
			}
			if (!strcmp(k, "bind_insert"))
				cfgaddbind(&runkeys, &nrunkeys, mods, sym, func, arg);
			else
				cfgaddbind(&runnormalkeys, &nrunnormalkeys, mods, sym, func, arg);
		} else if (!strcmp(k, "remember_layout")) {
			remember_layout = !strcmp(v, "true") || !strcmp(v, "1");
		} else if (!strcmp(k, "start_in_overview")) {
			start_in_overview = !strcmp(v, "true") || !strcmp(v, "1");
		} else if (!strcmp(k, "layout")) {
			default_layout = !strcmp(v, "scroll") ? LtScroll
					: !strcmp(v, "drift") ? LtDrift : LtBSP;
		} else if (!strcmp(k, "drift_snap")) {
			drift_snap = MAX(0, atoi(v));
		} else if (!strcmp(k, "drift_nudge")) {
			drift_nudge = MAX(1, atoi(v));
		} else if (!strcmp(k, "drift_zoom_min")) {
			drift_zoom_min = MAX(0.05f, strtof(v, NULL));
		} else if (!strcmp(k, "drift_zoom_max")) {
			drift_zoom_max = MAX(1.0f, strtof(v, NULL));
		} else if (!strcmp(k, "drift_zoom_step")) {
			drift_zoom_step = MAX(1.01f, strtof(v, NULL));
		} else if (!strcmp(k, "swipe_distance")) {
			swipe_distance = MAX(0, atoi(v));
		} else if (!strcmp(k, "drift_pan_speed")) {
			drift_pan_speed = MAX(0.1f, strtof(v, NULL));
		} else if (!strcmp(k, "gap")) {
			gappx = atoi(v);
		} else if (!strcmp(k, "border")) {
			borderpx = (unsigned int)atoi(v);
		} else if (!strcmp(k, "border_focus")) {
			cfgcolor(v, focuscolor);
		} else if (!strcmp(k, "border_normal")) {
			cfgcolor(v, bordercolor);
		} else if (!strcmp(k, "unfocused_borders")) {
			unfocused_borders = !strcmp(v, "true") || !strcmp(v, "1");
		} else if (!strcmp(k, "normal_mode_color")) {
			cfgcolor(v, normalmodecolor);
		} else if (!strcmp(k, "root_color")) {
			cfgcolor(v, rootcolor);
		} else if (!strcmp(k, "idle_inhibit_fullscreen")) {
			idle_inhibit_fullscreen = !strcmp(v, "true") || !strcmp(v, "1");
		} else if (!strcmp(k, "xwayland")) {
			/* shortcut: read once at startup, a reload does not open or close the X socket */
			xwayland_on = strcmp(v, "off") && strcmp(v, "false") && strcmp(v, "0");
		} else if (!strcmp(k, "fullscreen_apps")) {
			snprintf(fullscreen_apps, sizeof fullscreen_apps, "%s", v);
		} else if (!strcmp(k, "warp_pointer")) {
			warpcursor = !strcmp(v, "true") || !strcmp(v, "1");
		} else if (!strcmp(k, "corner_radius")) {
			corner_radius = atoi(v);
		} else if (!strcmp(k, "blur")) {
			blurenabled = !strcmp(v, "true") || !strcmp(v, "1");
		} else if (!strcmp(k, "blur_passes")) {
			blur_passes = atoi(v);
		} else if (!strcmp(k, "blur_radius")) {
			blur_radius = atoi(v);
		} else if (!strcmp(k, "opacity")) {
			win_opacity = strtof(v, NULL);
			if (win_opacity < 0.1f)
				win_opacity = 0.1f;
			if (win_opacity > 1.0f)
				win_opacity = 1.0f;
		} else if (!strcmp(k, "animations")) {
			animations = !strcmp(v, "true") || !strcmp(v, "1");
		} else if (!strcmp(k, "animation_duration")) {
			animation_duration = atoi(v);
		} else if (!strcmp(k, "animation_type_open")) {
			animation_type_open = cfganimtype(v);
		} else if (!strcmp(k, "animation_type_close")) {
			animation_type_close = cfganimtype(v);
		} else if (!strcmp(k, "animation_duration_open")) {
			animation_duration_open = atoi(v);
		} else if (!strcmp(k, "animation_duration_close")) {
			animation_duration_close = atoi(v);
		} else if (!strcmp(k, "animation_curve_open")) {
			cfgcurve(v, animation_curve_open);
		} else if (!strcmp(k, "animation_curve_close")) {
			cfgcurve(v, animation_curve_close);
		} else if (!strcmp(k, "zoom_initial_ratio")) {
			zoom_initial_ratio = MIN(1.0f, MAX(0.05f, strtof(v, NULL)));
		} else if (!strcmp(k, "zoom_end_ratio")) {
			zoom_end_ratio = MIN(1.0f, MAX(0.05f, strtof(v, NULL)));
		} else if (!strcmp(k, "repeat_rate")) {
			repeat_rate = atoi(v);
		} else if (!strcmp(k, "repeat_delay")) {
			repeat_delay = atoi(v);
		} else if (!strcmp(k, "xkb_layout")) {
			snprintf(xkb_layout_buf, sizeof xkb_layout_buf, "%s", v);
			xkb_rules.layout = *xkb_layout_buf ? xkb_layout_buf : NULL;
		} else if (!strcmp(k, "xkb_variant")) {
			snprintf(xkb_variant_buf, sizeof xkb_variant_buf, "%s", v);
			xkb_rules.variant = *xkb_variant_buf ? xkb_variant_buf : NULL;
		} else if (!strcmp(k, "xkb_options")) {
			snprintf(xkb_options_buf, sizeof xkb_options_buf, "%s", v);
			xkb_rules.options = *xkb_options_buf ? xkb_options_buf : NULL;
		} else if (!strcmp(k, "autostart")) {
			if (!(autostarts = realloc(autostarts, (nautostarts + 1) * sizeof(char *))))
				die("config: realloc:");
			autostarts[nautostarts++] = strdup(v);
		} else if (!strcmp(k, "output")) {
			cfgoutput(v);
		} else {
			cfgerror("unknown key '%s'", k);
		}
	}
	free(line);
	fclose(f);
	cfgoutputcheck();
	/* the layout the last session ended in wins over the configured one */
	loadlayoutstate();
}

void
setup(void)
{
	int drm_fd, i, sig[] = {SIGCHLD, SIGINT, SIGTERM, SIGPIPE};
	struct sigaction sa = {.sa_flags = SA_RESTART, .sa_handler = handlesig};
	sigemptyset(&sa.sa_mask);

	for (i = 0; i < (int)LENGTH(sig); i++)
		sigaction(sig[i], &sa, NULL);
	signal(SIGSEGV, handlecrash);
	signal(SIGABRT, handlecrash);
	signal(SIGBUS, handlecrash);

	wlr_log_init(log_level, logfilter);

	readconfig();
	readphoneconf();

	/* The Wayland display is managed by libwayland. It handles accepting
	 * clients from the Unix socket, manging Wayland globals, and so on. */
	dpy = wl_display_create();
	event_loop = wl_display_get_event_loop(dpy);
	/* the first readconfig() ran before there was an event loop to watch on */
	cfgwatch();
	overview_watchdog = wl_event_loop_add_timer(event_loop, overviewwatchdog, NULL);
	card_close_timer = wl_event_loop_add_timer(event_loop, cardcloseback, NULL);

	/* The backend is a wlroots feature which abstracts the underlying input and
	 * output hardware. The autocreate option will choose the most suitable
	 * backend based on the current environment, such as opening an X11 window
	 * if an X11 server is running. */
	if (!(backend = wlr_backend_autocreate(event_loop, &session)))
		die("couldn't create backend");

	/* Initialize the scene graph used to lay out windows */
	scene = wlr_scene_create();
	wlr_scene_set_blur_data(scene, blur_passes, blur_radius, 0.02f, 0.9f, 0.9f, 1.1f);
	root_bg = wlr_scene_rect_create(&scene->tree, 0, 0, rootcolor);
	wl_list_init(&close_anims);
	for (i = 0; i < NUM_LAYERS; i++)
		layers[i] = wlr_scene_tree_create(&scene->tree);
	drag_icon = wlr_scene_tree_create(&scene->tree);
	wlr_scene_node_place_below(&drag_icon->node, &layers[LyrBlock]->node);
	overview_dim_scene = wlr_scene_tree_create(layers[LyrBottom]);
	wlr_scene_node_set_enabled(&overview_dim_scene->node, 0);
	/* clear any state left behind by a session that died with the overview
	 * open, so the shell does not start up with its dock on screen */
	saveoverviewstate(0);
	overview_scene = wlr_scene_tree_create(layers[LyrOverview]);
	overview_panels_scene = wlr_scene_tree_create(overview_scene);
	overview_land_scene = wlr_scene_tree_create(overview_scene);
	overview_drag_scene = wlr_scene_tree_create(overview_scene);
	carry_edge_timer = wl_event_loop_add_timer(event_loop, carryedge, NULL);
	wlr_scene_node_set_enabled(&overview_scene->node, 0);

	/* Autocreates a renderer, either Pixman, GLES2 or Vulkan for us. The user
	 * can also specify a renderer using the WLR_RENDERER env var.
	 * The renderer is responsible for defining the various pixel formats it
	 * supports for shared memory, this configures that for clients. */
	if (!(drw = createrenderer()))
		die("couldn't create renderer");
	wl_signal_add(&drw->events.lost, &gpu_reset);

	/* Create shm, drm and linux_dmabuf interfaces by ourselves.
	 * The simplest way is to call:
	 *      wlr_renderer_init_wl_display(drw);
	 * but we need to create the linux_dmabuf interface manually to integrate it
	 * with wlr_scene. */
	wlr_renderer_init_wl_shm(drw, dpy);

	if (wlr_renderer_get_texture_formats(drw, WLR_BUFFER_CAP_DMABUF)) {
		wlr_drm_create(dpy, drw);
		wlr_scene_set_linux_dmabuf_v1(scene,
				wlr_linux_dmabuf_v1_create_with_renderer(dpy, 5, drw));
	}

	if ((drm_fd = wlr_renderer_get_drm_fd(drw)) >= 0 && drw->features.timeline
			&& backend->features.timeline)
		wlr_linux_drm_syncobj_manager_v1_create(dpy, 1, drm_fd);

	/* Autocreates an allocator for us.
	 * The allocator is the bridge between the renderer and the backend. It
	 * handles the buffer creation, allowing wlroots to render onto the
	 * screen */
	if (!(alloc = wlr_allocator_autocreate(backend, drw)))
		die("couldn't create allocator");

	/* This creates some hands-off wlroots interfaces. The compositor is
	 * necessary for clients to allocate surfaces and the data device manager
	 * handles the clipboard. Each of these wlroots interfaces has room for you
	 * to dig your fingers in and play with their behavior if you want. Note that
	 * the clients cannot set the selection directly without compositor approval,
	 * see the setsel() function. */
	compositor = wlr_compositor_create(dpy, 6, drw);
	wlr_subcompositor_create(dpy);
	wlr_data_device_manager_create(dpy);
	wlr_export_dmabuf_manager_v1_create(dpy);
	wlr_screencopy_manager_v1_create(dpy);
	wlr_data_control_manager_v1_create(dpy);
	wlr_primary_selection_v1_device_manager_create(dpy);
	wlr_viewporter_create(dpy);
	wlr_single_pixel_buffer_manager_v1_create(dpy);
	wlr_fractional_scale_manager_v1_create(dpy, 1);
	wlr_presentation_create(dpy, backend, 2);
	wlr_alpha_modifier_v1_create(dpy);

	wlr_scene_set_gamma_control_manager_v1(scene, wlr_gamma_control_manager_v1_create(dpy));

	power_mgr = wlr_output_power_manager_v1_create(dpy);
	wl_signal_add(&power_mgr->events.set_mode, &output_power_mgr_set_mode);

	/* Creates an output layout, which is a wlroots utility for working with an
	 * arrangement of screens in a physical layout. */
	output_layout = wlr_output_layout_create(dpy);
	wl_signal_add(&output_layout->events.change, &layout_change);

    wlr_xdg_output_manager_v1_create(dpy, output_layout);

	/* Configure a listener to be notified when new outputs are available on the
	 * backend. */
	wl_list_init(&mons);
	wl_signal_add(&backend->events.new_output, &new_output);

	/* Set up our client lists, the xdg-shell and the layer-shell. The xdg-shell is a
	 * Wayland protocol which is used for application windows. For more
	 * detail on shells, refer to the article:
	 *
	 * https://drewdevault.com/2018/07/29/Wayland-shells.html
	 */
	wl_list_init(&clients);
	wl_list_init(&fstack);

	xdg_shell = wlr_xdg_shell_create(dpy, 6);
	wl_signal_add(&xdg_shell->events.new_toplevel, &new_xdg_toplevel);
	wl_signal_add(&xdg_shell->events.new_popup, &new_xdg_popup);

	layer_shell = wlr_layer_shell_v1_create(dpy, 3);
	wl_signal_add(&layer_shell->events.new_surface, &new_layer_surface);

	idle_notifier = wlr_idle_notifier_v1_create(dpy);

	idle_inhibit_mgr = wlr_idle_inhibit_v1_create(dpy);
	wl_signal_add(&idle_inhibit_mgr->events.new_inhibitor, &new_idle_inhibitor);

	session_lock_mgr = wlr_session_lock_manager_v1_create(dpy);
	wl_signal_add(&session_lock_mgr->events.new_lock, &new_session_lock);
	locked_bg = wlr_scene_rect_create(layers[LyrBlock], sgeom.width, sgeom.height,
			(float [4]){0, 0, 0, 1});
	wlr_scene_node_set_enabled(&locked_bg->node, 0);

	/* Use decoration protocols to negotiate server-side decorations */
	wlr_server_decoration_manager_set_default_mode(
			wlr_server_decoration_manager_create(dpy),
			WLR_SERVER_DECORATION_MANAGER_MODE_SERVER);
	xdg_decoration_mgr = wlr_xdg_decoration_manager_v1_create(dpy);
	wl_signal_add(&xdg_decoration_mgr->events.new_toplevel_decoration, &new_xdg_decoration);

	pointer_constraints = wlr_pointer_constraints_v1_create(dpy);
	wl_signal_add(&pointer_constraints->events.new_constraint, &new_pointer_constraint);

	relative_pointer_mgr = wlr_relative_pointer_manager_v1_create(dpy);

	/*
	 * Creates a cursor, which is a wlroots utility for tracking the cursor
	 * image shown on screen.
	 */
	cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(cursor, output_layout);

	/* Creates an xcursor manager, another wlroots utility which loads up
	 * Xcursor themes to source cursor images from and makes sure that cursor
	 * images are available at all scale factors on the screen (necessary for
	 * HiDPI support). Scaled cursors will be loaded with each output. */
	cursor_mgr = wlr_xcursor_manager_create(NULL, 24);
	/* only a thin dark edge, so a light app shows the pill too: the bar has no background */
	bar_bg = wlr_scene_rect_create(layers[LyrPill], PILL_W + 2 * PILL_HALO, PILL_H + 2 * PILL_HALO,
			(const float[4]){0.0f, 0.0f, 0.0f, 0.3f});
	wlr_scene_rect_set_corner_radii(bar_bg, corner_radii_all((PILL_H + 2 * PILL_HALO) / 2));
	wlr_scene_node_set_enabled(&bar_bg->node, 0);
	pill = wlr_scene_rect_create(layers[LyrPill], PILL_W, PILL_H,
			(const float[4]){0.9f, 0.9f, 0.9f, 0.9f});
	wlr_scene_node_set_enabled(&pill->node, 0);
	wlr_scene_rect_set_corner_radii(pill, corner_radii_all(PILL_H / 2));
	setenv("XCURSOR_SIZE", "24", 1);

	/*
	 * wlr_cursor *only* displays an image on screen. It does not move around
	 * when the pointer moves. However, we can attach input devices to it, and
	 * it will generate aggregate events for all of them. In these events, we
	 * can choose how we want to process them, forwarding them to clients and
	 * moving the cursor around. More detail on this process is described in
	 * https://drewdevault.com/2018/07/17/Input-handling-in-wlroots.html
	 *
	 * And more comments are sprinkled throughout the notify functions above.
	 */
	wl_signal_add(&cursor->events.motion, &cursor_motion);
	wl_signal_add(&cursor->events.motion_absolute, &cursor_motion_absolute);
	wl_signal_add(&cursor->events.button, &cursor_button);
	wl_signal_add(&cursor->events.axis, &cursor_axis);
	wl_signal_add(&cursor->events.frame, &cursor_frame);
	wl_signal_add(&cursor->events.swipe_begin, &cursor_swipe_begin);
	wl_signal_add(&cursor->events.swipe_update, &cursor_swipe_update);
	wl_signal_add(&cursor->events.swipe_end, &cursor_swipe_end);
	wl_signal_add(&cursor->events.touch_cancel, &cursor_touch_cancel);
	wl_signal_add(&cursor->events.touch_down, &cursor_touch_down);
	wl_signal_add(&cursor->events.touch_frame, &cursor_touch_frame);
	wl_signal_add(&cursor->events.touch_motion, &cursor_touch_motion);
	wl_signal_add(&cursor->events.touch_up, &cursor_touch_up);
	wl_signal_add(&cursor->events.pinch_begin, &cursor_pinch_begin);
	wl_signal_add(&cursor->events.pinch_update, &cursor_pinch_update);
	wl_signal_add(&cursor->events.pinch_end, &cursor_pinch_end);

	cursor_shape_mgr = wlr_cursor_shape_manager_v1_create(dpy, 1);
	wl_signal_add(&cursor_shape_mgr->events.request_set_shape, &request_set_cursor_shape);

	/*
	 * Configures a seat, which is a single "seat" at which a user sits and
	 * operates the computer. This conceptually includes up to one keyboard,
	 * pointer, touch, and drawing tablet device. We also rig up a listener to
	 * let us know when new input devices are available on the backend.
	 */
	wl_signal_add(&backend->events.new_input, &new_input_device);
	virtual_keyboard_mgr = wlr_virtual_keyboard_manager_v1_create(dpy);
	wl_signal_add(&virtual_keyboard_mgr->events.new_virtual_keyboard,
			&new_virtual_keyboard);
	virtual_pointer_mgr = wlr_virtual_pointer_manager_v1_create(dpy);
    wl_signal_add(&virtual_pointer_mgr->events.new_virtual_pointer,
            &new_virtual_pointer);

	seat = wlr_seat_create(dpy, "seat0");
	wl_list_init(&text_inputs);
	wl_signal_add(&seat->keyboard_state.events.focus_change, &keyboard_focus_change);
	wl_signal_add(&wlr_text_input_manager_v3_create(dpy)->events.new_text_input, &new_text_input);
	wl_signal_add(&wlr_input_method_manager_v2_create(dpy)->events.new_input_method, &new_input_method);
	wl_signal_add(&seat->events.request_set_cursor, &request_cursor);
	wl_signal_add(&seat->events.request_set_selection, &request_set_sel);
	wl_signal_add(&seat->events.request_set_primary_selection, &request_set_psel);
	wl_signal_add(&seat->events.request_start_drag, &request_start_drag);
	wl_signal_add(&seat->events.start_drag, &start_drag);

	kb_group = createkeyboardgroup();
	wl_list_init(&kb_group->destroy.link);

	output_mgr = wlr_output_manager_v1_create(dpy);
	wl_signal_add(&output_mgr->events.apply, &output_mgr_apply);
	wl_signal_add(&output_mgr->events.test, &output_mgr_test);

	/* status bar support: dwl-ipc (workspaces/tags) + foreign-toplevel (windows) */
	wl_list_init(&ipc_outputs);
	wl_global_create(dpy, &zdwl_ipc_manager_v2_interface, 2, NULL, ipcmgrbind);
	ftl_mgr = wlr_foreign_toplevel_manager_v1_create(dpy);
#ifdef HYPR
	exportsetup();
#endif

	/* Make sure XWayland clients don't connect to the parent X server,
	 * e.g when running in the x11 backend or the wayland backend and the
	 * compositor has Xwayland support */
	unsetenv("DISPLAY");
#ifdef XWAYLAND
	/*
	 * Initialise the XWayland X server.
	 * It will be started when the first X client is started.
	 */
	if ((xwayland = wlr_xwayland_create(dpy, compositor, 1))) {
		wl_signal_add(&xwayland->events.ready, &xwayland_ready);
		wl_signal_add(&xwayland->events.new_surface, &new_xwayland_surface);

		setenv("DISPLAY", xwayland->display_name, 1);
	} else {
		fprintf(stderr, "failed to setup XWayland X server, continuing without it\n");
	}
#endif
}

/* A child that has forked but not exec'd still shares the compositor's
 * wlroots and GL state, so it has to leave through _exit(): exit() runs the
 * handlers that tear that state down, which crashes, and the crash handler
 * then dumps core over nothing worse than a missing binary. */
void
childdie(const char *what, const char *cmd)
{
	fprintf(stderr, "phonegluewc: %s %s failed: ", what, cmd);
	perror(NULL);
	_exit(1);
}

void
spawn(const Arg *arg)
{
	if ((spawned_pid = fork()) == 0) {
		dup2(STDERR_FILENO, STDOUT_FILENO);
		setsid();
		if (spawn_dir && chdir(spawn_dir) < 0)
			childdie("chdir", spawn_dir);
		execvp(((char **)arg->v)[0], (char **)arg->v);
		childdie("execvp", ((char **)arg->v)[0]);
	}
}

void
startdrag(struct wl_listener *listener, void *data)
{
	struct wlr_drag *drag = data;
	if (!drag->icon)
		return;

	drag->icon->data = &wlr_scene_drag_icon_create(drag_icon, drag->icon)->node;
	LISTEN_STATIC(&drag->icon->events.destroy, destroydragicon);
}

/* over the lock while locked, back under the block layer after */
static void
keyboardoverlock(void)
{
	Monitor *m;
	LayerSurface *l;
	struct wlr_scene_tree *tree;

	wl_list_for_each(m, &mons, link)
		wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link) {
			tree = layertree(l->layer_surface, l->layer_surface->current.layer);
			if (tree != layers[LyrBlock] && l->scene->node.parent != layers[LyrBlock])
				continue;
			wlr_scene_node_reparent(&l->scene->node, tree);
			if (tree == layers[LyrBlock])
				wlr_scene_node_raise_to_top(&l->scene->node);
		}
}

static void
spawnshell(void)
{
	const char *shell = getenv("PHONEGLUEWC_SHELL"), *r = getenv("WLR_RENDERER");
	/* GPU unless the compositor draws in software or software is asked for, as the tests do */
	const char *q = getenv("QT_QUICK_BACKEND");
	int soft = (r && !strcmp(r, "pixman")) || getenv("PHONEGLUEWC_SOFTWARE_SHELL") || (q && !strcmp(q, "software"));
	Arg a = {.v = (const char *[]){ "env", soft ? "QT_QUICK_BACKEND=software" : "QT_QUICK_BACKEND=",
		"qs", "-p", shell ? shell : SHELLDIR, NULL }};

	if (shell && !*shell)
		return;
	spawn(&a);
	shell_pid = spawned_pid;
}

/* the lock's client died: the screen stays locked, and a new shell brings the password
 * field back; after too many tries it stays black and locked */
static int
relock(void *data)
{
	if (!locked || cur_lock || relock_tries >= 5)
		return 0;
	relock_tries++;
	if (shell_pid > 0)
		kill(shell_pid, SIGKILL);
	setenv("PHONEGLUEWC_RELOCK", "1", 1);
	spawnshell();
	unsetenv("PHONEGLUEWC_RELOCK");
	/* it can die before it locks: look again */
	wl_event_source_timer_update(relock_timer, 5000);
	return 0;
}

/* the settings app's switch wins over config.conf */
static void
readphoneconf(void)
{
	char path[512], line[128], v[8];
	const char *env;
	FILE *f;

	if ((env = getenv("XDG_CONFIG_HOME")) && *env)
		snprintf(path, sizeof path, "%s/phonegluewc/phone.conf", env);
	else
		snprintf(path, sizeof path, "%s/.config/phonegluewc/phone.conf", getenv("HOME") ? getenv("HOME") : "");
	home_upright = 0;
	overview_grid = 0;
	if (!(f = fopen(path, "r")))
		return;
	while (fgets(line, sizeof line, f))
		if (sscanf(line, " animations = %7s", v) == 1)
			animations = !!strcmp(v, "off");
		else if (sscanf(line, " home_rotate = %7s", v) == 1)
			home_upright = !strcmp(v, "off");
		else if (sscanf(line, " overview = %7s", v) == 1)
			overview_grid = !strcmp(v, "grid");
	fclose(f);
}

void
reloadconfig(const Arg *arg)
{
	Client *c;
	Monitor *m;
	struct xkb_context *context;
	struct xkb_keymap *keymap;
	size_t i;

	for (i = 0; i < nautostarts; i++)
		free(autostarts[i]);
	nautostarts = 0;
	macrofreeall();
	free(runkeys);
	free(runnormalkeys);
	runkeys = runnormalkeys = NULL;
	nrunkeys = nrunnormalkeys = 0;
	readconfig();
	readphoneconf();
	cfgerrorshow();
	wl_list_for_each(m, &mons, link)
		animstop(m);
	applyoutputcfgs();

	wlr_scene_set_blur_data(scene, blur_passes, blur_radius, 0.02f, 0.9f, 0.9f, 1.1f);
	wlr_scene_rect_set_color(root_bg, rootcolor);

	if ((context = xkb_context_new(XKB_CONTEXT_NO_FLAGS))) {
		if ((keymap = xkb_keymap_new_from_names(context, &xkb_rules,
				XKB_KEYMAP_COMPILE_NO_FLAGS))) {
			wlr_keyboard_set_keymap(&kb_group->wlr_group->keyboard, keymap);
			xkb_keymap_unref(keymap);
		}
		xkb_context_unref(context);
	}
	wlr_keyboard_set_repeat_info(&kb_group->wlr_group->keyboard,
			repeat_rate, repeat_delay);

	wl_list_for_each(c, &clients, link) {
		if (!c->isfullscreen)
			c->bw = decorhidden ? 0 : borderpx;
		client_set_border_color(c, bordercolor);
		applyeffects(c);
		if (c->isfloating)
			resize(c, c->geom, 0);
	}
	focusclient(focustop(selmon), 1);
	wl_list_for_each(m, &mons, link)
		arrange(m);
}

void
setratio(const Arg *arg)
{
	Client *sel = focustop(selmon);
	if (!sel)
		return;
	if (sel->col) {
		/* resize the column, like niri's set-column-width +/- */
		sel->col->wfrac += arg->f;
		if (sel->col->wfrac < 0.15f)
			sel->col->wfrac = 0.15f;
		if (sel->col->wfrac > 1.0f)
			sel->col->wfrac = 1.0f;
		arrange(selmon);
		return;
	}
	if (!sel->node || !sel->node->par)
		return;
	sel->node->par->ratio += arg->f;
	if (sel->node->par->ratio < 0.1f)
		sel->node->par->ratio = 0.1f;
	if (sel->node->par->ratio > 0.9f)
		sel->node->par->ratio = 0.9f;
	arrange(selmon);
}

void
swapnodes(Client *sel, Client *t)
{
	Node *a = sel->node, *b = t->node;
	a->c = t;
	b->c = sel;
	sel->node = b;
	t->node = a;
	arrange(selmon);
	warpto(sel);
}

void
swapdir(const Arg *arg)
{
	Client *sel = focustop(selmon), *t;
	if (!sel || sel->isfloating || sel->isfullscreen || sel->isfakefull)
		return;
	if (sel->oncanvas) {
		/* nothing to swap on a canvas: move the window instead */
		driftnudge(arg);
		return;
	}
	if (sel->col) {
		scroll_swap(sel, arg->i);
		return;
	}
	if (!sel->node)
		return;
	if (!(t = dirpick(selmon, sel, arg->i)) || !t->node)
		return;
	swapnodes(sel, t);
}

void
swapstack(const Arg *arg)
{
	/* swap with the next (+1) or previous (-1) leaf in tree order */
	Client *sel = focustop(selmon);
	Node *n;
	if (!sel || sel->isfullscreen || sel->isfakefull || !selmon)
		return;
	if (sel->col) {
		scroll_swap(sel, arg->i > 0 ? DirRight : DirLeft);
		return;
	}
	if (!sel->node)
		return;
	n = arg->i > 0 ? bsp_nextleaf(selmon->tree[sel->ws], sel->node)
			: bsp_prevleaf(selmon->tree[sel->ws], sel->node);
	if (n && n->c != sel)
		swapnodes(sel, n->c);
}

void
toggledecor(const Arg *arg)
{
	Client *c;
	Monitor *m;
	decorhidden ^= 1;
	wl_list_for_each(c, &clients, link) {
		if (!c->isfullscreen && !c->isfakefull)
			c->bw = decorhidden ? 0 : borderpx;
		applyeffects(c);
		if (c->isfloating)
			resize(c, c->geom, 0);
	}
	wl_list_for_each(m, &mons, link)
		arrange(m);
}

void
applyfakefull(Client *c)
{
	/* scroll layout: fake fullscreen covers the whole output (above bars),
	 * so its scene node has to move between the tile and fullscreen layers */
	if (!c->mon || c->isfullscreen)
		return;
	c->bw = (c->isfakefull || decorhidden) ? 0 : borderpx;
	if (c->isfloating || !client_surface(c)->mapped)
		return;
	wlr_scene_node_reparent(&c->scene->node,
			layers[c->isfakefull && SCROLLLT(c->mon) ? LyrFS : LyrTile]);
}

void
togglefakefullscreen(const Arg *arg)
{
	Client *sel = focustop(selmon);
	if (!sel)
		return;
	if (sel->isfullscreen)
		setfullscreen(sel, 0);
	if (SCROLLLT(selmon) && sel->col && !sel->isfloating
			&& !sel->isfakefull) {
		/* scroll layout: no fullscreen - just make the column as wide as
		 * the screen and back, like a right-drag resize to full width */
		scroll_maximize(sel);
		return;
	}
	sel->isfakefull ^= 1;
	applyeffects(sel);
	if (sel->isfakefull) {
		sel->prev = sel->geom;
		if (sel->isfloating)
			setfloating(sel, 0);
	} else if (sel->isfloating) {
		resize(sel, sel->prev, 0);
	}
	applyfakefull(sel);
	arrange(selmon);
}

void
togglefloating(const Arg *arg)
{
	Client *sel = focustop(selmon);
	/* return if fullscreen */
	if (!sel || sel->isfullscreen || sel->isfakefull)
		return;
	if (!sel->isfloating && selmon) {
		/* float centered at 3/5 of the window area, like nvwm */
		struct wlr_box b;
		b.width = MAX(50, selmon->w.width * 3 / 5);
		b.height = MAX(50, selmon->w.height * 3 / 5);
		b.x = selmon->w.x + (selmon->w.width - b.width) / 2;
		b.y = selmon->w.y + (selmon->w.height - b.height) / 2;
		sel->isfloating = 1;
		resize(sel, b, 0);
		setfloating(sel, 1);
	} else {
		setfloating(sel, !sel->isfloating);
	}
}

void
togglefullscreen(const Arg *arg)
{
	Client *sel = focustop(selmon);
	if (sel)
		setfullscreen(sel, !sel->isfullscreen);
}

void
togglesplit(const Arg *arg)
{
	Client *sel = focustop(selmon);
	if (!sel)
		return;
	if (sel->col) {
		scroll_maximize(sel);
		return;
	}
	if (!sel->node || !sel->node->par)
		return;
	sel->node->par->horiz ^= 1;
	arrange(selmon);
}

/* the windows of the workspace just shown come in from that side */
static int
wsslidein(Monitor *m, int dir)
{
	Client *c;
	int started = 0;

	wl_list_for_each(c, &clients, link) {
		if (c->mon != m || !VISIBLEON(c, m)
				|| !c->scene->node.enabled || client_is_unmanaged(c))
			continue;
		c->anim.from.x = c->geom.x + (SCROLLLT(m) ? 0 : dir * m->m.width);
		c->anim.from.y = c->geom.y + (SCROLLLT(m) ? dir * m->m.height : 0);
		c->anim.to.x = c->geom.x;
		c->anim.to.y = c->geom.y;
		c->anim.fadein = 0;
		c->anim.workspace = 1;
		c->anim.hide = 0;
		c->anim.swipe = 0;
		c->anim.active = 1;
		c->anim.t = 0.0f;
		clientplace(c, c->anim.from.x, c->anim.from.y);
		started = 1;
	}
	return started;
}

void
viewws(const Arg *arg)
{
	Client *c;
	unsigned int oldws, forward, backward;
	int animate, dir, started = 0;

	if (!selmon || selmon->ws == arg->ui || arg->ui > wslimit(selmon))
		return;
	wlr_log(WLR_DEBUG, "viewws: %u -> %u", selmon->ws, arg->ui);
	oldws = selmon->ws;
	forward = (arg->ui + NUMWS - oldws) % NUMWS;
	backward = (oldws + NUMWS - arg->ui) % NUMWS;
	dir = forward <= backward ? 1 : -1;
	animate = animations && animation_duration > 0 && !overview_visible;
	/* always settle whatever was still moving: an animation left running
	 * across a switch finishes against the new workspace and takes windows
	 * that belong to it off screen */
	animstop(selmon);
	arrange(selmon);
	if (animate) {
		wl_list_for_each(c, &clients, link) {
			if (c->mon != selmon || c->ws != oldws
					|| !c->scene->node.enabled || client_is_unmanaged(c))
				continue;
			c->anim.from.x = c->scene->node.x;
			c->anim.from.y = c->scene->node.y;
			/* workspaces slide horizontally in BSP, vertically (like
			 * niri, one after another) in the scroll layout */
			c->anim.to.x = c->geom.x
					- (SCROLLLT(selmon) ? 0 : dir * selmon->m.width);
			c->anim.to.y = c->geom.y
					- (SCROLLLT(selmon) ? dir * selmon->m.height : 0);
			c->anim.fadein = 0;
			c->anim.workspace = 1;
			c->anim.hide = 1;
			c->anim.swipe = 0;
			c->anim.active = 1;
			c->anim.t = 0.0f;
			started = 1;
		}
	}
	selmon->ws = arg->ui;
	if (!overview_visible)
		focusclient(focustop(selmon), 1);
	arrange(selmon);
	if (animate)
		started |= wsslidein(selmon, dir);
	if (animate && started)
		animkick(selmon);
}

/* the cards keep their place on screen while their numbers change */
static void
wscompactcards(Monitor *m, int slots, int fadeleft, int faderight)
{
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	struct wlr_box target[3], center = m->overview[1];
	int i, stepx, stepy, held = touch_gesture == 4 && finger.m == m && finger.mode == 1;

	/* the pill's finger places the cards itself on its next move */
	if (!overview_active || (touch_gesture == 3 && finger.m == m))
		return;
	/* shortcut: grid cards jump to their new places, slide them if it looks abrupt */
	if (GRIDLT(m)) {
		grid_ws = -1;
		overviewbuild();
		return;
	}
	overviewtargets(m, target);
	stepx = target[2].x - target[1].x;
	stepy = target[2].y - target[1].y;
	for (i = 0; i < 3; i++) {
		m->overview[i] = center;
		m->overview[i].x += (i - 1 + slots) * stepx;
		m->overview[i].y += (i - 1 + slots) * stepy;
		m->overview_opacity[i] = 1.0f;
	}
	if (held) {
		finger.x0 -= slots * stepx;
		return;
	}
	if (fadeleft)
		m->overview_opacity[0] = 0.0f;
	if (faderight)
		m->overview_opacity[2] = 0.0f;
	card_close.from = card_close.dy;
	overviewtransition(m, target, shown, 1.0f);
}

/* one free workspace, always the rightmost: every way a window leaves one ends here */
static int
wscompact(Monitor *m)
{
	static int busy;
	int map[NUMWS], order[NUMWS], scrollx[NUMWS];
	Node *tree[NUMWS];
	struct wl_list cols[NUMWS];
	double camx[NUMWS], camy[NUMWS], camz[NUMWS];
	unsigned int occ = 0, oldmask = m->wsmask, oldws = m->ws, newws;
	int i, e, n = 0, moved = 0, emptied, left = -1, slots = 0;
	Client *c;

	if (busy)
		return 0;
	for (i = 0; i < NUMWS; i++) {
		map[i] = -1;
		if (wsoccupied(m, (unsigned int)i)) {
			occ |= 1u << i;
			moved |= n != i;
			map[i] = n;
			order[n++] = i;
		}
	}
	m->wsmask = occ;
	emptied = (oldmask >> oldws & 1) && !(occ >> oldws & 1);
	if (!moved && !emptied && (int)oldws <= MIN(n, NUMWS - 1))
		return 0;
	busy = 1;
	if (wsdrag.active && wsdrag.m == m)
		wsdragend(1, 0);
	for (i = (int)oldws - 1; i >= 0 && left < 0; i--)
		left = map[i];
	if (occ >> oldws & 1) {
		newws = (unsigned int)map[oldws];
	} else if (emptied && left >= 0) {
		newws = (unsigned int)left;
		slots = -1;
	} else if (emptied && n && GRIDLT(m)) {
		/* the grid hides the free card: the first one, not an invisible one */
		newws = 0;
	} else {
		newws = (unsigned int)MIN(n, NUMWS - 1);
		/* the card that was on the right ends up on the left of the free one */
		slots = emptied && n ? 2 : 0;
	}

	e = n;
	for (i = 0; i < NUMWS; i++) {
		if (map[i] < 0)
			order[e++] = i;
	}
	for (i = 0; i < NUMWS; i++) {
		int from = order[i];

		tree[i] = m->tree[from];
		wl_list_init(&cols[i]);
		wl_list_insert_list(&cols[i], &m->cols[from]);
		wl_list_init(&m->cols[from]);
		scrollx[i] = i < n ? m->scrollx[from] : 0;
		camx[i] = i < n ? m->camx[from] : 0.0;
		camy[i] = i < n ? m->camy[from] : 0.0;
		camz[i] = i < n ? m->camz[from] : 1.0;
	}
	for (i = 0; i < NUMWS; i++) {
		m->tree[i] = tree[i];
		wl_list_insert_list(&m->cols[i], &cols[i]);
		m->scrollx[i] = scrollx[i];
		m->camx[i] = camx[i];
		m->camy[i] = camy[i];
		m->camz[i] = camz[i];
	}
	wl_list_for_each(c, &clients, link) {
		if (c->mon == m && c->ws < NUMWS)
			c->ws = map[c->ws] >= 0 ? (unsigned int)map[c->ws] : newws;
	}
	m->ws = newws;
	m->wsmask = (1u << n) - 1;
	if (flick_ws >= 0)
		flick_ws = map[flick_ws];
	for (i = 0; i < 2; i++)
		if (flick_side_ws[i] >= 0)
			flick_side_ws[i] = map[flick_side_ws[i]];

	if (overview_visible && overviewvalid(m))
		wscompactcards(m, slots,
				!slots && oldws && newws && map[oldws - 1] != (int)newws - 1,
				!slots && oldws + 1 < NUMWS && (oldmask >> (oldws + 1) & 1)
				&& map[oldws + 1] != (int)newws + 1);
	if (m == selmon && !overview_visible && newws != oldws)
		focusclient(focustop(m), 1);
	arrange(m);
	if (slots < 0 && m == selmon && !overview_visible && animations && animation_duration > 0
			&& wsslidein(m, -1))
		animkick(m);
	if (overview_visible)
		overviewbuild();
	busy = 0;
	savewindowstate();
	ipcnotifyall();
	return 1;
}

void
movetows(const Arg *arg)
{
	Client *sel = focustop(selmon);
	if (!sel || !selmon || sel->ws == arg->ui
			|| (!sel->node && !sel->col && !sel->oncanvas))
		return;
	detachclient(sel);
	attachclient(selmon, arg->ui, sel);
	focusclient(focustop(selmon), 1);
	arrange(selmon);
}

void
movetowsfollow(const Arg *arg)
{
	Client *sel = focustop(selmon);
	if (!sel || !selmon || sel->ws == arg->ui
			|| (!sel->node && !sel->col && !sel->oncanvas))
		return;
	detachclient(sel);
	attachclient(selmon, arg->ui, sel);
	wscompact(selmon); /* the numbers may have closed up */
	{
		Arg a = {.ui = sel->ws};

		viewws(&a);
	}
}

void
wsstep(const Arg *arg)
{
	Arg a;
	int ws;
	if (!selmon || (ws = wsnext(selmon, arg->i)) < 0)
		return;
	a.ui = (unsigned int)ws;
	viewws(&a);
}

void
movewsstep(const Arg *arg)
{
	Arg a;
	int ws;
	if (!selmon || (ws = wsnext(selmon, arg->i)) < 0)
		return;
	a.ui = (unsigned int)ws;
	movetowsfollow(&a);
}

void
movedir(const Arg *arg)
{
	/* Mod+Ctrl+arrow: the window trades places with its neighbour in that
	 * direction, and once there is no neighbour left it goes on to the
	 * workspace that lies that way (up and down in the scroll layout,
	 * left and right in the others, as the workspaces are laid out). */
	Client *sel = focustop(selmon);
	int dir = arg->i, sideways;

	if (!sel || !selmon)
		return;
	if (sel->isfloating || sel->isfullscreen || sel->isfakefull
			|| sel->oncanvas) {
		movewsdir(arg);
		return;
	}
	sideways = dir == DirLeft || dir == DirRight;
	if (sel->col) {
		if (sideways) {
			struct wl_list *pos = dir == DirLeft ? sel->col->link.prev
					: sel->col->link.next;
			if (pos != &selmon->cols[sel->ws]) {
				scroll_swap(sel, dir);
				return;
			}
		} else {
			struct wl_list *pos = dir == DirUp ? sel->clink.prev
					: sel->clink.next;
			if (pos != &sel->col->clients) {
				scroll_swap(sel, dir);
				return;
			}
		}
		movewsdir(arg);
		return;
	}
	if (sel->node && dirpick(selmon, sel, dir)) {
		swapdir(arg);
		return;
	}
	movewsdir(arg);
}

void
movewsdir(const Arg *arg)
{
	/* Take the window along to the workspace in that direction, on the
	 * same axis focusdir() steps along when there is nothing left to focus:
	 * the scroll layout stacks workspaces vertically like niri, the others
	 * lay them out left to right. A press across the axis does nothing. */
	Arg a;

	if (!selmon)
		return;
	if (SCROLLLT(selmon) ? (arg->i == DirLeft || arg->i == DirRight)
			: (arg->i == DirUp || arg->i == DirDown))
		return;
	a.i = (arg->i == DirLeft || arg->i == DirUp) ? -1 : +1;
	movewsstep(&a);
}

void
warpto(Client *c)
{
	if (!warpcursor || !c)
		return;
	wlr_cursor_warp_closest(cursor, NULL,
			c->geom.x + c->geom.width / 2.0,
			c->geom.y + c->geom.height / 2.0);
	motionnotify(0, NULL, 0, 0, 0, 0);
}

void
unlocksession(struct wl_listener *listener, void *data)
{
	SessionLock *lock = wl_container_of(listener, lock, unlock);
	destroylock(lock, 1);
}

void
unmaplayersurfacenotify(struct wl_listener *listener, void *data)
{
	LayerSurface *l = wl_container_of(listener, l, unmap);

	if (!l->anim.closing && layeranimated(l))
		l->anim.closing = closeanimstart(&l->scene->node,
				layers[layermap[l->layer_surface->current.layer]], l->mon);
	l->anim.active = 0;
	l->anim.closing = 0;
	layeropacity(l, 1.0f);
	l->mapped = 0;
	wlr_scene_node_set_enabled(&l->scene->node, 0);
	if (l == exclusive_focus)
		exclusive_focus = NULL;
	if (l->layer_surface->output && (l->mon = l->layer_surface->output->data))
		arrangelayers(l->mon);
	if (l->layer_surface->surface == seat->keyboard_state.focused_surface)
		focusclient(focustop(selmon), 1);
	motionnotify(0, NULL, 0, 0, 0, 0);
}

void
unmapnotify(struct wl_listener *listener, void *data)
{
	/* Called when the surface is unmapped, and should no longer be shown. */
	Client *c = wl_container_of(listener, c, unmap);
#ifdef HYPR
	exportforget(c);
#endif
	clientcloseanim(c);
	c->anim.closing = 0;
	if (c == grabc) {
		cursor_mode = CurNormal;
		grabc = NULL;
		bsp_grabh = bsp_grabv = NULL;
	}
	if (c == card_close.c) {
		card_close.c = NULL;
		wl_event_source_timer_update(card_close_timer, 0);
	}
	if (c == overview_drag_client) {
		overview_drag_client = NULL;
		overview_dragging = 0;
		overviewdragclear();
	}
	{
		size_t i;

		for (i = 0; i < LENGTH(placements); i++)
			if (placements[i].anchor == c)
				placements[i].anchor = NULL;
	}
	if (c == overview_focus_client)
		overview_focus_client = NULL;

	if (c->ftl) {
		wl_list_remove(&c->ftl_activate.link);
		wl_list_remove(&c->ftl_close.link);
		wlr_foreign_toplevel_handle_v1_destroy(c->ftl);
		c->ftl = NULL;
	}
	c->surfbuf = NULL;

	if (client_is_unmanaged(c)) {
		if (c == exclusive_focus) {
			exclusive_focus = NULL;
			focusclient(focustop(selmon), 1);
		}
	} else {
		wl_list_remove(&c->link);
		setmon(c, NULL, 0);
		wl_list_remove(&c->flink);
		savewindowstate();
	}

	wlr_scene_node_destroy(&c->scene->node);
	c->border.top = c->border.bottom = NULL;
	c->border.left = c->border.right = NULL;
	c->border.top_left = c->border.top_right = NULL;
	c->border.bottom_right = c->border.bottom_left = NULL;
	c->blur = NULL;
	motionnotify(0, NULL, 0, 0, 0, 0);
	ipcnotifyall();
	if (overview_visible)
		overviewbuild();
}

void
updatemons(struct wl_listener *listener, void *data)
{
	/*
	 * Called whenever the output layout changes: adding or removing a
	 * monitor, changing an output's mode or position, etc. This is where
	 * the change officially happens and we update geometry, window
	 * positions, focus, and the stored configuration in wlroots'
	 * output-manager implementation.
	 */
	struct wlr_output_configuration_v1 *config
			= wlr_output_configuration_v1_create();
	Client *c;
	struct wlr_output_configuration_head_v1 *config_head;
	Monitor *m;
	int tw, th;

	placemirrors();

	/* First remove from the layout the disabled monitors */
	wl_list_for_each(m, &mons, link) {
		if (m->wlr_output->enabled || m->asleep)
			continue;
		config_head = wlr_output_configuration_head_v1_create(config, m->wlr_output);
		config_head->state.enabled = 0;
		/* Remove this output from the layout to avoid cursor enter inside it */
		wlr_output_layout_remove(output_layout, m->wlr_output);
		closemon(m);
		m->m = m->w = (struct wlr_box){0};
	}
	/* Insert outputs that need to */
	wl_list_for_each(m, &mons, link) {
		if (m->wlr_output->enabled && !m->mirroring
				&& !wlr_output_layout_get(output_layout, m->wlr_output))
			wlr_output_layout_add_auto(output_layout, m->wlr_output);
	}

	/* Now that we update the output layout we can get its box */
	wlr_output_layout_get_box(output_layout, NULL, &sgeom);

	wlr_scene_node_set_position(&root_bg->node, sgeom.x, sgeom.y);
	/* one more than the layout box: windows reach the output's last rows (see below) */
	wlr_scene_rect_set_size(root_bg, sgeom.width + 1, sgeom.height + 1);

	/* Make sure the clients are hidden when phonegluewc is locked */
	wlr_scene_node_set_position(&locked_bg->node, sgeom.x, sgeom.y);
	wlr_scene_rect_set_size(locked_bg, sgeom.width + 1, sgeom.height + 1);

	wl_list_for_each(m, &mons, link) {
		if (!m->wlr_output->enabled)
			continue;
		config_head = wlr_output_configuration_head_v1_create(config, m->wlr_output);

		/* Get the effective monitor geometry to use for surfaces */
		wlr_output_layout_get_box(output_layout, m->wlr_output, &m->m);
		/* the layout box rounds down: at a fractional scale the last rows would stay unpainted */
		wlr_output_transformed_resolution(m->wlr_output, &tw, &th);
		m->m.width = (int)ceil(tw / m->wlr_output->scale);
		m->m.height = (int)ceil(th / m->wlr_output->scale);
		m->w = m->m;
		wlr_scene_output_set_position(m->scene_output, m->m.x, m->m.y);

		wlr_scene_node_set_position(&m->fullscreen_bg->node, m->m.x, m->m.y);
		wlr_scene_rect_set_size(m->fullscreen_bg, m->m.width, m->m.height);

		if (m->lock_surface) {
			struct wlr_scene_tree *scene_tree = m->lock_surface->surface->data;
			wlr_scene_node_set_position(&scene_tree->node, m->m.x, m->m.y);
			wlr_session_lock_surface_v1_configure(m->lock_surface, m->m.width, m->m.height);
		}

		/* a mirror has nothing of its own to lay out */
		if (!m->mirroring) {
			/* Calculate the effective monitor geometry to use for clients */
			arrangelayers(m);
			/* Don't move clients to the left output when plugging monitors */
			arrange(m);
			/* make sure fullscreen clients have the right size */
			if ((c = focustop(m)) && c->isfullscreen)
				resize(c, m->m, 0);
			arrangehidden(m);
		}

		/* Try to re-set the gamma LUT when updating monitors,
		 * it's only really needed when enabling a disabled output, but meh. */
		m->gamma_lut_changed = 1;

		config_head->state.x = m->m.x;
		config_head->state.y = m->m.y;

		if (!selmon && !m->mirroring) {
			selmon = m;
		}
	}

	if (selmon && selmon->wlr_output->enabled) {
		wl_list_for_each(c, &clients, link) {
			if (!c->mon && client_surface(c)->mapped)
				setmon(c, selmon, c->ws);
		}
		if (!overview_visible)
			focusclient(focustop(selmon), 1);
		if (selmon->lock_surface) {
			client_notify_enter(selmon->lock_surface->surface,
					wlr_seat_get_keyboard(seat));
			client_activate_surface(selmon->lock_surface->surface, 1);
		}
	}

	/* FIXME: figure out why the cursor image is at 0,0 after turning all
	 * the monitors on.
	 * Move the cursor image where it used to be. It does not generate a
	 * wl_pointer.motion event for the clients, it's only the image what it's
	 * at the wrong position after all. */
	wlr_cursor_move(cursor, NULL, 0, 0);

	wlr_output_manager_v1_set_configuration(output_mgr, config);
	if (overview_visible)
		overviewrelayout();
	saveoutputstate();
	touchmap();
}

void
updatetitle(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, set_title);
	const char *title = client_get_title(c);
	if (c->ftl && title)
		wlr_foreign_toplevel_handle_v1_set_title(c->ftl, title);
	ipcnotifyall();
}

void
updateappid(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, set_app_id);
	const char *appid = client_get_appid(c);

	if (c->ftl && appid)
		wlr_foreign_toplevel_handle_v1_set_app_id(c->ftl, appid);
	savewindowstate();
	ipcnotifyall();
}

static TouchPoint *
touchfind(int32_t id)
{
	int i;

	for (i = 0; i < touch_n; i++)
		if (touch_pts[i].id == id)
			return &touch_pts[i];
	return NULL;
}

/* the screen is the one the device names, otherwise the built-in panel; wlr_cursor
 * only applies an output's rotation to a mapped device, hence the lone monitor case */
void
touchmap(void)
{
	TouchDevice *d;
	Monitor *m;

	wl_list_for_each(d, &touch_devices, link) {
		struct wlr_output *o = NULL;

		wl_list_for_each(m, &mons, link) {
			const char *name = m->wlr_output->name;

			if (d->touch->output_name ? !strcmp(name, d->touch->output_name)
					: !o && (!strncmp(name, "eDP", 3) || !strncmp(name, "DSI", 3)
						|| !strncmp(name, "LVDS", 4)))
				o = m->wlr_output;
		}
		if (!o && wl_list_length(&mons) == 1) {
			m = wl_container_of(mons.next, m, link);
			o = m->wlr_output;
		}
		wlr_cursor_map_input_to_output(cursor, &d->touch->base, o);
	}
}

static void
touchdevicedestroy(struct wl_listener *listener, void *data)
{
	TouchDevice *d = wl_container_of(listener, d, destroy);

	wl_list_remove(&d->destroy.link);
	wl_list_remove(&d->link);
	free(d);
}

void
createtouch(struct wlr_touch *touch)
{
	TouchDevice *d = ecalloc(1, sizeof(*d));

	d->touch = touch;
	wl_list_insert(&touch_devices, &d->link);
	LISTEN(&touch->base.events.destroy, &d->destroy, touchdevicedestroy);
	wlr_cursor_attach_input_device(cursor, &touch->base);
	touchmap();
}

static void
touchbutton(uint32_t time, enum wl_pointer_button_state state)
{
	struct wlr_pointer_button_event event = {
		.time_msec = time, .button = BTN_LEFT, .state = state };

	buttonpress(NULL, &event);
	wlr_seat_pointer_notify_frame(seat);
}

static void
touchpointermove(uint32_t time, double lx, double ly)
{
	wlr_cursor_warp(cursor, NULL, lx, ly);
	motionnotify(time, NULL, 0, 0, 0, 0);
	wlr_seat_pointer_notify_frame(seat);
}


static int
pillzone(Monitor *m, double x, double y)
{
	double up;
	LayerSurface *l;

	if (!m || greeter)
		return 0;
	up = m->m.y + m->m.height - y;
	/* with the keyboard up what its input region takes is its own, the rest of the strip ours */
	if ((l = keyboardlayer(m)))
		return up <= PILL_ZONE && !wlr_surface_point_accepts_input(l->layer_surface->surface,
				x - l->scene->node.x, y - l->scene->node.y);
	/* the shown bar is all ours, and the overview always shows it */
	return up <= (bar_shown || overview_active ? PILL_ZONE : BAR_ZONE);
}

/* shortcut: a pointer that leaves the window sends nothing here, so the bar stays until it is back */
static void
barhover(void)
{
	Monitor *m = xytomon(cursor->x, cursor->y);
	int in = m && !locked && !greeter && !overview_visible
			&& m->m.y + m->m.height - cursor->y <= (bar_shown ? PILL_ZONE : BAR_ZONE);

	if (in == bar_hover || touch_n)
		return;
	bar_hover = in;
	barset(in || bar_shown);
}

/* while screen text is open it owns the bar and every finger */
static int
screentextopen(Monitor *m)
{
	LayerSurface *l;

	if (!m)
		return 0;
	wl_list_for_each(l, &m->layers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], link)
		if (l->mapped && !strcmp(l->layer_surface->namespace, SCREENTEXT_NAMESPACE))
			return 1;
	return 0;
}

static int
layerwantskeyboard(Monitor *m)
{
	LayerSurface *l;
	int i;

	for (i = ZWLR_LAYER_SHELL_V1_LAYER_TOP; i <= ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY; i++) {
		wl_list_for_each(l, &m->layers[i], link) {
			if (l->mapped && l->layer_surface->current.keyboard_interactive)
				return 1;
		}
	}
	return 0;
}

static void
fingerbegin(int gesture, int32_t id, double x, double y, uint32_t time, Monitor *m)
{
	finger.id = id;
	finger.mode = 0;
	finger.x0 = finger.x = x;
	finger.y0 = finger.y = y;
	finger.velx = finger.vely = 0.0;
	finger.t0 = finger.time = time;
	finger.moved = 0;
	finger.caught = 0;
	finger.m = m;
	finger.hist[0].x = x;
	finger.hist[0].y = y;
	finger.hist[0].t = time;
	finger.nhist = 1;
	touch_gesture = gesture;
	if (gesture == 3)
		pill_a = keyboardshown(m) ? 1.0f : bar_t;
}

#define VEL_WINDOW 100 /* ms: older samples say nothing about the release */
/* speed over the samples of the last VEL_WINDOW ms, so a pause before the lift counts as none */
static void
fingertrack(double x, double y, uint32_t time)
{
	int i, n = (int)LENGTH(finger.hist), k = (finger.nhist - 1) % n, j;

	if (time != finger.time) {
		k = finger.nhist++ % n;
		finger.time = time;
	}
	finger.hist[k].x = x;
	finger.hist[k].y = y;
	finger.hist[k].t = time;
	finger.velx = finger.vely = 0.0;
	for (i = MIN(finger.nhist, n) - 1; i > 0; i--) {
		j = (k - i + n) % n;
		if (time - finger.hist[j].t <= VEL_WINDOW && time != finger.hist[j].t) {
			finger.velx = (x - finger.hist[j].x) / (time - finger.hist[j].t);
			finger.vely = (y - finger.hist[j].y) / (time - finger.hist[j].t);
			break;
		}
	}
	finger.x = x;
	finger.y = y;
}

#define PILL_FOLLOW_X 0.5
#define PILL_FOLLOW_Y 0.35
#define FLICK_CARD 0.38f

/* --- edge swipes: right edge is back, left edge is the keyboard --- */
#define EDGE_ZONE 20
#define EDGE_SLOP 8
#define EDGE_DIST 72
#define EDGE_HOLD_MS 200
#define EDGE_ICON 52
#define EDGE_ICON_MIN 30

struct edgeicon {
	struct wlr_buffer base;
	uint32_t *px;
};
static struct edgeicon *edge_icons[2]; /* before and past the threshold */
static float edge_icon_scale;

static void
edgeicondestroy(struct wlr_buffer *b)
{
	struct edgeicon *i = wl_container_of(b, i, base);

	wlr_buffer_finish(b);
	free(i->px);
	free(i);
}

static bool
edgeiconaccess(struct wlr_buffer *b, uint32_t flags, void **data, uint32_t *format, size_t *stride)
{
	struct edgeicon *i = wl_container_of(b, i, base);

	if (flags & WLR_BUFFER_DATA_PTR_ACCESS_WRITE)
		return false;
	*data = i->px;
	*format = DRM_FORMAT_ARGB8888;
	*stride = b->width * 4;
	return true;
}

static void
edgeiconaccessend(struct wlr_buffer *b)
{
}

static const struct wlr_buffer_impl edgeicon_impl = {
	.destroy = edgeicondestroy,
	.begin_data_ptr_access = edgeiconaccess,
	.end_data_ptr_access = edgeiconaccessend,
};

static double
segdist(double px, double py, double ax, double ay, double bx, double by)
{
	double dx = bx - ax, dy = by - ay;
	double t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);

	t = MAX(0.0, MIN(1.0, t));
	return hypot(px - ax - t * dx, py - ay - t * dy);
}

/* one pixel wide edge, the distances are in pixels */
static double
edgecover(double d)
{
	return MAX(0.0, MIN(1.0, 0.5 - d));
}

/* a chevron pointing left, with round ends, on a soft rounded square */
static struct edgeicon *
edgeiconmake(float scale, int armed)
{
	int n = (int)ceil(EDGE_ICON * scale), x, y;
	double pad = 3.0 * scale, half = n / 2.0 - pad, round = half * 0.46;
	double armx = half * 0.20, army = half * 0.42, tipx = -half * 0.24, line = half * 0.09;
	double bg = armed ? 0.95 : 0.11, fg = armed ? 0.08 : 0.92, bga = armed ? 1.0 : 0.92;
	struct edgeicon *i = ecalloc(1, sizeof(*i));

	i->px = ecalloc(n * n, sizeof(*i->px));
	wlr_buffer_init(&i->base, &edgeicon_impl, n, n);
	for (y = 0; y < n; y++) {
		for (x = 0; x < n; x++) {
			double px = x + 0.5 - n / 2.0, py = y + 0.5 - n / 2.0;
			double qx = fabs(px) - half + round, qy = fabs(py) - half + round;
			double d = hypot(MAX(qx, 0.0), MAX(qy, 0.0)) + MIN(MAX(qx, qy), 0.0) - round;
			double fade = d > 0 ? MAX(0.0, 1.0 - d / pad) : 1.0;
			double shadow = 0.30 * fade * fade;
			double a = edgecover(d) * bga;
			double c = MIN(segdist(px, py, tipx, 0, armx, -army),
					segdist(px, py, tipx, 0, armx, army)) - line;
			double ca = edgecover(c) * edgecover(d);
			double outa = a + shadow * (1.0 - a), v = bg * a;
			uint32_t pa, pv;

			v = fg * ca + v * (1.0 - ca);
			outa = ca + outa * (1.0 - ca);
			pa = (uint32_t)(outa * 255.0 + 0.5);
			pv = (uint32_t)(v * 255.0 + 0.5);
			i->px[y * n + x] = pa << 24 | pv << 16 | pv << 8 | pv;
		}
	}
	return i;
}

static double
edgepull(void)
{
	return edge_side > 0 ? finger.x0 - finger.x : finger.x - finger.x0;
}

/* no vibration path exists yet, this is where the tick at the threshold goes */
static void
edgehaptic(void)
{
}

static void
edgedraw(void)
{
	Monitor *m = finger.m;
	double pull = MAX(0.0, edgepull());
	int armed = pull >= EDGE_DIST, size;
	double inset, cx, cy;

	if (!edge_node) {
		edge_node = wlr_scene_buffer_create(layers[LyrPill], NULL);
		edge_node->point_accepts_input = closeaniminput;
	}
	if (edge_icon_scale != m->wlr_output->scale) {
		if (edge_icons[0]) {
			wlr_scene_buffer_set_buffer(edge_node, NULL);
			wlr_buffer_drop(&edge_icons[0]->base);
			wlr_buffer_drop(&edge_icons[1]->base);
		}
		edge_icon_scale = m->wlr_output->scale;
		edge_icons[0] = edgeiconmake(edge_icon_scale, 0);
		edge_icons[1] = edgeiconmake(edge_icon_scale, 1);
		edge_armed = -1;
	}
	if (armed != edge_armed) {
		if (armed && edge_armed == 0)
			edgehaptic();
		edge_armed = armed;
		wlr_scene_buffer_set_buffer(edge_node, &edge_icons[armed]->base);
		wlr_scene_buffer_set_transform(edge_node, edge_side > 0
				? WL_OUTPUT_TRANSFORM_NORMAL : WL_OUTPUT_TRANSFORM_FLIPPED);
	}
	size = armed ? EDGE_ICON : EDGE_ICON_MIN
			+ (int)((EDGE_ICON - 4 - EDGE_ICON_MIN) * pull / EDGE_DIST);
	inset = MIN(pull, EDGE_DIST) * 0.6 + MAX(0.0, pull - EDGE_DIST) * 0.12;
	cx = edge_side > 0 ? m->m.x + m->m.width - inset : m->m.x + inset;
	cy = MAX(m->w.y + size / 2.0, MIN(finger.y, m->w.y + m->w.height - size / 2.0));
	wlr_scene_buffer_set_dest_size(edge_node, size, size);
	wlr_scene_node_set_position(&edge_node->node, (int)round(cx - size / 2.0), (int)round(cy - size / 2.0));
	wlr_scene_node_set_enabled(&edge_node->node, 1);
}

/* 0 no back, 1 KEY_BACK, 2 Alt+Left. Alt+Left would type escape codes into a terminal */
static int
backkind(Client *c)
{
	static const char *const noback[] = { "alacritty", "foot", "footclient", "kitty", "st",
		"xterm", "urxvt", "uxterm", "konsole", "org.kde.konsole", "kgx", "org.gnome.Console",
		"org.wezfurlong.wezterm", "wezterm", "ghostty", "com.mitchellh.ghostty", "tilix",
		"terminator", "sakura", "termite", "rio", "org.gnome.Terminal", "gnome-terminal",
		"xfce4-terminal", "lxterminal", "qterminal" };
	const char *id = c ? client_get_appid(c) : NULL;
	size_t i;

	if (!id || !*id || !strcmp(id, "broken"))
		return 0;
	if (!strncasecmp(id, "waydroid", 8))
		return 1;
	for (i = 0; i < LENGTH(noback); i++)
		if (!strcasecmp(id, noback[i]))
			return 0;
	return 2;
}

static void
sendback(Client *c)
{
	int kind = backkind(c);
	uint32_t code = kind == 1 ? KEY_BACK : KEY_LEFT;

	if (!kind || !wlr_seat_get_keyboard(seat)
			|| seat->keyboard_state.focused_surface != client_surface(c))
		return;
	if (kind == 2)
		macromodifiers(WLR_MODIFIER_ALT);
	wlr_seat_keyboard_notify_key(seat, now_ms(), code, WL_KEYBOARD_KEY_STATE_PRESSED);
	wlr_seat_keyboard_notify_key(seat, now_ms(), code, WL_KEYBOARD_KEY_STATE_RELEASED);
	if (kind == 2)
		macrorestoremodifiers();
}

/* SIGUSR1 shows it and keeps it up, SIGUSR2 hides it even over a focused field */
static int
procatches(pid_t pid, int sig)
{
	char path[32], line[128];
	unsigned long long mask = 0;
	FILE *f;

	snprintf(path, sizeof path, "/proc/%d/status", (int)pid);
	if (!(f = fopen(path, "r")))
		return 0;
	while (fgets(line, sizeof line, f))
		if (sscanf(line, "SigCgt: %llx", &mask) == 1)
			break;
	fclose(f);
	return mask >> (sig - 1) & 1;
}

static void
keyboardforce(Monitor *m, int show)
{
	int sig = show ? SIGUSR1 : SIGUSR2;

	/* an uncaught signal would kill the keyboard */
	if (keyboard_pid > 0 && m && keyboardshown(m) != show && procatches(keyboard_pid, sig))
		kill(keyboard_pid, sig);
}

/* a keyboard left up with nobody touching burns into the OLED */
#define KBD_IDLE_MS 60000
static struct wl_event_source *kbd_idle;

static int
kbdidle(void *data)
{
	Monitor *m;

	wl_list_for_each(m, &mons, link)
		keyboardforce(m, 0);
	return 0;
}

static void
kbdactive(void)
{
	if (!kbd_idle)
		kbd_idle = wl_event_loop_add_timer(event_loop, kbdidle, NULL);
	wl_event_source_timer_update(kbd_idle, KBD_IDLE_MS);
}

/* what the finger starts on must stay a normal touch unless this says otherwise */
static int
edgezone(Monitor *m, double x, double y)
{
	LayerSurface *l = NULL;
	int side;

	if (!m || greeter || locked || overview_active || overview_visible || screentextopen(m)
			|| y < m->w.y || y >= m->w.y + m->w.height)
		return 0;
	side = x >= m->m.x + m->m.width - EDGE_ZONE ? 1 : x < m->m.x + EDGE_ZONE ? -1 : 0;
	if (!side || (side > 0 ? !backkind(focustop(m)) : keyboard_pid <= 0))
		return 0;
	xytonode(x, y, NULL, NULL, &l, NULL, NULL);
	return l && l->layer_surface->current.layer >= ZWLR_LAYER_SHELL_V1_LAYER_TOP ? 0 : side;
}

static void
edgeend(int cancelled)
{
	wl_event_source_timer_update(pill_hold, 0);
	if (edge_node)
		wlr_scene_node_set_enabled(&edge_node->node, 0);
	if (finger.mode != 1 || cancelled || locked || overview_active || edgepull() < EDGE_DIST)
		return;
	if (edge_side < 0)
		keyboardforce(finger.m, !keyboardshown(finger.m));
	else if (focustop(finger.m))
		sendback(focustop(finger.m));
}

/* how far the finger has pulled the overview open */
static float
pillprogress(void)
{
	double t = (finger.y0 - finger.y) / (finger.m->m.height * 0.38);

	return (float)MAX(0.0, MIN(1.0, t));
}

static void
pillupdate(void)
{
	Monitor *m = finger.m;
	float t;
	int i;

	if (finger.mode == 0 && finger.y0 - finger.y >= 8.0) {
		if (layerwantskeyboard(m)) {
			finger.mode = 2;
		} else if (!overview_active) {
			overviewset(1);
			finger.mode = overview_active ? 1 : 3;
			finger.y0 = finger.y; /* from here on, so the first frame does not jump */
			pillpause.t = finger.time;
			pillpause.paused = 0;
		} else {
			finger.mode = 3;
		}
	}
	if (finger.mode != 1)
		return;
	t = pillprogress();
	if (fabs(finger.vely) >= PILL_SLOW)
		pillpause.t = finger.time;
	else if (finger.time - pillpause.t >= PILL_PAUSE_MS && t >= PILL_PAUSE_MIN)
		pillpause.paused = 1;
	m->overview_animating = 0;
	for (i = 0; i < 3; i++) {
		m->overview[i] = overviewboxlerp(&m->overview_from[i],
				&m->overview_to[i], t);
		m->overview_opacity[i] = m->overview_opacity_from[i]
				+ (m->overview_opacity_to[i] - m->overview_opacity_from[i]) * t;
	}
	m->overview_dim = m->overview_dim_from + (m->overview_dim_to - m->overview_dim_from) * t;
	/* the window goes with the finger as well as shrinking; letting go settles it */
	m->overview[1].x += (int)round(PILL_FOLLOW_X * (finger.x - finger.x0));
	/* it rises with the finger, but never under the status bar */
	m->overview[1].y = MAX(m->overview[1].y - (int)round(PILL_FOLLOW_Y * MAX(0.0, finger.y0 - finger.y)),
			MIN(m->overview[1].y, m->overview_to[1].y));
	overviewbuild();
	pillplace(m);
}

/* mode 0 means the drag has not begun, so moving first can never wait on this */
static int
pillhold(void *data)
{
	const char *cmd = getenv("PHONEGLUEWC_SCREENTEXT");
	Arg a = {.v = (const char *[]){ cmd ? cmd : "phonetext", NULL }};

	if (touch_gesture == 5) {
		if (finger.mode == 0)
			edgepass(now_ms());
		return 0;
	}
	if (touch_gesture != 3 || finger.mode != 0 || overview_active || locked
			|| hypot(finger.x - finger.x0, finger.y - finger.y0) > PILL_HOLD_SLOP
			|| layerwantskeyboard(finger.m) || (cmd && !*cmd))
		return 0;
	finger.mode = 5;
	barset(1);
	spawn(&a);
	return 0;
}

/* the app leaves to home: it goes on from under the finger, shrinking and fading, over the settling wallpaper */
static void
pillflick(Monitor *m, double up)
{
	unsigned int target = freews(m), from = m->ws;
	struct wlr_box card = m->overview[1], small;
	float dim = m->overview_dim;
	int i;

	if (!wsoccupied(m, from) || wsoccupied(m, target)) {
		if (wsoccupied(m, from))
			buttonsend("nofree");
		overviewset(0);
		return;
	}
	flick_side_ws[0] = GRIDLT(m) ? -1 : wsnext(m, -1);
	flick_side_ws[1] = GRIDLT(m) ? -1 : wsnext(m, 1);
	for (i = 0; i < 2; i++) {
		flick_side[i] = m->overview[i * 2];
		flick_side_op[i] = m->overview_opacity[i * 2];
	}
	{
		Arg a = {.ui = target};

		viewws(&a);
	}
	flick_ws = (int)from;
	flick_dim = dim;
	m->overview[0] = card;
	m->overview[1] = m->m;
	m->overview_opacity[0] = m->overview_opacity[1] = 1.0f;
	overviewset(0);
	if (!m->overview_animating)
		return;
	small.width = MAX(1, (int)roundf(m->m.width * FLICK_CARD));
	small.height = MAX(1, (int)roundf(m->m.height * FLICK_CARD));
	small.x = card.x + (card.width - small.width) / 2;
	small.y = m->m.y + (int)roundf(m->m.height * 0.12f) - small.height / 2;
	m->overview_to[0] = small;
	m->overview_to[1] = m->m;
	/* the card's centre keeps the speed it had under the finger */
	m->overview_anim_v = (float)((PILL_FOLLOW_Y + 0.18) * up
			/ MAX(1, (card.y + card.height / 2) - (small.y + small.height / 2)));
}

/* distance and speed decide; a finger that rested before lifting has no speed */
static void
pillend(uint32_t time, int cancelled)
{
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	Monitor *m = finger.m;
	double up = time - finger.time > VEL_WINDOW ? 0.0 : -finger.vely;

	wl_event_source_timer_update(pill_hold, 0);
	pillplace(m);
	if (finger.mode == 1) {
		float t = pillprogress();
		double span = m->m.height * 0.38;

		int held = pillpause.paused || (time - pillpause.t >= PILL_PAUSE_MS && t >= PILL_PAUSE_MIN);

		if (!cancelled && up > -0.3 && !held && up >= PILL_FLICK) {
			pillflick(m, up);
		} else if (!cancelled && up > -0.3 && (held || t >= 0.35f)) {
			overviewtransition(m, m->overview_to, shown, 1.0f);
			m->overview_anim_v = (float)(MAX(up, 0.0) / span) / MAX(0.05f, 1.0f - t);
		} else {
			overviewset(0);
			m->overview_anim_v = (float)(MAX(-up, 0.0) / span) / MAX(0.05f, t);
		}
		/* it faded with the drag: it does not come back for the rest of the bar's time */
		barset(0);
		bar_t = 0.0f;
		pillplace(m);
	} else if (!cancelled && (finger.mode == 2 || (finger.mode == 0 && layerwantskeyboard(m)))) {
		pillseq++;
		savepillstate();
	} else if (!cancelled && finger.mode == 0 && overview_active) {
		overviewset(0);
	} else if (!cancelled && finger.mode == 3 && overview_active) {
		/* up from the overview goes home: the empty workspace, if there is one */
		if (wsoccupied(m, m->ws) && !wsoccupied(m, freews(m)))
			overviewnavigate(freews(m), 1);
		overviewset(0);
	} else if (!cancelled && finger.mode == 0
			&& hypot(finger.x - finger.x0, finger.y - finger.y0) <= PILL_HOLD_SLOP) {
		barset(1); /* decided here, so a swipe never shows it */
	}
	if (bar_shown)
		barset(1); /* the finger left it: the time starts again */
}

static int
cardcloseback(void *data)
{
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	struct wlr_box target[3];
	Monitor *m = card_close.c ? card_close.c->mon : NULL;

	if (!m || !overview_active || !overviewvalid(m))
		return 0;
	card_close.from = card_close.dy;
	card_close.to = 0.0f;
	overviewtargets(m, target);
	overviewtransition(m, target, shown, 1.0f);
	overviewbuild();
	return 0;
}

static void
carouselpick(uint32_t time)
{
	finger.mode = 2;
	touch_emu = finger.id;
	touchpointermove(time, finger.x0, finger.y0);
	touchbutton(time, WL_POINTER_BUTTON_STATE_PRESSED);
	touchpointermove(time, finger.x, finger.y);
}

/* the shell saw a held icon move: its finger becomes ours, and carries the icon */
static void
icondragstart(const char *cmd, const char *dir)
{
	struct timespec now;
	struct wlr_touch_point *point;
	TouchPoint *p = touch_pts;
	Monitor *m;
	uint32_t time;

	if (overview_drag_client || overview_drag_cmd
			|| touch_gesture || touch_n != 1 || !cmd || !*cmd
			|| !overviewvalid(m = xytomon(p->x, p->y)))
		return;
	/* held on home or over an app: the cards open under the finger to drop it on one */
	if (!overview_active)
		overviewset(1);
	if (!overview_active)
		return;
	while (!wl_list_empty(&seat->touch_state.touch_points)
			&& (point = wlr_seat_touch_get_point(seat, p->id)))
		wlr_seat_touch_notify_cancel(seat, point->client);
	clock_gettime(CLOCK_MONOTONIC, &now);
	time = (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
	overview_drag_cmd = strdup(cmd);
	overview_drag_dir = dir ? strdup(dir) : NULL;
	overview_dragging = 1;
	overview_button_swallow = 1;
	selmon = m;
	fingerbegin(4, p->id, p->x, p->y, time, m);
	finger.mode = 2;
	touch_emu = p->id;
	touchpointermove(time, p->x, p->y);
}

#define GLIDE_TAU 200.0 /* ms: a release lands where its speed would carry it in this time */
#define GLIDE_W 0.019 /* 1/ms: the settle from rest, about the overview's 340 ms */
#define GLIDE_TAIL 4.0 /* px from rest: cards this close count as stopped */

static double
glidespan(Monitor *m)
{
	struct wlr_box target[3];

	overviewtargets(m, target);
	return (target[2].x + target[2].width / 2.0) - (target[1].x + target[1].width / 2.0);
}

/* lays the cards at offset x from the current one; past half a card the next one becomes current */
static void
glideplace(Monitor *m, double *x, double *x0, double *tgt)
{
	struct wlr_box target[3];
	double span;
	int i, dir, ws;

	if (GRIDLT(m)) {
		gridplace(m, *x);
		return;
	}
	span = glidespan(m);
	while (span > 0 && fabs(*x) > span / 2 && (ws = wsnext(m, dir = *x < 0 ? 1 : -1)) >= 0) {
		Arg a = {.ui = (unsigned int)ws};
		Monitor *gm = glide.m;

		glide.m = NULL;
		viewws(&a);
		glide.m = gm;
		*x += dir * span;
		if (x0)
			*x0 += dir * span;
		if (tgt)
			*tgt += dir * span;
	}
	overviewlayout(m, target, *x);
	for (i = 0; i < 3; i++) {
		m->overview[i] = target[i];
		m->overview_opacity[i] = 1.0f;
	}
}

/* from offset x at speed v to the card n steps along, clamped to the row */
static void
glidestart(Monitor *m, double x, double v, int n)
{
	double span = glidespan(m);
	int right = (int)wslimit(m) - (int)m->ws, left = (int)m->ws;

	n = MAX(-left, MIN(MAX(0, right), n));
	glideto(m, x, v, -n * span);
}

/* from x at speed v to tgt, critically damped */
static void
glideto(Monitor *m, double x, double v, double tgt)
{
	double a;

	glide.m = m;
	glide.x0 = glide.x = x;
	glide.v0 = v;
	glide.tgt = tgt;
	glide.t = 0.0f;
	a = x - glide.tgt;
	/* never faster than the finger was, never past the card: between |v|/|a| and 2|v|/|a| */
	glide.w = fabs(v) < 0.1 || fabs(a) < 1.0 || (a > 0) == (v > 0) ? GLIDE_W
			: MAX(fabs(v) / fabs(a), MIN(GLIDE_W, 2.0 * fabs(v) / fabs(a)));
	m->overview_dim_from = m->overview_dim_to = m->overview_dim;
	m->overview_animating = 1;
	if (!animations || animation_duration <= 0) {
		glide.t = 1e6f;
		glide.x = glide.tgt;
	}
	animkick(m);
}

/* one frame of the glide; 1 while it moves */
static int
glideadvance(Monitor *m, float dt)
{
	double a = glide.x0 - glide.tgt, b, e, vel;

	if (glide.m != m)
		return 0;
	glide.t += dt;
	b = glide.v0 + glide.w * a;
	e = exp(-glide.w * glide.t);
	glide.x = glide.tgt + (a + b * glide.t) * e;
	vel = (b - glide.w * (a + b * glide.t)) * e;
	if (fabs(glide.x - glide.tgt) < 0.5 && fabs(vel) < 0.02) {
		glide.x = glide.tgt;
		glide.m = NULL;
		m->overview_animating = 0;
	}
	glideplace(m, &glide.x, &glide.x0, &glide.tgt);
	return 1;
}

/* the grid: up and down scrolls, sideways throws a window out, a finger that stayed put carries it */
static void
gridupdate(void)
{
	Monitor *m = finger.m;
	double dx = finger.x - finger.x0, dy = finger.y - finger.y0;

	if (finger.mode == 0 && !finger.moved && hypot(dx, dy) >= CARD_HOLD_SLOP)
		finger.moved = finger.time;
	if (finger.mode == 0 && hypot(dx, dy) >= 10.0) {
		Client *c = overviewclientat(m, finger.x0, finger.y0, NULL, NULL);

		if (c && finger.settled && finger.moved - finger.t0 >= 300) {
			carouselpick(finger.time);
		} else if (c && finger.settled && fabs(dx) > 1.5 * fabs(dy)) {
			wl_event_source_timer_update(card_close_timer, 0);
			card_close.c = c;
			card_close.dy = 0.0f;
			finger.mode = 6;
			finger.x0 = finger.x;
		} else {
			finger.mode = fabs(dy) >= fabs(dx) ? 1 : 3;
			finger.y0 = finger.y + grid_scroll;
		}
	}
	if (finger.mode == 6) {
		card_close.dy = (float)(finger.x - finger.x0);
		m->overview_animating = 0;
		overviewbuild();
	} else if (finger.mode == 1) {
		m->overview_animating = 0;
		gridplace(m, gridrubber(m, finger.y0 - finger.y));
		overviewbuild();
	}
}

/* 1 when the grid took the lift */
static int
gridend(uint32_t time, int cancelled)
{
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	struct wlr_box target[3], card;
	Monitor *m = finger.m;
	int recent = time - finger.time <= VEL_WINDOW && !cancelled;

	if (finger.mode == 1) {
		double v = recent ? -finger.vely : 0.0;

		selmon = m;
		glideto(m, grid_scroll, v, gridclamp(m, grid_scroll + v * GLIDE_TAU));
		return 1;
	}
	if (finger.caught && (finger.mode == 0 || finger.mode == 3)) {
		glideto(m, grid_scroll, 0.0, gridclamp(m, grid_scroll));
		return 1;
	}
	if (finger.mode == 6 && card_close.c) {
		Client *c = card_close.c;
		double v = recent ? finger.velx : 0.0, d = card_close.dy;
		double w = gridcard(m, c->ws, &card) ? card.width : m->m.width / 2.0;
		int gone = !cancelled && (v == 0.0 || (v > 0) == (d > 0)) && (fabs(d) >= w * CARD_CLOSE_FAR
				|| (fabs(v) >= CARD_CLOSE_SPEED && fabs(d) >= w * CARD_CLOSE_NEAR));

		card_close.from = card_close.dy;
		card_close.to = gone ? (d < 0 ? -1.0f : 1.0f) * m->m.width : 0.0f;
		overviewtargets(m, target);
		overviewtransition(m, target, shown, 1.0f);
		m->overview_anim_v = (float)(fabs(v) / MAX(1.0, fabs(card_close.to - card_close.from)));
		if (gone) {
			client_send_close(c);
			wl_event_source_timer_update(card_close_timer, 900);
		}
		return 1;
	}
	return 0;
}

/* sideways turns the cards however slowly, up closes, and only a finger that
 * stayed put first picks the window up with the overview's own drag */
static void
carouselupdate(void)
{
	struct wlr_box target[3];
	Monitor *m = finger.m;
	double dx = finger.x - finger.x0, dy = finger.y - finger.y0;
	int i;

	if (GRIDLT(m)) {
		gridupdate();
		return;
	}
	if (finger.mode == 0 && !finger.moved && hypot(dx, dy) >= CARD_HOLD_SLOP)
		finger.moved = finger.time;
	if (finger.mode == 0 && hypot(dx, dy) >= 10.0) {
		Client *c = overviewclientat(m, finger.x0, finger.y0, NULL, NULL);
		int held = finger.moved - finger.t0 >= 300;

		/* a card still on its way is no card to close or carry: it is where the last swipe left it */
		if (c && !finger.settled) {
			finger.mode = fabs(dx) >= fabs(dy) ? 1 : 3;
		} else if (c && !held && -dy > 1.5 * fabs(dx)) {
			wl_event_source_timer_update(card_close_timer, 0);
			card_close.c = c;
			card_close.dy = 0.0f;
			finger.mode = 6;
			finger.y0 = finger.y;
		} else if (c && (held || fabs(dy) > fabs(dx))) {
			carouselpick(finger.time);
		} else {
			finger.mode = fabs(dx) >= fabs(dy) ? 1 : 3;
		}
		overviewtargets(m, target);
		/* from where the cards are now: no jump, even in the middle of a settle */
		finger.x0 = finger.x - ((m->overview[1].x + m->overview[1].width / 2.0) - (target[1].x + target[1].width / 2.0));
		dx = finger.x - finger.x0;
	}
	if (finger.mode == 6) {
		card_close.dy = (float)MIN(0.0, finger.y - finger.y0);
		m->overview_animating = 0;
		overviewbuild();
	}
	if (finger.mode != 1)
		return;
	m->overview_animating = 0;
	if (!SCROLLLT(m)) {
		double x;

		/* the finger can drag past several cards; each one it passes becomes current */
		glideplace(m, &dx, NULL, NULL);
		finger.x0 = finger.x - dx;
		x = wsnext(m, dx < 0 ? 1 : -1) < 0 ? dx * 0.25 : dx;
		glideplace(m, &x, NULL, NULL);
		overviewbuild();
		return;
	}
	if (wsnext(m, dx < 0 ? 1 : -1) < 0)
		dx *= 0.25; /* the end of the row resists, then settles back */
	overviewtargets(m, target);
	for (i = 0; i < 3; i++) {
		m->overview[i] = target[i];
		m->overview[i].x += (int)round(dx);
	}
	overviewbuild();
}

static void
carouselend(uint32_t time, int cancelled)
{
	static const float shown[] = {1.0f, 1.0f, 1.0f};
	struct wlr_box target[3];
	Monitor *m = finger.m;
	double dx = finger.x - finger.x0;
	double vel = time - finger.time > VEL_WINDOW ? 0.0 : finger.velx;
	double span;

	if (GRIDLT(m) && gridend(time, cancelled))
		return;
	if (finger.mode == 2) {
		touch_emu = -1;
		if (cancelled && overview_drag_cmd) {
			free(overview_drag_cmd);
			free(overview_drag_dir);
			overview_drag_cmd = overview_drag_dir = NULL;
			overview_dragging = 0;
			overviewdragclear();
		}
		touchbutton(time, WL_POINTER_BUTTON_STATE_RELEASED);
	} else if (finger.caught && (finger.mode == 0 || finger.mode == 3)) {
		/* a touch that stopped the cards only stops them: they settle on the nearest */
		overviewtargets(m, target);
		glidestart(m, (m->overview[1].x + m->overview[1].width / 2.0) - (target[1].x + target[1].width / 2.0), 0.0, 0);
	} else if (finger.mode == 0 && !cancelled) {
		touchpointermove(time, finger.x0, finger.y0);
		touchbutton(time, WL_POINTER_BUTTON_STATE_PRESSED);
		touchbutton(time, WL_POINTER_BUTTON_STATE_RELEASED);
	} else if (finger.mode == 1 && !SCROLLLT(m)) {
		double x = wsnext(m, dx < 0 ? 1 : -1) < 0 ? dx * 0.25 : dx, p;
		int n;

		selmon = m;
		span = glidespan(m);
		if (cancelled)
			vel = 0.0;
		if (wsnext(m, dx < 0 ? 1 : -1) < 0)
			vel *= 0.25;
		/* where the speed would carry the cards, and the card nearest to that */
		p = x + vel * GLIDE_TAU;
		n = span > 0 ? (int)lround(-p / span) : 0;
		if (!n && fabs(vel) >= 0.5 && (vel < 0) == (x <= 0))
			n = vel < 0 ? 1 : -1;
		glidestart(m, x, vel, n);
	} else if (finger.mode == 1) {
		overviewtargets(m, target);
		span = target[2].x - target[1].x;
		selmon = m;
		if (!cancelled && (fabs(dx) >= m->m.width * 0.22 || fabs(vel) >= 0.5)
				&& (dx < 0) == (vel <= 0) && wsnext(m, dx < 0 ? 1 : -1) >= 0) {
			int dir = dx < 0 ? 1 : -1;

			overviewstep(dir);
			m->overview_anim_v = (float)(fabs(vel) / MAX(1.0, span - fabs(dx)));
		} else {
			overviewtransition(m, target, shown, 1.0f);
			if ((dx < 0) != (vel < 0))
				m->overview_anim_v = (float)(fabs(vel) / MAX(1.0, fabs(dx)));
		}
	} else if (finger.mode == 6 && card_close.c) {
		Client *c = card_close.c;
		double up = time - finger.time > VEL_WINDOW ? 0.0 : -finger.vely;
		int gone = !cancelled && up > -0.3 && (-card_close.dy >= m->overview[1].height * CARD_CLOSE_FAR
				|| (up >= CARD_CLOSE_SPEED && -card_close.dy >= m->overview[1].height * CARD_CLOSE_NEAR));

		card_close.from = card_close.dy;
		card_close.to = gone ? -(float)(m->m.height) : 0.0f;
		overviewtargets(m, target);
		overviewtransition(m, target, shown, 1.0f);
		m->overview_anim_v = (float)(MAX(up, 0.0)
				/ MAX(1.0, fabs(card_close.to - card_close.from)));
		if (gone) {
			client_send_close(c);
			/* an app may ask first: its card comes back if it stays */
			wl_event_source_timer_update(card_close_timer, 900);
		}
	}
}

/* the fourth finger takes the touches back from the clients and starts the
 * same swipe a touchpad would */
static void
touchgesturebegin(uint32_t time)
{
	double x = 0, y = 0;
	Monitor *m;
	int i, n;

	if (touch_emu >= 0) {
		touch_emu = -1;
		touchbutton(time, WL_POINTER_BUTTON_STATE_RELEASED);
	}
	/* the bound guards against a grab that keeps its points after a cancel */
	for (n = wlr_seat_touch_num_points(seat); n > 0; n--) {
		struct wlr_touch_point *point = wl_container_of(
				seat->touch_state.touch_points.next, point, link);

		if (wl_list_empty(&seat->touch_state.touch_points))
			break;
		wlr_seat_touch_notify_cancel(seat, point->client);
	}
	for (i = 0; i < touch_n; i++) {
		x += touch_pts[i].x / touch_n;
		y += touch_pts[i].y / touch_n;
	}
	gesturebegin(4);
	/* the gesture belongs to the touched monitor, not to the cursor's */
	m = xytomon(x, y);
	if (overview_swipe_active && overviewvalid(m))
		selmon = m;
	gesture_time = time;
	touch_gdx = touch_gdy = 0.0;
	touch_gesture = 1;
}

static void
homeswipeend(void)
{
	homeswipe.id = -1;
	wl_event_source_timer_update(home_hold, 0);
}

/* a still finger on bare home opens the home editor */
static int
homehold(void *data)
{
	if (homeswipe.id < 0 || homeswipe.id != touch_emu || locked || greeter || overview_visible)
		return 0;
	homeswipe.id = -1;
	editseq++;
	saveseq("edit", editseq);
	return 0;
}

/* hands a finger to whatever is under it */
static void
touchroute(TouchPoint *p, uint32_t time, int first, double lx, double ly)
{
	struct wlr_surface *surface = NULL;
	LayerSurface *l = NULL;
	Client *c = NULL, *tc = NULL;
	double sx = 0, sy = 0;

	xytonode(lx, ly, &surface, &c, &l, &sx, &sy);
	/* over the cards, what is under them is out of reach */
	if (overview_visible && surface && (toplevel_from_wlr_surface(surface, &tc, &l) != LayerShell
			|| l->layer_surface->current.layer < ZWLR_LAYER_SHELL_V1_LAYER_TOP))
		surface = NULL;
	/* the button row: a swipe from a button still moves the cards, a tap comes back to it as a click */
	if (overview_visible && surface && l && l == phonetray(xytomon(lx, ly))
			&& !trayside(xytomon(lx, ly), l) && ly < l->scene->node.y + TRAY_ROW)
		surface = NULL;
	if (!surface && overview_active && first && overviewvalid(xytomon(lx, ly))) {
		fingerbegin(4, p->id, lx, ly, time, xytomon(lx, ly));
		finger.settled = !finger.m->overview_animating;
		/* a touch catches gliding cards where they are; a slow tail of a few px just ends, so the tap counts */
		if (glide.m == finger.m) {
			int tail = fabs(glide.x - glide.tgt) < GLIDE_TAIL;

			if (tail) {
				glide.x = glide.tgt;
				glideplace(finger.m, &glide.x, &glide.x0, &glide.tgt);
				overviewbuild();
			}
			glide.m = NULL;
			finger.m->overview_animating = 0;
			finger.caught = !tail;
		}
		return;
	}
	if (surface && !overview_button_swallow
			&& wlr_surface_accepts_touch(surface, seat)) {
		if (first) {
			selmon = xytomon(lx, ly);
			if (!locked && c && (!client_is_unmanaged(c) || client_wants_focus(c)))
				focusclient(c, 1);
		}
		p->z = c && c->type != LayerShell && c->bufscale > 0.0 ? c->bufscale : 1.0;
		p->ox = lx - sx * p->z;
		p->oy = ly - sy * p->z;
		wlr_seat_touch_notify_down(seat, surface, time,
				p->id, sx, sy);
	} else if (first) {
		/* the overview and clients without touch support get a mouse */
		touch_emu = p->id;
		if (!surface && !locked && !greeter && !overview_visible) {
			homeswipe = (typeof(homeswipe)){ p->id, lx, ly };
			wl_event_source_timer_update(home_hold, HOME_HOLD_MS);
		}
		touchpointermove(time, lx, ly);
		touchbutton(time, WL_POINTER_BUTTON_STATE_PRESSED);
	}
}

static void
touchforward(TouchPoint *p, uint32_t time, double lx, double ly)
{
	struct wlr_touch_point *point;
	struct wlr_surface *surface = NULL;
	double sx = 0, sy = 0;

	if (p->id == touch_emu) {
		/* bare home: a swipe up opens the app menu, once */
		if (p->id == homeswipe.id && homeswipe.y0 - ly >= HOMESWIPE_UP
				&& homeswipe.y0 - ly > 1.5 * fabs(lx - homeswipe.x0)) {
			homeswipeend();
			menuseq++;
			saveseq("menu", menuseq);
		} else if (p->id == homeswipe.id && fabs(lx - homeswipe.x0) >= HOMESWIPE_UP
				&& fabs(lx - homeswipe.x0) > 1.5 * fabs(ly - homeswipe.y0)) {
			int next = lx < homeswipe.x0;

			homeswipeend();
			pageseq[next]++;
			saveseq(next ? "page-next" : "page-prev", pageseq[next]);
		} else if (p->id == homeswipe.id && hypot(lx - homeswipe.x0, ly - homeswipe.y0) > PILL_HOLD_SLOP) {
			wl_event_source_timer_update(home_hold, 0);
		}
		touchpointermove(time, lx, ly);
	} else if ((point = wlr_seat_touch_get_point(seat, p->id))) {
		/* the window may have moved since the finger landed on it */
		xytonode(lx, ly, &surface, NULL, NULL, &sx, &sy);
		if (surface == point->surface) {
			p->ox = lx - sx * p->z;
			p->oy = ly - sy * p->z;
		}
		wlr_seat_touch_notify_motion(seat, time, p->id, (lx - p->ox) / p->z, (ly - p->oy) / p->z);
	}
}

/* the zone did not turn into a swipe: the app gets the finger from where it landed */
void
edgepass(uint32_t time)
{
	TouchPoint *p = touchfind(finger.id);

	wl_event_source_timer_update(pill_hold, 0);
	touch_gesture = 0;
	if (!p)
		return;
	touchroute(p, time, 1, finger.x0, finger.y0);
	wlr_seat_touch_notify_frame(seat);
	if (finger.x != finger.x0 || finger.y != finger.y0)
		touchforward(p, time, finger.x, finger.y);
}

static void
edgeupdate(uint32_t time)
{
	if (locked && finger.mode == 1) {
		edgeend(1);
		finger.mode = 2;
	}
	if (finger.mode == 2)
		return;
	if (finger.mode == 0) {
		double dy = fabs(finger.y - finger.y0);

		if (hypot(finger.x - finger.x0, dy) < EDGE_SLOP)
			return;
		if (edgepull() < dy) {
			edgepass(time);
			return;
		}
		finger.mode = 1;
		edge_armed = 0;
		wl_event_source_timer_update(pill_hold, 0);
	}
	edgedraw();
}

void
touchdown(struct wl_listener *listener, void *data)
{
	struct wlr_touch_down_event *event = data;
	TouchPoint *p;
	Monitor *m;
	double lx, ly;
	int side;

	wlr_cursor_absolute_to_layout_coords(cursor, &event->touch->base, event->x, event->y, &lx, &ly);
	/* a dark screen takes no touch: a pocket or a palm would work the lock unseen */
	if ((m = xytomon(lx, ly)) && screendark(m))
		return;
	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	kbdactive();
	if (!(p = touchfind(event->touch_id))) {
		if (touch_n == LENGTH(touch_pts))
			return;
		p = &touch_pts[touch_n++];
	}
	*p = (TouchPoint){ .id = event->touch_id, .x = lx, .y = ly };
	if (touch_n > 1)
		homeswipeend();
	press_x = lx;
	press_y = ly;

	/* the touch still reaches whatever is under it */
	if (bar_shown && !pillzone(xytomon(lx, ly), lx, ly))
		barset(0);
	else if (bar_shown)
		wl_event_source_timer_update(bar_timer, 0);
	/* a second finger means this is not a swipe of the cards */
	if (touch_gesture == 4) {
		carouselend(event->time_msec, 1);
		touch_gesture = 0;
	}
	/* nor a swipe from the edge */
	if (touch_gesture == 5) {
		if (finger.mode == 0) {
			edgepass(event->time_msec);
		} else {
			edgeend(1);
			touch_gesture = 2;
		}
	}
	if (touch_gesture)
		return;
	if (touch_n == 4 && !locked && !greeter && !screentextopen(xytomon(lx, ly))) {
		touchgesturebegin(event->time_msec);
		return;
	}
	if (touch_n == 1 && !locked && pillzone(xytomon(lx, ly), lx, ly)
			&& !screentextopen(xytomon(lx, ly))) {
		fingerbegin(3, event->touch_id, lx, ly, event->time_msec, xytomon(lx, ly));
		wl_event_source_timer_update(pill_hold, PILL_HOLD_MS);
		return;
	}
	if (touch_n == 1 && (side = edgezone(xytomon(lx, ly), lx, ly))) {
		fingerbegin(5, event->touch_id, lx, ly, event->time_msec, xytomon(lx, ly));
		edge_side = side;
		wl_event_source_timer_update(pill_hold, EDGE_HOLD_MS);
		return;
	}

	touchroute(p, event->time_msec, touch_n == 1, lx, ly);
}

void
touchmotion(struct wl_listener *listener, void *data)
{
	struct wlr_touch_motion_event *event = data;
	TouchPoint *p = touchfind(event->touch_id);
	double lx, ly;

	if (!p)
		return;
	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	wlr_cursor_absolute_to_layout_coords(cursor, &event->touch->base, event->x, event->y, &lx, &ly);
	if (touch_gesture) {
		/* per finger, so a finger lost mid-swipe cannot make the sum jump */
		if (touch_gesture == 1) {
			touch_gdx += (lx - p->x) / touch_n;
			touch_gdy += (ly - p->y) / touch_n;
			gesture_time = event->time_msec;
		} else if (touch_gesture >= 3 && event->touch_id == finger.id) {
			fingertrack(lx, ly, event->time_msec);
			if (event->touch_id == touch_emu)
				touchpointermove(event->time_msec, lx, ly);
		}
	} else {
		touchforward(p, event->time_msec, lx, ly);
	}
	p->x = lx;
	p->y = ly;
}

void
touchframe(struct wl_listener *listener, void *data)
{
	wlr_seat_touch_notify_frame(seat);
	if (touch_gesture == 1 && (touch_gdx != 0.0 || touch_gdy != 0.0)) {
		gestureupdate(4, touch_gdx, touch_gdy);
		touch_gdx = touch_gdy = 0.0;
	} else if (touch_gesture == 3) {
		pillupdate();
	} else if (touch_gesture == 4) {
		carouselupdate();
	} else if (touch_gesture == 5) {
		edgeupdate(finger.time);
	}
}

/* like libinput, the first finger to lift ends the swipe */
static void
touchlift(int32_t id, uint32_t time, int cancelled)
{
	struct wlr_touch_point *point;
	TouchPoint *p = touchfind(id);

	if (!p)
		return;
	/* a short tap in the edge zone is the app's */
	if (touch_gesture == 5 && id == finger.id && finger.mode == 0 && !cancelled)
		edgepass(time);
	*p = touch_pts[--touch_n];
	if (touch_gesture >= 3 && id != finger.id) {
		return;
	} else if (touch_gesture) {
		if (touch_gesture == 1)
			gestureend(cancelled, time);
		else if (touch_gesture == 3)
			pillend(time, cancelled);
		else if (touch_gesture == 4)
			carouselend(time, cancelled);
		else if (touch_gesture == 5)
			edgeend(cancelled);
		touch_gesture = touch_n ? 2 : 0;
		pillplace(selmon); /* the drag's fade is over */
	} else if (id == touch_emu) {
		touch_emu = -1;
		homeswipeend();
		touchbutton(time, WL_POINTER_BUTTON_STATE_RELEASED);
	} else if (!cancelled) {
		wlr_seat_touch_notify_up(seat, time, id);
	} else if ((point = wlr_seat_touch_get_point(seat, id))) {
		wlr_seat_touch_notify_cancel(seat, point->client);
	}
}

void
touchup(struct wl_listener *listener, void *data)
{
	struct wlr_touch_up_event *event = data;

	wlr_idle_notifier_v1_notify_activity(idle_notifier, seat);
	touchlift(event->touch_id, event->time_msec, 0);
}

void
touchcancel(struct wl_listener *listener, void *data)
{
	struct wlr_touch_cancel_event *event = data;

	touchlift(event->touch_id, event->time_msec, 1);
}

void
virtualkeyboard(struct wl_listener *listener, void *data)
{
	struct wlr_virtual_keyboard_v1 *kb = data;
	/* virtual keyboards shouldn't share keyboard group */
	KeyboardGroup *group = createkeyboardgroup();
	/* Set the keymap to match the group keymap */
	wlr_keyboard_set_keymap(&kb->keyboard, group->wlr_group->keyboard.keymap);
	LISTEN(&kb->keyboard.base.events.destroy, &group->destroy, destroykeyboardgroup);

	/* Add the new keyboard to the group */
	wlr_keyboard_group_add_keyboard(group->wlr_group, &kb->keyboard);
	/* headless sessions have no physical keyboard to advertise one */
	wlr_seat_set_capabilities(seat, seat->capabilities | WL_SEAT_CAPABILITY_KEYBOARD);
}

void
virtualpointer(struct wl_listener *listener, void *data)
{
	struct wlr_virtual_pointer_v1_new_pointer_event *event = data;
	struct wlr_input_device *device = &event->new_pointer->pointer.base;

	wlr_cursor_attach_input_device(cursor, device);
	if (event->suggested_output)
		wlr_cursor_map_input_to_output(cursor, device, event->suggested_output);
}

Monitor *
xytomon(double x, double y)
{
	struct wlr_output *o = wlr_output_layout_output_at(output_layout, x, y);
	Monitor *m = o ? o->data : NULL;
	/* a mirror sits on the same spot as its source: the source owns it */
	return m && m->mirroring && m->mirror_src ? m->mirror_src : m;
}

void
xytonode(double x, double y, struct wlr_surface **psurface,
		Client **pc, LayerSurface **pl, double *nx, double *ny)
{
	struct wlr_scene_node *node, *pnode;
	struct wlr_surface *surface = NULL;
	Client *c = NULL;
	LayerSurface *l = NULL;
	int layer;

	/* while locked nothing under the block layer can be reached, even with no lock surface */
	for (layer = NUM_LAYERS - 1; !surface && layer >= (locked ? LyrBlock : 0); layer--) {
		if (!(node = wlr_scene_node_at(&layers[layer]->node, x, y, nx, ny)))
			continue;

		if (node->type == WLR_SCENE_NODE_BUFFER) {
			struct wlr_scene_surface *scene_surface =
					wlr_scene_surface_try_from_buffer(wlr_scene_buffer_from_node(node));
			if (scene_surface)
				surface = scene_surface->surface;
		}
		/* Walk the tree to find a node that knows the client */
		for (pnode = node; pnode && !c;
				pnode = pnode->parent ? &pnode->parent->node : NULL)
			c = pnode->data;
		if (c && c->type == LayerShell) {
			c = NULL;
			l = pnode ? pnode->data : NULL;
		}
	}

	if (psurface) *psurface = surface;
	if (pc) *pc = c;
	if (pl) *pl = l;
}

#ifdef XWAYLAND
void
activatex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, activate);

	/* Only "managed" windows can be activated */
	if (!client_is_unmanaged(c))
		wlr_xwayland_surface_activate(c->surface.xwayland, 1);
}

void
associatex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, associate);

	LISTEN(&client_surface(c)->events.client_commit, &c->precommit,
			precommitnotify);
	LISTEN(&client_surface(c)->events.map, &c->map, mapnotify);
	LISTEN(&client_surface(c)->events.unmap, &c->unmap, unmapnotify);
}

void
configurex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, configure);
	struct wlr_xwayland_surface_configure_event *event = data;
	if (!client_surface(c) || !client_surface(c)->mapped) {
		wlr_xwayland_surface_configure(c->surface.xwayland,
				event->x, event->y, event->width, event->height);
		return;
	}
	if (client_is_unmanaged(c)) {
		wlr_scene_node_set_position(&c->scene->node, event->x, event->y);
		wlr_xwayland_surface_configure(c->surface.xwayland,
				event->x, event->y, event->width, event->height);
		return;
	}
	if (c->isfloating && c != grabc) {
		resize(c, (struct wlr_box){.x = event->x - c->bw,
				.y = event->y - c->bw, .width = event->width + c->bw * 2,
				.height = event->height + c->bw * 2}, 0);
	} else {
		arrange(c->mon);
	}
}

void
createnotifyx11(struct wl_listener *listener, void *data)
{
	struct wlr_xwayland_surface *xsurface = data;
	Client *c;

	/* Allocate a Client for this surface */
	c = xsurface->data = ecalloc(1, sizeof(*c));
	c->surface.xwayland = xsurface;
	c->type = X11;
	c->bufscale = 1.0;
	c->fit = 1.0;
	c->bw = client_is_unmanaged(c) ? 0 : borderpx;

	/* Listen to the various events it can emit */
	LISTEN(&xsurface->events.associate, &c->associate, associatex11);
	LISTEN(&xsurface->events.destroy, &c->destroy, destroynotify);
	LISTEN(&xsurface->events.dissociate, &c->dissociate, dissociatex11);
	LISTEN(&xsurface->events.request_activate, &c->activate, activatex11);
	LISTEN(&xsurface->events.request_configure, &c->configure, configurex11);
	LISTEN(&xsurface->events.request_fullscreen, &c->fullscreen, fullscreennotify);
	LISTEN(&xsurface->events.set_title, &c->set_title, updatetitle);
}

void
dissociatex11(struct wl_listener *listener, void *data)
{
	Client *c = wl_container_of(listener, c, dissociate);
	wl_list_remove(&c->precommit.link);
	wl_list_remove(&c->map.link);
	wl_list_remove(&c->unmap.link);
}

void
xwaylandready(struct wl_listener *listener, void *data)
{
	struct wlr_xcursor *xcursor;

	/* assign the one and only seat */
	wlr_xwayland_set_seat(xwayland, seat);

	/* Set the default XWayland cursor to match the rest of phonegluewc. */
	if ((xcursor = wlr_xcursor_manager_get_xcursor(cursor_mgr, "default", 1)))
		wlr_xwayland_set_cursor(xwayland,
				wlr_xcursor_image_get_buffer(xcursor->images[0]),
				xcursor->images[0]->hotspot_x, xcursor->images[0]->hotspot_y);
}
#endif

int
main(int argc, char *argv[])
{
	char *startup_cmd = NULL;
	int c;

	while ((c = getopt(argc, argv, "s:hdv")) != -1) {
		if (c == 's')
			startup_cmd = optarg;
		else if (c == 'd')
			log_level = WLR_DEBUG;
		else if (c == 'v')
			die("phonegluewc " VERSION);
		else
			goto usage;
	}
	if (optind < argc)
		goto usage;

	/* Wayland requires XDG_RUNTIME_DIR for creating its communications socket */
	if (!getenv("XDG_RUNTIME_DIR"))
		die("XDG_RUNTIME_DIR must be set");
	setup();
	run(startup_cmd);
	cleanup();
	return EXIT_SUCCESS;

usage:
	die("Usage: %s [-v] [-d] [-s startup command]", argv[0]);
}
