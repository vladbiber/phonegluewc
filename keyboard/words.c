/* offline word lists: suggestions, autocorrect, learning and swipe decoding */
#include <ctype.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include "words.h"

/* score is 16 per doubling of frequency, so an edit costs about 2.5 doublings */
#define EDIT_COST 40
#define COMMON 170
#define SAMPLES 32
#define LEARNED_MAX 2000
/* one typing may be a typo, two make it a word */
#define LEARNED_AT 2
#define PAIR_MAX 2000
#define PAIR_WORD 24
/* the word before counts for about five doublings when it is the likeliest next word */
#define CTX_BONUS 80
#define CTX_STEP 3

float key_pos[26][2];

static const char *map;
static size_t map_len;
/* the languages on, and for each a count of recent matches: words from it score that much higher */
#define LANGS_MAX 31
static char langcode[LANGS_MAX][4];
static int bias[LANGS_MAX], nlang;

static struct { char word[WORD_MAX]; char key[WORD_MAX]; int count; char lang[4]; } *learned;
static int nlearned, learned_dirty;
static char learned_path[512];
static const char *bimap;
static size_t bimap_len;
static struct { char a[PAIR_WORD], b[PAIR_WORD]; int count; } *pairs;
static int npairs, pairs_dirty;
static char ctx[WORD_MAX];
static char pairs_path[512], stamp_path[560];
static long stamp_seen;

typedef struct {
	char key[WORD_MAX], word[WORD_MAX];
	int score;
	uint32_t lang; /* a bit for each language on, 0 when none has this word */
} Entry;

/* the base key of each Latin-1 and Latin Extended-A letter; the pack builder's fold must match */
static const char lat1[] = "aaaaaaaceeeeiiiidnooooo\0ouuuuyts" "aaaaaaaceeeeiiiidnooooo\0ouuuuyty";
static const char lata[] = "aaaaaaccccccccddddeeeeeeeeeegggggggghhhhiiiiiiiiiiiijjkkkllllllllllnnnnnnnnnoooo"
	"oooorrrrrrssssssssttttttuuuuuuuuuuuuwwyyyzzzzzzs";

/* the code point of a two byte letter, 0 for anything else */
static int
cp2(const char *s)
{
	return (s[0] & 0xe0) == 0xc0 && (s[1] & 0xc0) == 0x80 ? (s[0] & 0x1f) << 6 | (s[1] & 0x3f) : 0;
}

static char
foldcp(int c)
{
	if (c >= 0xc0 && c <= 0xff)
		return lat1[c - 0xc0];
	if (c >= 0x100 && c <= 0x17f)
		return lata[c - 0x100];
	return c >= 0x218 && c <= 0x219 ? 's' : c >= 0x21a && c <= 0x21b ? 't' : 0;
}

/* the capital of a lower case letter, 0 when c is not one */
static int
upcp(int c)
{
	if (c == 0xff)
		return 0x178;
	if (c >= 0xe0 && c <= 0xfe)
		return c == 0xf7 ? 0 : c - 0x20;
	if (c == 0x219 || c == 0x21b || (((c >= 0x100 && c <= 0x137) || (c >= 0x14a && c <= 0x177)) && (c & 1) && c != 0x131))
		return c - 1;
	if (((c >= 0x139 && c <= 0x148) || (c >= 0x179 && c <= 0x17e)) && !(c & 1))
		return c - 1;
	return 0;
}

static int
iscapcp(int c)
{
	return c && (c == 0x178 || (c >= 0xc0 && c <= 0xde && c != 0xd7) || c == 0x130 || upcp(c + 1) == c);
}

int
utf8_len(const char *s)
{
	int n = 0;

	for (; *s; s++)
		n += (*s & 0xc0) != 0x80;
	return n;
}

/* 0 when the word holds anything but letters, an apostrophe or a hyphen */
int
fold_word(const char *w, char *out, int size)
{
	int n = 0;

	while (*w && n < size - 1) {
		if (*w == '\'' || *w == '-') {
			w++;
		} else if (isalpha((unsigned char)*w)) {
			out[n++] = (char)tolower((unsigned char)*w++);
		} else {
			char to = foldcp(cp2(w));

			if (!to)
				return 0;
			out[n++] = to;
			w += 2;
		}
	}
	out[n] = 0;
	return n;
}

/* the typed word's capitals on a candidate; shortcut: Turkish dotted capitals are not special, upgrade with a per language rule */
static void
matchcase(const char *typed, char *w)
{
	char buf[WORD_MAX * 2], *o = buf;
	const char *p = w;
	int first = isupper((unsigned char)*typed) || iscapcp(cp2(typed));
	int all = first && utf8_len(typed) > 1;

	if (!first)
		return;
	for (const char *t = typed; *t && all; t++)
		if (islower((unsigned char)*t) || upcp(cp2(t)))
			all = 0;
	while (*p) {
		int up = all || p == w, c = cp2(p), u = up && c ? upcp(c) : 0;

		if (up && c == 0x131) {
			*o++ = 'I';
			p += 2;
		} else if (u) {
			*o++ = (char)(0xc0 | u >> 6);
			*o++ = (char)(0x80 | (u & 0x3f));
			p += 2;
		} else if (c) {
			*o++ = *p++;
			*o++ = *p++;
		} else {
			*o++ = up ? (char)toupper((unsigned char)*p) : *p;
			p++;
		}
	}
	*o = 0;
	snprintf(w, WORD_MAX, "%s", buf);
}

static const char *
nextline(const char *p)
{
	const char *e = memchr(p, '\n', (size_t)(map + map_len - p));

	return e ? e + 1 : map + map_len;
}

static uint32_t
langbit(const char *code, size_t l)
{
	for (int i = 0; i < nlang; i++)
		if (strlen(langcode[i]) == l && !memcmp(langcode[i], code, l))
			return 1u << i;
	return 0;
}

/* "en,ro", or the "e" of the shipped English list */
static uint32_t
tagbits(const char *p, const char *end)
{
	uint32_t m = 0;

	/* e is the shipped English list; r and b are a list merged before the codes, until its next merge */
	if (end - p == 1)
		return (*p == 'r' ? 0 : langbit("en", 2)) | (*p == 'e' ? 0 : langbit("ro", 2));
	while (p < end) {
		const char *c = memchr(p, ',', (size_t)(end - p));
		size_t l = (size_t)((c ? c : end) - p);

		m |= langbit(p, l);
		p += l + 1;
	}
	return m;
}

static const char *
parse(const char *p, Entry *e)
{
	const char *next = nextline(p), *t1, *t2, *t3;
	size_t k, w;

	if (!(t1 = memchr(p, '\t', (size_t)(next - p))) || !(t2 = memchr(t1 + 1, '\t', (size_t)(next - t1 - 1)))) {
		e->key[0] = 0;
		return next;
	}
	k = (size_t)(t1 - p);
	w = (size_t)(t2 - t1 - 1);
	if (k >= WORD_MAX || w >= WORD_MAX) {
		e->key[0] = 0;
		return next;
	}
	memcpy(e->key, p, k);
	e->key[k] = 0;
	memcpy(e->word, w ? t1 + 1 : p, w ? w : k);
	e->word[w ? w : k] = 0;
	e->score = atoi(t2 + 1);
	t3 = memchr(t2 + 1, '\t', (size_t)(next - t2 - 1));
	e->lang = t3 ? tagbits(t3 + 1, next - (next[-1] == '\n')) : 0;
	if (e->lang) {
		int best = -99;

		for (int i = 0; i < nlang; i++)
			if ((e->lang >> i & 1) && bias[i] > best)
				best = bias[i];
		e->score += best * 2;
	}
	return next;
}

static int
offlang(const Entry *e)
{
	return !e->lang;
}

void
words_langs(const char *codes)
{
	static char cur[128];
	char copy[128], *sv = NULL;

	/* the same list again keeps the counts: this runs at every show */
	if (nlang && !strcmp(cur, codes))
		return;
	snprintf(cur, sizeof cur, "%s", codes);
	snprintf(copy, sizeof copy, "%s", codes);
	nlang = 0;
	memset(bias, 0, sizeof bias);
	for (char *c = strtok_r(copy, " \t", &sv); c && nlang < LANGS_MAX; c = strtok_r(NULL, " \t", &sv))
		if (strlen(c) < sizeof langcode[0])
			snprintf(langcode[nlang++], sizeof langcode[0], "%s", c);
}

/* the language a new word is learned under: only when one clearly leads, else any language shows it */
static const char *
leading(void)
{
	int top = -1, tie = 0;

	for (int i = 0; i < nlang; i++) {
		if (top < 0 || bias[i] > bias[top]) {
			top = i;
			tie = 0;
		} else if (bias[i] == bias[top]) {
			tie = 1;
		}
	}
	return top < 0 || tie ? "" : langcode[top];
}

static int
learnedoff(int i)
{
	return learned[i].lang[0] && !langbit(learned[i].lang, strlen(learned[i].lang));
}

/* first line whose key is >= the prefix */
static const char *
seek(const char *prefix)
{
	size_t lo = 0, hi = map_len, n = strlen(prefix);

	while (lo < hi) {
		size_t mid = lo + (hi - lo) / 2;
		const char *p = map + mid;

		while (p > map && p[-1] != '\n')
			p--;
		if (strncmp(p, prefix, n) < 0 && strncmp(p, prefix, n) != 0) {
			lo = (size_t)(nextline(p) - map);
		} else {
			if ((size_t)(p - map) == hi || (size_t)(p - map) == mid) {
				if ((size_t)(p - map) == lo)
					break;
			}
			hi = (size_t)(p - map);
		}
	}
	return map + lo;
}

static long
stamp_now(void)
{
	struct stat st;

	if (!stamp_path[0] || stat(stamp_path, &st))
		return 0;
	return st.st_mtim.tv_sec * 1000 + st.st_mtim.tv_nsec / 1000000;
}

/* phonekbd --clear-learned from another process: what this one holds must not come back */
static void
checkcleared(void)
{
	long now = stamp_now();

	if (now == stamp_seen)
		return;
	stamp_seen = now;
	nlearned = npairs = 0;
	learned_dirty = pairs_dirty = 0;
}

static void
loadlearned(void)
{
	FILE *f = fopen(learned_path, "r");
	char line[128], w[WORD_MAX], l[4];
	int c;

	if (!f)
		return;
	while (nlearned < LEARNED_MAX && fgets(line, sizeof line, f)) {
		l[0] = 0;
		if (sscanf(line, "%63s %d %3s", w, &c, l) < 2)
			continue;
		snprintf(learned[nlearned].word, WORD_MAX, "%s", w);
		if (fold_word(w, learned[nlearned].key, WORD_MAX)) {
			learned[nlearned].count = c;
			snprintf(learned[nlearned].lang, sizeof learned[0].lang, "%s", l);
			nlearned++;
		}
	}
	fclose(f);
}

static void
savelearned(void)
{
	char tmp[600];
	FILE *f;
	int i, fd;

	checkcleared();
	if (!learned_dirty || !learned_path[0])
		return;
	snprintf(tmp, sizeof tmp, "%s.tmp", learned_path);
	if ((fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600)) < 0)
		return;
	if (!(f = fdopen(fd, "w"))) {
		close(fd);
		return;
	}
	for (i = 0; i < nlearned; i++)
		fprintf(f, "%s %d %s\n", learned[i].word, learned[i].count, learned[i].lang);
	if (fclose(f) == 0)
		rename(tmp, learned_path);
	learned_dirty = 0;
}

static void
savepairs(void)
{
	char tmp[600];
	FILE *f;
	int fd;

	checkcleared();
	if (!pairs_dirty || !pairs_path[0])
		return;
	snprintf(tmp, sizeof tmp, "%s.tmp", pairs_path);
	if ((fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600)) < 0)
		return;
	if (!(f = fdopen(fd, "w"))) {
		close(fd);
		return;
	}
	for (int i = 0; i < npairs; i++)
		fprintf(f, "%s %s %d\n", pairs[i].a, pairs[i].b, pairs[i].count);
	if (fclose(f) == 0)
		rename(tmp, pairs_path);
	pairs_dirty = 0;
}

int
words_open(const char *dict, const char *learnedfile)
{
	struct stat st;
	int fd;

	words_close();
	snprintf(learned_path, sizeof learned_path, "%s", learnedfile ? learnedfile : "");
	if (learned_path[0]) {
		const char *slash = strrchr(learned_path, '/');

		snprintf(stamp_path, sizeof stamp_path, "%.*s/cleared", slash ? (int)(slash - learned_path) : 1, slash ? learned_path : ".");
	} else {
		stamp_path[0] = 0;
	}
	stamp_seen = stamp_now();
	learned = calloc(LEARNED_MAX, sizeof *learned);
	if (learned && learned_path[0])
		loadlearned();
	if ((fd = open(dict, O_RDONLY)) < 0)
		return 0;
	if (fstat(fd, &st) == 0 && st.st_size > 0) {
		map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
		if (map == MAP_FAILED)
			map = NULL;
		else
			map_len = (size_t)st.st_size;
	}
	close(fd);
	return map != NULL;
}

void
words_close(void)
{
	savelearned();
	savepairs();
	if (map)
		munmap((void *)map, map_len);
	map = NULL;
	map_len = 0;
	free(learned);
	learned = NULL;
	nlearned = 0;
	if (bimap)
		munmap((void *)bimap, bimap_len);
	bimap = NULL;
	bimap_len = 0;
	free(pairs);
	pairs = NULL;
	npairs = 0;
}

int
words_bigrams_open(const char *data, const char *learnedfile)
{
	struct stat st;
	FILE *f;
	int fd;

	snprintf(pairs_path, sizeof pairs_path, "%s", learnedfile ? learnedfile : "");
	pairs = calloc(PAIR_MAX, sizeof *pairs);
	if (pairs && pairs_path[0] && (f = fopen(pairs_path, "r"))) {
		while (npairs < PAIR_MAX && fscanf(f, "%23s %23s %d", pairs[npairs].a, pairs[npairs].b, &pairs[npairs].count) == 3)
			npairs++;
		fclose(f);
	}
	if ((fd = open(data, O_RDONLY)) < 0)
		return 0;
	if (fstat(fd, &st) == 0 && st.st_size > 0) {
		bimap = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
		if (bimap == MAP_FAILED)
			bimap = NULL;
		else
			bimap_len = (size_t)st.st_size;
	}
	close(fd);
	return bimap != NULL;
}

/* the data file's line for a folded head, NULL if none */
static const char *
biseek(const char *head, const char **end)
{
	size_t lo = 0, hi = bimap_len, n = strlen(head);

	while (lo < hi) {
		size_t mid = lo + (hi - lo) / 2;
		const char *p = bimap + mid, *nl, *tab;
		int c;

		while (p > bimap && p[-1] != '\n')
			p--;
		nl = memchr(p, '\n', (size_t)(bimap + bimap_len - p));
		nl = nl ? nl : bimap + bimap_len;
		if (!(tab = memchr(p, '\t', (size_t)(nl - p))))
			return NULL;
		c = strncmp(head, p, n < (size_t)(tab - p) ? n : (size_t)(tab - p));
		if (!c)
			c = n < (size_t)(tab - p) ? -1 : n > (size_t)(tab - p);
		if (!c) {
			*end = nl;
			return tab + 1;
		}
		if (c < 0)
			hi = (size_t)(p - bimap);
		else
			lo = (size_t)(nl - bimap) + (nl < bimap + bimap_len);
	}
	return NULL;
}

/* the languages on that have this exact word */
static uint32_t
wordlang(const char *word)
{
	char key[WORD_MAX];
	Entry e;
	const char *p;

	if (!map || !fold_word(word, key, sizeof key))
		return 0;
	for (p = seek(key); p < map + map_len; ) {
		p = parse(p, &e);
		if (strcmp(e.key, key))
			break;
		if (!strcmp(e.word, word))
			return e.lang;
	}
	return 0;
}

int
words_next(const char *prev, char out[][WORD_MAX], int max)
{
	char head[WORD_MAX];
	const char *p, *end = NULL;
	char seg[LANGS_MAX][6][WORD_MAX];
	int nseg[LANGS_MAX] = {0}, n = 0, best[3] = {0, 0, 0}, en = -1;
	uint32_t cur = langbit("en", 2), used = 0;

	if (strcmp(prev, "<s>") == 0)
		snprintf(head, sizeof head, "<s>");
	else if (!fold_word(prev, head, sizeof head))
		snprintf(head, sizeof head, "<*>");
	/* the user's own pairs come first, most used on top */
	for (int i = 0; i < npairs; i++) {
		int at, c = pairs[i].count;

		if (c < LEARNED_AT || strcmp(pairs[i].a, head))
			continue;
		for (at = 0; at < n && best[at] >= c; at++)
			;
		if (at >= max || at >= 3)
			continue;
		for (int j = (n < 3 && n < max ? n : n - 1); j > at; j--) {
			best[j] = best[j - 1];
			memcpy(out[j], out[j - 1], WORD_MAX);
		}
		best[at] = c;
		snprintf(out[at], WORD_MAX, "%s", pairs[i].b);
		if (n < 3 && n < max)
			n++;
	}
	if (!bimap)
		return n;
	/* the head's own words, or the commonest ones so the strip is never half empty */
	if (!(p = biseek(head, &end)) && !(p = biseek("<*>", &end)))
		return n;
	while (p < end) {
		const char *sp = memchr(p, ' ', (size_t)(end - p));
		size_t l = (size_t)((sp ? sp : end) - p);
		char w[WORD_MAX];

		if (*p == '|') {
			cur = l == 1 ? langbit("ro", 2) : langbit(p + 1, l - 1);
		} else if (cur && l < WORD_MAX) {
			int at = __builtin_ctz(cur);

			memcpy(w, p, l);
			w[l] = 0;
			/* a word several languages share counts where its line lists it */
			if (nseg[at] < 6 && (wordlang(w) & cur))
				snprintf(seg[at][nseg[at]++], WORD_MAX, "%s", w);
		}
		p += l + 1;
	}
	if (langbit("en", 2))
		en = __builtin_ctz(langbit("en", 2));
	/* the language being typed goes first; before any word, the added ones go before English */
	for (int pass = 0; pass < nlang; pass++) {
		int top = -1;

		for (int i = 0; i < nlang; i++)
			if (!(used >> i & 1) && (top < 0 || bias[i] * 2 + (i != en) > bias[top] * 2 + (top != en)))
				top = i;
		used |= 1u << top;
		for (int i = 0; i < nseg[top] && n < max; i++) {
			const char *w = seg[top][i];
			int dup = 0;

			for (int j = 0; j < n; j++)
				dup |= !strcmp(out[j], w);
			if (!dup)
				snprintf(out[n++], WORD_MAX, "%s", w);
		}
	}
	if (n < max && strcmp(head, "<*>")) {
		char more[6][WORD_MAX];
		int m = words_next("<*>", more, 6);

		for (int i = 0; i < m && n < max; i++) {
			int dup = 0;

			for (int j = 0; j < n; j++)
				dup |= !strcasecmp(out[j], more[i]);
			if (!dup)
				snprintf(out[n++], WORD_MAX, "%s", more[i]);
		}
	}
	return n;
}

void
words_context(const char *prev)
{
	if (!prev[0] || !strcmp(prev, "<s>"))
		snprintf(ctx, sizeof ctx, "%s", prev);
	else if (!fold_word(prev, ctx, sizeof ctx))
		ctx[0] = 0;
}

/* how much the word before speaks for this word: the data's list is in order of use */
static int
ctxbonus(const char *word, const char *list, const char *end)
{
	int rank = 0;

	for (int i = 0; i < npairs; i++)
		if (pairs[i].count >= LEARNED_AT && !strcmp(pairs[i].a, ctx) && !strcmp(pairs[i].b, word))
			return CTX_BONUS;
	while (list && list < end) {
		const char *sp = memchr(list, ' ', (size_t)(end - list));
		size_t l = (size_t)((sp ? sp : end) - list);

		if (strlen(word) == l && !memcmp(list, word, l))
			return CTX_BONUS - rank * CTX_STEP;
		/* each language ranks on its own */
		rank = *list == '|' ? 0 : rank + 1;
		list += l + 1;
	}
	return 0;
}

void
words_pair(const char *prev, const char *next)
{
	char head[WORD_MAX], low[WORD_MAX];
	int low_i = -1;

	if (!pairs || strlen(next) >= PAIR_WORD)
		return;
	checkcleared();
	if (strcmp(prev, "<s>") == 0)
		snprintf(head, sizeof head, "<s>");
	else if (!fold_word(prev, head, sizeof head))
		return;
	if (strlen(head) >= PAIR_WORD)
		return;
	snprintf(low, sizeof low, "%s", next);
	if (*low != 'I' || low[1])
		low[0] = (char)tolower((unsigned char)low[0]);
	for (int i = 0; i < npairs; i++) {
		if (!strcmp(pairs[i].a, head) && !strcmp(pairs[i].b, low)) {
			pairs[i].count++;
			pairs_dirty = 1;
			return;
		}
		if (low_i < 0 || pairs[i].count < pairs[low_i].count)
			low_i = i;
	}
	if (npairs < PAIR_MAX)
		low_i = npairs++;
	snprintf(pairs[low_i].a, PAIR_WORD, "%s", head);
	snprintf(pairs[low_i].b, PAIR_WORD, "%s", low);
	pairs[low_i].count = 1;
	pairs_dirty = 1;
}

static float
keydist(char a, char b)
{
	if (a < 'a' || a > 'z' || b < 'a' || b > 'z')
		return 9;
	return hypotf(key_pos[a - 'a'][0] - key_pos[b - 'a'][0], key_pos[a - 'a'][1] - key_pos[b - 'a'][1]);
}

/* edit distance where a neighbouring key costs less and swapped letters are cheap */
static float
editdist(const char *a, const char *b, float limit)
{
	float d[WORD_MAX][WORD_MAX];
	int la = (int)strlen(a), lb = (int)strlen(b), i, j;

	if (abs(la - lb) > 1)
		return 99;
	for (i = 0; i <= la; i++)
		d[i][0] = (float)i;
	for (j = 0; j <= lb; j++)
		d[0][j] = (float)j;
	for (i = 1; i <= la; i++) {
		float low = 99;

		for (j = 1; j <= lb; j++) {
			float sub = a[i - 1] == b[j - 1] ? 0 : keydist(a[i - 1], b[j - 1]) < 1.5f ? 0.6f : 1.0f;
			float v = d[i - 1][j - 1] + sub;

			/* a doubled letter is the commonest slip of all */
			float del = i > 1 && a[i - 1] == a[i - 2] ? 0.25f : 1;
			float ins = j > 1 && b[j - 1] == b[j - 2] ? 0.25f : 1;

			if (d[i - 1][j] + del < v)
				v = d[i - 1][j] + del;
			if (d[i][j - 1] + ins < v)
				v = d[i][j - 1] + ins;
			if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]
					&& d[i - 2][j - 2] + 0.6f < v)
				v = d[i - 2][j - 2] + 0.6f;
			d[i][j] = v;
			if (v < low)
				low = v;
		}
		if (low > limit)
			return 99;
	}
	return d[la][lb];
}

typedef struct { char word[WORD_MAX]; int score; } Cand;

static void
addcand(Cand *c, int *n, int max, const char *word, int score)
{
	int i, at;

	for (i = 0; i < *n; i++)
		if (!strcmp(c[i].word, word)) {
			if (score <= c[i].score)
				return;
			memmove(&c[i], &c[i + 1], sizeof *c * (size_t)(*n - i - 1));
			(*n)--;
			break;
		}
	for (at = 0; at < *n && c[at].score >= score; at++)
		;
	if (at >= max)
		return;
	if (*n == max)
		(*n)--;
	memmove(&c[at + 1], &c[at], sizeof *c * (size_t)(*n - at));
	snprintf(c[at].word, WORD_MAX, "%s", word);
	c[at].score = score;
	(*n)++;
}

static int
learnedscore(int count)
{
	return 200 + (int)(16 * log2((double)count + 1));
}

int
words_suggest(const char *typed, char out[][WORD_MAX], int max)
{
	char key[WORD_MAX];
	Cand c[12];
	Entry e;
	const char *p, *list = NULL, *lend = NULL;
	size_t klen;
	int n = 0, i;

	if (max > 12)
		max = 12;
	if (!map || !*typed || !fold_word(typed, key, sizeof key))
		return 0;
	klen = strlen(key);
	if (ctx[0] && bimap)
		list = biseek(ctx, &lend);
	for (p = seek(key); p < map + map_len; ) {
		p = parse(p, &e);
		if (strncmp(e.key, key, klen))
			break;
		if (offlang(&e))
			continue;
		/* the word itself first, then what it may become */
		addcand(c, &n, 12, e.word, e.score + (strlen(e.key) == klen ? 60 : 0) + (ctx[0] ? ctxbonus(e.word, list, lend) : 0));
	}
	for (i = 0; i < nlearned; i++)
		if (learned[i].count >= LEARNED_AT && !strncmp(learned[i].key, key, klen) && !learnedoff(i))
			addcand(c, &n, 12, learned[i].word, learnedscore(learned[i].count) + (strlen(learned[i].key) == klen ? 60 : 0));
	if (klen >= 3)
		for (p = map; p < map + map_len; ) {
			float d;

			p = parse(p, &e);
			if (offlang(&e) || e.score < 100 || (e.key[0] != key[0] && keydist(e.key[0], key[0]) > 1.5f))
				continue;
			if ((d = editdist(key, e.key, 1.2f)) <= 1.2f && d > 0)
				addcand(c, &n, 12, e.word, e.score - (int)(d * EDIT_COST));
		}
	for (i = 0; i < n && i < max; i++) {
		snprintf(out[i], WORD_MAX, "%s", c[i].word);
		matchcase(typed, out[i]);
	}
	return n < max ? n : max;
}

int
words_correct(const char *typed, char *fixed)
{
	char key[WORD_MAX], low[WORD_MAX];
	Entry e;
	const char *p;
	int i, klen, self = -1, best = -1, en = 0;
	uint32_t enbit = langbit("en", 2);
	char bestword[WORD_MAX] = "";

	if (!map || !fold_word(typed, key, sizeof key) || (klen = (int)strlen(key)) < 2)
		return 0;
	/* diacritics are picked by hand, so the spelling is deliberate */
	for (p = typed; *p; p++)
		if ((*p & 0x80) || *p == '\'' || *p == '-')
			return 0;
	for (i = 0; i < nlearned; i++)
		if (learned[i].count >= LEARNED_AT && !strcasecmp(learned[i].word, typed))
			return 0;
	snprintf(low, sizeof low, "%s", typed);
	low[0] = (char)tolower((unsigned char)low[0]);
	for (p = seek(key); p < map + map_len; ) {
		p = parse(p, &e);
		if (strcmp(e.key, key))
			break;
		/* a word of a language switched off is left alone, never turned into another language */
		if (offlang(&e))
			return 0;
		if (!strcmp(e.word, low) || !strcmp(e.word, typed))
			self = e.score;
		if (e.lang & enbit)
			en = 1;
		if (e.score > best) {
			best = e.score;
			snprintf(bestword, sizeof bestword, "%s", e.word);
		}
	}
	/* a real word stays, unless it is nearly always the same word with diacritics */
	if (self >= 0 && (en || best < self + 25 || !strcmp(bestword, low)))
		return 0;
	if (best < 0 && klen >= 3) {
		int score = 0;
		float limit = isupper((unsigned char)*typed) ? 0.8f : 1.0f;

		for (p = map; p < map + map_len; ) {
			float d;

			p = parse(p, &e);
			if (offlang(&e) || e.score < COMMON || (e.key[0] != key[0] && keydist(e.key[0], key[0]) > 1.5f))
				continue;
			/* a capital may be a name, so only a slip of the finger is fixed there */
			if ((d = editdist(key, e.key, limit)) <= limit && e.score - (int)(d * EDIT_COST) > score) {
				score = e.score - (int)(d * EDIT_COST);
				snprintf(bestword, sizeof bestword, "%s", e.word);
			}
		}
		if (!score)
			return 0;
	}
	if (!bestword[0])
		return 0;
	snprintf(fixed, WORD_MAX, "%s", bestword);
	matchcase(typed, fixed);
	return 1;
}

void
words_note(const char *word)
{
	char key[WORD_MAX], low[WORD_MAX];
	Entry e;
	const char *p;

	if (!map || !fold_word(word, key, sizeof key))
		return;
	snprintf(low, sizeof low, "%s", word);
	low[0] = (char)tolower((unsigned char)low[0]);
	for (p = seek(key); p < map + map_len; ) {
		p = parse(p, &e);
		if (strcmp(e.key, key))
			break;
		if (strcmp(e.word, low))
			continue;
		/* a word all of them share says nothing */
		if (e.lang && e.lang != (nlang < 31 ? (1u << nlang) - 1 : 0x7fffffffu))
			for (int i = 0; i < nlang; i++) {
				if ((e.lang >> i & 1) && bias[i] < 8)
					bias[i]++;
				else if (!(e.lang >> i & 1) && bias[i] > -8)
					bias[i]--;
			}
		return;
	}
}

void
words_learn(const char *word, int weight)
{
	char key[WORD_MAX], low[WORD_MAX];
	uint32_t found = 0;
	Entry e;
	const char *p;
	int i;

	if (!learned || !fold_word(word, key, sizeof key) || strlen(key) < 2)
		return;
	checkcleared();
	snprintf(low, sizeof low, "%s", word);
	low[0] = (char)tolower((unsigned char)low[0]);
	if (map)
		for (p = seek(key); p < map + map_len; ) {
			p = parse(p, &e);
			if (strcmp(e.key, key))
				break;
			if (!strcmp(e.word, low)) {
				found = e.lang;
				break;
			}
		}
	if (found)
		return;
	for (i = 0; i < nlearned; i++)
		if (!strcmp(learned[i].word, low)) {
			learned[i].count += weight;
			learned_dirty = 1;
			return;
		}
	if (nlearned == LEARNED_MAX)
		return;
	snprintf(learned[nlearned].word, WORD_MAX, "%s", low);
	snprintf(learned[nlearned].key, WORD_MAX, "%s", key);
	snprintf(learned[nlearned].lang, sizeof learned[0].lang, "%s", leading());
	learned[nlearned++].count = weight;
	learned_dirty = 1;
}

/* n points evenly along a polyline, returns its length */
static float
resample(const float (*in)[2], int n, float (*out)[2])
{
	float len = 0, step, acc = 0;
	int i, o = 1;

	for (i = 1; i < n; i++)
		len += hypotf(in[i][0] - in[i - 1][0], in[i][1] - in[i - 1][1]);
	out[0][0] = in[0][0];
	out[0][1] = in[0][1];
	step = len / (SAMPLES - 1);
	for (i = 1; i < n && step > 0; i++) {
		float seg = hypotf(in[i][0] - in[i - 1][0], in[i][1] - in[i - 1][1]);

		while (seg > 0 && acc + seg >= step * (float)o && o < SAMPLES - 1) {
			float t = (step * (float)o - acc) / seg;

			out[o][0] = in[i - 1][0] + t * (in[i][0] - in[i - 1][0]);
			out[o][1] = in[i - 1][1] + t * (in[i][1] - in[i - 1][1]);
			o++;
		}
		acc += seg;
	}
	for (; o < SAMPLES; o++) {
		out[o][0] = in[n - 1][0];
		out[o][1] = in[n - 1][1];
	}
	return len;
}

/* shortcut: compares against ideal key to key lines with no learned user style, replace with a trained model if accuracy on real fingers disappoints */
int
words_swipe(const float (*path)[2], int n, char out[][WORD_MAX], int max)
{
	float in[SAMPLES][2], tpl[WORD_MAX][2], t[SAMPLES][2], len;
	Cand c[12];
	Entry e;
	const char *p;
	int nc = 0, i;

	if (!map || n < 2)
		return 0;
	if (max > 12)
		max = 12;
	len = resample(path, n, in);
	for (p = map; p < map + map_len; ) {
		float tlen = 0, d = 0;
		int m = 0, l;

		p = parse(p, &e);
		if (!e.key[0] || e.key[1] == 0 || offlang(&e))
			continue;
		l = e.key[0] - 'a';
		if (l < 0 || l > 25 || hypotf(key_pos[l][0] - in[0][0], key_pos[l][1] - in[0][1]) > 1.2f)
			continue;
		for (const char *k = e.key; *k; k++) {
			if (*k < 'a' || *k > 'z')
				continue;
			if (m && tpl[m - 1][0] == key_pos[*k - 'a'][0] && tpl[m - 1][1] == key_pos[*k - 'a'][1])
				continue;
			tpl[m][0] = key_pos[*k - 'a'][0];
			tpl[m][1] = key_pos[*k - 'a'][1];
			if (m)
				tlen += hypotf(tpl[m][0] - tpl[m - 1][0], tpl[m][1] - tpl[m - 1][1]);
			m++;
		}
		if (m < 2 || hypotf(tpl[m - 1][0] - in[SAMPLES - 1][0], tpl[m - 1][1] - in[SAMPLES - 1][1]) > 1.2f)
			continue;
		if (tlen < len * 0.6f || tlen > len * 1.5f)
			continue;
		resample((const float (*)[2])tpl, m, t);
		for (i = 0; i < SAMPLES; i++)
			d += hypotf(t[i][0] - in[i][0], t[i][1] - in[i][1]);
		d /= SAMPLES;
		addcand(c, &nc, 12, e.word, e.score - (int)(d * d * 400));
	}
	for (i = 0; i < nc && i < max; i++)
		snprintf(out[i], WORD_MAX, "%s", c[i].word);
	return nc < max ? nc : max;
}
