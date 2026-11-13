/* phonetext: read, select and translate the text on a frozen screen. Starts on demand, exits afterwards.
 * Offline: nothing leaves the device unless the user taps Search; nothing is written to disk. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <wayland-client.h>
#include "viewporter-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "wlr-screencopy-unstable-v1-client-protocol.h"
#include "ocr.h"

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define LEN(a) (sizeof(a) / sizeof(*(a)))

#define SEARCH_URL "https://www.google.com/search?q="
#define SETTLE_MS 250 /* the keyboard hides and the app settles before the freeze */
#define BAR_ZONE 26.f /* the compositor's bar at the bottom */
#define BAR_H 52.f
#define BAR_GAP 10.f
#define BTN_PAD 18.f
#define TAP_SLOP 10.f
#define FONT_SIZE 15.f

#define BLACK 0xff000000u
#define WHITE 0xffffffffu
#define DIM 0xff9a9a9au
#define ACCENT 0xffd71921u

enum { S_WAIT, S_READING, S_READY, S_FAILED };
enum { ACT_COPY, ACT_SEARCH, ACT_TRANSLATE, ACT_ORIGINAL };
enum { T_NONE, T_BAR, T_BTN, T_SEL, T_TAP };

typedef struct {
	struct wl_buffer *buf;
	uint32_t *data;
	int busy;
} Buffer;

typedef struct {
	const char *label;
	int act;
	float x, w;
} Btn;

static struct wl_display *dpy;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct wl_touch *touch;
static struct wl_output *output;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct zwlr_screencopy_manager_v1 *copy_mgr;
static struct wp_viewporter *viewporter;

static struct wl_surface *surf;
static struct zwlr_layer_surface_v1 *layer;
static struct wp_viewport *viewport;
static struct wl_callback *frame_cb;
static struct wl_buffer *clear_buf;

static struct zwlr_screencopy_frame_v1 *frame;
static uint32_t *cap;
static uint32_t cap_format, cap_stride;
static size_t cap_size;
static struct wl_buffer *cap_buf;
static int cap_invert;

static Buffer buffers[2];
static uint32_t *shot;
static uint32_t *px;
static int bw, bh;
static int width, height;
static float sc = 1;
static FT_Library ft;
static FT_Face face;

#include "../keyboard/draw.h"

static int quit, dirty, state = S_WAIT;
static const char *message;
static Ocr ocr;
static int sel_a = -1, sel_b = -1, copied;
static int translated, have_translation, translating;

static pid_t child;
static int child_fd = -1;
static char *child_out;
static size_t child_len, child_cap;
static long child_start;

static int timerfd;
static int touch_id = -1, touch_mode, touch_press = -1, touch_moved;
static float down_x, down_y;

static FILE *dump;

static long
now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static int
memfd_with(const void *data, size_t n)
{
	int fd = memfd_create("phonetext", MFD_CLOEXEC);
	const char *p = data;

	if (fd < 0)
		return -1;
	while (n) {
		ssize_t w = write(fd, p, n);

		if (w <= 0) {
			close(fd);
			return -1;
		}
		p += w;
		n -= (size_t)w;
	}
	lseek(fd, 0, SEEK_SET);
	return fd;
}

/* the input lives in a memfd, so no temp file holds screen content */
static int
childio(int infd, int outfd)
{
	int null = open("/dev/null", O_RDWR | O_CLOEXEC);

	if (null < 0 || dup2(infd >= 0 ? infd : null, 0) < 0 || dup2(outfd >= 0 ? outfd : null, 1) < 0 || dup2(null, 2) < 0)
		return -1;
	return 0;
}

static int
startchild(char *const argv[], const void *in, size_t n)
{
	int infd = memfd_with(in, n), out[2];

	if (infd < 0 || pipe2(out, O_CLOEXEC) < 0)
		return -1;
	child = fork();
	if (child < 0)
		return -1;
	if (!child) {
		prctl(PR_SET_PDEATHSIG, SIGKILL);
		if (childio(infd, out[1]) < 0)
			_exit(127);
		execvp(argv[0], argv);
		_exit(127);
	}
	close(infd);
	close(out[1]);
	child_fd = out[0];
	child_len = 0;
	child_start = now_ms();
	return 0;
}

/* wl-copy forks to hold the clipboard, so its first process returns at once */
static int
runwait(char *const argv[], const char *in)
{
	int infd = memfd_with(in, strlen(in)), status = 1;
	pid_t p;

	if (infd < 0 || (p = fork()) < 0)
		return -1;
	if (!p) {
		setsid();
		if (childio(infd, -1) < 0)
			_exit(127);
		execvp(argv[0], argv);
		_exit(127);
	}
	close(infd);
	waitpid(p, &status, 0);
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/* the browser must outlive us */
static void
rundetached(char *const argv[])
{
	pid_t p = fork();

	if (p < 0)
		return;
	if (!p) {
		setsid();
		if (fork() > 0)
			_exit(0);
		if (childio(-1, -1) < 0)
			_exit(127);
		execvp(argv[0], argv);
		_exit(127);
	}
	waitpid(p, NULL, 0);
}

static void
dumpusage(const char *what, long ms)
{
	struct rusage u, c;

	if (!dump)
		return;
	getrusage(RUSAGE_SELF, &u);
	getrusage(RUSAGE_CHILDREN, &c);
	fprintf(dump, "state %s ms=%ld self_kb=%ld child_kb=%ld\n", what, ms, u.ru_maxrss, c.ru_maxrss);
	fflush(dump);
}

/* --- reading --- */
static void
startocr(void)
{
	static char *argv[] = {"tesseract", "stdin", "stdout", "-l", "ron+eng", "--dpi", "300", "--oem", "1", "--psm", "3",
		"-c", "tessedit_create_tsv=1", NULL};
	char head[64];
	int hl = snprintf(head, sizeof head, "P5\n%d %d\n255\n", bw, bh);
	size_t size = (size_t)bw * (size_t)bh;
	unsigned char *img = malloc((size_t)hl + size), *q;
	uint64_t sum = 0;

	if (!img)
		goto fail;
	memcpy(img, head, (size_t)hl);
	q = img + hl;
	for (size_t i = 0; i < size; i++) {
		uint32_t c = shot[i];

		q[i] = (unsigned char)(((c >> 16 & 255) * 77 + (c >> 8 & 255) * 150 + (c & 255) * 29) >> 8);
		sum += q[i];
	}
	/* tesseract reads dark on light best */
	if (sum / size < 110)
		for (size_t i = 0; i < size; i++)
			q[i] = (unsigned char)(255 - q[i]);
	if (startchild(argv, img, (size_t)hl + size) < 0) {
		free(img);
		goto fail;
	}
	free(img);
	state = S_READING;
	return;
fail:
	state = S_FAILED;
	message = "Could not read this screen";
}

/* the ring around a paragraph tells what to paint it with */
static void
blockcolors(OcrBlock *b)
{
	uint64_t r = 0, g = 0, l = 0, n = 0;
	int x0 = MAX(b->x - 6, 0), y0 = MAX(b->y - 6, 0), x1 = MIN(b->x + b->w + 5, bw - 1), y1 = MIN(b->y + b->h + 5, bh - 1);

	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			uint32_t c;

			if (y != y0 && y != y1 && x != x0 && x != x1)
				continue;
			c = shot[y * bw + x];
			r += c >> 16 & 255;
			g += c >> 8 & 255;
			l += c & 255;
			n++;
		}
	}
	if (!n)
		n = 1;
	r /= n;
	g /= n;
	l /= n;
	b->bg = BLACK | (unsigned)r << 16 | (unsigned)g << 8 | (unsigned)l;
	b->fg = r * 77 + g * 150 + l * 29 > 128 * 256 ? BLACK : WHITE;
}

static void
ocrdone(int status, long ms)
{
	if (!WIFEXITED(status) || WEXITSTATUS(status)) {
		state = S_FAILED;
		message = WIFEXITED(status) && WEXITSTATUS(status) == 127
			? "Install tesseract to read text" : "Install tesseract's ron and eng data";
		return;
	}
	if (ocr_parse(&ocr, child_out ? child_out : "") < 0) {
		state = S_FAILED;
		message = "Could not read this screen";
		return;
	}
	if (!ocr.nwords) {
		state = S_FAILED;
		message = "No text on this screen";
		return;
	}
	for (int i = 0; i < ocr.nblocks; i++)
		blockcolors(&ocr.blocks[i]);
	state = S_READY;
	if (dump) {
		for (int i = 0; i < ocr.nwords; i++) {
			OcrWord *w = &ocr.words[i];

			fprintf(dump, "word %d %d %d %d %d %s\n", (int)((float)w->x / sc), (int)((float)w->y / sc), (int)((float)w->w / sc),
				(int)((float)w->h / sc), w->block, ocr.text + w->text);
		}
		dumpusage("ready", ms);
	}
}

static void
starttranslate(void)
{
	char *in = ocr_blocks_text(&ocr);
	int ro = ocr_language(&ocr) == 'r';
	char *argv[] = {"phonetext-translate", ro ? "ro" : "en", ro ? "en" : "ro", NULL};

	if (!in || startchild(argv, in, strlen(in)) < 0) {
		message = "Could not start translation";
	} else {
		translating = 1;
		message = NULL;
	}
	free(in);
}

static void
translatedone(int status, long ms)
{
	char *p = child_out;
	int n = 0;

	translating = 0;
	if (!WIFEXITED(status) || WEXITSTATUS(status)) {
		message = WIFEXITED(status) && WEXITSTATUS(status) == 127
			? "Add a language in the keyboard's Translate panel" : "Translation failed";
		return;
	}
	for (char *c = p; c && *c; c++)
		n += *c == '\n';
	if (n != ocr.nblocks) {
		message = "Translation failed";
		return;
	}
	for (int i = 0; i < ocr.nblocks; i++) {
		char *e = strchr(p, '\n');

		*e = 0;
		free(ocr.blocks[i].dst);
		ocr.blocks[i].dst = strdup(p);
		if (dump)
			fprintf(dump, "dst %d %s\n", i, p);
		p = e + 1;
	}
	have_translation = translated = 1;
	dumpusage("translated", ms);
}

static void
childread(void)
{
	ssize_t r;
	int status = 0;
	long ms;
	pid_t pid = child;

	if (child_cap - child_len < 65536) {
		char *n = realloc(child_out, child_cap + 262144);

		if (!n) {
			kill(child, SIGKILL);
			quit = 1;
			return;
		}
		child_out = n;
		child_cap += 262144;
	}
	r = read(child_fd, child_out + child_len, child_cap - child_len - 1);
	if (r > 0) {
		child_len += (size_t)r;
		return;
	}
	if (r < 0 && errno == EINTR)
		return;
	close(child_fd);
	child_fd = -1;
	child_out[child_len] = 0;
	waitpid(pid, &status, 0);
	child = 0;
	ms = now_ms() - child_start;
	if (state == S_READING) {
		ocrdone(status, ms);
		if (dump && state == S_FAILED) {
			fprintf(dump, "message %s\n", message);
			fflush(dump);
		}
	} else {
		translatedone(status, ms);
		if (dump && message) {
			fprintf(dump, "message %s\n", message);
			fflush(dump);
		}
	}
	free(child_out);
	child_out = NULL;
	child_cap = child_len = 0;
	dirty = 1;
}

/* --- drawing --- */
static void
tint(int x, int y, int w, int h, uint32_t col, float a)
{
	for (int j = MAX(y, 0); j < MIN(y + h, bh); j++)
		for (int i = MAX(x, 0); i < MIN(x + w, bw); i++)
			blend(i, j, col, a);
}

static void
drawselection(void)
{
	int a = MIN(sel_a, sel_b), b = MAX(sel_a, sel_b), pad = (int)(2 * sc);

	if (a < 0)
		return;
	/* a run along one line reads as one highlight, not separate words */
	for (int i = a; i <= b;) {
		const OcrWord *w = &ocr.words[i];
		int x = w->x, y = w->y, r = w->x + w->w, d = w->y + w->h, k = i + 1;

		while (k <= b && ocr.words[k].block == w->block && ocr.words[k].line == w->line) {
			const OcrWord *n = &ocr.words[k++];

			y = MIN(y, n->y);
			r = MAX(r, n->x + n->w);
			d = MAX(d, n->y + n->h);
		}
		tint(x - pad, y - pad, r - x + 2 * pad, d - y + 2 * pad, ACCENT, 0.42f);
		i = k;
	}
}

/* splits into lines at spaces; counts lines, and draws them when told to */
static int
wrap(const char *s, float x, float y, float w, float size, float lh, uint32_t col, int draw)
{
	char line[1024], cand[1024];
	int lines = 0;

	line[0] = 0;
	while (*s) {
		const char *e = strchr(s, ' ');
		size_t n = e ? (size_t)(e - s) : strlen(s);

		snprintf(cand, sizeof cand, "%s%s%.*s", line, *line ? " " : "", (int)n, s);
		if (*line && textw(cand, size) > w) {
			if (draw)
				text(line, x + textw(line, size) / 2, y + lh * ((float)lines + 0.5f), size, 0, col);
			lines++;
			snprintf(line, sizeof line, "%.*s", (int)n, s);
		} else {
			memcpy(line, cand, sizeof line);
		}
		s += n;
		while (*s == ' ')
			s++;
	}
	if (*line) {
		if (draw)
			text(line, x + textw(line, size) / 2, y + lh * ((float)lines + 0.5f), size, 0, col);
		lines++;
	}
	return lines;
}

static void
drawtranslation(void)
{
	for (int i = 0; i < ocr.nblocks; i++) {
		const OcrBlock *b = &ocr.blocks[i];
		float x = (float)b->x / sc, y = (float)b->y / sc, w = (float)b->w / sc, h = (float)b->h / sc;
		int nl = ocr.words[b->last].line - ocr.words[b->first].line + 1;
		float size = h / (float)nl * 0.82f, lh;

		/* numbers and names come back the same; the original looks better */
		if (!b->dst || !*b->dst || !strcmp(b->dst, b->src))
			continue;
		w = MAX(w, MIN((float)width - x - 8, 60.f));
		size = MAX(size, 10.f);
		while (size > 10 && (float)wrap(b->dst, 0, 0, w, size, size * 1.22f, 0, 0) * size * 1.22f > h + 4)
			size -= 0.5f;
		lh = size * 1.22f;
		rrect(x - 3, y - 3, w + 6, MAX(h, (float)wrap(b->dst, 0, 0, w, size, lh, 0, 0) * lh) + 6, 4, b->bg);
		wrap(b->dst, x, y, w, size, lh, b->fg, 1);
	}
}

static int
barbuttons(Btn *out, const char **label)
{
	int n = 0, hassel = sel_a >= 0;

	*label = message;
	if (state == S_READY) {
		if (hassel && !translated) {
			out[n++] = (Btn){copied ? "Copied" : "Copy", ACT_COPY, 0, 0};
			out[n++] = (Btn){"Search", ACT_SEARCH, 0, 0};
		}
		if (translating)
			*label = "Translating";
		else if (translated)
			out[n++] = (Btn){"Original", ACT_ORIGINAL, 0, 0};
		else
			out[n++] = (Btn){"Translate all", ACT_TRANSLATE, 0, 0};
		if (!hassel && !translating && !message && !translated)
			*label = "Drag over text";
	} else if (state == S_READING) {
		*label = "Reading text";
	}
	return n;
}

static float
barlayout(Btn *btn, int n, const char *label, float *lw)
{
	float total = 0, x;

	*lw = label ? textw(label, FONT_SIZE) + (state == S_READING || translating ? 34.f : 2 * BTN_PAD) : 0;
	total = 0;
	for (int i = 0; i < n; i++) {
		btn[i].w = MAX(textw(btn[i].label, FONT_SIZE) + 2 * BTN_PAD, 64.f);
		total += btn[i].w;
	}
	/* the buttons must stay on screen: a message that does not fit gives way */
	if (n && total + *lw > (float)width - 16)
		*lw = 0;
	total += *lw;
	x = ((float)width - total) / 2 + *lw;
	for (int i = 0; i < n; i++) {
		btn[i].x = x;
		x += btn[i].w;
	}
	return total;
}

static float
bary(void)
{
	return (float)height - BAR_ZONE - BAR_GAP - BAR_H;
}

static void
drawbar(void)
{
	Btn btn[3];
	const char *label;
	int n = barbuttons(btn, &label);
	float lw, total = barlayout(btn, n, label, &lw), y = bary(), x;

	if (total <= 0)
		return;
	x = ((float)width - total) / 2;
	/* a hairline keeps the black bar visible on black screens */
	rrect(x - 1, y - 1, total + 2, BAR_H + 2, BAR_H / 2 + 1, 0xff3a3a3au);
	rrect(x, y, total, BAR_H, BAR_H / 2, BLACK);
	if (label && lw > 0) {
		int busy = state == S_READING || translating;

		if (busy)
			rrect(x + 16, y + BAR_H / 2 - 4, 8, 8, 4, ACCENT);
		text(label, x + (busy ? 34.f + (lw - 34.f) / 2 - 8 : lw / 2), y + BAR_H / 2, FONT_SIZE, 0, n ? DIM : WHITE);
	}
	for (int i = 0; i < n; i++) {
		int on = touch_mode == T_BTN && touch_press == i;

		if (on)
			rrect(btn[i].x + 3, y + 3, btn[i].w - 6, BAR_H - 6, BAR_H / 2 - 3, WHITE);
		text(btn[i].label, btn[i].x + btn[i].w / 2, y + BAR_H / 2, FONT_SIZE, 0, on ? BLACK : WHITE);
	}
}

static void buffer_release(void *data, struct wl_buffer *b) { ((Buffer *)data)->busy = 0; }
static const struct wl_buffer_listener buffer_listener = {buffer_release};

static void
frame_done(void *data, struct wl_callback *cb, uint32_t t)
{
	wl_callback_destroy(cb);
	frame_cb = NULL;
}
static const struct wl_callback_listener frame_listener = {frame_done};

static void
flushdraw(void)
{
	Buffer *b = NULL;

	if (!dirty || frame_cb || !shot)
		return;
	for (size_t i = 0; i < LEN(buffers); i++)
		if (!buffers[i].busy)
			b = &buffers[i];
	if (!b)
		return;
	px = b->data;
	memcpy(px, shot, (size_t)bw * (size_t)bh * 4);
	if (state == S_READING) {
		for (size_t i = 0, n = (size_t)bw * (size_t)bh; i < n; i++)
			px[i] = BLACK | (px[i] >> 1 & 0x7f7f7fu);
	} else if (translated) {
		drawtranslation();
	} else if (state == S_READY) {
		drawselection();
	}
	drawbar();
	b->busy = 1;
	wl_surface_attach(surf, b->buf, 0, 0);
	wl_surface_damage_buffer(surf, 0, 0, bw, bh);
	frame_cb = wl_surface_frame(surf);
	wl_callback_add_listener(frame_cb, &frame_listener, NULL);
	wl_surface_commit(surf);
	dirty = 0;
}

/* --- freezing --- */
static struct wl_buffer *
shmbuffer(int w, int h, int stride, uint32_t format, uint32_t **data)
{
	size_t size = (size_t)stride * (size_t)h;
	int fd = memfd_create("phonetext", MFD_CLOEXEC);
	struct wl_shm_pool *pool;
	struct wl_buffer *buf;
	void *m;

	if (fd < 0 || ftruncate(fd, (off_t)size) < 0)
		return NULL;
	m = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (m == MAP_FAILED) {
		close(fd);
		return NULL;
	}
	pool = wl_shm_create_pool(shm, fd, (int32_t)size);
	buf = wl_shm_pool_create_buffer(pool, 0, w, h, stride, format);
	wl_shm_pool_destroy(pool);
	close(fd);
	*data = m;
	return buf;
}

static void
frozen(void)
{
	sc = (float)bw / (float)width;
	if (!(shot = malloc((size_t)bw * (size_t)bh * 4)))
		exit(1);
	for (int y = 0; y < bh; y++) {
		const uint32_t *row = (const uint32_t *)((const char *)cap + (size_t)cap_stride * (size_t)(cap_invert ? bh - 1 - y : y));

		for (int x = 0; x < bw; x++) {
			uint32_t c = row[x];

			if (cap_format == WL_SHM_FORMAT_XBGR8888 || cap_format == WL_SHM_FORMAT_ABGR8888)
				c = (c & 0xff00u) | (c & 0xffu) << 16 | (c >> 16 & 0xffu);
			shot[y * bw + x] = BLACK | c;
		}
	}
	munmap(cap, cap_size);
	wl_buffer_destroy(cap_buf);
	cap = NULL;
	for (size_t i = 0; i < LEN(buffers); i++) {
		buffers[i].buf = shmbuffer(bw, bh, bw * 4, WL_SHM_FORMAT_ARGB8888, &buffers[i].data);
		if (!buffers[i].buf)
			exit(1);
		wl_buffer_add_listener(buffers[i].buf, &buffer_listener, &buffers[i]);
	}
	startocr();
	dirty = 1;
}

static void
frame_buffer(void *data, struct zwlr_screencopy_frame_v1 *f, uint32_t format, uint32_t w, uint32_t h, uint32_t stride)
{
	cap_format = format;
	cap_stride = stride;
	cap_size = (size_t)stride * h;
	bw = (int)w;
	bh = (int)h;
	if (!(cap_buf = shmbuffer((int)w, (int)h, (int)stride, format, &cap)))
		exit(1);
	zwlr_screencopy_frame_v1_copy(f, cap_buf);
}

static void
frame_flags(void *data, struct zwlr_screencopy_frame_v1 *f, uint32_t flags)
{
	cap_invert = flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT;
}

static void
frame_ready(void *data, struct zwlr_screencopy_frame_v1 *f, uint32_t a, uint32_t b, uint32_t c)
{
	zwlr_screencopy_frame_v1_destroy(f);
	frame = NULL;
	frozen();
}

static void
frame_failed(void *data, struct zwlr_screencopy_frame_v1 *f)
{
	quit = 1;
}
static const struct zwlr_screencopy_frame_v1_listener frame_listener2 = {
	.buffer = frame_buffer, .flags = frame_flags, .ready = frame_ready, .failed = frame_failed,
};

static void
layer_configure(void *data, struct zwlr_layer_surface_v1 *l, uint32_t serial, uint32_t w, uint32_t h)
{
	zwlr_layer_surface_v1_ack_configure(l, serial);
	if (width)
		return;
	width = (int)w;
	height = (int)h;
	wp_viewport_set_destination(viewport, width, height);
	/* see-through until the freeze, so the capture shows the apps and takes focus from them first */
	{
		uint32_t *d;

		if (!(clear_buf = shmbuffer(1, 1, 4, WL_SHM_FORMAT_ARGB8888, &d)))
			exit(1);
		*d = 0;
	}
	wl_surface_attach(surf, clear_buf, 0, 0);
	wl_surface_damage_buffer(surf, 0, 0, 1, 1);
	wl_surface_commit(surf);
	timerfd_settime(timerfd, 0, &(struct itimerspec){.it_value = {SETTLE_MS / 1000, (long)(SETTLE_MS % 1000) * 1000000}}, NULL);
}

static void
layer_closed(void *data, struct zwlr_layer_surface_v1 *l)
{
	quit = 1;
}
static const struct zwlr_layer_surface_v1_listener layer_listener = {layer_configure, layer_closed};

/* --- actions --- */
static void
act(int action)
{
	char *s = sel_a >= 0 ? ocr_selection(&ocr, sel_a, sel_b) : NULL;

	switch (action) {
	case ACT_COPY:
		if (s) {
			char *argv[] = {"wl-copy", NULL};
			int r = runwait(argv, s);

			copied = !r;
			message = r ? "Install wl-clipboard to copy" : NULL;
		}
		break;
	case ACT_SEARCH:
		if (s) {
			char *q = url_encode(s), *url = NULL;

			for (char *c = q; c && *c; c++)
				if (c[0] == '%' && c[1] == '0' && c[2] == 'A')
					c[1] = '2', c[2] = '0';
			if (q && asprintf(&url, "%s%s", SEARCH_URL, q) >= 0) {
				char *argv[] = {"xdg-open", url, NULL};

				rundetached(argv);
				free(url);
			}
			free(q);
			quit = 1;
		}
		break;
	case ACT_TRANSLATE:
		sel_a = sel_b = -1;
		if (have_translation)
			translated = 1;
		else if (!translating)
			starttranslate();
		break;
	case ACT_ORIGINAL:
		translated = 0;
		break;
	}
	free(s);
	dirty = 1;
}

/* --- touch --- */
static int
btnat(float x, float y)
{
	Btn btn[3];
	const char *label;
	int n = barbuttons(btn, &label);
	float lw;

	barlayout(btn, n, label, &lw);
	if (y < bary() || y > bary() + BAR_H)
		return -1;
	for (int i = 0; i < n; i++)
		if (x >= btn[i].x && x < btn[i].x + btn[i].w)
			return i;
	return -1;
}

static int
onblock(float x, float y)
{
	int ix = (int)(x * sc), iy = (int)(y * sc);

	for (int i = 0; i < ocr.nblocks; i++) {
		const OcrBlock *b = &ocr.blocks[i];

		if (ix >= b->x && ix < b->x + b->w && iy >= b->y && iy < b->y + b->h)
			return 1;
	}
	return 0;
}

static void
touch_down(void *data, struct wl_touch *t, uint32_t serial, uint32_t time, struct wl_surface *s, int32_t id, wl_fixed_t fx, wl_fixed_t fy)
{
	float x = (float)wl_fixed_to_double(fx), y = (float)wl_fixed_to_double(fy);

	if (touch_id >= 0 || !shot)
		return;
	touch_id = id;
	down_x = x;
	down_y = y;
	touch_moved = 0;
	touch_press = btnat(x, y);
	if (y >= (float)height - BAR_ZONE) {
		touch_mode = T_BAR;
	} else if (touch_press >= 0) {
		touch_mode = T_BTN;
		dirty = 1;
	} else if (state == S_READY && !translated) {
		touch_mode = T_SEL;
		sel_a = sel_b = ocr_nearest(&ocr, (int)(x * sc), (int)(y * sc), (int)(16 * sc));
		copied = 0;
		dirty = 1;
	} else {
		touch_mode = T_TAP;
	}
}

static void
touch_motion(void *data, struct wl_touch *t, uint32_t time, int32_t id, wl_fixed_t fx, wl_fixed_t fy)
{
	float x = (float)wl_fixed_to_double(fx), y = (float)wl_fixed_to_double(fy);

	if (id != touch_id)
		return;
	if (hypotf(x - down_x, y - down_y) > TAP_SLOP)
		touch_moved = 1;
	if (touch_mode == T_SEL && touch_moved) {
		if (sel_a < 0)
			sel_a = ocr_nearest(&ocr, (int)(down_x * sc), (int)(down_y * sc), bw + bh);
		sel_b = ocr_nearest(&ocr, (int)(x * sc), (int)(y * sc), bw + bh);
		dirty = 1;
	} else if (touch_mode == T_BTN && btnat(x, y) != touch_press) {
		touch_mode = T_NONE;
		dirty = 1;
	}
}

static void
touch_up(void *data, struct wl_touch *t, uint32_t serial, uint32_t time, int32_t id)
{
	int mode = touch_mode, press = touch_press, moved = touch_moved;

	if (id != touch_id)
		return;
	touch_id = -1;
	touch_mode = T_NONE;
	touch_press = -1;
	dirty = 1;
	if (mode == T_BAR) {
		quit = 1;
	} else if (mode == T_BTN) {
		Btn btn[3];
		const char *label;
		int n = barbuttons(btn, &label);

		if (press >= 0 && press < n)
			act(btn[press].act);
	} else if (mode == T_SEL) {
		if (sel_a < 0 && !moved)
			quit = 1;
	} else if (mode == T_TAP && !moved) {
		if (state != S_READY || !onblock(down_x, down_y))
			quit = 1;
	}
}

static void
touch_cancel(void *data, struct wl_touch *t)
{
	touch_id = -1;
	touch_mode = T_NONE;
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
	}
}
static void seat_name(void *data, struct wl_seat *s, const char *n) {}
static const struct wl_seat_listener seat_listener = {seat_caps, seat_name};

static void
reg_global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver)
{
	if (!strcmp(iface, wl_compositor_interface.name))
		compositor = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	else if (!strcmp(iface, wl_shm_interface.name))
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	else if (!strcmp(iface, wl_seat_interface.name) && !seat) {
		seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
		wl_seat_add_listener(seat, &seat_listener, NULL);
	} else if (!strcmp(iface, wl_output_interface.name) && !output)
		/* shortcut: first output only, a phone has one; pick the focused one if this ever runs on two */
		output = wl_registry_bind(r, name, &wl_output_interface, 1);
	else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name))
		layer_shell = wl_registry_bind(r, name, &zwlr_layer_shell_v1_interface, 1);
	else if (!strcmp(iface, zwlr_screencopy_manager_v1_interface.name))
		copy_mgr = wl_registry_bind(r, name, &zwlr_screencopy_manager_v1_interface, 1);
	else if (!strcmp(iface, wp_viewporter_interface.name))
		viewporter = wl_registry_bind(r, name, &wp_viewporter_interface, 1);
}
static void reg_remove(void *data, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg_listener = {reg_global, reg_remove};

int
main(void)
{
	struct wl_registry *reg;
	char fontbuf[512];
	const char *font, *d;

	signal(SIGPIPE, SIG_IGN);
	if (!(dpy = wl_display_connect(NULL))) {
		fprintf(stderr, "phonetext: no wayland display\n");
		return 1;
	}
	reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &reg_listener, NULL);
	wl_display_roundtrip(dpy);
	wl_display_roundtrip(dpy);
	if (!compositor || !shm || !output || !layer_shell || !copy_mgr || !viewporter) {
		fprintf(stderr, "phonetext: compositor lacks a needed protocol\n");
		return 1;
	}
	/* test hook: what was read goes to a file only when asked for */
	if ((d = getenv("PHONETEXT_DUMP")))
		dump = fopen(d, "a");
	if (FT_Init_FreeType(&ft) || !(font = findfont(fontbuf, sizeof fontbuf)) || FT_New_Face(ft, font, 0, &face)) {
		fprintf(stderr, "phonetext: no font\n");
		return 1;
	}
	timerfd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC);
	surf = wl_compositor_create_surface(compositor);
	viewport = wp_viewporter_get_viewport(viewporter, surf);
	layer = zwlr_layer_shell_v1_get_layer_surface(layer_shell, surf, output,
		ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "phone-screentext");
	zwlr_layer_surface_v1_add_listener(layer, &layer_listener, NULL);
	zwlr_layer_surface_v1_set_anchor(layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM
		| ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
	zwlr_layer_surface_v1_set_exclusive_zone(layer, -1);
	zwlr_layer_surface_v1_set_keyboard_interactivity(layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
	wl_surface_commit(surf);

	while (!quit) {
		struct pollfd fds[3] = {
			{wl_display_get_fd(dpy), POLLIN, 0},
			{timerfd, POLLIN, 0},
			{child_fd, POLLIN, 0},
		};

		flushdraw();
		while (wl_display_prepare_read(dpy))
			wl_display_dispatch_pending(dpy);
		wl_display_flush(dpy);
		if (poll(fds, 3, -1) < 0) {
			wl_display_cancel_read(dpy);
			if (errno == EINTR)
				continue;
			break;
		}
		if (fds[0].revents & POLLIN) {
			if (wl_display_read_events(dpy) < 0)
				break;
		} else {
			wl_display_cancel_read(dpy);
		}
		if (fds[0].revents & (POLLERR | POLLHUP))
			break;
		wl_display_dispatch_pending(dpy);
		if (fds[1].revents & POLLIN) {
			uint64_t n;

			if (read(timerfd, &n, sizeof n) == sizeof n) {
				frame = zwlr_screencopy_manager_v1_capture_output(copy_mgr, 0, output);
				zwlr_screencopy_frame_v1_add_listener(frame, &frame_listener2, NULL);
			}
		}
		if (child_fd >= 0 && fds[2].revents & (POLLIN | POLLHUP))
			childread();
	}
	if (child)
		kill(child, SIGKILL);
	wl_display_disconnect(dpy);
	return 0;
}
