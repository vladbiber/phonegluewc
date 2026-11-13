/* emoji data and font, alive only while the panel is open */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include "emoji.h"
#include "words.h"

#define CACHE 64
#define TAG(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

static const char *const font_paths[] = {
	"/usr/share/fonts/noto-emoji/NotoColorEmoji.ttf",
	"/usr/share/fonts/noto/NotoColorEmoji.ttf",
	"/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
	"/usr/share/fonts/google-noto-color-emoji-fonts/NotoColorEmoji.ttf",
	"/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf",
	"/usr/share/fonts/TTF/NotoColorEmoji.ttf",
	"/usr/share/fonts/noto-emoji/NotoEmoji-Regular.ttf",
	"/usr/share/fonts/noto/NotoEmoji-Regular.ttf",
	"/usr/share/fonts/truetype/noto/NotoEmoji-Regular.ttf",
	"/usr/share/fonts/TTF/NotoEmoji-Regular.ttf",
};

static FT_Face face;
static const uint8_t *font;
static size_t font_len;
static size_t gsub, gsub_len;
static int kind;
static char path_used[512];

static char *data;
static Emoji *list;
static int nlist;

static struct {
	uint32_t *px;
	int gid, size, w, h;
	unsigned age;
} cache[CACHE];
static unsigned tick;

static char recent[EMOJI_RECENT][EMOJI_SEQ];
static int nrecent, recent_dirty;
static char recent_path[560], stamp_path[560];
static long stamp_seen;

static uint32_t
utf8_cp(const char **s)
{
	const unsigned char *p = (const unsigned char *)*s;
	uint32_t c = *p;
	int n = c < 0x80 ? 0 : c < 0xe0 ? 1 : c < 0xf0 ? 2 : 3;

	if (n)
		c &= 0x3fu >> n;
	p++;
	while (n-- && (*p & 0xc0) == 0x80)
		c = c << 6 | (*p++ & 0x3f);
	*s = (const char *)p;
	return c;
}

/* offsets stay inside the font even if the file lies about them */
static unsigned
u16at(size_t o)
{
	return o + 2 <= font_len ? (unsigned)font[o] << 8 | font[o + 1] : 0;
}

static size_t
u32at(size_t o)
{
	return (size_t)u16at(o) << 16 | u16at(o + 2);
}

static void
findgsub(void)
{
	unsigned n = u16at(4);

	gsub = gsub_len = 0;
	for (unsigned i = 0; i < n; i++) {
		size_t r = 12 + (size_t)i * 16;

		if (u32at(r) == TAG('G', 'S', 'U', 'B')) {
			gsub = u32at(r + 8);
			gsub_len = u32at(r + 12);
		}
	}
	if (gsub + gsub_len > font_len)
		gsub = gsub_len = 0;
}

static int
coverage(size_t c, unsigned glyph)
{
	unsigned fmt = u16at(c), n = u16at(c + 2);

	for (unsigned lo = 0, hi = n; lo < hi; ) {
		unsigned mid = (lo + hi) / 2;

		if (fmt == 1) {
			unsigned g = u16at(c + 4 + (size_t)mid * 2);

			if (g == glyph)
				return (int)mid;
			if (g < glyph)
				lo = mid + 1;
			else
				hi = mid;
		} else if (fmt == 2) {
			size_t r = c + 4 + (size_t)mid * 6;

			if (glyph < u16at(r))
				hi = mid;
			else if (glyph > u16at(r + 2))
				lo = mid + 1;
			else
				return (int)(u16at(r + 4) + glyph - u16at(r));
		} else {
			return -1;
		}
	}
	return -1;
}

/* FreeType does not shape: this is the one GSUB rule emoji need, whole sequence to one glyph */
static int
ligature(const unsigned *g, int n)
{
	size_t lists;
	unsigned nl;

	if (!gsub_len)
		return 0;
	lists = gsub + u16at(gsub + 8);
	nl = u16at(lists);
	for (unsigned l = 0; l < nl; l++) {
		size_t lk = lists + u16at(lists + 2 + (size_t)l * 2);
		unsigned type = u16at(lk), nsub = u16at(lk + 4);

		for (unsigned s = 0; s < nsub; s++) {
			size_t st = lk + u16at(lk + 6 + (size_t)s * 2), set;
			int idx;

			if (type == 7) {
				if (u16at(st + 2) != 4)
					continue;
				st += u32at(st + 4);
			} else if (type != 4) {
				continue;
			}
			if ((idx = coverage(st + u16at(st + 2), g[0])) < 0 || idx >= (int)u16at(st + 4))
				continue;
			set = st + u16at(st + 6 + (size_t)idx * 2);
			for (unsigned i = 0, nlig = u16at(set); i < nlig; i++) {
				size_t lg = set + u16at(set + 2 + (size_t)i * 2);
				int match = (int)u16at(lg + 2) == n;

				for (int k = 1; match && k < n; k++)
					match = u16at(lg + 4 + (size_t)(k - 1) * 2) == g[k];
				if (match)
					return (int)u16at(lg);
			}
		}
	}
	return 0;
}

static int
resolve(const char *seq)
{
	unsigned g[16];
	int n = 0;

	if (!face)
		return 0;
	while (*seq) {
		uint32_t c = utf8_cp(&seq);

		if (c == 0xfe0f)
			continue;
		if (n == 16 || !(g[n] = FT_Get_Char_Index(face, c)))
			return 0;
		n++;
	}
	return n == 1 ? (int)g[0] : n ? ligature(g, n) : 0;
}

static void
dropfont(void)
{
	if (face)
		FT_Done_Face(face);
	face = NULL;
	if (font)
		munmap((void *)font, font_len);
	font = NULL;
	font_len = 0;
	kind = EMOJI_NONE;
}

/* a font counts only if FreeType really draws a face with it: COLRv1 only fonts load but come out empty */
static int
tryfont(FT_Library ft, const char *path)
{
	struct stat st;
	void *m;
	int fd = open(path, O_RDONLY | O_CLOEXEC), gid;

	if (fd < 0)
		return 0;
	m = !fstat(fd, &st) && st.st_size > 12 ? mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0) : MAP_FAILED;
	close(fd);
	if (m == MAP_FAILED)
		return 0;
	font = m;
	font_len = (size_t)st.st_size;
	if (FT_New_Memory_Face(ft, font, (FT_Long)font_len, 0, &face)) {
		face = NULL;
		dropfont();
		return 0;
	}
	gid = (int)FT_Get_Char_Index(face, 0x1f600);
	if (gid) {
		if (face->num_fixed_sizes > 0)
			FT_Select_Size(face, 0);
		else
			FT_Set_Pixel_Sizes(face, 0, 64);
		if (!FT_Load_Glyph(face, (FT_UInt)gid, FT_LOAD_COLOR | FT_LOAD_RENDER) && face->glyph->bitmap.width)
			kind = face->glyph->bitmap.pixel_mode == FT_PIXEL_MODE_BGRA ? EMOJI_COLOR : EMOJI_MONO;
	}
	if (kind == EMOJI_NONE) {
		dropfont();
		return 0;
	}
	findgsub();
	snprintf(path_used, sizeof path_used, "%s", path);
	return 1;
}

static void
findfont_emoji(FT_Library ft)
{
	const char *e = getenv("PHONEKBD_EMOJI_FONT");
	char buf[512];
	FILE *p;

	path_used[0] = 0;
	/* an explicit choice, tests included, never falls back on something else */
	if (e && *e) {
		if (strcmp(e, "none"))
			tryfont(ft, e);
		return;
	}
	/* colour first; shortcut: the fixed list orders colour before mono, a mono font fc-match finds may lose to none */
	for (size_t i = 0; i < sizeof font_paths / sizeof *font_paths; i++)
		if (tryfont(ft, font_paths[i]))
			return;
	if ((p = popen("fc-match -f %{file} emoji 2>/dev/null", "r"))) {
		size_t n = fread(buf, 1, sizeof buf - 1, p);

		buf[n] = 0;
		pclose(p);
		if (n)
			tryfont(ft, buf);
	}
}

static long
stamp_now(void)
{
	struct stat st;

	if (!stamp_path[0] || stat(stamp_path, &st))
		return 0;
	return st.st_mtim.tv_sec * 1000 + st.st_mtim.tv_nsec / 1000000;
}

static void
saverecent(void)
{
	char tmp[600];
	FILE *f;
	int fd;

	if (!recent_dirty || !recent_path[0])
		return;
	recent_dirty = 0;
	/* cleared by another process while the panel was open: nothing comes back */
	if (stamp_now() != stamp_seen)
		return;
	snprintf(tmp, sizeof tmp, "%s.tmp", recent_path);
	if ((fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600)) < 0)
		return;
	if (!(f = fdopen(fd, "w"))) {
		close(fd);
		return;
	}
	for (int i = 0; i < nrecent; i++)
		fprintf(f, "%s\n", recent[i]);
	if (fclose(f) == 0)
		rename(tmp, recent_path);
}

static void
loadrecent(const char *state_dir)
{
	char line[128];
	FILE *f;

	nrecent = 0;
	recent_dirty = 0;
	snprintf(recent_path, sizeof recent_path, "%s/emoji-recent", state_dir ? state_dir : "");
	snprintf(stamp_path, sizeof stamp_path, "%s/emoji-cleared", state_dir ? state_dir : "");
	if (!state_dir) {
		recent_path[0] = stamp_path[0] = 0;
		return;
	}
	stamp_seen = stamp_now();
	if (!(f = fopen(recent_path, "r")))
		return;
	while (nrecent < EMOJI_RECENT && fgets(line, sizeof line, f)) {
		line[strcspn(line, "\n")] = 0;
		if (strlen(line) < EMOJI_SEQ && resolve(line))
			snprintf(recent[nrecent++], EMOJI_SEQ, "%s", line);
	}
	fclose(f);
}

static int
loaddata(const char *path)
{
	struct stat st;
	char *p;
	size_t lines = 0;
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	ssize_t got;

	if (fd < 0)
		return 0;
	if (fstat(fd, &st) || !(data = malloc((size_t)st.st_size + 1))) {
		close(fd);
		return 0;
	}
	got = read(fd, data, (size_t)st.st_size);
	close(fd);
	if (got != st.st_size)
		return 0;
	data[got] = 0;
	for (p = data; (p = strchr(p, '\n')); p++)
		lines++;
	if (!(list = malloc((lines + 1) * sizeof *list)))
		return 0;
	nlist = 0;
	for (p = data; *p; ) {
		char *nl = strchr(p, '\n'), *t1, *t2, *t3;
		Emoji e;

		if (nl)
			*nl = 0;
		t1 = strchr(p, '\t');
		t2 = t1 ? strchr(t1 + 1, '\t') : NULL;
		t3 = t2 ? strchr(t2 + 1, '\t') : NULL;
		if (t3) {
			*t1 = *t2 = *t3 = 0;
			e = (Emoji){t1 + 1, t2 + 1, t3 + 1, atoi(p)};
			if (strlen(e.seq) < EMOJI_SEQ && resolve(e.seq)) {
				/* tones only if the font has them */
				if (e.tone[0] && (strlen(e.tone) >= EMOJI_SEQ || !resolve(e.tone)))
					e.tone = "";
				list[nlist++] = e;
			}
		}
		if (!nl)
			break;
		p = nl + 1;
	}
	return nlist > 0;
}

int
emoji_open(FT_Library ft, const char *datafile, const char *state_dir)
{
	emoji_close();
	findfont_emoji(ft);
	if (kind == EMOJI_NONE)
		return EMOJI_NONE;
	if (!loaddata(datafile)) {
		emoji_close();
		return EMOJI_NONE;
	}
	loadrecent(state_dir);
	return kind;
}

void
emoji_close(void)
{
	saverecent();
	for (int i = 0; i < CACHE; i++)
		free(cache[i].px);
	memset(cache, 0, sizeof cache);
	dropfont();
	free(list);
	list = NULL;
	nlist = 0;
	free(data);
	data = NULL;
	nrecent = 0;
}

const char *
emoji_font_path(void)
{
	return path_used;
}

int
emoji_count(void)
{
	return nlist;
}

const Emoji *
emoji_at(int i)
{
	return i >= 0 && i < nlist ? &list[i] : NULL;
}

const char *
emoji_first(int group)
{
	for (int i = 0; i < nlist; i++)
		if (list[i].group == group)
			return list[i].seq;
	return NULL;
}

static int
hasword(const char *words, const char *tok, int exact)
{
	size_t n = strlen(tok);

	for (const char *p = words; (p = strstr(p, tok)); p++)
		if ((p == words || p[-1] == ' ') && (!exact || p[n] == ' ' || !p[n]))
			return 1;
	return 0;
}

int
emoji_search(const char *query, int *out, int max)
{
	char tok[4][WORD_MAX], buf[128], *save = NULL, *t;
	int ntok = 0, n = 0;

	snprintf(buf, sizeof buf, "%s", query);
	for (t = strtok_r(buf, " ", &save); t && ntok < 4; t = strtok_r(NULL, " ", &save))
		if (fold_word(t, tok[ntok], WORD_MAX))
			ntok++;
	if (!ntok)
		return 0;
	for (int pass = 1; pass >= 0; pass--)
		for (int i = 0; i < nlist && n < max; i++) {
			int all = 1;

			for (int k = 0; all && k < ntok; k++)
				all = hasword(list[i].words, tok[k], 0);
			if (!all || hasword(list[i].words, tok[0], 1) != pass)
				continue;
			out[n++] = i;
		}
	return n;
}

int
emoji_toned(const Emoji *e, int tone, char *out, int size)
{
	static const char *const lights = "\xf0\x9f\x8f\xbb";
	const char *p = e->tone, *at;
	int o = 0;

	if (!p[0] || tone < 0 || tone >= EMOJI_TONES)
		return 0;
	while ((at = strstr(p, lights))) {
		int n = (int)(at - p);

		if (o + n + 4 >= size)
			return 0;
		memcpy(out + o, p, (size_t)n);
		o += n;
		memcpy(out + o, lights, 4);
		out[o + 3] = (char)(0xbb + tone);
		o += 4;
		p = at + 4;
	}
	if (o + (int)strlen(p) >= size)
		return 0;
	strcpy(out + o, p);
	return resolve(out) != 0;
}

/* box filter down to fit size; premultiplied, so a plain average is right */
static uint32_t *
scale(const uint8_t *src, int sw, int sh, int pitch, int size, int *w, int *h)
{
	float f = (float)size / (float)(sw > sh ? sw : sh);
	int dw = (int)((float)sw * f + 0.5f), dh = (int)((float)sh * f + 0.5f);
	uint32_t *out;

	dw = dw < 1 ? 1 : dw;
	dh = dh < 1 ? 1 : dh;
	if (!(out = malloc((size_t)dw * (size_t)dh * 4)))
		return NULL;
	for (int y = 0; y < dh; y++) {
		int y0 = y * sh / dh, y1 = (y + 1) * sh / dh;

		y1 = y1 <= y0 ? y0 + 1 : y1;
		for (int x = 0; x < dw; x++) {
			int x0 = x * sw / dw, x1 = (x + 1) * sw / dw;
			uint32_t b = 0, g = 0, r = 0, a = 0, n;

			x1 = x1 <= x0 ? x0 + 1 : x1;
			for (int j = y0; j < y1; j++) {
				const uint8_t *row = src + (ptrdiff_t)j * pitch + (ptrdiff_t)x0 * 4;

				for (int i = x0; i < x1; i++, row += 4) {
					b += row[0];
					g += row[1];
					r += row[2];
					a += row[3];
				}
			}
			n = (uint32_t)((x1 - x0) * (y1 - y0));
			out[y * dw + x] = (a / n) << 24 | (r / n) << 16 | (g / n) << 8 | (b / n);
		}
	}
	*w = dw;
	*h = dh;
	return out;
}

const uint32_t *
emoji_glyph(const char *seq, int size, int *w, int *h)
{
	int gid = resolve(seq), slot = 0;
	FT_Bitmap *b;
	uint32_t *res = NULL;

	if (!gid || size < 1)
		return NULL;
	tick++;
	for (int i = 0; i < CACHE; i++) {
		if (cache[i].px && cache[i].gid == gid && cache[i].size == size) {
			cache[i].age = tick;
			*w = cache[i].w;
			*h = cache[i].h;
			return cache[i].px;
		}
		if (cache[i].age < cache[slot].age)
			slot = i;
	}
	if (kind == EMOJI_MONO)
		FT_Set_Pixel_Sizes(face, 0, (FT_UInt)size);
	if (FT_Load_Glyph(face, (FT_UInt)gid, FT_LOAD_COLOR | FT_LOAD_RENDER))
		return NULL;
	b = &face->glyph->bitmap;
	if (!b->width || !b->rows)
		return NULL;
	if (b->pixel_mode == FT_PIXEL_MODE_BGRA) {
		res = scale(b->buffer, (int)b->width, (int)b->rows, b->pitch, size, w, h);
	} else if (b->pixel_mode == FT_PIXEL_MODE_GRAY && (res = malloc((size_t)b->width * b->rows * 4))) {
		*w = (int)b->width;
		*h = (int)b->rows;
		for (unsigned j = 0; j < b->rows; j++)
			for (unsigned i = 0; i < b->width; i++) {
				uint32_t a = b->buffer[(ptrdiff_t)j * b->pitch + (ptrdiff_t)i];

				res[j * b->width + i] = a << 24 | a << 16 | a << 8 | a;
			}
	}
	if (!res)
		return NULL;
	free(cache[slot].px);
	cache[slot].px = res;
	cache[slot].gid = gid;
	cache[slot].size = size;
	cache[slot].w = *w;
	cache[slot].h = *h;
	cache[slot].age = tick;
	return res;
}

int
emoji_recent_count(void)
{
	return nrecent;
}

const char *
emoji_recent(int i)
{
	return i >= 0 && i < nrecent ? recent[i] : NULL;
}

void
emoji_recent_forget(void)
{
	nrecent = 0;
	recent_dirty = 0;
}

void
emoji_recent_add(const char *seq)
{
	int at = nrecent < EMOJI_RECENT ? nrecent : EMOJI_RECENT - 1;

	if (strlen(seq) >= EMOJI_SEQ)
		return;
	for (int i = 0; i < nrecent; i++)
		if (!strcmp(recent[i], seq)) {
			at = i;
			break;
		}
	if (at == nrecent)
		nrecent++;
	memmove(recent[1], recent[0], (size_t)at * EMOJI_SEQ);
	snprintf(recent[0], EMOJI_SEQ, "%s", seq);
	recent_dirty = 1;
}
