/* phonekbd: on-screen keyboard for phonegluewc. Offline: never opens a network socket. */
#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <math.h>
#include <malloc.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <wayland-client.h>
#include "fractional-scale-v1-client-protocol.h"
#include "input-method-unstable-v2-client-protocol.h"
#include "viewporter-client-protocol.h"
#include "virtual-keyboard-unstable-v1-client-protocol.h"
#include "wlr-data-control-unstable-v1-client-protocol.h"
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "emoji.h"
#include "langnames.h"
#include "words.h"

#ifndef DATADIR
#define DATADIR "/usr/local/share/phonegluewc/keyboard"
#endif

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define LEN(a) (sizeof(a) / sizeof(*(a)))

/* logical px */
#define SUG_H 48.f
#define ROW_H 52.f
#define LAP_ROW_H (landscape ? 34.f : 48.f) /* seven rows must leave room for the window */
#define WIDE_W 600 /* wider than this is a turned screen */
#define GAP 2.5f
#define RADIUS 9.f
#define BAR_ROOM 26 /* the strip under the keys, the compositor's PILL_ZONE: its bar and pill go here, not over a key */
#define POPUP_W 48.f
#define POPUP_H 56.f
#define MOD_H 44.f
#define TAB_H 44.f
#define PANEL_BOT 48.f
#define QUERY_H 40.f
#define STRIP_H 52.f
#define CLIP_ROW 44.f

#define LONG_NORMAL 350
#define REPEAT_MS 60
#define HIDE_MS 150
#define CHEV_W 56 /* the hide area in the strip under the keys, beside the compositor's pill */
#define PILL_HALF 62
#define CHEV_SLOP 12.f
#define CHEV_TAP_MS 500
#define DOUBLE_MS 400
#define SYNC_MS 300

#define BG (theme->bg)
#define KEY_BG (theme->key)
#define SPECIAL_BG (theme->special)
#define WHITE (theme->fg)
#define BLACK (theme->ink)
#define HILITE (theme->hi)
#define LINE (theme->line)
#define DIM (theme->dim)
#define ACCENT (theme->accent)

#define SHIFT_MASK 1u
#define CTRL_MASK 4u
#define ALT_MASK 8u
#define SUPER_MASK 64u
/* private: never reaches the virtual keyboard */
#define FN_MASK 0x100u
#define HARD_MASK (CTRL_MASK | ALT_MASK | SUPER_MASK)

/* text input purposes and hints from the text-input-v3 protocol */
enum { P_DIGITS = 2, P_NUMBER = 3, P_PHONE = 4, P_URL = 5, P_EMAIL = 6, P_PASSWORD = 8, P_PIN = 9, P_TERMINAL = 13 };
#define HINT_AUTOCAP 0x4u
#define HINT_HIDDEN 0x40u
#define HINT_SENSITIVE 0x80u

enum { K_CHAR, K_SPACE, K_BKSP, K_ENTER, K_SHIFT, K_PAGE, K_LAPTOP, K_MOD, K_CODE, K_MODS, K_CLIP, K_EMOJI, K_TAB,
	K_ABC, K_SEARCH, K_ACT, K_CLEARCLIP, K_ONEHAND, K_SWAP, K_THEME, K_TRANSLATE, K_GEAR, K_TRFROM, K_TRTO, K_TRSWAP, K_LANGS,
	K_LANGBACK, K_LANGACT, K_HIDE };
enum { PANEL_NONE, PANEL_EMOJI, PANEL_CLIP, PANEL_TRANS, PANEL_LANGS };
enum { D_NONE, D_SPACE, D_BKSP, D_GRID, D_STRIP, D_CLIP, D_TRINS, D_LANG };
enum { PAGE_ABC, PAGE_SYM, PAGE_SYM2 };

typedef struct {
	const char *label, *text;
	int kind, code;
	float x, y, w, h;
} Key;

typedef struct {
	int used, id, key, sug, fired, swiping, drag, tile;
	float downx, downy, x, y, dragx;
} Slot;

typedef struct {
	struct wl_buffer *buf;
	uint32_t *data;
	size_t size;
	int busy;
} Buffer;

static struct wl_display *dpy;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct wl_touch *touch;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct zwp_input_method_manager_v2 *im_mgr;
static struct zwp_input_method_v2 *im;
static struct zwp_virtual_keyboard_manager_v1 *vk_mgr;
static struct zwp_virtual_keyboard_v1 *vk;
static struct wp_fractional_scale_manager_v1 *frac_mgr;
static struct wp_viewporter *viewporter;
static struct zwlr_data_control_manager_v1 *dc_mgr;
static struct zwlr_data_control_device_v1 *dc_dev;

static struct wl_surface *surf;
static struct zwlr_layer_surface_v1 *layer;
static struct wp_fractional_scale_v1 *frac;
static struct wp_viewport *viewport;
static struct wl_callback *frame_cb;
static Buffer buffers[2];
static int configured, dirty;
static int width, height, bw, bh;
static uint32_t scale120 = 240;
static float sc = 2;
static uint32_t *px;

static FT_Library ft;
static FT_Face face;

struct Theme {
	const char *name;
	uint32_t bg, key, special, dim, accent, fg, ink, hi, line;
};
static const struct Theme themes[] = {
	{"dark", 0xff000000u, 0xff1c1c1cu, 0xff0e0e0eu, 0xff7a7a7au, 0xffd71921u, 0xffffffffu, 0xff000000u, 0xff2a2a2au, 0xff3a3a3au},
	{"contrast", 0xff000000u, 0xff303030u, 0xff1a1a1au, 0xffbbbbbbu, 0xffff3b30u, 0xffffffffu, 0xff000000u, 0xff2a2a2au, 0xff3a3a3au},
	{"red", 0xff0a0000u, 0xff2a0a0bu, 0xff170506u, 0xff9a6a6au, 0xffff2a2au, 0xffffffffu, 0xff000000u, 0xff2a2a2au, 0xff3a3a3au},
	{"light", 0xffe6e6e6u, 0xfffafafau, 0xffcfcfcfu, 0xff5f5f5fu, 0xffd71921u, 0xff111111u, 0xffffffffu, 0xffbdbdbdu, 0xffa8a8a8u},
};
#define THEME_LIGHT 3
static const struct { const char *name; uint32_t col; } accents[] = {
	{"red", 0xffd71921u}, {"orange", 0xffe8590cu}, {"yellow", 0xffd9a400u},
	{"green", 0xff2b9348u}, {"blue", 0xff2f7fe0u}, {"purple", 0xff8a5cf0u},
};
static struct Theme theme_now = {.bg = 0xff000000u};
static const struct Theme *theme = &theme_now;

static void wordslangs(void);

static struct {
	int autocorrect, predict, learn, number_row, key_height, sound, vibrate, one_handed;
	int key_borders, corner_hints, key_preview, long_ms, theme_system, accent, ringer_off;
	int theme, space_cursor, clipboard_history, emoji_history, autocap, double_space;
	int langs_set;
	char langs[128];
} cfg;

static int page, laptop, landscape;
static int modrow, panel, secret;
static Key keys[96];
/* release time per key, the pressed white fades back over KEY_FADE_MS */
static long key_rel[96];
static int fading;
#define KEY_FADE_MS 160
static int nkeys, nsug;
static float U, sug_x, sug_w;
static char keytext[64][8];
static int nkeytext;

static int shift_state; /* 1 for the next key, 2 locked */
static long shift_time;
static unsigned mods_latched, mods_locked;
static long mod_time[9];
static unsigned held_mods; /* a held key keeps the modifiers it started with */
static Key rep_key;
static unsigned rep_mods;
static int rep_on;

static Slot slots[5];
static int timerfd, hidefd;
static int timer_slot = -1;
static int popup_slot = -1, popup_sel, popup_n;
static char popup[8][EMOJI_SEQ];
static int popup_emoji;
static float popup_x, popup_y;

static uint32_t done_serial;
static int active_pending, active, shown, forced;
static int surf_region; /* the current surface has its input region */
static int chev_id = -1;
static float chev_x, chev_y;
static uint32_t chev_t;
static int sig_pipe[2] = {-1, -1};

/* the same way down as the compositor's signal, once the touch that asked is over */
static void
askhide(void)
{
	char c = SIGUSR2;

	if (write(sig_pipe[1], &c, 1) < 0) {}
}
static uint32_t purpose, hint;
static char surround[4096];
static uint32_t cursor;
static int sur_new;
static long last_key;

static char word[WORD_MAX];
static char sug[3][WORD_MAX];
static int sug_fix = -1;
static char undo_from[WORD_MAX], undo_to[WORD_MAX];
static int undo_extra;
static char swiped[WORD_MAX];
static int auto_space;
static int plain;
static char prev[WORD_MAX]; /* the word before the cursor, "<s>" at a sentence start, empty when unknown */
static int s_pending, cap_auto;
static long dbl_time;

static int em_kind, em_group, em_search, em_start[EMOJI_GROUPS + 1], em_found[64], em_nfound;
static float em_scroll, clip_scroll;
static char em_query[64];

/* Translate: this text reaches only a local process's stdin, and is wiped when the panel closes */
#define TRANS_TOP (TAB_H + QUERY_H + STRIP_H)
static char tr_in[1024], tr_out[2048], tr_from[12], tr_to[12], tr_msg[64];
static int tr_fd = -1, tr_timer = -1, tr_pending, ntr;
static size_t tr_outn;
static pid_t tr_pid;
static struct { char code[12]; int from, to; } tr_langs[64];

/* the language list comes from the helper, the only part of the keyboard that touches the network */
typedef struct { char code[12], name[48], dir[8]; long size; int installed, usable; } LangRow;
enum { JOB_NONE, JOB_LIST, JOB_INSTALL, JOB_REMOVE };
#define LANG_ROWS 128
static LangRow *lrows;
static int nlrows, lr_sel = -1, lr_fd = -1, lr_job, lr_failed, lr_finished, lr_cancelled;
static float lr_scroll;
static char lr_msg[96], lr_label[80], lr_buf[512];
static size_t lr_bn;
static long lr_done, lr_total;
static pid_t lr_pid;

/* memory only, on purpose */
#define CLIP_MAX 20
#define CLIP_ONE (16 * 1024)
#define CLIP_TOTAL (64 * 1024)
static char *clips[CLIP_MAX];
static int nclips;
static int clip_fd = -1;
static char *clip_buf;
static size_t clip_len;

/* what language packs add: from the data dir, so English alone means none */
#define LETTERS_MAX 64
/* shortcut: the password page shows the first 28 special letters, add a page if a user installs more */
static struct { char base, low[8], up[8]; int active; } lets[LETTERS_MAX];
static int nlets;

static int vib_fd = -2, vib_id = -1;
static pid_t snd_pid;

static float path[300][2];
static int npath;

static char state_dir[512];

static void resize(void);
static void closepanel(void);
static void trchanged(void);
static const char *tileseq(int i);
static int tilecount(void);

static unsigned
fnon(void)
{
	return (mods_latched | mods_locked) & FN_MASK;
}

static unsigned
hardmods(void)
{
	return (mods_latched | mods_locked | held_mods) & HARD_MASK;
}

static long
now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void
arm(int fd, int ms, int interval)
{
	struct itimerspec it = {
		.it_value = {ms / 1000, (long)(ms % 1000) * 1000000},
		.it_interval = {interval / 1000, (long)(interval % 1000) * 1000000},
	};

	timerfd_settime(fd, 0, &it, NULL);
}

/* --- drawing --- */
#include "draw.h"

#define ICON_R 0.85f

static void
stroke(float ax, float ay, float bx, float by, float lr, uint32_t col)
{
	float x0 = ax * sc, y0 = ay * sc, x1 = bx * sc, y1 = by * sc, r = lr * sc;
	float dx = x1 - x0, dy = y1 - y0, l2 = dx * dx + dy * dy;
	int minx = (int)floorf(MIN(x0, x1) - r - 1), maxx = (int)ceilf(MAX(x0, x1) + r + 1);
	int miny = (int)floorf(MIN(y0, y1) - r - 1), maxy = (int)ceilf(MAX(y0, y1) + r + 1);

	for (int j = miny; j <= maxy; j++)
		for (int i = minx; i <= maxx; i++) {
			float pxx = (float)i + 0.5f - x0, pyy = (float)j + 0.5f - y0;
			float t = l2 > 0 ? (pxx * dx + pyy * dy) / l2 : 0;

			t = t < 0 ? 0 : t > 1 ? 1 : t;
			blend(i, j, col, 0.5f - (hypotf(pxx - t * dx, pyy - t * dy) - r));
		}
}

/* one coverage for the whole shape, so joins and retraced lines are not blended twice */
static void
polyr(float cx, float cy, const float *p, int n, float lr, uint32_t col)
{
	float r = lr * sc, lim = (r + 1) * (r + 1);
	float x0 = cx + p[0], x1 = x0, y0 = cy + p[1], y1 = y0;

	for (int i = 1; i < n; i++) {
		x0 = MIN(x0, cx + p[i * 2]);
		x1 = MAX(x1, cx + p[i * 2]);
		y0 = MIN(y0, cy + p[i * 2 + 1]);
		y1 = MAX(y1, cy + p[i * 2 + 1]);
	}
	for (int j = (int)floorf(y0 * sc - r - 1); j <= (int)ceilf(y1 * sc + r + 1); j++)
		for (int i = (int)floorf(x0 * sc - r - 1); i <= (int)ceilf(x1 * sc + r + 1); i++) {
			float best = lim;

			for (int s = 0; s + 1 < n; s++) {
				float ax = (cx + p[s * 2]) * sc, ay = (cy + p[s * 2 + 1]) * sc;
				float dx = (cx + p[s * 2 + 2]) * sc - ax, dy = (cy + p[s * 2 + 3]) * sc - ay;
				float px = (float)i + 0.5f - ax, py = (float)j + 0.5f - ay, l2 = dx * dx + dy * dy;
				float t = l2 > 0 ? (px * dx + py * dy) / l2 : 0;

				t = t < 0 ? 0 : t > 1 ? 1 : t;
				px -= t * dx;
				py -= t * dy;
				best = MIN(best, px * px + py * py);
			}
			if (best < lim)
				blend(i, j, col, 0.5f - (sqrtf(best) - r));
		}
}

static void
poly(float cx, float cy, const float *p, int n, uint32_t col)
{
	polyr(cx, cy, p, n, ICON_R, col);
}

static void
arrow(float cx, float cy, int dx, int dy, uint32_t col)
{
	/* tail, tip, wing, tip, wing: a right angle at the tip, and the round ends come from the stroke */
	static const float along[] = {-6.2f, 6.2f, 3.1f, 6.2f, 3.1f}, side[] = {0, 0, -3.1f, 0, 3.1f};
	float p[10];

	for (int i = 0; i < 5; i++) {
		p[i * 2] = along[i] * (float)dx - side[i] * (float)dy;
		p[i * 2 + 1] = along[i] * (float)dy + side[i] * (float)dx;
	}
	polyr(cx, cy, p, 5, 1.15f, col);
}

static void
icon(const Key *k, float cx, float cy, uint32_t col)
{
	static const float shift_i[] = {-6, 0, 0, -7, 6, 0, 3, 0, 3, 6, -3, 6, -3, 0, -6, 0};
	static const float bk[] = {-9, 0, -4, -6, 9, -6, 9, 6, -4, 6, -9, 0};
	static const float bx1[] = {-1, -2.5f, 4, 2.5f}, bx2[] = {4, -2.5f, -1, 2.5f};
	static const float en1[] = {7, -6, 7, 2, -7, 2}, en2[] = {-3, -2, -7, 2, -3, 6};
	static const float lp[] = {-10, -6, 10, -6, 10, 6, -10, 6, -10, -6};
	static const float board[] = {-6, -6, -6, 8, 6, 8, 6, -6, -6, -6};
	static const float tab[] = {-3, -6, -3, -8, 3, -8, 3, -6};

	switch (k->kind) {
	case K_MODS: {
		float dir = modrow ? 1.f : -1.f;

		/* a chevron of dots above the name of what it opens */
		for (int i = -2; i <= 2; i++)
			stroke(cx + (float)i * 2.5f, cy - 7 + dir * (3 - (float)abs(i) * 1.5f), cx + (float)i * 2.5f,
				cy - 7 + dir * (3 - (float)abs(i) * 1.5f), 1.f, col);
		text("Ctrl", cx, cy + 8, 11, k->w - 6, col);
		break;
	}
	case K_TRANSLATE:
		text("Aa", cx, cy - 3, 14, 0, col);
		stroke(cx - 8, cy + 8, cx + 8, cy + 8, 0.8f, col);
		stroke(cx + 8, cy + 8, cx + 5, cy + 5, 0.8f, col);
		stroke(cx + 8, cy + 8, cx + 5, cy + 11, 0.8f, col);
		break;
	case K_TRSWAP:
		stroke(cx - 8, cy - 3, cx + 8, cy - 3, 0.8f, col);
		stroke(cx + 8, cy - 3, cx + 5, cy - 6, 0.8f, col);
		stroke(cx - 8, cy + 4, cx + 8, cy + 4, 0.8f, col);
		stroke(cx - 8, cy + 4, cx - 5, cy + 7, 0.8f, col);
		break;
	case K_EMOJI: {
		float face[50], smile[18];

		for (int i = 0; i < 25; i++) {
			face[i * 2] = 9.5f * cosf((float)i * 6.2832f / 24);
			face[i * 2 + 1] = 9.5f * sinf((float)i * 6.2832f / 24);
		}
		for (int i = 0; i < 9; i++) {
			float a = 0.4f + (float)i * 2.34f / 8;

			smile[i * 2] = 5.4f * cosf(a);
			smile[i * 2 + 1] = 0.6f + 5.4f * sinf(a);
		}
		poly(cx, cy, face, 25, col);
		poly(cx, cy, smile, 9, col);
		stroke(cx - 3.4f, cy - 3, cx - 3.4f, cy - 3, 1.45f, col);
		stroke(cx + 3.4f, cy - 3, cx + 3.4f, cy - 3, 1.45f, col);
		break;
	}
	case K_HIDE:
		stroke(cx - 7, cy - 3, cx, cy + 3, 1.1f, col);
		stroke(cx, cy + 3, cx + 7, cy - 3, 1.1f, col);
		break;
	case K_GEAR: {
		float ring[26];

		for (int i = 0; i < 13; i++) {
			ring[i * 2] = 5.6f * cosf((float)i * 6.2832f / 12);
			ring[i * 2 + 1] = 5.6f * sinf((float)i * 6.2832f / 12);
		}
		poly(cx, cy, ring, 13, col);
		for (int i = 0; i < 8; i++) {
			float a = (float)i * 6.2832f / 8, c = cosf(a), n = sinf(a);

			stroke(cx + 6.4f * c, cy + 6.4f * n, cx + 9.f * c, cy + 9.f * n, 0.95f, col);
		}
		stroke(cx, cy, cx, cy, 1.5f, col);
		break;
	}
	case K_CLIP:
		poly(cx, cy, board, 5, col);
		poly(cx, cy, tab, 4, col);
		for (int i = -1; i <= 1; i++)
			stroke(cx + (float)i * 2.8f, cy + 1, cx + (float)i * 2.8f, cy + 1, 0.8f, col);
		break;
	case K_SEARCH:
		for (int i = 0; i < 10; i++) {
			float a = (float)i * 6.2832f / 10;

			stroke(cx - 2 + 6 * cosf(a), cy - 2 + 6 * sinf(a), cx - 2 + 6 * cosf(a), cy - 2 + 6 * sinf(a), 0.8f, col);
		}
		stroke(cx + 2.5f, cy + 2.5f, cx + 7.5f, cy + 7.5f, 0.9f, col);
		break;
	case K_TAB:
		if (k->code < 0) {
			for (int i = 0; i < 12; i++) {
				float a = (float)i * 6.2832f / 12;

				stroke(cx + 9 * cosf(a), cy + 9 * sinf(a), cx + 9 * cosf(a), cy + 9 * sinf(a), 0.8f, col);
			}
			stroke(cx, cy, cx, cy - 5.5f, ICON_R, col);
			stroke(cx, cy, cx + 4, cy, ICON_R, col);
		}
		break;
	case K_SHIFT:
		poly(cx, cy, shift_i, 8, col);
		if (shift_state == 2)
			stroke(cx - 5, cy + 9, cx + 5, cy + 9, ICON_R, col);
		break;
	case K_BKSP:
		poly(cx, cy, bk, 6, col);
		poly(cx, cy, bx1, 2, col);
		poly(cx, cy, bx2, 2, col);
		break;
	case K_ENTER:
		poly(cx, cy, en1, 3, col);
		poly(cx, cy, en2, 3, col);
		break;
	case K_LAPTOP:
		poly(cx, cy, lp, 5, laptop ? ACCENT : col);
		for (int i = -1; i <= 1; i++)
			stroke(cx + (float)i * 5, cy - 2, cx + (float)i * 5, cy - 2, 0.9f, laptop ? ACCENT : col);
		stroke(cx - 5, cy + 2.5f, cx + 5, cy + 2.5f, ICON_R, laptop ? ACCENT : col);
		break;
	case K_CODE:
		switch (k->code) {
		case KEY_LEFT: arrow(cx, cy, -1, 0, col); break;
		case KEY_RIGHT: arrow(cx, cy, 1, 0, col); break;
		case KEY_UP: arrow(cx, cy, 0, -1, col); break;
		case KEY_DOWN: arrow(cx, cy, 0, 1, col); break;
		}
		break;
	}
}

static int
isicon(const Key *k)
{
	return k->kind == K_SHIFT || k->kind == K_BKSP || k->kind == K_ENTER || (k->kind == K_LAPTOP && !k->label)
		|| k->kind == K_MODS || k->kind == K_EMOJI || k->kind == K_CLIP || k->kind == K_GEAR || k->kind == K_HIDE || k->kind == K_TAB || k->kind == K_TRANSLATE || k->kind == K_TRSWAP
		|| (k->kind == K_SEARCH && !k->label) || (k->kind == K_CODE && !k->label);
}

static void
upper(const char *in, char *out, int size)
{
	for (int i = 0; i < nlets; i++)
		if (!strcmp(in, lets[i].low)) {
			snprintf(out, (size_t)size, "%s", lets[i].up);
			return;
		}
	snprintf(out, (size_t)size, "%s", in);
	if (strlen(out) == 1)
		out[0] = (char)toupper((unsigned char)out[0]);
}

static const struct { char c; const char *alts; } alts_m[] = {
	{'a', "@"}, {'i', "8"}, {'s', "#"}, {'t', "5"},
	{'q', "1"}, {'w', "2"}, {'e', "3"}, {'r', "4"}, {'y', "6"}, {'u', "7"}, {'o', "9"}, {'p', "0"},
	{'d', "$"}, {'f', "_"}, {'g', "&"}, {'h', "-"}, {'j', "+"}, {'k', "("}, {'l', ")"},
	{'z', "*"}, {'x', "\""}, {'c', "'"}, {'v', ":"}, {'b', ";"}, {'n', "!"}, {'m', "?"},
	{'.', "? ! ; : …"}, {',', "' \" -"},
};

/* the quiet corner hint: a language's letters stay out of sight until held */
static const char *
corner_for(const char *t)
{
	if (!t[0] || t[1])
		return NULL;
	for (size_t i = 0; i < LEN(alts_m); i++)
		if (alts_m[i].c == t[0])
			return alts_m[i].alts;
	return NULL;
}

static const char *
alts_for(const char *t)
{
	static char buf[64];
	const char *base = corner_for(t);
	size_t n = 0;

	if (!base)
		return NULL;
	/* a language's letters stay first: they are what typing it reaches for */
	for (int l = 0; l < nlets; l++)
		/* a secret field also offers removed languages: a password may still hold their letters */
		if ((lets[l].active || secret) && lets[l].base == t[0] && n + strlen(lets[l].low) + 2 < sizeof buf / 2)
			n += (size_t)snprintf(buf + n, sizeof buf - n, "%.7s ", lets[l].low);
	snprintf(buf + n, sizeof buf - n, "%s", base);
	return buf;
}

static int
pressed_key(int key)
{
	for (size_t i = 0; i < LEN(slots); i++)
		if (slots[i].used && slots[i].key == key && !slots[i].swiping)
			return 1;
	return 0;
}

/* premultiplied over the frame, clipped to [y0, y1) in logical px */
static void
blitemoji(const char *seq, float cx, float cy, float size, float y0, float y1)
{
	int w, h;
	const uint32_t *g = emoji_glyph(seq, (int)(size * sc + 0.5f), &w, &h);
	int ox, oy, top = (int)(y0 * sc), bot = (int)(y1 * sc);

	if (!g)
		return;
	ox = (int)(cx * sc) - w / 2;
	oy = (int)(cy * sc) - h / 2;
	for (int j = 0; j < h; j++) {
		int yy = oy + j;

		if (yy < top || yy >= bot || yy < 0 || yy >= bh)
			continue;
		for (int i = 0; i < w; i++) {
			int xx = ox + i;
			uint32_t v, a, ia, d;

			if (xx < 0 || xx >= bw || !(v = g[j * w + i]))
				continue;
			a = v >> 24;
			ia = 255 - a;
			d = px[yy * bw + xx];
			px[yy * bw + xx] = 0xff000000u
				| ((v >> 16 & 255) + (d >> 16 & 255) * ia / 255) << 16
				| ((v >> 8 & 255) + (d >> 8 & 255) * ia / 255) << 8
				| ((v & 255) + (d & 255) * ia / 255);
		}
	}
}

static uint32_t
mixc(uint32_t a, uint32_t b, float f)
{
	uint32_t r = 0;

	for (int sh = 0; sh < 32; sh += 8)
		r |= (uint32_t)((a >> sh & 255) * (1 - f) + (b >> sh & 255) * f + 0.5f) << sh;
	return r;
}

static void
drawkey(int idx)
{
	const Key *k = &keys[idx];
	/* nothing about a secret key press shows */
	int down = pressed_key(idx) && !(secret && k->kind == K_CHAR);
	float x = k->x + GAP, y = k->y + GAP, w = k->w - 2 * GAP, h = k->h - 2 * GAP;
	float cx = k->x + k->w / 2, cy = k->y + k->h / 2;
	int special = k->kind != K_CHAR && k->kind != K_SPACE;
	uint32_t bg = special ? SPECIAL_BG : KEY_BG, fg = WHITE;
	char up[8];
	const char *label = k->label;
	const char *alts;
	int dot = 0, outline = 0, underline = 0;

	if (k->kind == K_TAB) {
		if (k->code >= 0 && emoji_first(k->code))
			blitemoji(emoji_first(k->code), cx, cy, 22, 0, TAB_H);
		else
			icon(k, cx, cy, em_group == k->code ? WHITE : DIM);
		if (em_group == k->code && !em_search)
			stroke(cx - 9, TAB_H - 4, cx + 9, TAB_H - 4, 1.1f, ACCENT);
		return;
	}
	if (k->kind == K_CHAR && shift_state && !k->label) {
		upper(k->text, up, sizeof up);
		label = up;
	} else if (k->kind == K_CHAR && !k->label) {
		label = k->text;
	}
	if (k->kind == K_SHIFT && shift_state)
		fg = ACCENT;
	if (k->kind == K_MOD) {
		/* one tap outlined with a dot, locked solid and underlined */
		if (mods_locked & (unsigned)k->code) {
			bg = ACCENT;
			underline = 1;
		} else if (mods_latched & (unsigned)k->code) {
			dot = outline = 1;
		}
	}
	if (k->kind == K_MODS && (mods_latched || mods_locked))
		fg = ACCENT;
	if (down) {
		bg = WHITE;
		fg = BLACK;
	} else if (!(secret && k->kind == K_CHAR) && now_ms() - key_rel[idx] < KEY_FADE_MS) {
		float f = (float)(now_ms() - key_rel[idx]) / KEY_FADE_MS;

		f = 1 - (1 - f) * (1 - f);
		bg = mixc(WHITE, bg, f);
		fg = mixc(BLACK, fg, f);
		fading = 1;
	}
	if (!cfg.key_borders && !down && bg == (special ? SPECIAL_BG : KEY_BG)) {
		/* flat: only the label */
	} else if (outline) {
		rrect(x, y, w, h, RADIUS, ACCENT);
		rrect(x + 1.5f, y + 1.5f, w - 3, h - 3, RADIUS - 1.5f, bg);
	} else {
		rrect(x, y, w, h, RADIUS, bg);
	}
	if (underline)
		stroke(cx - 9, y + h - 6, cx + 9, y + h - 6, 1.f, WHITE);
	if (isicon(k)) {
		icon(k, cx, cy, fg);
	} else if (k->kind == K_SPACE) {
		stroke(cx - 14, cy, cx + 14, cy, 0.75f, down ? BLACK : DIM);
	} else {
		text(label, cx, cy, k->kind == K_CHAR ? (laptop ? 18 : 20) : 13, w - 6, fg);
	}
	if (dot)
		stroke(x + w - 8, y + 8, x + w - 8, y + 8, 2.2f, ACCENT);
	/* what a long press offers, kept quiet in the corner */
	if (cfg.corner_hints && k->kind == K_CHAR && !down && (alts = corner_for(k->text))) {
		char first[8] = "";

		sscanf(alts, "%7s", first);
		if (shift_state)
			upper(first, first, sizeof first);
		text(first, x + w - 6.5f, y + 8.5f, 9.5f, 0, DIM);
	}
}

/* one line of an entry, cut short: the list is for recognising, not reading */
static void
clippreview(const char *in, char *out, size_t size)
{
	size_t o = 0;
	int chars = 0;

	while (*in && chars < 44 && o + 5 < size) {
		const char *start = in;

		utf8_next(&in);
		if ((unsigned char)*start < 0x20) {
			out[o++] = ' ';
		} else {
			memcpy(out + o, start, (size_t)(in - start));
			o += (size_t)(in - start);
		}
		chars++;
	}
	if (*in) {
		memcpy(out + o, "…", 3);
		o += 3;
	}
	out[o] = 0;
}

static void
drawpanel(void)
{
	float wf = (float)width;

	if (panel == PANEL_CLIP) {
		float top = TAB_H, bot = (float)height - PANEL_BOT;
		char line[256];

		if (!cfg.clipboard_history) {
			text("Clipboard history is off", wf / 2, (top + bot) / 2, 14, wf - 24, DIM);
			return;
		}
		if (!nclips) {
			text("Nothing copied yet", wf / 2, (top + bot) / 2, 14, wf - 24, DIM);
			return;
		}
		for (int i = 0; i < nclips; i++) {
			float y = top + (float)i * CLIP_ROW - clip_scroll;
			int down = 0;

			if (y + CLIP_ROW <= top || y >= bot)
				continue;
			for (size_t s = 0; s < LEN(slots); s++)
				down |= slots[s].used && slots[s].drag == D_CLIP && slots[s].tile == i;
			if (y + CLIP_ROW / 2 < top || y + CLIP_ROW / 2 >= bot)
				continue;
			rrect(GAP, y + GAP, wf - 2 * GAP, CLIP_ROW - 2 * GAP, RADIUS, down ? HILITE : KEY_BG);
			clippreview(clips[i], line, sizeof line);
			text(line, wf / 2, y + CLIP_ROW / 2, 14, wf - 24, WHITE);
		}
		return;
	}
	if (em_kind == EMOJI_NONE) {
		const char *found = emoji_font_path();

		text(found[0] ? "Emoji data is missing." : "No emoji font found.", wf / 2, (float)height / 2 - 24, 16, wf - 24, WHITE);
		text(found[0] ? "Reinstall the keyboard data." : "Install Noto Color Emoji.", wf / 2, (float)height / 2 + 2, 14, wf - 24, DIM);
		return;
	}
	if (em_search) {
		float t = wf / (float)MAX(8, width / 49);

		text(em_query[0] ? em_query : "Search emoji", (wf - U * 1.6f) / 2, QUERY_H / 2, 15, wf - U * 2, em_query[0] ? WHITE : DIM);
		stroke(8, QUERY_H - 2, wf - U * 1.6f, QUERY_H - 2, 0.5f, LINE);
		if (em_query[0] && !em_nfound)
			text("No match", wf / 2, QUERY_H + STRIP_H / 2, 14, wf - 24, DIM);
		for (int i = 0; i < em_nfound && (float)i * t < wf; i++)
			blitemoji(emoji_at(em_found[i])->seq, ((float)i + 0.5f) * t, QUERY_H + STRIP_H / 2, t * 0.68f, QUERY_H, QUERY_H + STRIP_H);
		return;
	}
	{
		int cols = MAX(8, width / 49), n = tilecount();
		float t = wf / (float)cols, top = TAB_H, bot = (float)height - PANEL_BOT;

		if (!n)
			text("Emoji you use appear here", wf / 2, (top + bot) / 2, 14, wf - 24, DIM);
		for (int i = (int)(em_scroll / t) * cols; i < n; i++) {
			float y = top + (float)(i / cols) * t - em_scroll, x = (float)(i % cols) * t;
			int down = 0;

			if (y >= bot)
				break;
			for (size_t s = 0; s < LEN(slots); s++)
				down |= slots[s].used && slots[s].drag == D_GRID && slots[s].tile == i && (int)s != popup_slot;
			if (down && y >= top && y + t <= bot)
				rrect(x + GAP, y + GAP, t - 2 * GAP, t - 2 * GAP, RADIUS, HILITE);
			blitemoji(tileseq(i), x + t / 2, y + t / 2, t * 0.68f, top, bot);
		}
	}
}

static const char *
trname(const char *code)
{
	for (size_t i = 0; i < LEN(lang_names); i++)
		if (!strcmp(lang_names[i].code, code))
			return lang_names[i].name;
	return code;
}

static void
drawtrans(void)
{
	char line[256];
	float wf = (float)width, ry = TAB_H + QUERY_H + STRIP_H / 2;
	const char *s = tr_in + (strlen(tr_in) > 160 ? strlen(tr_in) - 160 : 0);

	/* the end of the text is what is being typed */
	while ((*s & 0xc0) == 0x80)
		s++;
	while (*s && textw(s, 15) > wf - 24)
		utf8_next(&s);
	text(tr_in[0] ? s : "Type to translate", wf / 2, TAB_H + QUERY_H / 2, 15, wf - 24, tr_in[0] ? WHITE : DIM);
	stroke(8, TAB_H + QUERY_H - 2, wf - 8, TAB_H + QUERY_H - 2, 0.5f, LINE);
	if (!tr_from[0] || !tr_to[0]) {
		text("Tap Add to get a language", wf / 2, ry, 14, wf - 24, DIM);
	} else if (tr_pending || tr_pid) {
		text("...", wf / 2, ry, 15, 0, DIM);
	} else if (tr_msg[0]) {
		text(tr_msg, wf / 2, ry, 14, wf - 24, DIM);
	} else if (tr_out[0]) {
		/* shortcut: one line shows the start of a long translation, wrap it if that proves too little */
		rrect(GAP, TAB_H + QUERY_H + GAP, wf - 2 * GAP, STRIP_H - 2 * GAP, RADIUS, KEY_BG);
		clippreview(tr_out, line, sizeof line);
		text(line, wf / 2, ry - 2, 15, wf - 24, WHITE);
		stroke(wf / 2 - 8, TAB_H + QUERY_H + STRIP_H - 8, wf / 2 + 8, TAB_H + QUERY_H + STRIP_H - 8, 1.1f, ACCENT);
	}
}

static void
drawlangs(void)
{
	float wf = (float)width, top = TAB_H, bot = (float)height - PANEL_BOT;
	char line[96];

	if (lr_job == JOB_INSTALL && lr_total > 0) {
		snprintf(line, sizeof line, "Downloading %ld of %ld MB", lr_done / 1048576, (lr_total + 1048575) / 1048576);
		text(line, wf / 2, TAB_H / 2, 14, wf - 24, WHITE);
		rrect(0, TAB_H - 3, wf * (float)MIN(lr_done, lr_total) / (float)lr_total, 3, 1, ACCENT);
	} else {
		text(lr_msg[0] ? lr_msg : "Languages", wf / 2, TAB_H / 2, 14, wf - 24, lr_msg[0] ? DIM : WHITE);
	}
	for (int i = 0; i < nlrows; i++) {
		const LangRow *r = &lrows[i];
		float y = top + (float)i * CLIP_ROW - lr_scroll;
		const char *what;
		char sz[24];

		if (y + CLIP_ROW / 2 < top || y + CLIP_ROW / 2 >= bot)
			continue;
		if (i == lr_sel)
			rrect(GAP, y + GAP, wf - 2 * GAP, CLIP_ROW - 2 * GAP, RADIUS, ACCENT);
		rrect(GAP + (i == lr_sel ? 1.5f : 0), y + GAP + (i == lr_sel ? 1.5f : 0), wf - 2 * GAP - (i == lr_sel ? 3 : 0),
			CLIP_ROW - 2 * GAP - (i == lr_sel ? 3 : 0), RADIUS, KEY_BG);
		text(r->name, 14 + MIN(textw(r->name, 15), wf * 0.5f) / 2, y + CLIP_ROW / 2, 15, wf * 0.5f, r->usable ? WHITE : DIM);
		snprintf(sz, sizeof sz, "%ld MB", (r->size + 1048575) / 1048576);
		what = r->installed ? "Installed" : !r->usable ? "Not available"
			: !strcmp(r->dir, "toen") ? "To English only" : !strcmp(r->dir, "fromen") ? "From English only" : sz;
		text(what, wf - 14 - textw(what, 12) / 2, y + CLIP_ROW / 2, 12, 0, r->installed ? ACCENT : DIM);
	}
}

static int
chevx(void)
{
	return width / 2 + PILL_HALF + 4;
}

static void
draw(void)
{
	Buffer *b = NULL;

	for (size_t i = 0; i < LEN(buffers); i++)
		if (buffers[i].buf && !buffers[i].busy) {
			b = &buffers[i];
			break;
		}
	if (!b)
		return;
	px = b->data;
	for (int i = 0; i < bw * bh; i++)
		px[i] = BG;

	/* suggestions: the best guess in the centre, marked when space would write it instead */
	for (int i = 0; i < nsug; i++) {
		float cw = sug_w, cx = sug_x + cw * ((float)i + 0.5f);
		int down = 0;

		for (size_t s = 0; s < LEN(slots); s++)
			down |= slots[s].used && slots[s].sug == i;
		if (down && sug[i][0])
			rrect(sug_x + cw * (float)i + GAP, GAP, cw - 2 * GAP, SUG_H - 2 * GAP, RADIUS, HILITE);
		text(sug[i], cx, SUG_H / 2, 16, cw - 14, i == 1 ? WHITE : DIM);
		if (i == sug_fix)
			stroke(cx - 8, SUG_H - 7, cx + 8, SUG_H - 7, 1.1f, ACCENT);
		if (i && sug[i][0] && sug[i - 1][0])
			stroke(sug_x + cw * (float)i, SUG_H / 2, sug_x + cw * (float)i, SUG_H / 2, 1.1f, LINE);
	}

	if (panel == PANEL_TRANS)
		drawtrans();
	else if (panel == PANEL_LANGS)
		drawlangs();
	else if (panel)
		drawpanel();

	for (int i = 0; i < nkeys; i++)
		drawkey(i);

	/* bubble above a pressed letter, so the finger hides nothing */
	for (size_t s = 0; s < LEN(slots); s++)
		if (slots[s].used && slots[s].key >= 0 && !slots[s].swiping && (int)s != popup_slot) {
			const Key *k = &keys[slots[s].key];
			char up[8];
			float bwid = MAX(k->w, POPUP_W), bx = k->x + k->w / 2 - bwid / 2;

			if (k->kind != K_CHAR || k->label || secret || !cfg.key_preview)
				continue;
			bx = MAX(2.f, MIN((float)width - bwid - 2, bx));
			rrect(bx, k->y - POPUP_H + 2, bwid, POPUP_H, 12, WHITE);
			if (shift_state)
				upper(k->text, up, sizeof up);
			text(shift_state ? up : k->text, bx + bwid / 2, k->y - POPUP_H / 2 + 2, 26, 0, BLACK);
		}

	/* long press choices */
	if (popup_slot >= 0) {
		rrect(popup_x - 3, popup_y - 3, POPUP_W * (float)popup_n + 6, POPUP_H + 6, 14, HILITE);
		for (int i = 0; i < popup_n; i++) {
			float x = popup_x + POPUP_W * (float)i;

			if (i == popup_sel)
				rrect(x, popup_y, POPUP_W, POPUP_H, 11, ACCENT);
			if (popup_emoji)
				blitemoji(popup[i], x + POPUP_W / 2, popup_y + POPUP_H / 2, 34, 0, (float)height);
			else
				text(popup[i], x + POPUP_W / 2, popup_y + POPUP_H / 2, 24, 0, WHITE);
		}
	}

	/* no way back from a hidden keyboard on the lock screen, and a secret field looks the same from here */
	if (!secret && height) {
		float cx = (float)chevx() + 16, cy = (float)height + BAR_ROOM / 2.f;

		stroke(cx - 7, cy - 2.5f, cx, cy + 2.5f, 0.8f, DIM);
		stroke(cx, cy + 2.5f, cx + 7, cy - 2.5f, 0.8f, DIM);
	}

	/* swipe trail as a line of dots */
	if (npath > 1)
		for (int i = 0; i < npath; i += 2)
			stroke(path[i][0], path[i][1], path[i][0], path[i][1], 2.2f, WHITE);

	wl_surface_attach(surf, b->buf, 0, 0);
	wl_surface_damage_buffer(surf, 0, 0, bw, bh);
	b->busy = 1;
	dirty = 0;
}

static void
frame_done(void *data, struct wl_callback *cb, uint32_t t)
{
	wl_callback_destroy(cb);
	frame_cb = NULL;
}
static const struct wl_callback_listener frame_listener = {frame_done};

static void
buffer_release(void *data, struct wl_buffer *b)
{
	((Buffer *)data)->busy = 0;
}
static const struct wl_buffer_listener buffer_listener = {buffer_release};

/* the keys, and the hide area where there is one; the rest of the strip is the compositor's */
static void
setinputregion(void)
{
	static int w, h, sec;
	struct wl_region *r;

	if (w == width && h == height && sec == secret && surf_region)
		return;
	w = width;
	h = height;
	sec = secret;
	surf_region = 1;
	r = wl_compositor_create_region(compositor);
	wl_region_add(r, 0, 0, width, height);
	if (!secret)
		wl_region_add(r, chevx(), height, CHEV_W, BAR_ROOM);
	wl_surface_set_input_region(surf, r);
	wl_region_destroy(r);
}

static void
flushdraw(void)
{
	if (!dirty || !configured || frame_cb || !surf)
		return;
	fading = 0;
	draw();
	if (dirty)
		return;
	setinputregion();
	frame_cb = wl_surface_frame(surf);
	wl_callback_add_listener(frame_cb, &frame_listener, NULL);
	wl_surface_commit(surf);
	dirty = fading;
}

static void
freebuffers(void)
{
	for (size_t i = 0; i < LEN(buffers); i++) {
		if (buffers[i].buf) {
			wl_buffer_destroy(buffers[i].buf);
			munmap(buffers[i].data, buffers[i].size);
		}
		memset(&buffers[i], 0, sizeof buffers[i]);
	}
}

static int
makebuffers(void)
{
	size_t one;
	int fd;
	uint8_t *mem;
	struct wl_shm_pool *pool;

	freebuffers();
	bw = (int)lroundf((float)width * (float)scale120 / 120);
	bh = (int)lroundf((float)(height + BAR_ROOM) * (float)scale120 / 120);
	sc = (float)bw / (float)width;
	one = (size_t)bw * (size_t)bh * 4;
	if ((fd = memfd_create("phonekbd", MFD_CLOEXEC)) < 0)
		return 0;
	if (ftruncate(fd, (off_t)(one * 2)) < 0 ||
			(mem = mmap(NULL, one * 2, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)) == MAP_FAILED) {
		close(fd);
		return 0;
	}
	pool = wl_shm_create_pool(shm, fd, (int32_t)(one * 2));
	for (int i = 0; i < 2; i++) {
		buffers[i].buf = wl_shm_pool_create_buffer(pool, (int32_t)((size_t)i * one), bw, bh, bw * 4, WL_SHM_FORMAT_XRGB8888);
		buffers[i].data = (uint32_t *)(void *)(mem + (size_t)i * one);
		buffers[i].size = one;
		wl_buffer_add_listener(buffers[i].buf, &buffer_listener, &buffers[i]);
	}
	/* shortcut: maps the pair as one and unmaps it as two halves, which is what munmap allows */
	wl_shm_pool_destroy(pool);
	close(fd);
	if (viewport)
		wp_viewport_set_destination(viewport, width, height + BAR_ROOM);
	return 1;
}

/* --- config: format in keyboard/CONFIG.md --- */
static int
configpath(char *out, size_t size)
{
	const char *x = getenv("XDG_CONFIG_HOME"), *h = getenv("HOME");

	if (x && *x)
		snprintf(out, size, "%s/phonekbd/config", x);
	else
		snprintf(out, size, "%s/.config/phonekbd/config", h ? h : "/tmp");
	return 1;
}

static int
onoff(const char *v, int fallback)
{
	return !strcmp(v, "on") || !strcmp(v, "true") ? 1 : !strcmp(v, "off") || !strcmp(v, "false") ? 0 : fallback;
}

static void clipwipe(void);

static long
statems(const char *name)
{
	char p[600];
	struct stat st;

	snprintf(p, sizeof p, "%s/%s", state_dir, name);
	if (stat(p, &st))
		return 0;
	return st.st_mtim.tv_sec * 1000 + st.st_mtim.tv_nsec / 1000000;
}

/* off means gone at once; another process asks for a wipe through a stamp, the list lives only here */
static void
applyhistory(void)
{
	static long clip_seen;
	long now = statems("clipboard-cleared");
	char p[600];

	if (!cfg.emoji_history) {
		snprintf(p, sizeof p, "%s/emoji-recent", state_dir);
		unlink(p);
		emoji_recent_forget();
	}
	if (!cfg.clipboard_history || now != clip_seen)
		clipwipe();
	clip_seen = now;
}

/* small, normal, large or a percentage; 0 when it is none of them */
static int
parseheight(const char *v)
{
	char *end;
	long n = strtol(v, &end, 10);

	if (!strcmp(v, "small"))
		return 85;
	if (!strcmp(v, "normal"))
		return 100;
	if (!strcmp(v, "large"))
		return 115;
	return end != v && (!*end || !strcmp(end, "%")) && n >= 70 && n <= 140 ? (int)n : 0;
}

/* one key of the shell's phone.conf, the last line wins; a missing file or key leaves v empty */
static void
phoneconf(const char *key, char v[32])
{
	const char *x = getenv("XDG_CONFIG_HOME"), *h = getenv("HOME");
	char p[600], line[128], k[32], val[32];
	FILE *f;

	v[0] = 0;
	if (x && *x)
		snprintf(p, sizeof p, "%s/phonegluewc/phone.conf", x);
	else
		snprintf(p, sizeof p, "%s/.config/phonegluewc/phone.conf", h ? h : "/tmp");
	if (!(f = fopen(p, "r")))
		return;
	while (fgets(line, sizeof line, f))
		if (sscanf(line, " %31[^= \t] = %31s", k, val) == 2 && !strcmp(k, key))
			snprintf(v, 32, "%s", val);
	fclose(f);
}

/* the phone's own light or dark first; theme=system without it asks gsettings, the default without it is dark */
/* shortcut: asks gsettings at each show when following the system, read the portal if that shows up in a profile */
static int
systemlight(void)
{
	char line[64] = "";
	FILE *f;

	phoneconf("theme", line);
	if (line[0])
		return !strcmp(line, "light");
	if (cfg.theme_system != 1 || !(f = popen("gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null", "r")))
		return 0;
	if (!fgets(line, sizeof line, f))
		line[0] = 0;
	pclose(f);
	return strstr(line, "prefer-light") || strstr(line, "default");
}

static void
applytheme(void)
{
	char v[32];
	unsigned int rgb;

	theme_now = themes[cfg.theme_system ? (systemlight() ? THEME_LIGHT : 0) : cfg.theme];
	if (cfg.accent)
		theme_now.accent = accents[cfg.accent - 1].col;
	else {
		/* the shell's accent, its white turned dark on the light keys */
		phoneconf("accent", v);
		if (v[0] == '#' && strlen(v) == 7 && strspn(v + 1, "0123456789abcdefABCDEF") == 6 && sscanf(v + 1, "%x", &rgb) == 1)
			theme_now.accent = 0xff000000u | (rgb == 0xf5f5f5 && theme_now.bg == themes[THEME_LIGHT].bg ? 0x111111 : rgb);
	}
}

/* the status bar's ringer: read at show, so a change while shown waits for the next */
static int
ringeroff(void)
{
	char v[32];

	phoneconf("ringer", v);
	return !strcmp(v, "vibrate") || !strcmp(v, "silent");
}

static void
loadconfig(void)
{
	char p[600], line[256], *k, *v, *eq;
	FILE *f;

	cfg.autocorrect = cfg.predict = cfg.learn = cfg.space_cursor = cfg.clipboard_history = cfg.emoji_history = cfg.autocap = cfg.double_space = 1;
	cfg.number_row = cfg.sound = cfg.vibrate = cfg.one_handed = cfg.theme = 0;
	cfg.key_height = 100;
	cfg.key_borders = cfg.corner_hints = cfg.key_preview = 1;
	cfg.long_ms = LONG_NORMAL;
	/* 2 follows only the phone's own setting, 1 (theme=system) falls back to gsettings */
	cfg.theme_system = 2;
	cfg.accent = 0;
	cfg.langs_set = 0;
	int height_set = 0;
	configpath(p, sizeof p);
	if ((f = fopen(p, "r"))) {
		while (fgets(line, sizeof line, f)) {
			if ((k = strchr(line, '#')))
				*k = 0;
			if (!(eq = strchr(line, '=')))
				continue;
			*eq = 0;
			k = line + strspn(line, " \t");
			k[strcspn(k, " \t")] = 0;
			v = eq + 1 + strspn(eq + 1, " \t");
			if (!strcmp(k, "predict_languages")) {
				v[strcspn(v, "\r\n")] = 0;
				snprintf(cfg.langs, sizeof cfg.langs, "%s", v);
				cfg.langs_set = 1;
				continue;
			}
			v[strcspn(v, " \t\r\n")] = 0;
			if (!strcmp(k, "autocorrect")) cfg.autocorrect = onoff(v, 1);
			else if (!strcmp(k, "predict")) cfg.predict = onoff(v, 1);
			else if (!strcmp(k, "learn")) cfg.learn = onoff(v, 1);
			else if (!strcmp(k, "number_row")) cfg.number_row = onoff(v, 0);
			else if (!strcmp(k, "sound")) cfg.sound = onoff(v, 0);
			else if (!strcmp(k, "vibrate")) cfg.vibrate = onoff(v, 0);
			else if (!strcmp(k, "space_cursor")) cfg.space_cursor = onoff(v, 1);
			else if (!strcmp(k, "clipboard_history")) cfg.clipboard_history = onoff(v, 1);
			else if (!strcmp(k, "emoji_history")) cfg.emoji_history = onoff(v, 1);
			else if (!strcmp(k, "autocap")) cfg.autocap = onoff(v, 1);
			else if (!strcmp(k, "double_space")) cfg.double_space = onoff(v, 1);
			else if (!strcmp(k, "translate_from")) snprintf(tr_from, sizeof tr_from, "%s", v);
			else if (!strcmp(k, "translate_to")) snprintf(tr_to, sizeof tr_to, "%s", v);
			else if (!strcmp(k, "key_borders")) cfg.key_borders = onoff(v, 1);
			else if (!strcmp(k, "corner_hints")) cfg.corner_hints = onoff(v, 1);
			else if (!strcmp(k, "key_preview")) cfg.key_preview = onoff(v, 1);
			else if (!strcmp(k, "long_press"))
				cfg.long_ms = !strcmp(v, "short") ? 220 : !strcmp(v, "long") ? 600 : LONG_NORMAL;
			else if (!strcmp(k, "accent")) {
				for (size_t i = 0; i < LEN(accents); i++)
					if (!strcmp(v, accents[i].name))
						cfg.accent = (int)i + 1;
			} else if (!strcmp(k, "height")) {
				int n = parseheight(v);

				if (n) {
					cfg.key_height = n;
					height_set = 1;
				}
			} else if (!strcmp(k, "key_height")) {
				/* the older name; height wins wherever the two lines are */
				if (!height_set)
					cfg.key_height = parseheight(v) ? parseheight(v) : 100;
			} else if (!strcmp(k, "one_handed"))
				cfg.one_handed = !strcmp(v, "left") ? 1 : !strcmp(v, "right") ? 2 : 0;
			else if (!strcmp(k, "theme")) {
				cfg.theme_system = !strcmp(v, "system") ? 1 : !strcmp(v, "phone") ? 2 : 0;
				/* the name this theme had before */
				if (!strcmp(v, "nothing"))
					cfg.theme = 0;
				for (size_t i = 0; i < LEN(themes); i++)
					if (!strcmp(v, themes[i].name))
						cfg.theme = (int)i;
			}
		}
		fclose(f);
	}
	/* an empty list is the same as both switched off; the long press letters do not depend on it */
	if (cfg.langs_set && !cfg.langs[strspn(cfg.langs, " \t")])
		cfg.predict = cfg.autocorrect = 0;
	cfg.ringer_off = ringeroff();
	applytheme();
	applyhistory();
	wordslangs();
}

/* rewrites one key and keeps every other line, comments included */
static void
setconfig(const char *key, const char *val)
{
	char p[600], tmp[620], line[256], dir[600], *slash;
	size_t kl = strlen(key);
	int done = 0, fd;
	FILE *in, *out;

	configpath(p, sizeof p);
	snprintf(dir, sizeof dir, "%s", p);
	slash = strrchr(dir, '/');
	*slash = 0;
	if ((slash = strrchr(dir, '/'))) {
		*slash = 0;
		mkdir(dir, 0700);
		*slash = '/';
	}
	mkdir(dir, 0700);
	snprintf(tmp, sizeof tmp, "%s.tmp", p);
	if ((fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600)) < 0 || !(out = fdopen(fd, "w")))
		return;
	if ((in = fopen(p, "r"))) {
		while (fgets(line, sizeof line, in)) {
			const char *t = line + strspn(line, " \t");

			if (!strncmp(t, key, kl) && strchr(" \t=", t[kl])) {
				if (!done)
					fprintf(out, "%s = %s\n", key, val);
				done = 1;
			} else {
				fputs(line, out);
			}
		}
		fclose(in);
	}
	if (!done)
		fprintf(out, "%s = %s\n", key, val);
	if (fclose(out) == 0)
		rename(tmp, p);
}

/* --- layouts --- */
static void
addkey(float *x, float y, float w, float h, int kind, int code, const char *label, const char *txt)
{
	Key *k;

	if ((size_t)nkeys >= LEN(keys))
		return;
	k = &keys[nkeys++];
	*k = (Key){.label = label, .text = txt, .kind = kind, .code = code, .x = *x, .y = y, .w = w, .h = h};
	*x += w;
}

static void
letters(const char *row, float *x, float y, float h)
{
	const char *p = row;

	while (*p) {
		const char *start = p;
		char *t = keytext[nkeytext++ % 64];

		utf8_next(&p);
		snprintf(t, 8, "%.*s", (int)(p - start), start);
		if (page == PAGE_ABC && !t[1] && t[0] >= 'a' && t[0] <= 'z') {
			key_pos[t[0] - 'a'][0] = (*x + U / 2) / U;
			key_pos[t[0] - 'a'][1] = (y + h / 2) / U;
		}
		addkey(x, y, U, h, K_CHAR, 0, NULL, t);
	}
}

static float
rowh(void)
{
	float b = laptop ? LAP_ROW_H : landscape ? 48.f : ROW_H;
	/* the lock screen keeps its room whatever the settings say */
	int kh = secret ? MIN(cfg.key_height, 100) : cfg.key_height;

	return landscape ? b : b * (float)kh / 100;
}

static float
wantheight(void)
{
	float kb = (landscape ? 0 : SUG_H) + (float)(4 + cfg.number_row) * rowh();

	/* turned: no suggestions, the keys keep their size and the window keeps the room */
	if (laptop)
		return rowh() * 7;
	if (panel == PANEL_EMOJI && em_search)
		return QUERY_H + STRIP_H + rowh() * 4;
	if (panel == PANEL_TRANS)
		return TRANS_TOP + rowh() * 4;
	if (panel == PANEL_LANGS)
		return TAB_H + CLIP_ROW * 7 + PANEL_BOT;
	if (panel)
		return kb;
	return kb + (modrow ? MOD_H : 0);
}

static void
dumpkeys(void)
{
	const char *p = getenv("PHONEKBD_DUMP");
	FILE *f = p ? fopen(p, "w") : NULL;

	if (!f)
		return;
	for (int i = 0; i < nkeys; i++)
		fprintf(f, "%s %d %d %.1f %.1f\n", keys[i].label ? keys[i].label : keys[i].text ? keys[i].text : "-",
			keys[i].kind, keys[i].code, keys[i].x + keys[i].w / 2, keys[i].y + keys[i].h / 2);
	for (int i = 0; i < nkeys; i++)
		if (keys[i].kind == K_CHAR && corner_for(keys[i].text))
			fprintf(f, "hint %s %s\n", keys[i].text, corner_for(keys[i].text));
	fprintf(f, "state - panel=%d kind=%d search=%d modrow=%d secret=%d nsug=%d tiles=%d clips=%d rows=%d job=%d from=%s to=%s\n", panel, em_kind, em_search,
		modrow, secret, nsug, panel == PANEL_EMOJI ? tilecount() : 0, nclips, nlrows, lr_job, tr_from, tr_to);
	fprintf(f, "size - - %d %d\n", width, height);
	fclose(f);
}

static void
buildemoji(float wf)
{
	float x = 0, y = (float)height - PANEL_BOT, tw;

	U = wf / 10;
	if (em_kind != EMOJI_NONE) {
		tw = wf / (EMOJI_GROUPS + (cfg.emoji_history ? 1 : 0));
		if (cfg.emoji_history)
			addkey(&x, 0, tw, TAB_H, K_TAB, -1, NULL, "recent");
		for (int i = 0; i < EMOJI_GROUPS; i++)
			addkey(&x, 0, tw, TAB_H, K_TAB, i, NULL, "tab");
	}
	x = 0;
	addkey(&x, y, U * 1.5f, PANEL_BOT, K_ABC, 0, "abc", NULL);
	if (em_kind != EMOJI_NONE) {
		addkey(&x, y, U * 1.5f, PANEL_BOT, K_SEARCH, 0, NULL, "search");
		addkey(&x, y, U * 5.5f, PANEL_BOT, K_SPACE, 0, NULL, " ");
		addkey(&x, y, U * 1.5f, PANEL_BOT, K_BKSP, 0, NULL, NULL);
	}
}

static void
buildclip(float wf)
{
	static const struct { const char *l; int code; } acts[] = {
		{"All", KEY_A}, {"Cut", KEY_X}, {"Copy", KEY_C}, {"Paste", KEY_V}, {"Undo", KEY_Z}, {"Redo", KEY_Y},
	};
	float x = 0, y = (float)height - PANEL_BOT;

	U = wf / 10;
	for (size_t i = 0; i < LEN(acts); i++)
		addkey(&x, 0, wf / 6, TAB_H, K_ACT, acts[i].code, acts[i].l, NULL);
	x = 0;
	float w = wf / (cfg.clipboard_history ? 5 : 4);
	addkey(&x, y, w, PANEL_BOT, K_ABC, 0, "abc", NULL);
	addkey(&x, y, w, PANEL_BOT, K_LAPTOP, 0, "Laptop", NULL);
	addkey(&x, y, w, PANEL_BOT, K_ONEHAND, 0, "One hand", NULL);
	addkey(&x, y, w, PANEL_BOT, K_THEME, 0, "Theme", NULL);
	if (cfg.clipboard_history)
		addkey(&x, y, w, PANEL_BOT, K_CLEARCLIP, 0, "Clear", NULL);
}

static void
buildlangs(float wf)
{
	float x = 0, y = (float)height - PANEL_BOT;
	const LangRow *r = lr_sel >= 0 && lr_sel < nlrows ? &lrows[lr_sel] : NULL;

	U = wf / 10;
	if (lr_job == JOB_INSTALL)
		snprintf(lr_label, sizeof lr_label, "Cancel");
	else if (!r)
		snprintf(lr_label, sizeof lr_label, "Choose a language");
	else if (r->installed)
		snprintf(lr_label, sizeof lr_label, "Delete %.48s", r->name);
	else if (r->usable)
		snprintf(lr_label, sizeof lr_label, "Download %.48s, %ld MB", r->name, (r->size + 1048575) / 1048576);
	else
		snprintf(lr_label, sizeof lr_label, "Not available");
	addkey(&x, y, U * 2, PANEL_BOT, K_LANGBACK, 0, "Back", NULL);
	addkey(&x, y, U * 8, PANEL_BOT, K_LANGACT, 0, lr_label, NULL);
}

static void
build(void)
{
	memset(key_rel, 0, sizeof key_rel);
	static const char *rows[3][3] = {
		{"qwertyuiop", "asdfghjkl", "zxcvbnm"},
		{"1234567890", "@#$%&-+()", "*\"':;!?"},
		{"~`|\\^_={}/", "[]<>€£°§¶", "•…«»¿¡×"},
	};
	static const struct { const char *l; int code; } nav[] = {
		{"Home", KEY_HOME}, {"End", KEY_END}, {"PgUp", KEY_PAGEUP}, {"PgDn", KEY_PAGEDOWN},
		{NULL, KEY_LEFT}, {NULL, KEY_UP}, {NULL, KEY_DOWN}, {NULL, KEY_RIGHT},
	};
	static const struct { const char *l; int code; } fns[] = {
		{"F1", KEY_F1}, {"F2", KEY_F2}, {"F3", KEY_F3}, {"F4", KEY_F4}, {"F5", KEY_F5}, {"F6", KEY_F6},
		{"F7", KEY_F7}, {"F8", KEY_F8}, {"F9", KEY_F9}, {"F10", KEY_F10}, {"F11", KEY_F11}, {"F12", KEY_F12},
	};
	float y = 0, x, h = rowh(), wf = (float)width, ox = 0, blockw = wf;
	const char *const *r = rows[page];
	int onehand = cfg.one_handed && !laptop && !panel && !landscape;
	int search = (panel == PANEL_EMOJI && em_search) || panel == PANEL_TRANS, numrow = cfg.number_row && !laptop && !search && page == PAGE_ABC;
	int fnkeys = fnon() && !laptop;

	/* the keys under a finger may be gone: only what was already fired or copied survives */
	for (size_t i = 0; i < LEN(slots); i++)
		if (slots[i].used)
			slots[i].key = -1;
	nkeys = 0;
	nkeytext = 0;
	nsug = 0;
	if (onehand) {
		blockw = wf * 0.84f;
		ox = cfg.one_handed == 2 ? wf - blockw : 0;
	}
	U = blockw / 10;
	if (panel == PANEL_EMOJI && !search) {
		buildemoji(wf);
		dumpkeys();
		return;
	}
	if (panel == PANEL_CLIP) {
		buildclip(wf);
		dumpkeys();
		return;
	}
	if (panel == PANEL_LANGS) {
		buildlangs(wf);
		dumpkeys();
		return;
	}
	/* the symbol pages have digits of their own, so their rows take the number row's room */
	if (cfg.number_row && !laptop && !search && page != PAGE_ABC)
		h = h * 5 / 4;
	if (panel == PANEL_TRANS) {
		x = 0;
		addkey(&x, 0, U * 3.2f, TAB_H, K_TRFROM, 0, tr_from[0] ? trname(tr_from) : "English", NULL);
		addkey(&x, 0, U, TAB_H, K_TRSWAP, 0, NULL, "swap");
		addkey(&x, 0, U * 3.2f, TAB_H, K_TRTO, 0, tr_to[0] ? trname(tr_to) : "-", NULL);
		addkey(&x, 0, U * 1.3f, TAB_H, K_LANGS, 0, "Add", NULL);
		addkey(&x, 0, U * 1.3f, TAB_H, K_ABC, 0, "abc", NULL);
		y = TRANS_TOP;
	} else if (search) {
		x = wf - U * 1.5f;
		addkey(&x, 0, U * 1.5f, QUERY_H, K_SEARCH, 1, "Done", NULL);
		y = QUERY_H + STRIP_H;
	} else if (!laptop) {
		if (!landscape) {
			float barw = U * 1.1f;

			x = ox;
			addkey(&x, 0, barw, SUG_H, K_MODS, 0, NULL, "mods");
			if (!secret) {
				addkey(&x, 0, barw, SUG_H, K_TRANSLATE, 0, NULL, "translate");
				x = ox + blockw - barw * 3;
				addkey(&x, 0, barw, SUG_H, K_CLIP, 0, NULL, "clip");
				addkey(&x, 0, barw, SUG_H, K_HIDE, 0, NULL, "hide");
				addkey(&x, 0, barw, SUG_H, K_GEAR, 0, NULL, "gear");
				nsug = cfg.predict ? 3 : 0;
				sug_w = (blockw - barw * 5) / 3;
				sug_x = ox + barw * 2;
			} else {
				/* the lock screen's only way to put it down */
				x = ox + blockw - barw;
				addkey(&x, 0, barw, SUG_H, K_HIDE, 0, NULL, "hide");
			}
			y = SUG_H;
		}
		if (modrow) {
			static const struct { const char *l; int kind; unsigned code; } m[] = {
				{"Ctrl", K_MOD, CTRL_MASK}, {"Super", K_MOD, SUPER_MASK}, {"Alt", K_MOD, ALT_MASK}, {"Fn", K_MOD, FN_MASK},
				{"Esc", K_CODE, KEY_ESC}, {"Tab", K_CODE, KEY_TAB},
			};
			static const struct { int code, fncode; const char *fnl; } ar[] = {
				{KEY_LEFT, KEY_HOME, "Home"}, {KEY_DOWN, KEY_PAGEDOWN, "PgDn"}, {KEY_UP, KEY_PAGEUP, "PgUp"}, {KEY_RIGHT, KEY_END, "End"},
			};

			x = ox;
			for (size_t i = 0; i < LEN(m); i++)
				addkey(&x, y, U, MOD_H, m[i].kind, (int)m[i].code, m[i].l, NULL);
			for (size_t i = 0; i < LEN(ar); i++)
				addkey(&x, y, U, MOD_H, K_CODE, fnon() ? ar[i].fncode : ar[i].code, fnon() ? ar[i].fnl : NULL, NULL);
			y += MOD_H;
		}
		if (numrow) {
			x = ox;
			letters("1234567890", &x, y, h);
			y += h;
		}
	} else {
		float w = wf / 7;

		x = 0;
		addkey(&x, y, w, h, K_CODE, KEY_ESC, "Esc", NULL);
		addkey(&x, y, w, h, K_CODE, KEY_TAB, "Tab", NULL);
		addkey(&x, y, w, h, K_MOD, CTRL_MASK, "Ctrl", NULL);
		addkey(&x, y, w, h, K_MOD, ALT_MASK, "Alt", NULL);
		addkey(&x, y, w, h, K_MOD, SUPER_MASK, "Super", NULL);
		addkey(&x, y, w, h, K_CODE, KEY_DELETE, "Del", NULL);
		addkey(&x, y, w, h, K_MOD, FN_MASK, "Fn", NULL);
		y += h;
		if (fnon()) {
			for (int row = 0; row < 2; row++, y += h) {
				x = 0;
				for (int i = 0; i < 6; i++)
					addkey(&x, y, wf / 6, h, K_CODE, fns[row * 6 + i].code, fns[row * 6 + i].l, NULL);
			}
		} else {
			x = 0;
			for (size_t i = 0; i < LEN(nav); i++)
				addkey(&x, y, wf / 8, h, K_CODE, nav[i].code, nav[i].l, NULL);
			y += h;
			x = 0;
			letters("1234567890", &x, y, h);
			y += h;
		}
	}
	if (fnkeys) {
		for (int row = 0; row < 2; row++, y += h) {
			x = ox;
			for (int i = 0; i < 6; i++)
				addkey(&x, y, blockw / 6, h, K_CODE, fns[row * 6 + i].code, fns[row * 6 + i].l, NULL);
		}
	} else {
		x = ox;
		letters(r[0], &x, y, h);
		y += h;
		x = ox + U / 2;
		letters(r[1], &x, y, h);
		y += h;
	}
	x = ox;
	if (page == PAGE_ABC)
		addkey(&x, y, U * 1.5f, h, K_SHIFT, 0, NULL, NULL);
	else
		addkey(&x, y, U * 1.5f, h, K_PAGE, page == PAGE_SYM ? PAGE_SYM2 : PAGE_SYM, page == PAGE_SYM ? "=\\<" : "?123", NULL);
	letters(r[2], &x, y, h);
	addkey(&x, y, U * 1.5f, h, K_BKSP, 0, NULL, NULL);
	y += h;
	x = ox;
	addkey(&x, y, U * 1.5f, h, K_PAGE, page == PAGE_ABC ? PAGE_SYM : PAGE_ABC, page == PAGE_ABC ? "?123" : "abc", NULL);
	/* the laptop layout has no panels, so this is its way back; the way in is in the clipboard panel */
	if (laptop && !search)
		addkey(&x, y, U, h, K_LAPTOP, 0, NULL, NULL);
	else if (!search && !secret)
		addkey(&x, y, U, h, K_EMOJI, 0, NULL, "emoji");
	/* turned there is no bar, so its button comes down here */
	if (landscape && !laptop && !search)
		addkey(&x, y, U, h, K_MODS, 0, NULL, "mods");
	/* space takes whatever the row leaves after comma, full stop and enter */
	float spacew = blockw - (x - ox) - U * 3.5f;
	addkey(&x, y, U, h, K_CHAR, 0, NULL, ",");
	addkey(&x, y, spacew, h, K_SPACE, 0, NULL, " ");
	addkey(&x, y, U, h, K_CHAR, 0, NULL, ".");
	addkey(&x, y, U * 1.5f, h, K_ENTER, 0, NULL, NULL);
	if (onehand) {
		float top = SUG_H + (modrow ? MOD_H : 0), sh = ((float)height - top) / 2;

		x = cfg.one_handed == 1 ? blockw : 0;
		addkey(&x, top, wf - blockw, sh, K_SWAP, 0, cfg.one_handed == 1 ? ">" : "<", NULL);
		x = cfg.one_handed == 1 ? blockw : 0;
		addkey(&x, top + sh, wf - blockw, sh, K_ONEHAND, 0, "x", NULL);
	}
	dumpkeys();
}

static void
savelayout(void)
{
	char p[600];
	FILE *f;

	snprintf(p, sizeof p, "%s/layout", state_dir);
	if ((f = fopen(p, "w"))) {
		fputs(laptop ? "laptop\n" : "normal\n", f);
		fclose(f);
	}
}

static void
loadlayout(void)
{
	char p[600], s[16] = "";
	FILE *f;

	snprintf(p, sizeof p, "%s/layout", state_dir);
	if ((f = fopen(p, "r"))) {
		if (fgets(s, sizeof s, f))
			laptop = !strncmp(s, "laptop", 6);
		fclose(f);
	}
}

/* --- sending text --- */
static const char *keymap_text =
	"xkb_keymap {\n"
	"xkb_keycodes { include \"evdev+aliases(qwerty)\" };\n"
	"xkb_types { include \"complete\" };\n"
	"xkb_compat { include \"complete\" };\n"
	"xkb_symbols { include \"pc+us+inet(evdev)\" };\n"
	"};\n";

static void
setupvk(void)
{
	size_t len = strlen(keymap_text) + 1;
	int fd = memfd_create("phonekbd-keymap", MFD_CLOEXEC);

	vk = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(vk_mgr, seat);
	if (fd >= 0 && write(fd, keymap_text, len) == (ssize_t)len)
		zwp_virtual_keyboard_v1_keymap(vk, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, (uint32_t)len);
	if (fd >= 0)
		close(fd);
}

/* --- Waydroid: Android has no text-input, a small IME (android/) takes text over a unix socket in its data dir --- */
static struct zwlr_foreign_toplevel_manager_v1 *ftl_mgr;
static struct zwlr_foreign_toplevel_handle_v1 *focus_top;
static int focus_droid, br_fd = -1, br_ino = -1;
static char br_dir[512], br_in[256];
static size_t br_len;

static int
todroid(void)
{
	return br_fd >= 0 && focus_droid && !active;
}

static void
brclose(void)
{
	if (br_fd >= 0)
		close(br_fd);
	br_fd = -1;
	br_len = 0;
}

static void brsend(char op, const char *s);

/* Waydroid resizes its display on a resize and apps restart their input: overlay it and let Android inset the app instead */
static int32_t
zone(void)
{
	return todroid() ? 0 : (int32_t)wantheight() + BAR_ROOM;
}

/* logical height and width, Android scales by its own display width; 0 lets its IME window go */
static void
droidh(void)
{
	char a[32];
	int on = todroid() && shown;

	/* shown but not configured yet: the configure sends it */
	if (br_fd < 0 || (on && !height))
		return;
	snprintf(a, sizeof a, "%d %d", on ? height + BAR_ROOM : 0, width);
	brsend('h', a);
}

static void
brsend(char op, const char *s)
{
	char buf[6400];
	size_t n = 0;

	buf[n++] = op;
	for (; *s && n < sizeof buf - 3; s++) {
		if (*s == '\n' || *s == '\\')
			buf[n++] = '\\';
		buf[n++] = *s == '\n' ? 'n' : *s;
	}
	buf[n++] = '\n';
	if (send(br_fd, buf, n, MSG_DONTWAIT | MSG_NOSIGNAL) != (ssize_t)n)
		brclose();
}

static void
sendkey(int code, unsigned mask)
{
	uint32_t t = (uint32_t)now_ms();

	if (todroid()) {
		char a[32];

		snprintf(a, sizeof a, "%d %u", code, mask & 0xff);
		brsend('k', a);
		return;
	}

	/* held only around this one key: nothing the keyboard does later can leave a modifier stuck in the seat */
	zwp_virtual_keyboard_v1_modifiers(vk, mask & 0xff, 0, 0, 0);
	zwp_virtual_keyboard_v1_key(vk, t, (uint32_t)code, WL_KEYBOARD_KEY_STATE_PRESSED);
	zwp_virtual_keyboard_v1_key(vk, t, (uint32_t)code, WL_KEYBOARD_KEY_STATE_RELEASED);
	zwp_virtual_keyboard_v1_modifiers(vk, 0, 0, 0, 0);
}

static int
asciikey(char c, unsigned *mask)
{
	static const struct { char c; int code, sh; } m[] = {
		{'-', 12, 0}, {'=', 13, 0}, {'_', 12, 1}, {'+', 13, 1}, {'[', 26, 0}, {'{', 26, 1}, {']', 27, 0}, {'}', 27, 1},
		{';', 39, 0}, {':', 39, 1}, {'\'', 40, 0}, {'"', 40, 1}, {'`', 41, 0}, {'~', 41, 1}, {'\\', 43, 0}, {'|', 43, 1},
		{',', 51, 0}, {'<', 51, 1}, {'.', 52, 0}, {'>', 52, 1}, {'/', 53, 0}, {'?', 53, 1},
		{'!', 2, 1}, {'@', 3, 1}, {'#', 4, 1}, {'$', 5, 1}, {'%', 6, 1}, {'^', 7, 1}, {'&', 8, 1}, {'*', 9, 1},
		{'(', 10, 1}, {')', 11, 1}, {' ', 57, 0},
	};
	static const struct { const char *row; int start; } rows[] = {{"qwertyuiop", 16}, {"asdfghjkl", 30}, {"zxcvbnm", 44}};
	char low = (char)tolower((unsigned char)c);

	if (c >= 'A' && c <= 'Z')
		*mask |= SHIFT_MASK;
	for (size_t i = 0; i < LEN(rows); i++) {
		const char *at = strchr(rows[i].row, low);

		if (at && low)
			return rows[i].start + (int)(at - rows[i].row);
	}
	if (c >= '1' && c <= '9')
		return c - '1' + 2;
	if (c == '0')
		return 11;
	for (size_t i = 0; i < LEN(m); i++)
		if (m[i].c == c) {
			if (m[i].sh)
				*mask |= SHIFT_MASK;
			return m[i].code;
		}
	return 0;
}

static void
commit_text(const char *s)
{
	char part[3001];

	if (!im)
		return;
	if (!active && !todroid()) {
		/* shortcut: without a field only keys on the US map arrive and other characters are dropped, upgrade with a temporary keymap */
		for (; *s; s++) {
			unsigned mask = 0;
			int code = asciikey(*s, &mask);

			if (code)
				sendkey(code, mask);
		}
		return;
	}
	/* one protocol message holds about 4 KB, so a long paste goes in pieces, cut between characters */
	while (*s) {
		size_t n = strlen(s);

		if (n > 3000) {
			n = 3000;
			while (n && (s[n] & 0xc0) == 0x80)
				n--;
		}
		memcpy(part, s, n);
		part[n] = 0;
		s += n;
		if (todroid()) {
			brsend('t', part);
			continue;
		}
		zwp_input_method_v2_commit_string(im, part);
		zwp_input_method_v2_commit(im, done_serial);
	}
}

/* one atomic step: backspace keys would arrive after the text in toolkits that queue key events */
static void
replace_text(size_t delete_bytes, const char *s)
{
	if (todroid()) {
		char a[3100];

		snprintf(a, sizeof a, "%zu %s", delete_bytes, s);
		brsend('r', a);
		return;
	}
	if (!im)
		return;
	if (delete_bytes)
		zwp_input_method_v2_delete_surrounding_text(im, (uint32_t)delete_bytes, 0);
	if (*s)
		zwp_input_method_v2_commit_string(im, s);
	zwp_input_method_v2_commit(im, done_serial);
}

static void
clearlatched(void)
{
	int rebuild = (mods_latched & FN_MASK) != 0;

	if (mods_latched) {
		mods_latched = 0;
		dirty = 1;
	}
	if (shift_state == 1) {
		shift_state = 0;
		cap_auto = 0;
		dirty = 1;
	}
	if (rebuild)
		build();
}

/* every modifier, latched or locked: the row closed or the keyboard went away */
static void
clearmods(void)
{
	int rebuild = fnon() != 0;

	mods_latched = mods_locked = 0;
	held_mods = 0;
	shift_state = 0;
	cap_auto = 0;
	dirty = 1;
	if (vk)
		zwp_virtual_keyboard_v1_modifiers(vk, 0, 0, 0, 0);
	if (rebuild && width)
		build();
}

static unsigned
curmods(void)
{
	return mods_latched | mods_locked | held_mods | (shift_state ? SHIFT_MASK : 0);
}

/* a real key press whenever one exists: the laptop layout always, the normal one under a modifier */
static void
typetext(const char *s)
{
	unsigned mask = curmods();
	int code;

	if ((laptop || hardmods()) && !s[1] && (code = asciikey(s[0], &mask))) {
		sendkey(code, mask);
		clearlatched();
		return;
	}
	commit_text(s);
	clearlatched();
}

/* --- words --- */
static int
isword(const char *t)
{
	char tmp[16];

	if (!strcmp(t, "'") || !strcmp(t, "-"))
		return word[0] != 0;
	return fold_word(t, tmp, sizeof tmp) > 0;
}

static void
capfirst(char *w)
{
	char first[8], rest[WORD_MAX];
	const char *q = w, *start = w;

	utf8_next(&q);
	snprintf(first, sizeof first, "%.*s", (int)(q - start), start);
	upper(first, first, sizeof first);
	snprintf(rest, sizeof rest, "%s", q);
	snprintf(w, WORD_MAX, "%s%s", first, rest);
}

/* best in the centre, second on the left, third on the right */
static void
putsug(const char *w)
{
	static const int order[3] = {1, 0, 2};

	for (int i = 0; i < 3; i++)
		if (!sug[order[i]][0]) {
			snprintf(sug[order[i]], WORD_MAX, "%s", w);
			return;
		}
}

static void
updatesug(void)
{
	char out[4][WORD_MAX], fixed[WORD_MAX];
	int n = 0, wantcap = plain && cfg.autocap && (hint & HINT_AUTOCAP) && !word[0] && !s_pending && !strcmp(prev, "<s>");

	if (wantcap && !shift_state) {
		shift_state = 1;
		cap_auto = 1;
	} else if (!wantcap && cap_auto && shift_state == 1) {
		shift_state = 0;
		cap_auto = 0;
	}
	memset(sug, 0, sizeof sug);
	sug_fix = -1;
	dirty = 1;
	if (!plain || !cfg.predict)
		return;
	if (undo_from[0]) {
		putsug(undo_from);
		return;
	}
	if (!word[0]) {
		if (prev[0] && !s_pending) {
			n = words_next(prev, out, 3);
			for (int i = 0; i < n; i++) {
				if (shift_state)
					capfirst(out[i]);
				putsug(out[i]);
			}
		}
		return;
	}
	words_context(prev);
	n = words_suggest(word, out, 4);
	if (cfg.autocorrect && words_correct(word, fixed)) {
		sug_fix = 1;
		putsug(fixed);
	} else {
		putsug(n ? out[0] : word);
	}
	/* the exact word stays reachable on the left */
	if (strcmp(sug[1], word))
		snprintf(sug[0], WORD_MAX, "%s", word);
	for (int i = 0; i < n; i++)
		if (strcmp(out[i], sug[0]) && strcmp(out[i], sug[1]) && strcmp(out[i], sug[2]))
			putsug(out[i]);
}

static void
clearword(void)
{
	word[0] = 0;
	undo_from[0] = 0;
	swiped[0] = 0;
	auto_space = 0;
	prev[0] = 0;
	s_pending = 0;
	updatesug();
}

/* a sentence only starts once its full stop has its space, so "e.g" stays lower case */
static void
notesep(const char *sep)
{
	if (!*sep)
		return;
	if (strchr(".!?", sep[0]) || !strcmp(sep, "…")) {
		s_pending = 1;
	} else if (sep[0] == ' ') {
		if (s_pending)
			snprintf(prev, sizeof prev, "<s>");
		s_pending = 0;
	} else if (sep[0] != ',') {
		prev[0] = 0;
		s_pending = 0;
	}
}

/* a word ends here: this is the only moment autocorrect acts */
static void
endword(const char *sep)
{
	char fixed[WORD_MAX], done[WORD_MAX] = "";

	undo_from[0] = 0;
	if (word[0] && plain) {
		if (cfg.autocorrect && words_correct(word, fixed)) {
			replace_text(strlen(word), fixed);
			snprintf(undo_from, WORD_MAX, "%s", word);
			snprintf(undo_to, WORD_MAX, "%s", fixed);
			undo_extra = (int)strlen(sep);
			snprintf(done, sizeof done, "%s", fixed);
		} else {
			if (cfg.learn)
				words_learn(word, 1);
			snprintf(done, sizeof done, "%s", word);
		}
	}
	commit_text(sep);
	if (done[0]) {
		words_note(done);
		/* sentence starts are not learned: their capitals would teach the wrong word */
		if (cfg.learn && cfg.predict && prev[0] && strcmp(prev, "<s>"))
			words_pair(prev, done);
		snprintf(prev, sizeof prev, "%s", done);
	}
	notesep(sep);
	word[0] = 0;
	swiped[0] = 0;
	updatesug();
}

static void
typechar(const char *t)
{
	char up[8];
	const char *s = t;

	if (shift_state && !laptop) {
		upper(t, up, sizeof up);
		s = up;
	}
	if (panel == PANEL_TRANS) {
		size_t n = strlen(tr_in);

		if (n + strlen(s) < sizeof tr_in) {
			strcpy(tr_in + n, s);
			trchanged();
		}
		clearlatched();
		dirty = 1;
		return;
	}
	if (panel == PANEL_EMOJI && em_search) {
		size_t n = strlen(em_query);

		if (n + strlen(s) < sizeof em_query) {
			strcpy(em_query + n, s);
			em_nfound = emoji_search(em_query, em_found, (int)LEN(em_found));
		}
		clearlatched();
		dirty = 1;
		return;
	}
	if (laptop) {
		typetext(s);
		return;
	}
	if (hardmods()) {
		typetext(s);
		clearword();
		return;
	}
	/* punctuation after a swiped word takes the place of its automatic space */
	if (auto_space && strchr(".,?!;:", s[0]) && !s[1]) {
		char out[4];

		snprintf(out, sizeof out, "%s ", s);
		replace_text(1, out);
		clearword();
		clearlatched();
		return;
	}
	auto_space = 0;
	if (isword(t) && plain) {
		if (swiped[0])
			swiped[0] = 0;
		undo_from[0] = 0;
		if (strlen(word) + strlen(s) < WORD_MAX - 1)
			strcat(word, s);
		commit_text(s);
		clearlatched();
		updatesug();
		return;
	}
	/* a digit after letters is a code or a name, never a typo to correct */
	if (plain && !(*t >= '0' && *t <= '9'))
		endword(s);
	else {
		if (plain)
			clearword();
		commit_text(s);
	}
	clearlatched();
}

static void
backspace(void)
{
	if (panel == PANEL_TRANS) {
		int n = (int)strlen(tr_in);

		while (n > 0 && (tr_in[n - 1] & 0xc0) == 0x80)
			n--;
		tr_in[n > 0 ? n - 1 : 0] = 0;
		trchanged();
		dirty = 1;
		return;
	}
	if (panel == PANEL_EMOJI && em_search) {
		int n = (int)strlen(em_query);

		while (n > 0 && (em_query[n - 1] & 0xc0) == 0x80)
			n--;
		em_query[n > 0 ? n - 1 : 0] = 0;
		em_nfound = emoji_search(em_query, em_found, (int)LEN(em_found));
		dirty = 1;
		return;
	}
	if (hardmods()) {
		sendkey(KEY_BACKSPACE, curmods());
		clearlatched();
		clearword();
		return;
	}
	if (undo_from[0]) {
		/* undoes the correction and teaches the word */
		char orig[WORD_MAX];

		snprintf(orig, sizeof orig, "%s", undo_from);
		replace_text(strlen(undo_to) + (size_t)undo_extra, orig);
		if (cfg.learn)
			words_learn(orig, 2);
		snprintf(word, sizeof word, "%s", orig);
		undo_from[0] = 0;
		updatesug();
		return;
	}
	sendkey(KEY_BACKSPACE, curmods());
	clearlatched();
	auto_space = 0;
	swiped[0] = 0;
	if (word[0]) {
		int n = (int)strlen(word);

		while (n > 0 && (word[n - 1] & 0xc0) == 0x80)
			n--;
		word[n > 0 ? n - 1 : 0] = 0;
	}
	updatesug();
}

static void
picksug(int i)
{
	char text_[WORD_MAX + 2];

	if (i < 0 || i >= 3 || !sug[i][0])
		return;
	if (undo_from[0]) {
		backspace();
		return;
	}
	snprintf(text_, sizeof text_, "%s ", sug[i]);
	replace_text(swiped[0] ? strlen(swiped) + 1 : strlen(word), text_);
	if (cfg.learn) {
		words_learn(sug[i], 2);
		if (prev[0] && strcmp(prev, "<s>") && !swiped[0])
			words_pair(prev, sug[i]);
	}
	snprintf(prev, sizeof prev, "%s", sug[i]);
	s_pending = 0;
	word[0] = 0;
	swiped[0] = 0;
	auto_space = 1;
	clearlatched();
	updatesug();
}

static void
finishswipe(void)
{
	float p[300][2];
	char out[4][WORD_MAX], text_[WORD_MAX + 3];
	int n;

	for (int i = 0; i < npath; i++) {
		p[i][0] = path[i][0] / U;
		p[i][1] = path[i][1] / U;
	}
	n = words_swipe((const float (*)[2])p, npath, out, 4);
	npath = 0;
	dirty = 1;
	if (n <= 0)
		return;
	if (shift_state)
		capfirst(out[0]);
	/* a word still being typed ends before the swiped one */
	if (word[0]) {
		endword(" ");
	}
	snprintf(text_, sizeof text_, "%s ", out[0]);
	commit_text(text_);
	snprintf(swiped, sizeof swiped, "%s", out[0]);
	snprintf(prev, sizeof prev, "%s", out[0]);
	s_pending = 0;
	auto_space = 1;
	undo_from[0] = 0;
	word[0] = 0;
	clearlatched();
	memset(sug, 0, sizeof sug);
	sug_fix = -1;
	for (int i = 1; i < n && cfg.predict; i++)
		putsug(out[i]);
}

/* --- panels: emoji and clipboard data exist only while open --- */
static int
tilecount(void)
{
	return em_kind == EMOJI_NONE ? 0 : em_group < 0 ? emoji_recent_count() : em_start[em_group + 1] - em_start[em_group];
}

static const char *
tileseq(int i)
{
	return em_group < 0 ? emoji_recent(i) : emoji_at(em_start[em_group] + i)->seq;
}

static const Emoji *
tilemoji(const char *seq)
{
	for (int i = 0; i < emoji_count(); i++)
		if (!strcmp(emoji_at(i)->seq, seq))
			return emoji_at(i);
	return NULL;
}

static void
datapath(const char *name, char *out, size_t size)
{
	const char *d = getenv("PHONEKBD_DATA");

	snprintf(out, size, "%s/%s", d ? d : DATADIR, name);
}

/* a downloaded language's merged data, else what the keyboard ships */
static void
wordspath(const char *name, char *out, size_t size)
{
	const char *xdg = getenv("XDG_DATA_HOME"), *home = getenv("HOME");

	if (xdg && *xdg)
		snprintf(out, size, "%s/phonekbd/%s", xdg, name);
	else
		snprintf(out, size, "%s/.local/share/phonekbd/%s", home ? home : "", name);
	if (access(out, R_OK))
		datapath(name, out, size);
}

/* lines of base, lower, upper; the data was checked when it was merged, this only stays in bounds */
static void
readletters(const char *name, int active)
{
	char p[600], line[64], low[8], up[8], base[2];
	FILE *f;

	wordspath(name, p, sizeof p);
	if (!(f = fopen(p, "r")))
		return;
	while (fgets(line, sizeof line, f)) {
		int i;

		if (sscanf(line, "%1[a-z]\t%7[^\t\n]\t%7[^\t\n]", base, low, up) != 3)
			continue;
		for (i = 0; i < nlets && strcmp(lets[i].low, low); i++)
			;
		if (i == nlets && nlets == LETTERS_MAX)
			continue;
		if (i == nlets)
			nlets++;
		lets[i].base = base[0];
		snprintf(lets[i].low, sizeof lets[i].low, "%s", low);
		snprintf(lets[i].up, sizeof lets[i].up, "%s", up);
		lets[i].active |= active;
	}
	fclose(f);
}

static void
loadletters(void)
{
	nlets = 0;
	memset(lets, 0, sizeof lets);
	/* password-letters outlives a removed language: a password may still hold them */
	readletters("password-letters", 0);
	readletters("letters", 1);
}

/* none of it in memory when both features are off; learned files stay untouched then too */
/* the key, or English and every language with a word list */
static void
wordslangs(void)
{
	char list[128], dir[600], p[900];
	struct dirent *d;
	DIR *dp;

	if (cfg.langs_set) {
		words_langs(cfg.langs);
		return;
	}
	snprintf(list, sizeof list, "en");
	wordspath("langs", dir, sizeof dir);
	if ((dp = opendir(dir))) {
		while ((d = readdir(dp))) {
			snprintf(p, sizeof p, "%s/%.200s/words.tsv", dir, d->d_name);
			if (d->d_name[0] != '.' && !access(p, R_OK) && strlen(list) + strlen(d->d_name) + 2 < sizeof list)
				strcat(strcat(list, " "), d->d_name);
		}
		closedir(dp);
	}
	words_langs(list);
}

static void
openwords(void)
{
	char dict[600], learned[600];

	if (!cfg.predict && !cfg.autocorrect) {
		words_close();
		return;
	}
	wordspath("words.tsv", dict, sizeof dict);
	snprintf(learned, sizeof learned, "%s/learned.tsv", state_dir);
	words_open(dict, learned);
	if (cfg.predict) {
		wordspath("bigrams.tsv", dict, sizeof dict);
		snprintf(learned, sizeof learned, "%s/bigrams.tsv", state_dir);
		words_bigrams_open(dict, learned);
	}
}

/* a process of its own, in its own group so a kill reaches what it started */
static pid_t
spawnpipe(char *const argv[], int *to, int *from)
{
	extern char **environ;
	posix_spawn_file_actions_t fa;
	posix_spawnattr_t at;
	sigset_t def;
	int in[2] = {-1, -1}, out[2];
	pid_t pid = 0;

	if (pipe2(out, O_CLOEXEC))
		return 0;
	if (to && pipe2(in, O_CLOEXEC)) {
		close(out[0]);
		close(out[1]);
		return 0;
	}
	posix_spawn_file_actions_init(&fa);
	if (to)
		posix_spawn_file_actions_adddup2(&fa, in[0], 0);
	else
		posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
	posix_spawn_file_actions_adddup2(&fa, out[1], 1);
	posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
	posix_spawnattr_init(&at);
	sigemptyset(&def);
	sigaddset(&def, SIGPIPE);
	posix_spawnattr_setsigdefault(&at, &def);
	posix_spawnattr_setpgroup(&at, 0);
	posix_spawnattr_setflags(&at, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF);
	if (posix_spawnp(&pid, argv[0], &fa, &at, argv, environ))
		pid = 0;
	posix_spawn_file_actions_destroy(&fa);
	posix_spawnattr_destroy(&at);
	close(out[1]);
	if (to)
		close(in[0]);
	if (!pid) {
		close(out[0]);
		if (to)
			close(in[1]);
		return 0;
	}
	fcntl(out[0], F_SETFL, O_NONBLOCK);
	*from = out[0];
	if (to)
		*to = in[1];
	return pid;
}

static void
trkill(void)
{
	if (tr_pid > 0) {
		kill(-tr_pid, SIGKILL);
		waitpid(tr_pid, NULL, 0);
	}
	tr_pid = 0;
	if (tr_fd >= 0)
		close(tr_fd);
	tr_fd = -1;
}

/* the text changed: what was being translated is stale, and a new process follows a pause in typing */
static void
trchanged(void)
{
	trkill();
	tr_out[0] = 0;
	tr_outn = 0;
	tr_msg[0] = 0;
	tr_pending = tr_in[0] != 0;
	arm(tr_timer, tr_pending ? 600 : 0, 0);
	dirty = 1;
}

/* one process for one request: it holds a model only while it answers, then it is gone */
static void
trstart(void)
{
	char *argv[] = {"phonetext-translate", tr_from, tr_to, NULL};
	int to;

	tr_pending = 0;
	dirty = 1;
	if (!tr_in[0] || !tr_from[0] || !tr_to[0])
		return;
	if (!(tr_pid = spawnpipe(argv, &to, &tr_fd))) {
		snprintf(tr_msg, sizeof tr_msg, "The translator is not installed");
		return;
	}
	/* under the size of a pipe's buffer, so this never blocks */
	if (write(to, tr_in, strlen(tr_in)) < 0 || write(to, "\n", 1) < 0)
		tr_msg[0] = 0;
	close(to);
}

static void
trread(void)
{
	char tmp[512];
	ssize_t n;
	int st = 0;

	while ((n = read(tr_fd, tmp, sizeof tmp)) > 0) {
		size_t c = MIN((size_t)n, sizeof tr_out - 1 - tr_outn);

		memcpy(tr_out + tr_outn, tmp, c);
		tr_outn += c;
		tr_out[tr_outn] = 0;
	}
	explicit_bzero(tmp, sizeof tmp);
	if (n < 0 && errno == EAGAIN)
		return;
	close(tr_fd);
	tr_fd = -1;
	waitpid(tr_pid, &st, 0);
	tr_pid = 0;
	while (tr_outn && strchr(" \n", tr_out[tr_outn - 1]))
		tr_out[--tr_outn] = 0;
	for (char *c = tr_out; *c; c++)
		if (*c == '\n')
			*c = ' ';
	if (WIFEXITED(st) && WEXITSTATUS(st) == 127)
		snprintf(tr_msg, sizeof tr_msg, "The translator is not installed");
	else if (!tr_out[0])
		snprintf(tr_msg, sizeof tr_msg, "No translation");
	dirty = 1;
}

static void
trmark(const char *code, size_t n, int from)
{
	int i;

	if (!n || n >= sizeof tr_langs[0].code)
		return;
	for (i = 0; i < ntr && (strncmp(tr_langs[i].code, code, n) || tr_langs[i].code[n]); i++)
		;
	if (i == ntr) {
		if (ntr == (int)LEN(tr_langs))
			return;
		memcpy(tr_langs[i].code, code, n);
		tr_langs[i].code[n] = 0;
		tr_langs[i].from = tr_langs[i].to = 0;
		ntr++;
	}
	*(from ? &tr_langs[i].from : &tr_langs[i].to) = 1;
}

/* what is installed decides the choices, and every pair goes through English when it must */
static void
trscan(void)
{
	char dir[512], p[800];
	const char *env = getenv("PHONETEXT_MODELS"), *xdg = getenv("XDG_DATA_HOME"), *home = getenv("HOME");
	struct dirent *e;
	DIR *d;
	int ok, have;

	if (env && *env)
		snprintf(dir, sizeof dir, "%s", env);
	else if (xdg && *xdg)
		snprintf(dir, sizeof dir, "%s/phonegluewc/translate", xdg);
	else
		snprintf(dir, sizeof dir, "%s/.local/share/phonegluewc/translate", home ? home : "");
	ntr = 0;
	if ((d = opendir(dir))) {
		while ((e = readdir(d))) {
			size_t n = strlen(e->d_name);

			if (!strcmp(e->d_name, "model.enro.intgemm.alphas.bin")) {
				trmark("en", 2, 1);
				trmark("ro", 2, 0);
			} else if (!strcmp(e->d_name, "model.roen.intgemm.alphas.bin")) {
				trmark("ro", 2, 1);
				trmark("en", 2, 0);
			}
			if (n < 5)
				continue;
			snprintf(p, sizeof p, "%s/%s/model", dir, e->d_name);
			if (access(p, R_OK))
				continue;
			if (!strncmp(e->d_name, "en-", 3)) {
				trmark("en", 2, 1);
				trmark(e->d_name + 3, n - 3, 0);
			} else if (!strcmp(e->d_name + n - 3, "-en")) {
				trmark(e->d_name, n - 3, 1);
				trmark("en", 2, 0);
			}
		}
		closedir(d);
	}
	/* keep a saved choice while it is still installed, else settle on one that works */
	for (ok = 0, have = 0; have < ntr; have++)
		if (!strcmp(tr_langs[have].code, tr_from) && tr_langs[have].from)
			ok |= 1;
		else if (!strcmp(tr_langs[have].code, tr_to) && tr_langs[have].to)
			ok |= 2;
	if (ok != 3 || !strcmp(tr_from, tr_to)) {
		tr_from[0] = tr_to[0] = 0;
		for (int i = 0; i < ntr && !tr_to[0]; i++)
			if (tr_langs[i].to && strcmp(tr_langs[i].code, "en"))
				snprintf(tr_to, sizeof tr_to, "%s", tr_langs[i].code);
		for (int i = 0; i < ntr && !tr_from[0]; i++)
			if (tr_langs[i].from && strcmp(tr_langs[i].code, tr_to))
				snprintf(tr_from, sizeof tr_from, "%s", tr_langs[i].code);
		/* the only language left goes one way, to English */
		if (!tr_to[0] && tr_from[0])
			for (int i = 0; i < ntr && !tr_to[0]; i++)
				if (tr_langs[i].to && strcmp(tr_langs[i].code, tr_from))
					snprintf(tr_to, sizeof tr_to, "%s", tr_langs[i].code);
		if (!tr_to[0])
			tr_from[0] = 0;
	}
}

static void
trcycle(char *sel, const char *other, int src)
{
	int cur = -1;

	for (int i = 0; i < ntr; i++)
		if (!strcmp(tr_langs[i].code, sel))
			cur = i;
	for (int n = 1; n <= ntr; n++) {
		int j = (cur + n + ntr) % ntr;

		if ((src ? tr_langs[j].from : tr_langs[j].to) && strcmp(tr_langs[j].code, other)) {
			snprintf(sel, sizeof tr_from, "%s", tr_langs[j].code);
			break;
		}
	}
}

static void
trchoice(void)
{
	setconfig("translate_from", tr_from);
	setconfig("translate_to", tr_to);
	trchanged();
	build();
}

static void
trswap(void)
{
	char a[12];
	int can = 0;

	for (int i = 0; i < ntr; i++) {
		can |= !strcmp(tr_langs[i].code, tr_to) && tr_langs[i].from;
		can |= (!strcmp(tr_langs[i].code, tr_from) && tr_langs[i].to) << 1;
	}
	if (can != 3 || !tr_from[0])
		return;
	snprintf(a, sizeof a, "%s", tr_from);
	snprintf(tr_from, sizeof tr_from, "%s", tr_to);
	snprintf(tr_to, sizeof tr_to, "%s", a);
	trchoice();
}

static void
trinsert(void)
{
	char keep[sizeof tr_out];

	if (tr_pending || tr_pid || !tr_out[0])
		return;
	snprintf(keep, sizeof keep, "%s", tr_out);
	closepanel();
	if (word[0] && plain)
		endword("");
	commit_text(keep);
	clearword();
	explicit_bzero(keep, sizeof keep);
	dirty = 1;
}

/* the one reader of what the helper prints; it is ours, and it checked what it downloaded */
static void
lrline(char *l)
{
	char *save, *f[6];

	if (!strcmp(l, "D")) {
		lr_finished = 1;
	} else if (!strncmp(l, "S ", 2)) {
		if (!strcmp(l + 2, "offline"))
			snprintf(lr_msg, sizeof lr_msg, "No connection: only what is installed");
		else if (!strcmp(l + 2, "cached"))
			snprintf(lr_msg, sizeof lr_msg, "No connection: the list from last time");
		else
			lr_msg[0] = 0;
	} else if (!strncmp(l, "E ", 2)) {
		lr_failed = 1;
		snprintf(lr_msg, sizeof lr_msg, "%s", l + 2);
	} else if (!strncmp(l, "P ", 2)) {
		sscanf(l + 2, "%ld %ld", &lr_done, &lr_total);
	} else if (!strncmp(l, "L ", 2) && lrows && nlrows < LANG_ROWS) {
		f[0] = strtok_r(l + 2, "\t", &save);
		for (int i = 1; i < 6; i++)
			f[i] = f[i - 1] ? strtok_r(NULL, "\t", &save) : NULL;
		if (f[5]) {
			LangRow *r = &lrows[nlrows++];

			snprintf(r->code, sizeof r->code, "%s", f[0]);
			snprintf(r->name, sizeof r->name, "%s", f[1]);
			snprintf(r->dir, sizeof r->dir, "%s", f[2]);
			r->size = atol(f[3]);
			r->installed = !strcmp(f[4], "installed");
			r->usable = r->installed || !strcmp(f[4], "available");
		}
	}
}

static void
lrspawn(int job, const char *code)
{
	char arg[12] = "";
	char *argv[] = {"phonekbd-lang", job == JOB_LIST ? "list" : job == JOB_INSTALL ? "install" : "remove", arg, NULL};

	if (code)
		snprintf(arg, sizeof arg, "%s", code);
	else
		argv[2] = NULL;
	lr_failed = lr_finished = lr_cancelled = 0;
	lr_done = lr_total = 0;
	lr_bn = 0;
	if (!(lr_pid = spawnpipe(argv, NULL, &lr_fd))) {
		snprintf(lr_msg, sizeof lr_msg, "The language helper is missing");
		return;
	}
	lr_job = job;
}

static void
lrread(void)
{
	ssize_t n;
	int job = lr_job;

	while ((n = read(lr_fd, lr_buf + lr_bn, sizeof lr_buf - 1 - lr_bn)) > 0) {
		char *nl, *start = lr_buf;

		lr_bn += (size_t)n;
		lr_buf[lr_bn] = 0;
		while ((nl = strchr(start, '\n'))) {
			*nl = 0;
			lrline(start);
			start = nl + 1;
		}
		lr_bn = (size_t)(lr_buf + lr_bn - start);
		memmove(lr_buf, start, lr_bn);
		/* a line longer than the buffer is no line of ours */
		if (lr_bn == sizeof lr_buf - 1)
			lr_bn = 0;
	}
	dirty = 1;
	if (n < 0 && errno == EAGAIN) {
		build();
		return;
	}
	close(lr_fd);
	lr_fd = -1;
	waitpid(lr_pid, NULL, 0);
	lr_pid = 0;
	lr_job = JOB_NONE;
	if (job != JOB_LIST && lr_sel >= 0 && lr_sel < nlrows) {
		if (lr_cancelled) {
			snprintf(lr_msg, sizeof lr_msg, "Cancelled");
		} else if (lr_finished && !lr_failed) {
			lrows[lr_sel].installed = job == JOB_INSTALL;
			lrows[lr_sel].usable = 1;
			snprintf(lr_msg, sizeof lr_msg, "%s %.48s", job == JOB_INSTALL ? "Installed" : "Deleted", lrows[lr_sel].name);
			/* the new words, letters and choices count from now on */
			loadletters();
			openwords();
			trscan();
			setconfig("translate_from", tr_from);
			setconfig("translate_to", tr_to);
		} else if (!lr_failed) {
			snprintf(lr_msg, sizeof lr_msg, "That did not finish");
		}
	} else if (job == JOB_LIST && !nlrows && !lr_msg[0]) {
		snprintf(lr_msg, sizeof lr_msg, "No languages to show");
	}
	build();
}

static void
lrkill(void)
{
	if (lr_pid > 0) {
		int tries = 100;

		/* the helper cleans up after itself on TERM */
		kill(-lr_pid, SIGTERM);
		while (tries-- && !waitpid(lr_pid, NULL, WNOHANG))
			usleep(10000);
		if (tries < 0) {
			kill(-lr_pid, SIGKILL);
			waitpid(lr_pid, NULL, 0);
		}
	}
	lr_pid = 0;
	lr_job = JOB_NONE;
	if (lr_fd >= 0)
		close(lr_fd);
	lr_fd = -1;
}

static void
lract(void)
{
	const LangRow *r = lr_sel >= 0 && lr_sel < nlrows ? &lrows[lr_sel] : NULL;

	if (lr_job == JOB_INSTALL) {
		lr_cancelled = 1;
		kill(-lr_pid, SIGTERM);
	} else if (lr_job == JOB_NONE && r && r->installed) {
		lrspawn(JOB_REMOVE, r->code);
	} else if (lr_job == JOB_NONE && r && r->usable) {
		lrspawn(JOB_INSTALL, r->code);
	}
	lr_msg[0] = 0;
	build();
	dirty = 1;
}

static void
openpanel(int which)
{
	char p[600];

	if (secret || panel == which)
		return;
	loadconfig();
	closepanel();
	clearmods();
	modrow = 0;
	panel = which;
	clip_scroll = em_scroll = lr_scroll = 0;
	if (which == PANEL_TRANS) {
		page = PAGE_ABC;
		shift_state = 0;
		trscan();
	} else if (which == PANEL_LANGS) {
		/* shortcut: going to the list drops the typed text, keep it if users complain */
		lrows = calloc(LANG_ROWS, sizeof *lrows);
		nlrows = 0;
		lr_sel = -1;
		snprintf(lr_msg, sizeof lr_msg, "Reading the list");
		lrspawn(JOB_LIST, NULL);
	}
	if (which == PANEL_EMOJI) {
		datapath("emoji.tsv", p, sizeof p);
		em_kind = emoji_open(ft, p, state_dir);
		em_search = 0;
		em_query[0] = 0;
		em_nfound = 0;
		for (int g = 0, i = 0; g <= EMOJI_GROUPS; g++) {
			while (i < emoji_count() && emoji_at(i)->group < g)
				i++;
			em_start[g] = i;
		}
		em_group = emoji_recent_count() ? -1 : 0;
	}
	resize();
}

static void
droppanel(void)
{
	if (panel == PANEL_EMOJI) {
		emoji_close();
		em_kind = EMOJI_NONE;
		em_search = 0;
		em_query[0] = 0;
		em_nfound = 0;
#ifdef __GLIBC__
		malloc_trim(0);
#endif
	}
	if (panel == PANEL_TRANS) {
		trkill();
		arm(tr_timer, 0, 0);
		tr_pending = 0;
		tr_outn = 0;
		tr_msg[0] = 0;
		explicit_bzero(tr_in, sizeof tr_in);
		explicit_bzero(tr_out, sizeof tr_out);
	}
	if (panel == PANEL_LANGS) {
		lrkill();
		free(lrows);
		lrows = NULL;
		nlrows = 0;
		lr_sel = -1;
	}
	panel = PANEL_NONE;
}

static void
closepanel(void)
{
	if (!panel)
		return;
	droppanel();
	resize();
}

static void
commitemoji(const char *seq)
{
	char keep[EMOJI_SEQ];

	snprintf(keep, sizeof keep, "%s", seq);
	if (word[0] && plain)
		endword("");
	commit_text(keep);
	if (cfg.learn && cfg.emoji_history && !secret)
		emoji_recent_add(keep);
	auto_space = 0;
	undo_from[0] = 0;
	dirty = 1;
}

/* the terminal takes its shortcuts with Shift, which is what a Ctrl+C that must stay a signal needs */
static unsigned
actmask(void)
{
	return CTRL_MASK | (purpose == P_TERMINAL ? SHIFT_MASK : 0);
}

static void
clipwipe(void)
{
	for (int i = 0; i < nclips; i++) {
		explicit_bzero(clips[i], strlen(clips[i]));
		free(clips[i]);
	}
	nclips = 0;
	dirty = 1;
}

static void
clipdrop(void)
{
	if (clip_fd >= 0)
		close(clip_fd);
	clip_fd = -1;
	if (clip_buf)
		explicit_bzero(clip_buf, clip_len);
	free(clip_buf);
	clip_buf = NULL;
	clip_len = 0;
}

static int
validutf8(const char *s, size_t n)
{
	const unsigned char *p = (const unsigned char *)s, *e = p + n;

	while (p < e) {
		int more = *p < 0x80 ? 0 : *p >= 0xc2 && *p < 0xe0 ? 1 : *p >= 0xe0 && *p < 0xf0 ? 2 : *p >= 0xf0 && *p < 0xf5 ? 3 : -1;

		if (more < 0 || !*p || e - p <= more)
			return 0;
		p++;
		while (more--)
			if ((*p++ & 0xc0) != 0x80)
				return 0;
	}
	return 1;
}

static void
clipadd(const char *s)
{
	size_t total = strlen(s);
	char *copy;

	for (int i = 0; i < nclips; i++)
		if (!strcmp(clips[i], s)) {
			copy = clips[i];
			memmove(clips + 1, clips, (size_t)i * sizeof *clips);
			clips[0] = copy;
			dirty = 1;
			return;
		}
	if (!(copy = strdup(s)))
		return;
	if (nclips == CLIP_MAX) {
		explicit_bzero(clips[nclips - 1], strlen(clips[nclips - 1]));
		free(clips[--nclips]);
	}
	for (int i = 0; i < nclips; i++)
		total += strlen(clips[i]);
	while (total > CLIP_TOTAL && nclips) {
		total -= strlen(clips[nclips - 1]);
		explicit_bzero(clips[nclips - 1], strlen(clips[nclips - 1]));
		free(clips[--nclips]);
	}
	memmove(clips + 1, clips, (size_t)nclips * sizeof *clips);
	clips[0] = copy;
	nclips++;
	dirty = 1;
}

static void
clipread(void)
{
	char tmp[4096];
	ssize_t n = read(clip_fd, tmp, sizeof tmp);

	if (n < 0 && (errno == EAGAIN || errno == EINTR))
		return;
	if (n > 0) {
		char *grown;

		/* too large to keep: dropped whole, a cut piece is never what was copied */
		if (clip_len + (size_t)n > CLIP_ONE || !(grown = realloc(clip_buf, clip_len + (size_t)n + 1))) {
			clipdrop();
			return;
		}
		clip_buf = grown;
		memcpy(clip_buf + clip_len, tmp, (size_t)n);
		clip_len += (size_t)n;
		return;
	}
	if (n == 0 && clip_len && validutf8(clip_buf, clip_len)) {
		clip_buf[clip_len] = 0;
		/* a field turned secret during the read: this is not kept either */
		if (cfg.clipboard_history && !(active && secret))
			clipadd(clip_buf);
	}
	clipdrop();
}

enum { MIME_UTF8 = 1, MIME_PLAIN = 2, MIME_STRING = 4, MIME_SECRET = 8 };

static void
offer_mime(void *data, struct zwlr_data_control_offer_v1 *o, const char *m)
{
	unsigned *bits = data;

	if (!strcmp(m, "text/plain;charset=utf-8"))
		*bits |= MIME_UTF8;
	else if (!strcmp(m, "text/plain"))
		*bits |= MIME_PLAIN;
	else if (!strcmp(m, "UTF8_STRING"))
		*bits |= MIME_STRING;
	else if (!strcmp(m, "x-kde-passwordManagerHint"))
		*bits |= MIME_SECRET;
}
static const struct zwlr_data_control_offer_v1_listener offer_listener = {offer_mime};

static void
offer_free(struct zwlr_data_control_offer_v1 *o)
{
	free(zwlr_data_control_offer_v1_get_user_data(o));
	zwlr_data_control_offer_v1_destroy(o);
}

static void
dc_offer(void *data, struct zwlr_data_control_device_v1 *d, struct zwlr_data_control_offer_v1 *o)
{
	zwlr_data_control_offer_v1_add_listener(o, &offer_listener, calloc(1, sizeof(unsigned)));
}

static void
dc_selection(void *data, struct zwlr_data_control_device_v1 *d, struct zwlr_data_control_offer_v1 *o)
{
	unsigned bits;
	const char *m;
	int p[2];

	clipdrop();
	if (!o)
		return;
	bits = *(unsigned *)zwlr_data_control_offer_v1_get_user_data(o);
	loadconfig();
	if (!cfg.clipboard_history)
		clipwipe();
	m = bits & MIME_UTF8 ? "text/plain;charset=utf-8" : bits & MIME_PLAIN ? "text/plain" : bits & MIME_STRING ? "UTF8_STRING" : NULL;
	if (m && cfg.clipboard_history && !(active && secret) && !(bits & MIME_SECRET) && !pipe2(p, O_CLOEXEC | O_NONBLOCK)) {
		zwlr_data_control_offer_v1_receive(o, m, p[1]);
		close(p[1]);
		clip_fd = p[0];
	}
	offer_free(o);
}

static void
dc_finished(void *data, struct zwlr_data_control_device_v1 *d)
{
	zwlr_data_control_device_v1_destroy(d);
	dc_dev = NULL;
}

static void
dc_primary(void *data, struct zwlr_data_control_device_v1 *d, struct zwlr_data_control_offer_v1 *o)
{
	if (o)
		offer_free(o);
}
static const struct zwlr_data_control_device_v1_listener dc_listener = {dc_offer, dc_selection, dc_finished, dc_primary};

/* --- feedback: off unless asked for; neither ever looks at which key it was --- */
static void
reapsound(void)
{
	if (snd_pid > 0 && waitpid(snd_pid, NULL, WNOHANG) != 0)
		snd_pid = 0;
}

/* shortcut: spawns a player per tap, latency unmeasured on a phone; link a sound library if taps lag */
static void
playclick(void)
{
	static const char *const players[] = {"pw-play", "paplay", "aplay"};
	static char wav[300];
	extern char **environ;
	posix_spawn_file_actions_t fa;

	reapsound();
	if (snd_pid > 0)
		return;
	if (!wav[0]) {
		const char *rt = getenv("XDG_RUNTIME_DIR");
		uint8_t h[44 + 240] = "RIFF";
		uint32_t v;
		int fd;

		if (!rt)
			return;
		snprintf(wav, sizeof wav, "%s/phonekbd-click.wav", rt);
		v = 36 + 240;
		memcpy(h + 4, &v, 4);
		memcpy(h + 8, "WAVEfmt ", 8);
		v = 16;
		memcpy(h + 16, &v, 4);
		h[20] = 1;
		h[22] = 1;
		v = 8000;
		memcpy(h + 24, &v, 4);
		memcpy(h + 28, &v, 4);
		h[32] = 1;
		h[34] = 8;
		memcpy(h + 36, "data", 4);
		v = 240;
		memcpy(h + 40, &v, 4);
		for (int i = 0; i < 240; i++)
			h[44 + i] = (uint8_t)(128 + (i % 8 < 4 ? 1 : -1) * (40 * (240 - i) / 240));
		if ((fd = open(wav, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600)) < 0) {
			wav[0] = 0;
			return;
		}
		if (write(fd, h, sizeof h) != (ssize_t)sizeof h)
			wav[0] = 0;
		close(fd);
		if (!wav[0])
			return;
	}
	posix_spawn_file_actions_init(&fa);
	posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
	posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0);
	posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
	for (size_t i = 0; i < LEN(players); i++) {
		char *argv[] = {(char *)players[i], wav, NULL};

		if (!posix_spawnp(&snd_pid, players[i], &fa, NULL, argv, environ))
			break;
		snd_pid = 0;
	}
	posix_spawn_file_actions_destroy(&fa);
}

/* only ever writes force feedback to the device; key events are never read */
static int
vibtry(const char *path)
{
	unsigned char bits[(FF_MAX >> 3) + 1] = {0};
	struct ff_effect e = {.type = FF_RUMBLE, .id = -1, .replay = {.length = 30}};
	int fd = open(path, O_RDWR | O_CLOEXEC | O_NONBLOCK);

	if (fd < 0)
		return -1;
	e.u.rumble.strong_magnitude = 0xc000;
	if (ioctl(fd, EVIOCGBIT(EV_FF, sizeof bits), bits) < 0 || !(bits[FF_RUMBLE >> 3] >> (FF_RUMBLE & 7) & 1)
			|| ioctl(fd, EVIOCSFF, &e) < 0) {
		close(fd);
		return -1;
	}
	vib_id = e.id;
	return fd;
}

static void
buzz(void)
{
	struct input_event ev = {.type = EV_FF, .value = 1};

	if (vib_fd == -2) {
		const char *o = getenv("PHONEKBD_VIBRATOR");

		vib_fd = -1;
		if (o) {
			vib_fd = vibtry(o);
		} else {
			for (int i = 0; i < 32 && vib_fd < 0; i++) {
				char p[32];

				snprintf(p, sizeof p, "/dev/input/event%d", i);
				vib_fd = vibtry(p);
			}
		}
	}
	if (vib_fd < 0)
		return;
	ev.code = (unsigned short)vib_id;
	if (write(vib_fd, &ev, sizeof ev) < 0)
		return;
}

static void
feedback(void)
{
	if (cfg.sound && !cfg.ringer_off)
		playclick();
	if (cfg.vibrate)
		buzz();
}

/* --- touch --- */
static int
hit(float x, float y)
{
	int best = -1;
	float bd = 1e9f;

	for (int i = 0; i < nkeys; i++) {
		const Key *k = &keys[i];
		float dx = MAX(MAX(k->x - x, x - (k->x + k->w)), 0.f);
		float dy = MAX(MAX(k->y - y, y - (k->y + k->h)), 0.f);
		float d = dx * dx + dy * dy;

		if (d < bd) {
			bd = d;
			best = i;
		}
	}
	return best;
}

static void
resize(void)
{
	float h = wantheight();

	if ((int)h != height && layer) {
		zwlr_layer_surface_v1_set_size(layer, 0, (uint32_t)h + BAR_ROOM);
		zwlr_layer_surface_v1_set_exclusive_zone(layer, zone());
		wl_surface_commit(surf);
	} else {
		build();
		dirty = 1;
	}
}

/* what the field asked for, recalculated on every change it reports */
static void
setmodes(void)
{
	int was = secret;

	secret = (hint & (HINT_HIDDEN | HINT_SENSITIVE)) || purpose == P_PASSWORD || purpose == P_PIN;
	plain = active && !laptop && !secret && purpose != P_DIGITS && purpose != P_NUMBER && purpose != P_PHONE && purpose != P_URL
		&& purpose != P_EMAIL && purpose != P_TERMINAL;
	if (secret) {
		surround[0] = 0;
		word[0] = 0;
		prev[0] = 0;
		s_pending = 0;
		undo_from[0] = 0;
		swiped[0] = 0;
		memset(sug, 0, sizeof sug);
		sug_fix = -1;
	}
	if (secret != was && shown) {
		if (secret)
			droppanel();
		resize();
	}
}

static void
setlaptop(int on)
{
	laptop = on;
	clearmods();
	modrow = 0;
	page = PAGE_ABC;
	savelayout();
	clearword();
	setmodes();
	resize();
}

static void
tapmod(unsigned mask)
{
	int bit = __builtin_ctz(mask);
	long t = now_ms();
	unsigned before = fnon();

	if (mods_locked & mask) {
		mods_locked &= ~mask;
	} else if ((mods_latched & mask) && t - mod_time[bit] < DOUBLE_MS) {
		mods_latched &= ~mask;
		mods_locked |= mask;
	} else if (mods_latched & mask) {
		mods_latched &= ~mask;
	} else {
		mods_latched |= mask;
	}
	mod_time[bit] = t;
	dirty = 1;
	if (before != fnon())
		build();
}

/* the key does its work */
static void
fire(const Key *k)
{
	last_key = now_ms();
	switch (k->kind) {
	case K_CHAR:
		typechar(k->text);
		break;
	case K_SPACE:
		if ((panel == PANEL_EMOJI && em_search) || panel == PANEL_TRANS) {
			typechar(" ");
		} else if (laptop) {
			typetext(" ");
		} else if (hardmods()) {
			typetext(" ");
			clearword();
		} else if (auto_space) {
			auto_space = 0;
		} else if (plain) {
			long at = now_ms();

			/* two quick spaces after a word end the sentence */
			if (cfg.double_space && !word[0] && dbl_time && at - dbl_time < 500) {
				replace_text(1, ". ");
				dbl_time = 0;
				s_pending = 0;
				snprintf(prev, sizeof prev, "<s>");
				updatesug();
			} else {
				dbl_time = word[0] ? at : 0;
				endword(" ");
			}
		} else {
			commit_text(" ");
		}
		/* the space may have just started a sentence: its capital stays, modifiers do not */
		{
			int keep = cap_auto && shift_state == 1;

			clearlatched();
			if (keep) {
				shift_state = 1;
				cap_auto = 1;
			}
		}
		break;
	case K_BKSP:
		backspace();
		break;
	case K_ENTER: {
		unsigned m = curmods();

		if (panel == PANEL_TRANS) {
			trinsert();
			break;
		}
		if (panel == PANEL_EMOJI && em_search) {
			em_search = 0;
			resize();
			break;
		}
		if (word[0] && plain)
			endword("");
		sendkey(KEY_ENTER, m);
		clearlatched();
		clearword();
		snprintf(prev, sizeof prev, "<s>");
		updatesug();
		break;
	}
	case K_SHIFT: {
		long t = now_ms();

		cap_auto = 0;
		if (shift_state == 2 || shift_state == 1) {
			shift_state = shift_state == 1 && t - shift_time < DOUBLE_MS ? 2 : 0;
		} else {
			shift_state = 1;
		}
		shift_time = t;
		dirty = 1;
		break;
	}
	case K_PAGE:
		page = k->code;
		shift_state = 0;
		resize();
		break;
	case K_LAPTOP:
		if (panel)
			closepanel();
		setlaptop(!laptop);
		break;
	case K_MOD:
		tapmod((unsigned)k->code);
		break;
	case K_MODS:
		modrow = !modrow;
		if (!modrow)
			clearmods();
		resize();
		break;
	case K_EMOJI:
		openpanel(PANEL_EMOJI);
		break;
	case K_CLIP:
		/* the settings page may have cleared it while the keyboard is up */
		applyhistory();
		openpanel(PANEL_CLIP);
		break;
	case K_ABC:
		closepanel();
		break;
	case K_TRANSLATE:
		openpanel(PANEL_TRANS);
		break;
	case K_TRFROM:
		trcycle(tr_from, tr_to, 1);
		trchoice();
		break;
	case K_TRTO:
		trcycle(tr_to, tr_from, 0);
		trchoice();
		break;
	case K_TRSWAP:
		trswap();
		break;
	case K_LANGS:
		openpanel(PANEL_LANGS);
		break;
	case K_LANGBACK:
		/* a download goes on until it is cancelled; going back must not end it by accident */
		if (lr_job != JOB_INSTALL)
			openpanel(PANEL_TRANS);
		break;
	case K_LANGACT:
		lract();
		break;
	case K_TAB:
		em_group = k->code;
		em_scroll = 0;
		build();
		dirty = 1;
		break;
	case K_SEARCH:
		em_search = !k->code;
		em_query[0] = 0;
		em_nfound = 0;
		page = PAGE_ABC;
		shift_state = 0;
		resize();
		break;
	case K_ACT:
		sendkey(k->code, actmask());
		clearword();
		break;
	case K_CLEARCLIP:
		clipwipe();
		clip_scroll = 0;
		build();
		break;
	case K_ONEHAND:
		cfg.one_handed = cfg.one_handed ? 0 : 2;
		setconfig("one_handed", cfg.one_handed ? "right" : "off");
		if (panel)
			closepanel();
		else
			resize();
		break;
	case K_SWAP:
		cfg.one_handed = cfg.one_handed == 1 ? 2 : 1;
		setconfig("one_handed", cfg.one_handed == 1 ? "left" : "right");
		build();
		dirty = 1;
		break;
	case K_HIDE:
		askhide();
		break;
	case K_GEAR:
		/* the bar has no such key on a secret field; the check stays with the action */
		if (!secret) {
			if (system("phonesettings keyboard </dev/null >/dev/null 2>&1 &")) {}
			askhide();
		}
		break;
	case K_THEME:
		cfg.theme = (cfg.theme + 1) % (int)LEN(themes);
		cfg.theme_system = 0;
		applytheme();
		setconfig("theme", theme->name);
		dirty = 1;
		break;
	case K_CODE:
		sendkey(k->code, curmods());
		clearlatched();
		clearword();
		break;
	}
}

static int
repeats(const Key *k)
{
	return k->kind == K_BKSP || (k->kind == K_CODE && (k->code == KEY_LEFT || k->code == KEY_RIGHT
		|| k->code == KEY_UP || k->code == KEY_DOWN || k->code == KEY_DELETE
		|| k->code == KEY_PAGEUP || k->code == KEY_PAGEDOWN));
}

static void
touch_down(void *data, struct wl_touch *t, uint32_t serial, uint32_t time, struct wl_surface *s,
		int32_t id, wl_fixed_t fx, wl_fixed_t fy)
{
	float x = (float)wl_fixed_to_double(fx), y = (float)wl_fixed_to_double(fy);
	Slot *sl = NULL;

	/* under the keys nothing types; only the hide area answers, and only to a tap */
	if (y >= (float)height) {
		chev_id = !secret && x >= (float)chevx() && x < (float)(chevx() + CHEV_W) ? id : -1;
		chev_x = x;
		chev_y = y;
		chev_t = time;
		return;
	}

	for (size_t i = 0; i < LEN(slots); i++) {
		/* a second finger completes the first key, which is how fast typing works */
		if (slots[i].used && slots[i].key >= 0 && !slots[i].fired && !slots[i].swiping
				&& (int)i != popup_slot && !repeats(&keys[slots[i].key])) {
			const Key copy = keys[slots[i].key];

			slots[i].fired = 1;
			fire(&copy);
		}
		if (!slots[i].used && !sl)
			sl = &slots[i];
	}
	if (!sl)
		return;
	*sl = (Slot){.used = 1, .id = id, .key = -1, .sug = -1, .tile = -1, .downx = x, .downy = y, .x = x, .y = y};
	/* a new finger ends whatever an earlier one was holding down */
	rep_on = 0;
	arm(timerfd, 0, 0);
	timer_slot = -1;
	feedback();
	dirty = 1;
	if (panel == PANEL_EMOJI && !em_search && em_kind != EMOJI_NONE && y >= TAB_H && y < (float)height - PANEL_BOT) {
		int cols = MAX(8, width / 49), row = (int)((y - TAB_H + em_scroll) / ((float)width / (float)cols));
		int i = row * cols + MIN((int)(x / ((float)width / (float)cols)), cols - 1);

		sl->drag = D_GRID;
		sl->dragx = em_scroll;
		sl->tile = i < tilecount() ? i : -1;
		timer_slot = (int)(sl - slots);
		arm(timerfd, cfg.long_ms, 0);
		return;
	}
	if (panel == PANEL_EMOJI && em_search && y >= QUERY_H && y < QUERY_H + STRIP_H) {
		int i = (int)(x / ((float)width / (float)MAX(8, width / 49)));

		sl->drag = D_STRIP;
		sl->tile = i < em_nfound ? i : -1;
		return;
	}
	if (panel == PANEL_CLIP && y >= TAB_H && y < (float)height - PANEL_BOT) {
		int i = (int)((y - TAB_H + clip_scroll) / CLIP_ROW);

		sl->drag = D_CLIP;
		sl->dragx = clip_scroll;
		sl->tile = i < nclips ? i : -1;
		return;
	}
	if (panel == PANEL_TRANS && y >= TAB_H && y < TRANS_TOP) {
		sl->drag = y >= TAB_H + QUERY_H ? D_TRINS : D_NONE;
		return;
	}
	if (panel == PANEL_LANGS && y >= TAB_H && y < (float)height - PANEL_BOT) {
		int i = (int)((y - TAB_H + lr_scroll) / CLIP_ROW);

		sl->drag = D_LANG;
		sl->dragx = lr_scroll;
		sl->tile = i < nlrows ? i : -1;
		return;
	}
	if (!laptop && !panel && !landscape && y < SUG_H) {
		/* the bar has its buttons and three word cells; nothing else in it may type */
		for (int i = 0; i < nkeys && keys[i].y < SUG_H; i++)
			if (x >= keys[i].x && x < keys[i].x + keys[i].w) {
				sl->key = i;
				break;
			}
		if (sl->key < 0) {
			if (nsug && x >= sug_x && x < sug_x + sug_w * 3)
				sl->sug = MIN((int)((x - sug_x) / sug_w), nsug - 1);
			return;
		}
	} else {
		sl->key = hit(x, y);
	}
	if (sl->key >= 0) {
		const Key *k = &keys[sl->key];

		timer_slot = (int)(sl - slots);
		if (k->kind == K_BKSP) {
			/* waits for the finger: it may be the start of a swipe that deletes words */
			rep_key = *k;
			rep_mods = curmods();
			rep_on = 1;
			arm(timerfd, cfg.long_ms, REPEAT_MS);
			if (!laptop && !em_search && panel != PANEL_TRANS) {
				sl->drag = D_BKSP;
				sl->dragx = x;
			}
		} else if (repeats(k)) {
			const Key copy = *k;

			rep_key = copy;
			rep_mods = curmods();
			rep_on = 1;
			sl->fired = 1;
			fire(&copy);
			arm(timerfd, cfg.long_ms, REPEAT_MS);
		} else if (k->kind == K_CHAR) {
			arm(timerfd, cfg.long_ms, 0);
		} else if (k->kind == K_SPACE && cfg.space_cursor && !laptop && !em_search && panel != PANEL_TRANS) {
			sl->drag = D_SPACE;
			sl->dragx = x;
		}
	}
}

static void
openpopup(int si)
{
	const Key *k = &keys[slots[si].key];
	const char *a = alts_for(k->text);
	char buf[64], *save = NULL, *tok;
	float total;

	if (!a)
		return;
	snprintf(buf, sizeof buf, "%s", a);
	popup_n = 0;
	for (tok = strtok_r(buf, " ", &save); tok && popup_n < 8; tok = strtok_r(NULL, " ", &save)) {
		snprintf(popup[popup_n], EMOJI_SEQ, "%s", tok);
		if (shift_state)
			upper(tok, popup[popup_n], 8);
		popup_n++;
	}
	total = POPUP_W * (float)popup_n;
	popup_x = MAX(4.f, MIN((float)width - total - 4, k->x + k->w / 2 - total / 2));
	popup_y = MAX(3.f, k->y - POPUP_H);
	popup_sel = 0;
	popup_slot = si;
	popup_emoji = 0;
	dirty = 1;
}

static void
openemojipopup(int si)
{
	const char *seq = tileseq(slots[si].tile);
	const Emoji *e = tilemoji(seq);
	int cols = MAX(8, width / 49);
	float t = (float)width / (float)cols, total, tx, ty;

	if (!e || !e->tone[0])
		return;
	snprintf(popup[0], EMOJI_SEQ, "%s", e->seq);
	popup_n = 1;
	for (int i = 0; i < EMOJI_TONES; i++)
		if (emoji_toned(e, i, popup[popup_n], EMOJI_SEQ))
			popup_n++;
	if (popup_n < 2)
		return;
	total = POPUP_W * (float)popup_n;
	tx = ((float)(slots[si].tile % cols) + 0.5f) * t;
	ty = TAB_H + (float)(slots[si].tile / cols) * t - em_scroll;
	popup_x = MAX(4.f, MIN((float)width - total - 4, tx - total / 2));
	popup_y = MAX(3.f, ty - POPUP_H);
	popup_sel = 0;
	popup_slot = si;
	popup_emoji = 1;
	dirty = 1;
}

static void
touch_motion(void *data, struct wl_touch *t, uint32_t time, int32_t id, wl_fixed_t fx, wl_fixed_t fy)
{
	float x = (float)wl_fixed_to_double(fx), y = (float)wl_fixed_to_double(fy);

	if (id == chev_id && (fabsf(x - chev_x) > CHEV_SLOP || fabsf(y - chev_y) > CHEV_SLOP))
		chev_id = -1;
	for (size_t i = 0; i < LEN(slots); i++) {
		Slot *sl = &slots[i];
		int others = 0;

		if (!sl->used || sl->id != id)
			continue;
		sl->x = x;
		sl->y = y;
		if ((int)i == popup_slot) {
			int sel = (int)floorf((x - popup_x) / POPUP_W);

			sel = sel < 0 ? 0 : sel >= popup_n ? popup_n - 1 : sel;
			if (sel != popup_sel) {
				popup_sel = sel;
				dirty = 1;
			}
			continue;
		}
		if (sl->drag == D_GRID || sl->drag == D_CLIP || sl->drag == D_LANG) {
			float dy = y - sl->downy, limit;

			if (sl->tile >= 0 && fabsf(dy) < 10)
				continue;
			sl->tile = -1;
			if (timer_slot == (int)i) {
				arm(timerfd, 0, 0);
				timer_slot = -1;
			}
			if (sl->drag == D_GRID) {
				int cols = MAX(8, width / 49);
				float t = (float)width / (float)cols;

				limit = (float)((tilecount() + cols - 1) / cols) * t - ((float)height - PANEL_BOT - TAB_H);
				em_scroll = MAX(0.f, MIN(MAX(limit, 0.f), sl->dragx - dy));
			} else if (sl->drag == D_LANG) {
				limit = (float)nlrows * CLIP_ROW - ((float)height - PANEL_BOT - TAB_H);
				lr_scroll = MAX(0.f, MIN(MAX(limit, 0.f), sl->dragx - dy));
			} else {
				limit = (float)nclips * CLIP_ROW - ((float)height - PANEL_BOT - TAB_H);
				clip_scroll = MAX(0.f, MIN(MAX(limit, 0.f), sl->dragx - dy));
			}
			dirty = 1;
			continue;
		}
		if (sl->drag == D_SPACE) {
			/* the cursor follows half a key per step, and the space is off */
			while (fabsf(x - sl->dragx) >= U * 0.5f) {
				int right = x > sl->dragx;

				sendkey(right ? KEY_RIGHT : KEY_LEFT, curmods());
				sl->dragx += right ? U * 0.5f : -U * 0.5f;
				if (!sl->fired)
					clearword();
				sl->fired = 1;
			}
			continue;
		}
		if (sl->drag == D_BKSP) {
			while (sl->dragx - x >= U * 0.8f) {
				if (timer_slot == (int)i) {
					arm(timerfd, 0, 0);
					timer_slot = -1;
				}
				rep_on = 0;
				/* a terminal has no word delete on Ctrl+Backspace, so it gets its own */
				sendkey(purpose == P_TERMINAL ? KEY_W : KEY_BACKSPACE, CTRL_MASK);
				sl->dragx -= U * 0.8f;
				if (!sl->fired)
					clearword();
				sl->fired = 1;
			}
			continue;
		}
		if (sl->key < 0 || sl->fired)
			continue;
		for (size_t j = 0; j < LEN(slots); j++)
			others |= j != i && slots[j].used;
		if (!sl->swiping && plain && (cfg.predict || cfg.autocorrect) && !panel && !fnon() && !hardmods() && page == PAGE_ABC && !others && keys[sl->key].kind == K_CHAR
				&& keys[sl->key].text[0] >= 'a' && keys[sl->key].text[0] <= 'z'
				&& hypotf(x - sl->downx, y - sl->downy) > U * 0.9f) {
			sl->swiping = 1;
			arm(timerfd, 0, 0);
			timer_slot = -1;
			npath = 0;
			path[npath][0] = sl->downx;
			path[npath++][1] = sl->downy;
			dirty = 1;
		}
		if (sl->swiping && npath < (int)LEN(path)
				&& hypotf(x - path[npath - 1][0], y - path[npath - 1][1]) > U * 0.1f) {
			path[npath][0] = x;
			path[npath++][1] = y;
			dirty = 1;
		}
	}
}

static void
touch_up(void *data, struct wl_touch *t, uint32_t serial, uint32_t time, int32_t id)
{
	if (id == chev_id) {
		chev_id = -1;
		if (time - chev_t < CHEV_TAP_MS)
			askhide();
		return;
	}
	for (size_t i = 0; i < LEN(slots); i++) {
		Slot *sl = &slots[i];

		if (!sl->used || sl->id != id)
			continue;
		last_key = now_ms();
		if (timer_slot == (int)i) {
			arm(timerfd, 0, 0);
			timer_slot = -1;
			rep_on = 0;
		}
		if ((int)i == popup_slot && popup_emoji) {
			popup_slot = -1;
			popup_emoji = 0;
			commitemoji(popup[popup_sel]);
		} else if ((int)i == popup_slot) {
			char s[EMOJI_SEQ];

			snprintf(s, sizeof s, "%s", popup[popup_sel]);
			popup_slot = -1;
			/* already cased by the popup */
			shift_state = shift_state == 2 ? 2 : 0;
			{
				int keep = shift_state;

				shift_state = 0;
				typechar(s);
				shift_state = keep;
			}
		} else if (sl->drag == D_GRID) {
			if (sl->tile >= 0 && sl->tile < tilecount())
				commitemoji(tileseq(sl->tile));
		} else if (sl->drag == D_STRIP) {
			if (sl->tile >= 0 && sl->tile < em_nfound)
				commitemoji(emoji_at(em_found[sl->tile])->seq);
		} else if (sl->drag == D_TRINS) {
			trinsert();
		} else if (sl->drag == D_LANG) {
			if (sl->tile >= 0 && sl->tile < nlrows && lr_job != JOB_INSTALL) {
				lr_sel = sl->tile;
				build();
			}
		} else if (sl->drag == D_CLIP) {
			if (sl->tile >= 0 && sl->tile < nclips) {
				commit_text(clips[sl->tile]);
				clearword();
			}
		} else if (sl->swiping) {
			sl->used = 0;
			finishswipe();
		} else if (sl->sug >= 0) {
			int s = sl->sug;

			sl->used = 0;
			picksug(s);
		} else if (sl->key >= 0 && !sl->fired && (nkeys > sl->key)) {
			Key copy = keys[sl->key];

			key_rel[sl->key] = now_ms();

			sl->used = 0;
			/* a finger that slid off a non letter key changed its mind */
			if (hypotf(sl->x - sl->downx, sl->y - sl->downy) < U * 1.5f)
				fire(&copy);
		}
		sl->used = 0;
		dirty = 1;
	}
}

static void
touch_cancel(void *data, struct wl_touch *t)
{
	chev_id = -1;
	memset(slots, 0, sizeof slots);
	popup_slot = -1;
	timer_slot = -1;
	rep_on = 0;
	npath = 0;
	arm(timerfd, 0, 0);
	dirty = 1;
}

static void touch_frame(void *data, struct wl_touch *t) {}
static void touch_shape(void *data, struct wl_touch *t, int32_t id, wl_fixed_t a, wl_fixed_t b) {}
static void touch_orient(void *data, struct wl_touch *t, int32_t id, wl_fixed_t o) {}
static const struct wl_touch_listener touch_listener = {
	touch_down, touch_up, touch_motion, touch_frame, touch_cancel, touch_shape, touch_orient,
};

static void
seat_caps(void *data, struct wl_seat *s, uint32_t caps)
{
	if ((caps & WL_SEAT_CAPABILITY_TOUCH) && !touch) {
		touch = wl_seat_get_touch(s);
		wl_touch_add_listener(touch, &touch_listener, NULL);
	} else if (!(caps & WL_SEAT_CAPABILITY_TOUCH) && touch) {
		wl_touch_destroy(touch);
		touch = NULL;
	}
}
static void seat_name(void *data, struct wl_seat *s, const char *n) {}
static const struct wl_seat_listener seat_listener = {seat_caps, seat_name};

/* --- surface --- */
static void
layer_configure(void *data, struct zwlr_layer_surface_v1 *l, uint32_t serial, uint32_t w, uint32_t h)
{
	zwlr_layer_surface_v1_ack_configure(l, serial);
	width = (int)w;
	height = h > BAR_ROOM ? (int)h - BAR_ROOM : 0;
	if (!width || !height)
		return;
	droidh();
	if (landscape != (width >= WIDE_W)) {
		landscape = width >= WIDE_W;
		if ((int)wantheight() != height) {
			resize();
			return;
		}
	}
	if (makebuffers()) {
		build();
		configured = 1;
		dirty = 1;
		flushdraw();
	}
}

static void hidekbd(void);

static void
layer_closed(void *data, struct zwlr_layer_surface_v1 *l)
{
	hidekbd();
}
static const struct zwlr_layer_surface_v1_listener layer_listener = {layer_configure, layer_closed};

static void
preferred_scale(void *data, struct wp_fractional_scale_v1 *f, uint32_t s)
{
	if (s == scale120 || !s)
		return;
	scale120 = s;
	if (configured && makebuffers()) {
		build();
		dirty = 1;
	}
}
static const struct wp_fractional_scale_v1_listener frac_listener = {preferred_scale};

static void
showkbd(void)
{
	char fontbuf[512];
	const char *font;

	if (shown)
		return;
	shown = 1;
	loadconfig();
	/* the settings page writes this file while the keyboard is hidden */
	int was_laptop = laptop;
	loadlayout();
	if (laptop != was_laptop) {
		clearmods();
		modrow = 0;
		page = PAGE_ABC;
		setmodes();
	}
	loadletters();
	openwords();
	FT_Init_FreeType(&ft);
	if ((font = findfont(fontbuf, sizeof fontbuf)))
		FT_New_Face(ft, font, 0, &face);
	surf = wl_compositor_create_surface(compositor);
	if (frac_mgr && viewporter) {
		frac = wp_fractional_scale_manager_v1_get_fractional_scale(frac_mgr, surf);
		wp_fractional_scale_v1_add_listener(frac, &frac_listener, NULL);
		viewport = wp_viewporter_get_viewport(viewporter, surf);
	}
	layer = zwlr_layer_shell_v1_get_layer_surface(layer_shell, surf, NULL,
		ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "phone-keyboard");
	zwlr_layer_surface_v1_add_listener(layer, &layer_listener, NULL);
	zwlr_layer_surface_v1_set_anchor(layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM
		| ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
	zwlr_layer_surface_v1_set_size(layer, 0, (uint32_t)wantheight() + BAR_ROOM);
	zwlr_layer_surface_v1_set_exclusive_zone(layer, zone());
	zwlr_layer_surface_v1_set_keyboard_interactivity(layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
	wl_surface_commit(surf);
}

/* everything but the connection goes, so a hidden keyboard stays small */
static void
hidekbd(void)
{
	forced = 0;
	if (!shown)
		return;
	shown = 0;
	droidh();
	configured = 0;
	memset(slots, 0, sizeof slots);
	popup_slot = -1;
	popup_emoji = 0;
	timer_slot = -1;
	rep_on = 0;
	npath = 0;
	arm(timerfd, 0, 0);
	droppanel();
	modrow = 0;
	clearmods();
	reapsound();
	if (vib_fd >= 0)
		close(vib_fd);
	vib_fd = -2;
	if (frame_cb) {
		wl_callback_destroy(frame_cb);
		frame_cb = NULL;
	}
	freebuffers();
	if (viewport)
		wp_viewport_destroy(viewport);
	if (frac)
		wp_fractional_scale_v1_destroy(frac);
	viewport = NULL;
	frac = NULL;
	zwlr_layer_surface_v1_destroy(layer);
	wl_surface_destroy(surf);
	layer = NULL;
	surf = NULL;
	surf_region = 0;
	width = height = 0;
	words_close();
	if (face)
		FT_Done_Face(face);
	face = NULL;
	if (ft)
		FT_Done_FreeType(ft);
	ft = NULL;
#ifdef __GLIBC__
	malloc_trim(0);
#endif
}

/* --- input method --- */
static void
syncprev(size_t start)
{
	size_t end = start, b;
	unsigned char ch = 0;

	prev[0] = 0;
	s_pending = 0;
	while (end > 0 && surround[end - 1] == ' ')
		end--;
	if (end == 0) {
		snprintf(prev, sizeof prev, "<s>");
		return;
	}
	ch = (unsigned char)surround[end - 1];
	if (strchr(".!?\n", ch)) {
		/* no space yet, so no new sentence yet */
		if (end == start)
			s_pending = 1;
		else
			snprintf(prev, sizeof prev, "<s>");
		return;
	}
	for (b = end; b > 0; b--) {
		ch = (unsigned char)surround[b - 1];
		if (ch < 0x80 && !isalpha(ch) && ch != '\'' && ch != '-')
			break;
	}
	if (b < end && end - b < WORD_MAX)
		snprintf(prev, sizeof prev, "%.*s", (int)(end - b), surround + b);
}

static void
syncword(void)
{
	size_t c = MIN((size_t)cursor, strlen(surround));
	size_t start = c;
	char tmp[WORD_MAX];

	while (start > 0) {
		unsigned char ch = (unsigned char)surround[start - 1];

		if (ch < 0x80 && !isalpha(ch) && ch != '\'' && ch != '-')
			break;
		start--;
	}
	if (c - start < WORD_MAX - 1) {
		snprintf(tmp, sizeof tmp, "%.*s", (int)(c - start), surround + start);
		word[0] = 0;
		if (tmp[0] && fold_word(tmp, word, sizeof word))
			snprintf(word, sizeof word, "%s", tmp);
		else
			word[0] = 0;
	} else {
		word[0] = 0;
	}
	syncprev(start);
}

static void
im_activate(void *data, struct zwp_input_method_v2 *i)
{
	active_pending = 1;
	surround[0] = 0;
	cursor = 0;
	purpose = hint = 0;
	sur_new = 0;
}

static void
im_deactivate(void *data, struct zwp_input_method_v2 *i)
{
	active_pending = 0;
}

static void
im_surrounding(void *data, struct zwp_input_method_v2 *i, const char *t, uint32_t c, uint32_t a)
{
	snprintf(surround, sizeof surround, "%s", t);
	cursor = c;
	sur_new = 1;
}

static void im_cause(void *data, struct zwp_input_method_v2 *i, uint32_t c) {}

static void
im_content(void *data, struct zwp_input_method_v2 *i, uint32_t h, uint32_t p)
{
	hint = h;
	purpose = p;
}

/* nothing to type in: keys go out as real key presses and no word logic runs */
static void
nofield(void)
{
	hint = purpose = 0;
	setmodes();
	word[0] = 0;
	prev[0] = 0;
	undo_from[0] = 0;
	swiped[0] = 0;
	auto_space = 0;
	s_pending = 0;
	page = PAGE_ABC;
	updatesug();
	if (configured)
		build();
}

static void
sigwrite(int sig)
{
	int saved = errno;
	char c = (char)sig;

	/* a full pipe already holds a signal that will be handled */
	if (write(sig_pipe[1], &c, 1) < 0) {}
	errno = saved;
}

static void
sigread(void)
{
	char c;

	while (read(sig_pipe[0], &c, 1) == 1) {
		if (c == SIGUSR2) {
			arm(hidefd, 0, 0);
			hidekbd();
		} else if (!forced || !shown) {
			forced = 1;
			arm(hidefd, 0, 0);
			showkbd();
			if (!active)
				nofield();
		}
	}
}

static void
brconnect(void)
{
	struct sockaddr_un a = {.sun_family = AF_UNIX};

	if (br_fd >= 0 || snprintf(a.sun_path, sizeof a.sun_path, "%s/s", br_dir) >= (int)sizeof a.sun_path)
		return;
	br_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (br_fd >= 0 && connect(br_fd, (struct sockaddr *)&a, sizeof a))
		brclose();
}

/* shortcut: the IME's directory must exist when the keyboard starts, a first install counts from the next session */
static void
brsetup(void)
{
	const char *d = getenv("PHONEKBD_BRIDGE"), *h = getenv("HOME");

	if (d)
		snprintf(br_dir, sizeof br_dir, "%s", d);
	else if (h)
		snprintf(br_dir, sizeof br_dir, "%s/.local/share/waydroid/data/data/org.phonegluewc.ime/b", h);
	else
		return;
	br_ino = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
	if (br_ino >= 0 && inotify_add_watch(br_ino, br_dir, IN_CREATE) < 0) {
		close(br_ino);
		br_ino = -1;
		return;
	}
	brconnect();
}

/* a new socket means a new Android session */
static void
brnotify(void)
{
	char buf[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
	ssize_t n;
	int hit = 0;

	while ((n = read(br_ino, buf, sizeof buf)) > 0)
		for (char *p = buf; p < buf + n; p += sizeof(struct inotify_event) + ((struct inotify_event *)p)->len)
			if (((struct inotify_event *)p)->len && !strcmp(((struct inotify_event *)p)->name, "s"))
				hit = 1;
	if (hit) {
		brclose();
		brconnect();
	}
}

/* Android asked for a keyboard: s<inputType> on a tap in a field, x when no field is left */
static void
brread(void)
{
	ssize_t n = recv(br_fd, br_in + br_len, sizeof br_in - 1 - br_len, MSG_DONTWAIT);
	char *nl;

	if (n <= 0) {
		if (n == 0 || errno != EAGAIN)
			brclose();
		return;
	}
	br_len += (size_t)n;
	br_in[br_len] = 0;
	while ((nl = strchr(br_in, '\n'))) {
		*nl = 0;
		if (br_in[0] == 's' && focus_droid && !active) {
			int cls = atoi(br_in + 1) & 0xf;

			if (!forced || !shown) {
				forced = 1;
				arm(hidefd, 0, 0);
				showkbd();
				nofield();
			}
			droidh();
			/* number, phone and date fields */
			if (cls >= 2 && cls <= 4) {
				page = PAGE_SYM;
				if (configured)
					build();
			}
		} else if (br_in[0] == 'x' && focus_droid && forced && !active) {
			hidekbd();
		}
		br_len -= (size_t)(nl + 1 - br_in);
		memmove(br_in, nl + 1, br_len + 1);
	}
	if (br_len == sizeof br_in - 1)
		br_len = 0;
}

static void
top_appid(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, const char *id)
{
	zwlr_foreign_toplevel_handle_v1_set_user_data(h, (void *)(intptr_t)!strncasecmp(id, "waydroid", 8));
}

static void
top_state(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_array *st)
{
	uint32_t *s;
	int on = 0;

	wl_array_for_each(s, st)
		on |= *s == ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED;
	if (on)
		focus_top = h;
	else if (focus_top == h)
		focus_top = NULL;
}

static void
top_done(void *data, struct zwlr_foreign_toplevel_handle_v1 *h)
{
	int was = todroid();

	focus_droid = focus_top && zwlr_foreign_toplevel_handle_v1_get_user_data(focus_top);
	if (layer && was != todroid()) {
		zwlr_layer_surface_v1_set_exclusive_zone(layer, zone());
		wl_surface_commit(surf);
		droidh();
	}
}

static void
top_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *h)
{
	if (focus_top == h) {
		focus_top = NULL;
		focus_droid = 0;
	}
	zwlr_foreign_toplevel_handle_v1_destroy(h);
}

static void top_title(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, const char *t) {}
static void top_output(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct wl_output *o) {}
static void top_parent(void *data, struct zwlr_foreign_toplevel_handle_v1 *h, struct zwlr_foreign_toplevel_handle_v1 *p) {}
static const struct zwlr_foreign_toplevel_handle_v1_listener top_listener = {
	top_title, top_appid, top_output, top_output, top_state, top_done, top_closed, top_parent,
};

static void
ftl_toplevel(void *data, struct zwlr_foreign_toplevel_manager_v1 *m, struct zwlr_foreign_toplevel_handle_v1 *h)
{
	zwlr_foreign_toplevel_handle_v1_add_listener(h, &top_listener, NULL);
}

static void ftl_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *m) {}
static const struct zwlr_foreign_toplevel_manager_v1_listener ftl_listener = {ftl_toplevel, ftl_finished};

static void
im_done(void *data, struct zwp_input_method_v2 *i)
{
	int was = active;

	done_serial++;
	active = active_pending;
	if (active)
		setmodes();
	if (active && !was) {
		arm(hidefd, 0, 0);
		showkbd();
		closepanel();
		word[0] = 0;
		undo_from[0] = 0;
		swiped[0] = 0;
		auto_space = 0;
		dbl_time = 0;
		snprintf(prev, sizeof prev, "%s", secret || !plain ? "" : "<s>");
		s_pending = 0;
		if (purpose == P_DIGITS || purpose == P_NUMBER || purpose == P_PHONE || purpose == P_PIN)
			page = PAGE_SYM;
		else
			page = PAGE_ABC;
		if (sur_new && plain)
			syncword();
		updatesug();
		if ((int)wantheight() != height && height)
			resize();
		else if (configured)
			build();
	} else if (!active && was) {
		if (forced)
			nofield();
		else
			arm(hidefd, HIDE_MS, 0);
		/* a modifier never outlives the field it was meant for */
		clearmods();
	} else if (active && shown && sur_new && plain && now_ms() - last_key > SYNC_MS) {
		/* the cursor moved by itself, for instance a tap elsewhere in the field */
		syncword();
		undo_from[0] = 0;
		swiped[0] = 0;
		auto_space = 0;
		updatesug();
	}
	sur_new = 0;
}

static void
im_unavailable(void *data, struct zwp_input_method_v2 *i)
{
	fprintf(stderr, "phonekbd: another input method is running\n");
	exit(1);
}

static const struct zwp_input_method_v2_listener im_listener = {
	im_activate, im_deactivate, im_surrounding, im_cause, im_content, im_done, im_unavailable,
};

/* --- startup --- */
static void
reg_global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver)
{
	if (!strcmp(iface, wl_compositor_interface.name))
		compositor = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	else if (!strcmp(iface, wl_shm_interface.name))
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	else if (!strcmp(iface, wl_seat_interface.name) && !seat) {
		seat = wl_registry_bind(r, name, &wl_seat_interface, MIN(ver, 5));
		wl_seat_add_listener(seat, &seat_listener, NULL);
	} else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name))
		layer_shell = wl_registry_bind(r, name, &zwlr_layer_shell_v1_interface, MIN(ver, 4));
	else if (!strcmp(iface, zwp_input_method_manager_v2_interface.name))
		im_mgr = wl_registry_bind(r, name, &zwp_input_method_manager_v2_interface, 1);
	else if (!strcmp(iface, zwp_virtual_keyboard_manager_v1_interface.name))
		vk_mgr = wl_registry_bind(r, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
	else if (!strcmp(iface, wp_fractional_scale_manager_v1_interface.name))
		frac_mgr = wl_registry_bind(r, name, &wp_fractional_scale_manager_v1_interface, 1);
	else if (!strcmp(iface, wp_viewporter_interface.name))
		viewporter = wl_registry_bind(r, name, &wp_viewporter_interface, 1);
	else if (!strcmp(iface, zwlr_data_control_manager_v1_interface.name))
		dc_mgr = wl_registry_bind(r, name, &zwlr_data_control_manager_v1_interface, MIN(ver, 2));
	else if (!strcmp(iface, zwlr_foreign_toplevel_manager_v1_interface.name)) {
		ftl_mgr = wl_registry_bind(r, name, &zwlr_foreign_toplevel_manager_v1_interface, MIN(ver, 3));
		zwlr_foreign_toplevel_manager_v1_add_listener(ftl_mgr, &ftl_listener, NULL);
	}
}
static void reg_remove(void *data, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener reg_listener = {reg_global, reg_remove};

static void
statedir(void)
{
	const char *x = getenv("XDG_STATE_HOME"), *h = getenv("HOME");
	char base[480];

	if (x && *x)
		snprintf(base, sizeof base, "%s", x);
	else
		snprintf(base, sizeof base, "%s/.local/state", h ? h : "/tmp");
	snprintf(state_dir, sizeof state_dir, "%s/phonekbd", base);
	mkdir(base, 0700);
	mkdir(state_dir, 0700);
	chmod(state_dir, 0700);
}

static void
timer_fired(void)
{
	uint64_t n;

	if (read(timerfd, &n, sizeof n) != sizeof n || timer_slot < 0)
		return;
	if (rep_on) {
		const Key copy = rep_key;

		if (slots[timer_slot].used)
			slots[timer_slot].fired = 1;
		held_mods = rep_mods;
		fire(&copy);
		held_mods = 0;
		return;
	}
	if (!slots[timer_slot].used)
		return;
	if (slots[timer_slot].drag == D_GRID) {
		if (slots[timer_slot].tile >= 0)
			openemojipopup(timer_slot);
		if (popup_slot < 0)
			timer_slot = -1;
		return;
	}
	if (slots[timer_slot].key < 0)
		return;
	if (!slots[timer_slot].swiping) {
		openpopup(timer_slot);
		if (popup_slot < 0)
			timer_slot = -1;
	}
}

static int
stampfile(const char *name)
{
	char p[600];
	FILE *f;

	snprintf(p, sizeof p, "%s/%s", state_dir, name);
	if (!(f = fopen(p, "w")) || fclose(f))
		return 1;
	return utimensat(AT_FDCWD, p, NULL, 0) != 0;
}

/* for the settings page: forgets what the keyboard learned, also for a keyboard running right now */
static int
clearlearned(void)
{
	static const char *const names[] = {"learned.tsv", "bigrams.tsv", "emoji-recent"};
	char p[600];

	statedir();
	for (size_t i = 0; i < LEN(names); i++) {
		snprintf(p, sizeof p, "%s/%s", state_dir, names[i]);
		if (unlink(p) && errno != ENOENT)
			return 1;
	}
	return stampfile("cleared") || stampfile("emoji-cleared");
}

static int
clearemoji(void)
{
	char p[600];

	statedir();
	snprintf(p, sizeof p, "%s/emoji-recent", state_dir);
	if (unlink(p) && errno != ENOENT)
		return 1;
	return stampfile("emoji-cleared");
}

/* shortcut: a hidden keyboard wipes on its next show or copy, signal it if that gap ever matters */
static int
clearclipboard(void)
{
	statedir();
	return stampfile("clipboard-cleared");
}

int
main(int argc, char **argv)
{
	struct wl_registry *reg;
	struct pollfd fds[10];
	struct sigaction sa = {.sa_handler = sigwrite, .sa_flags = SA_RESTART};

	if (argc > 1 && !strcmp(argv[1], "--clear-learned"))
		return clearlearned();
	if (argc > 1 && !strcmp(argv[1], "--clear-emoji-history"))
		return clearemoji();
	if (argc > 1 && !strcmp(argv[1], "--clear-clipboard-history"))
		return clearclipboard();
	/* the compositor may signal as soon as it has spawned this */
	if (pipe2(sig_pipe, O_CLOEXEC | O_NONBLOCK))
		return 1;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGUSR1, &sa, NULL);
	sigaction(SIGUSR2, &sa, NULL);
	if (!(dpy = wl_display_connect(NULL))) {
		fprintf(stderr, "phonekbd: no wayland display\n");
		return 1;
	}
	statedir();
	loadlayout();
	timerfd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
	hidefd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
	tr_timer = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
	signal(SIGPIPE, SIG_IGN);
	reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &reg_listener, NULL);
	wl_display_roundtrip(dpy);
	if (!compositor || !shm || !seat || !layer_shell || !im_mgr || !vk_mgr) {
		fprintf(stderr, "phonekbd: the compositor lacks a protocol this keyboard needs\n");
		return 1;
	}
	im = zwp_input_method_manager_v2_get_input_method(im_mgr, seat);
	zwp_input_method_v2_add_listener(im, &im_listener, NULL);
	setupvk();
	loadconfig();
	if (dc_mgr) {
		dc_dev = zwlr_data_control_manager_v1_get_data_device(dc_mgr, seat);
		zwlr_data_control_device_v1_add_listener(dc_dev, &dc_listener, NULL);
	}
	wl_display_roundtrip(dpy);
	brsetup();

	fds[0] = (struct pollfd){wl_display_get_fd(dpy), POLLIN, 0};
	fds[1] = (struct pollfd){timerfd, POLLIN, 0};
	fds[2] = (struct pollfd){hidefd, POLLIN, 0};
	fds[7] = (struct pollfd){sig_pipe[0], POLLIN, 0};
	for (;;) {
		flushdraw();
		fds[3] = (struct pollfd){clip_fd, POLLIN, 0};
		fds[4] = (struct pollfd){tr_fd, POLLIN, 0};
		fds[5] = (struct pollfd){tr_timer, POLLIN, 0};
		fds[6] = (struct pollfd){lr_fd, POLLIN, 0};
		fds[8] = (struct pollfd){br_ino, POLLIN, 0};
		fds[9] = (struct pollfd){br_fd, POLLIN, 0};
		while (wl_display_prepare_read(dpy) != 0)
			wl_display_dispatch_pending(dpy);
		wl_display_flush(dpy);
		if (poll(fds, LEN(fds), -1) < 0) {
			if (errno != EINTR) {
				wl_display_cancel_read(dpy);
				break;
			}
			/* a signal: nothing is ready, and the last round's results must not count again */
			for (size_t f = 0; f < LEN(fds); f++)
				fds[f].revents = 0;
		}
		if (fds[0].revents & POLLIN) {
			if (wl_display_read_events(dpy) < 0)
				break;
		} else {
			wl_display_cancel_read(dpy);
		}
		if (fds[0].revents & (POLLHUP | POLLERR))
			break;
		if (wl_display_dispatch_pending(dpy) < 0)
			break;
		if (fds[1].revents & POLLIN)
			timer_fired();
		if (clip_fd >= 0 && fds[3].fd == clip_fd && (fds[3].revents & (POLLIN | POLLHUP)))
			clipread();
		if (fds[5].revents & POLLIN) {
			uint64_t n;

			if (read(tr_timer, &n, sizeof n) == sizeof n && panel == PANEL_TRANS && tr_pending)
				trstart();
		}
		if (tr_fd >= 0 && fds[4].fd == tr_fd && (fds[4].revents & (POLLIN | POLLHUP)))
			trread();
		if (lr_fd >= 0 && fds[6].fd == lr_fd && (fds[6].revents & (POLLIN | POLLHUP)))
			lrread();
		if (fds[2].revents & POLLIN) {
			uint64_t n;

			if (read(hidefd, &n, sizeof n) == sizeof n && !active && !forced)
				hidekbd();
		}
		if (fds[7].revents & POLLIN)
			sigread();
		if (br_ino >= 0 && (fds[8].revents & POLLIN))
			brnotify();
		if (br_fd >= 0 && fds[9].fd == br_fd && fds[9].revents)
			brread();
	}
	return 0;
}
