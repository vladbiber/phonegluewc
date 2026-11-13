#define _GNU_SOURCE
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "ocr.h"

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

void
ocr_free(Ocr *o)
{
	for (int i = 0; i < o->nblocks; i++) {
		free(o->blocks[i].src);
		free(o->blocks[i].dst);
	}
	free(o->words);
	free(o->blocks);
	free(o->text);
	memset(o, 0, sizeof *o);
}

/* single stray marks are how tesseract reads icons and edges */
static int
isnoise(const char *w, int conf)
{
	size_t n = strlen(w);
	int alnum = 0;

	for (const char *p = w; *p; p++)
		if (isalnum((unsigned char)*p) || (*p & 0x80))
			alnum = 1;
	return conf < OCR_MIN_CONF || !alnum || (n == 1 && conf < 80);
}

/* the models lose the comma of the commonest Romanian word; "si" means nothing else there */
static void
fixcomma(char *w)
{
	if ((w[0] == 's' || w[0] == 'S') && w[1] == 'i' && (ispunct((unsigned char)w[2]) || !w[2])) {
		memmove(w + 3, w + 2, strlen(w + 2) + 1);
		w[1] = w[0] == 's' ? (char)0x99 : (char)0x98;
		w[0] = (char)0xc8;
		w[2] = 'i';
	}
}

int
ocr_parse(Ocr *o, const char *tsv)
{
	const char *p = tsv;
	size_t tlen = 0, tcap = strlen(tsv) + 1;
	int cap = 0, lastkey[3] = {-1, -1, -1}, block = -1, line = -1;

	memset(o, 0, sizeof *o);
	if (!(o->text = malloc(tcap)))
		return -1;
	while (*p) {
		const char *end = strchr(p, '\n');
		size_t len = end ? (size_t)(end - p) : strlen(p);
		int level, page, bl, par, ln, wn, x, y, w, h, off = 0;
		float conf;

		if (sscanf(p, "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%f\t%n", &level, &page, &bl, &par, &ln, &wn,
				&x, &y, &w, &h, &conf, &off) == 11 && level == 5 && off && (size_t)off < len) {
			char word[256];
			size_t wlen = MIN(len - (size_t)off, sizeof word - 1);

			memcpy(word, p + off, wlen);
			word[wlen] = 0;
			if (word[wlen ? wlen - 1 : 0] == '\r')
				word[wlen - 1] = 0;
			if (!isnoise(word, (int)conf)) {
				if (o->nwords == cap) {
					OcrWord *nw;

					cap = cap ? cap * 2 : 256;
					if (!(nw = realloc(o->words, (size_t)cap * sizeof *nw)))
						return -1;
					o->words = nw;
				}
				if (bl != lastkey[0] || par != lastkey[1]) {
					block++;
					line = -1;
					lastkey[2] = -1;
				}
				if (ln != lastkey[2])
					line++;
				lastkey[0] = bl;
				lastkey[1] = par;
				lastkey[2] = ln;
				o->words[o->nwords++] = (OcrWord){x, y, w, h, block, line, (int)tlen};
				memcpy(o->text + tlen, word, strlen(word) + 1);
				tlen += strlen(word) + 2; /* room for fixcomma */
			}
		}
		p += len + (end ? 1 : 0);
	}
	if (ocr_language(o) == 'r')
		for (int i = 0; i < o->nwords; i++)
			fixcomma(o->text + o->words[i].text);
	o->nblocks = block + 1;
	if (o->nblocks && !(o->blocks = calloc((size_t)o->nblocks, sizeof *o->blocks)))
		return -1;
	for (int i = 0; i < o->nblocks; i++)
		o->blocks[i].first = -1;
	for (int i = 0; i < o->nwords; i++) {
		const OcrWord *w = &o->words[i];
		OcrBlock *b = &o->blocks[w->block];

		if (b->first < 0) {
			b->first = i;
			b->x = w->x;
			b->y = w->y;
			b->w = w->w;
			b->h = w->h;
		}
		b->last = i;
		{
			int r = MAX(b->x + b->w, w->x + w->w), d = MAX(b->y + b->h, w->y + w->h);

			b->x = MIN(b->x, w->x);
			b->y = MIN(b->y, w->y);
			b->w = r - b->x;
			b->h = d - b->y;
		}
	}
	for (int i = 0; i < o->nblocks; i++) {
		OcrBlock *b = &o->blocks[i];

		if (b->first >= 0 && !(b->src = ocr_selection(o, b->first, b->last)))
			return -1;
		/* a paragraph is one sentence stream for the translator, wherever its lines broke */
		for (char *c = b->src; c && *c; c++)
			if (*c == '\n')
				*c = ' ';
	}
	return 0;
}

char *
ocr_selection(const Ocr *o, int a, int b)
{
	size_t n = 1;
	char *s, *q;

	if (a > b) {
		int t = a;

		a = b;
		b = t;
	}
	if (a < 0 || b >= o->nwords)
		return strdup("");
	for (int i = a; i <= b; i++)
		n += strlen(o->text + o->words[i].text) + 1;
	if (!(q = s = malloc(n)))
		return NULL;
	for (int i = a; i <= b; i++) {
		size_t l = strlen(o->text + o->words[i].text);

		memcpy(q, o->text + o->words[i].text, l);
		q += l;
		if (i < b)
			*q++ = o->words[i].block == o->words[i + 1].block && o->words[i].line == o->words[i + 1].line ? ' ' : '\n';
	}
	*q = 0;
	return s;
}

int
ocr_nearest(const Ocr *o, int x, int y, int maxdist)
{
	long best = (long)maxdist * maxdist;
	int at = -1;

	for (int i = 0; i < o->nwords; i++) {
		const OcrWord *w = &o->words[i];
		long dx = x < w->x ? w->x - x : x > w->x + w->w ? x - w->x - w->w : 0;
		long dy = y < w->y ? w->y - y : y > w->y + w->h ? y - w->y - w->h : 0;
		long d = dx * dx + dy * dy;

		if (d <= best) {
			best = d;
			at = i;
			if (!d)
				break;
		}
	}
	return at;
}

char *
ocr_blocks_text(const Ocr *o)
{
	size_t n = 1;
	char *s, *q;

	for (int i = 0; i < o->nblocks; i++)
		n += (o->blocks[i].src ? strlen(o->blocks[i].src) : 0) + 1;
	if (!(q = s = malloc(n)))
		return NULL;
	for (int i = 0; i < o->nblocks; i++) {
		const char *t = o->blocks[i].src ? o->blocks[i].src : "";
		size_t l = strlen(t);

		memcpy(q, t, l);
		q += l;
		*q++ = '\n';
	}
	*q = 0;
	return s;
}

char
ocr_language(const Ocr *o)
{
	static const char *ro[] = {"și", "si", "în", "este", "sunt", "de", "la", "cu", "pe", "un", "o", "care", "nu", "pentru", "din", "să", "mai", "ce", "al", "ale"};
	static const char *en[] = {"the", "and", "is", "are", "of", "to", "in", "for", "with", "on", "that", "this", "it", "you", "was", "from", "be", "at", "by", "or"};
	int r = 0, e = 0;

	for (int i = 0; i < o->nwords; i++) {
		const char *w = o->text + o->words[i].text;
		char clean[64];
		size_t n = 0;

		/* ă â î ș ț and their capitals, plus the cedilla forms old fonts give */
		if (strstr(w, "ă") || strstr(w, "â") || strstr(w, "î") || strstr(w, "ș") || strstr(w, "ț")
				|| strstr(w, "ş") || strstr(w, "ţ") || strstr(w, "Ă") || strstr(w, "Î") || strstr(w, "Ș") || strstr(w, "Ț"))
			r += 2;
		for (; *w && n < sizeof clean - 1; w++)
			if (isalpha((unsigned char)*w) || (*w & 0x80))
				clean[n++] = *w;
		clean[n] = 0;
		for (size_t k = 0; k < sizeof ro / sizeof *ro; k++)
			if (!strcasecmp(clean, ro[k]))
				r++;
		for (size_t k = 0; k < sizeof en / sizeof *en; k++)
			if (!strcasecmp(clean, en[k]))
				e++;
	}
	return r > e ? 'r' : 'e';
}

char *
url_encode(const char *s)
{
	static const char hex[] = "0123456789ABCDEF";
	char *out = malloc(strlen(s) * 3 + 1), *q = out;

	if (!out)
		return NULL;
	for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
		if (isalnum(*p) || *p == '-' || *p == '_' || *p == '.' || *p == '~') {
			*q++ = (char)*p;
		} else {
			*q++ = '%';
			*q++ = hex[*p >> 4];
			*q++ = hex[*p & 15];
		}
	}
	*q = 0;
	return out;
}
