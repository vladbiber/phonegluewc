/* hit rates of suggestions and corrections on real phrases: eval-words WORDS BIGRAMS PHRASES [mask] [minhit...] */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "words.h"

static const char *near_[26] = {"s", "v", "x", "s", "r", "d", "h", "j", "o", "k", "l", "k", "n", "m", "p", "o",
	"w", "t", "d", "y", "i", "b", "e", "c", "u", "x"};
static struct { int hit, all; } pre[4], two[4], next_, start, keep, fix, top, plainfix, plaintop, full;

static void
pct(const char *name, int hit, int all)
{
	printf("%-28s %5.1f%%  (%d of %d)\n", name, all ? 100.0 * hit / all : 0.0, hit, all);
}

static int
has(char out[][WORD_MAX], int n, const char *w)
{
	char a[WORD_MAX], b[WORD_MAX];

	if (!fold_word(w, a, sizeof a))
		return 0;
	for (int i = 0; i < n; i++)
		if (!strcasecmp(out[i], w) || (fold_word(out[i], b, sizeof b) && !strcmp(a, b) && !strcasecmp(out[i], w)))
			return 1;
	return 0;
}

static void
oneword(const char *prev, const char *w, int isfirst)
{
	char out[4][WORD_MAX], fixed[WORD_MAX], low[WORD_MAX], fold[WORD_MAX], typo[WORD_MAX];
	size_t len = strlen(w);
	int ascii = 1;

	snprintf(low, sizeof low, "%s", w);
	if (isfirst)
		low[0] = (char)tolower((unsigned char)low[0]);
	for (const char *p = low; *p; p++)
		ascii &= !(*p & 0x80);
	if (prev[0]) {
		int n = words_next(prev, out, 3), first = !strcmp(prev, "<s>");

		(first ? &start : &next_)->all++;
		(first ? &start : &next_)->hit += has(out, n, isfirst ? w : low) || has(out, n, low);
		full.all++;
		full.hit += n == 3;
		words_context(prev);
	}
	/* the first letters, without a case trick: what the strip offers while typing */
	for (int k = 1; k <= 3; k++) {
		char pfx[WORD_MAX];
		int nb = 0, chars = 0;

		while (low[nb] && chars < k) {
			nb++;
			while ((low[nb] & 0xc0) == 0x80)
				nb++;
			chars++;
		}
		if (!low[nb])
			break;
		memcpy(pfx, low, (size_t)nb);
		pfx[nb] = 0;
		pre[k].all++;
		pre[k].hit += has(out, words_suggest(pfx, out, 3), low);
		/* a side slot holds the typed letters, so usually two guesses show */
		two[k].all++;
		two[k].hit += has(out, words_suggest(pfx, out, 2), low);
	}
	if (len < 2)
		return;
	/* a word typed right must stay as it was */
	if (ascii) {
		keep.all++;
		keep.hit += !words_correct(low, fixed);
	}
	if (!fold_word(low, fold, sizeof fold))
		return;
	/* diacritics left out, on purpose or in a hurry */
	if (!ascii) {
		plainfix.all++;
		plainfix.hit += words_correct(fold, fixed) && !strcmp(fixed, low);
		plaintop.all++;
		plaintop.hit += has(out, words_suggest(fold, out, 3), low);
	}
	if (strlen(fold) < 4 || !ascii)
		return;
	/* a neighbouring key in the middle of the word */
	snprintf(typo, sizeof typo, "%s", low);
	typo[len / 2] = isalpha((unsigned char)low[len / 2]) && low[len / 2] >= 'a' ? near_[low[len / 2] - 'a'][0] : low[len / 2];
	if (!strcmp(typo, low))
		return;
	fix.all++;
	fix.hit += words_correct(typo, fixed) && !strcmp(fixed, low);
	top.all++;
	top.hit += has(out, words_suggest(typo, out, 3), low);
}

int
main(int argc, char **argv)
{
	static const char rows[3][11] = {"qwertyuiop", "asdfghjkl", "zxcvbnm"};
	static const float off[3] = {0, 0.5f, 1.5f};
	char line[1024];
	FILE *f;
	int fail = 0;

	if (argc < 4 || !(f = fopen(argv[3], "r")))
		return 2;
	for (int r = 0; r < 3; r++)
		for (int i = 0; rows[r][i]; i++) {
			key_pos[rows[r][i] - 'a'][0] = off[r] + (float)i + 0.5f;
			key_pos[rows[r][i] - 'a'][1] = (float)r * 1.3f + 0.65f;
		}
	if (!words_open(argv[1], NULL) || !words_bigrams_open(argv[2], NULL))
		return 2;
	words_langs(argc > 4 ? argv[4] : "en");
	while (fgets(line, sizeof line, f)) {
		char prev[WORD_MAX] = "<s>", *p = line;
		int first = 1;

		while (*p) {
			char w[WORD_MAX];
			int n = 0;

			while (*p && !(isalpha((unsigned char)*p) || (*p & 0x80)))
				p++;
			while (*p && (isalpha((unsigned char)*p) || (*p & 0x80) || *p == '\'') && n < WORD_MAX - 1)
				w[n++] = *p++;
			w[n] = 0;
			if (!n)
				break;
			oneword(prev, w, first);
			words_note(w);
			snprintf(prev, sizeof prev, "%s", w);
			if (first)
				prev[0] = (char)tolower((unsigned char)prev[0]);
			first = 0;
			/* a hyphen or comma breaks the chain the keyboard follows too */
			if (*p && *p != ' ')
				snprintf(prev, sizeof prev, "%s", *p == ',' ? prev : "");
		}
	}
	pct("after 1 letter, top 3", pre[1].hit, pre[1].all);
	pct("after 2 letters, top 3", pre[2].hit, pre[2].all);
	pct("after 3 letters, top 3", pre[3].hit, pre[3].all);
	pct("after 1 letter, top 2", two[1].hit, two[1].all);
	pct("after 2 letters, top 2", two[2].hit, two[2].all);
	pct("after 3 letters, top 2", two[3].hit, two[3].all);
	pct("next word, top 3", next_.hit, next_.all);
	pct("three shown with no letters", full.hit, full.all);
	pct("sentence start, top 3", start.hit, start.all);
	pct("right word left alone", keep.hit, keep.all);
	pct("typo corrected", fix.hit, fix.all);
	pct("typo fix in top 3", top.hit, top.all);
	pct("no diacritics, corrected", plainfix.hit, plainfix.all);
	pct("no diacritics, in top 3", plaintop.hit, plaintop.all);
	/* floors: after2 next keep typo-top3 */
	if (argc > 5 && 100 * pre[2].hit < atoi(argv[5]) * pre[2].all)
		fail = 1;
	if (argc > 6 && 100 * next_.hit < atoi(argv[6]) * next_.all)
		fail = 1;
	if (argc > 7 && 100 * keep.hit < atoi(argv[7]) * keep.all)
		fail = 1;
	if (argc > 8 && 100 * top.hit < atoi(argv[8]) * top.all)
		fail = 1;
	return fail;
}
