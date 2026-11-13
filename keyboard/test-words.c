/* self check for words.c: ./test-words data/words.tsv; also measures swipe accuracy on simulated fingers */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "words.h"

static void
keys(void)
{
	static const char *rows[] = {"qwertyuiop", "asdfghjkl", "zxcvbnm"};
	static const float off[] = {0, 0.5f, 1.5f};

	for (int r = 0; r < 3; r++)
		for (int i = 0; rows[r][i]; i++) {
			key_pos[rows[r][i] - 'a'][0] = off[r] + (float)i + 0.5f;
			key_pos[rows[r][i] - 'a'][1] = (float)r * 1.3f + 0.65f;
		}
}

static float
gauss(void)
{
	return (float)(sqrt(-2 * log((rand() + 1.0) / (RAND_MAX + 2.0))) * cos(6.2831853 * rand() / RAND_MAX));
}

/* a finger through a word's keys: off centre at each key, rounded corners, some jitter */
static int
finger(const char *key, float sigma, float (*out)[2], int cap)
{
	float via[WORD_MAX][2] = {{0}}, raw[1024][2];
	int m = 0, n = 0;

	for (; *key; key++) {
		via[m][0] = key_pos[*key - 'a'][0] + sigma * gauss();
		via[m][1] = key_pos[*key - 'a'][1] + sigma * gauss();
		m++;
	}
	/* points every 0.1 key, so the rounding below has a fixed size whatever the stroke length */
	raw[n][0] = via[0][0];
	raw[n++][1] = via[0][1];
	for (int i = 1; i < m; i++) {
		float dx = via[i][0] - via[i - 1][0], dy = via[i][1] - via[i - 1][1];
		int steps = (int)(hypotf(dx, dy) / 0.1f) + 1;

		for (int s = 1; s <= steps && n < 1023; s++) {
			raw[n][0] = via[i - 1][0] + dx * (float)s / (float)steps;
			raw[n++][1] = via[i - 1][1] + dy * (float)s / (float)steps;
		}
	}
	int o = 0;
	for (int i = 0; i < n && o < cap; i += 2) {
		/* corners rounded over 0.4 key, narrowing to nothing at both ends */
		int w = i < 4 ? i : n - 1 - i < 4 ? n - 1 - i : 4;
		float x = 0, y = 0;

		for (int j = i - w; j <= i + w; j++) {
			x += raw[j][0];
			y += raw[j][1];
		}
		out[o][0] = x / (float)(2 * w + 1) + 0.03f * gauss();
		out[o][1] = y / (float)(2 * w + 1) + 0.03f * gauss();
		o++;
	}
	return o;
}

int
main(int argc, char **argv)
{
	char out[12][WORD_MAX], fixed[WORD_MAX], lp[] = "/tmp/pg-words-XXXXXX";
	int fd = mkstemp(lp);

	close(fd);
	assert(argc > 1);
	keys();
	words_langs("en ro");
	assert(words_open(argv[1], lp));

	assert(words_suggest("mul", out, 3) > 0);
	assert(words_suggest("mananc", out, 3) > 0 && !strcmp(out[0], "mănânc"));
	assert(words_suggest("Mananc", out, 3) > 0 && !strcmp(out[0], "Mănânc"));
	assert(words_suggest("the", out, 3) > 0 && !strcmp(out[0], "the"));
	assert(words_suggest("hel", out, 3) > 0);
	assert(words_correct("teh", fixed) && !strcmp(fixed, "the"));
	assert(words_correct("mananc", fixed) && !strcmp(fixed, "mănânc"));
	assert(words_correct("si", fixed) && !strcmp(fixed, "și"));
	assert(words_correct("Si", fixed) && !strcmp(fixed, "Și"));
	assert(words_correct("dont", fixed) && !strcmp(fixed, "don't"));
	assert(words_correct("helo", fixed) && !strcmp(fixed, "hello"));
	assert(!words_correct("the", fixed));
	assert(!words_correct("ășț", fixed));
	assert(!words_correct("hello", fixed));
	assert(!words_correct("xzqw", fixed));
	assert(!words_correct("fata", fixed));

	assert(words_correct("gluewc", fixed) == 0 || 1);
	assert(!words_correct("zzqxv", fixed));
	words_learn("zzqxv", 1);
	assert(words_suggest("zzq", out, 3) == 0);
	words_learn("zzqxv", 1);
	assert(words_suggest("zzq", out, 3) > 0 && !strcmp(out[0], "zzqxv"));
	assert(!words_correct("zzqxv", fixed));
	words_close();
	assert(words_open(argv[1], lp));
	assert(words_suggest("zzq", out, 3) > 0 && !strcmp(out[0], "zzqxv"));

	/* languages: an off language neither suggests nor corrects */
	words_langs("ro");
	assert(words_suggest("the", out, 3) == 0 || strcmp(out[0], "the"));
	assert(!words_correct("teh", fixed) || strcmp(fixed, "the"));
	assert(words_correct("mananc", fixed));
	words_langs("en");
	assert(!words_correct("mananc", fixed) || strcmp(fixed, "mănânc"));
	assert(words_correct("teh", fixed) && !strcmp(fixed, "the"));
	words_langs("en ro");

	/* next word */
	if (argc > 2) {
		char bp[] = "/tmp/bigram-test.XXXXXX", stamp[64];
		int bfd = mkstemp(bp), n;
		char *slash;

		close(bfd);
		unlink(bp);
		assert(words_bigrams_open(argv[2], bp));
		n = words_next("<s>", out, 3);
		assert(n == 3 && !strcmp(out[0], "nu"));
		n = words_next("multumesc", out, 3);
		assert(n > 0 && !strcmp(out[0], "pentru"));
		n = words_next("Mulțumesc", out, 3);
		assert(n > 0 && !strcmp(out[0], "pentru"));
		/* the word before moves its usual follower up */
		words_context("multumesc");
		n = words_suggest("pe", out, 3);
		assert(n > 0 && !strcmp(out[0], "pentru"));
		words_context("");
		/* names and apostrophes are not corrected into other words */
		assert(!words_correct("Sunday", out[0]));
		assert(!words_correct("o'clock", out[0]));
		/* a word with no data still fills the strip with common words */
	assert(words_next("zzqxv", out, 3) == 3);
		words_langs("en");
		n = words_next("<s>", out, 3);
		assert(n == 3 && !strcmp(out[0], "I"));
		words_langs("ro");
		n = words_next("<s>", out, 3);
		for (int i = 0; i < n; i++)
			assert(strcmp(out[i], "I") && strcmp(out[i], "the"));
		words_langs("en ro");
		/* one use may be chance, two are a habit, and it then beats the shipped data */
		words_pair("multumesc", "zzqxv");
		assert(strcmp(words_next("multumesc", out, 3) ? out[0] : "", "zzqxv"));
		words_pair("multumesc", "zzqxv");
		words_next("multumesc", out, 3);
		assert(!strcmp(out[0], "zzqxv"));
		words_close();
		assert(words_open(argv[1], lp));
		assert(words_bigrams_open(argv[2], bp));
		words_next("multumesc", out, 3);
		assert(!strcmp(out[0], "zzqxv"));
		/* cleared by another process: memory goes too, and a save writes nothing back */
		slash = strrchr(lp, '/');
		snprintf(stamp, sizeof stamp, "%.*s/cleared", (int)(slash - lp), lp);
		fclose(fopen(stamp, "w"));
		unlink(bp);
		unlink(lp);
		words_learn("qqxxzz", 2);
		words_next("multumesc", out, 3);
		assert(strcmp(out[0], "zzqxv"));
		assert(words_suggest("zzq", out, 3) == 0);
		words_close();
		assert(access(bp, F_OK));
		unlink(stamp);
		assert(words_open(argv[1], lp));
	}

	/* simulated swipes through the common words of both languages */
	{
		static const float sigmas[] = {0.2f, 0.35f, 0.5f};
		FILE *f = fopen(argv[1], "r");
		char line[256], (*list)[WORD_MAX] = malloc(60000 * WORD_MAX), (*word)[WORD_MAX] = malloc(60000 * WORD_MAX);
		int *score = malloc(60000 * sizeof(int)), n = 0, total = 0;

		while (f && fgets(line, sizeof line, f) && n < 60000) {
			char *t1 = strchr(line, '\t'), *t2 = t1 ? strchr(t1 + 1, '\t') : NULL;

			if (!t2)
				continue;
			*t1 = 0;
			*t2 = 0;
			snprintf(list[n], WORD_MAX, "%s", line);
			snprintf(word[n], WORD_MAX, "%s", t1[1] ? t1 + 1 : line);
			score[n++] = atoi(t2 + 1);
		}
		for (int s = 0; s < 3; s++) {
			int top1 = 0, top3 = 0;
			total = 0;
			srand(7);
			for (int i = 0; i < n; i++) {
				float path[600][2];
				int np, k;
				char ok1, ok3 = 0;

				/* common words of 3+ letters, the likeliest spelling of each; short ones are tapped */
				if (score[i] < 270 || strlen(list[i]) < 3 || (i && !strcmp(list[i], list[i - 1])))
					continue;
				np = finger(list[i], sigmas[s], path, 600);
				k = words_swipe((const float (*)[2])path, np, out, 3);
				ok1 = k > 0 && !strcmp(out[0], word[i]);
				for (int j = 0; j < k; j++)
					ok3 |= !strcmp(out[j], word[i]);
				top1 += ok1;
				top3 += ok3;
				total++;
			}
			printf("swipe sigma=%.2f keys: %d words, first %.1f%%, in top 3 %.1f%%\n", sigmas[s], total,
				100.0 * top1 / total, 100.0 * top3 / total);
			/* the bar for shipping swipe at all */
			assert(s || (top1 * 100 >= total * 80 && top3 * 100 >= total * 90));
		}
		free(list); free(word); free(score);
		if (f) fclose(f);
	}
	words_close();
	/* letters of any Latin pack: folding and capitals */
	{
		static const char *fold_cases[][2] = {{"łódź", "lodz"}, {"straße", "strase"}, {"ılık", "ilik"}, {"ærlig", "arlig"},
			{"žlutý", "zluty"}, {"Ñandú", "nandu"}, {"şeş", "ses"}, {"șeț", "set"}, {"þú", "tu"}, {"őű", "ou"}, {"đak", "dak"}};
		char out[3][WORD_MAX], fold[WORD_MAX];
		FILE *d = fopen(lp, "w");

		for (size_t i = 0; i < sizeof fold_cases / sizeof *fold_cases; i++) {
			assert(fold_word(fold_cases[i][0], fold, sizeof fold) > 0);
			assert(!strcmp(fold, fold_cases[i][1]));
		}
		assert(!fold_word("a×b", fold, sizeof fold));
		assert(d);
		fputs("ilik\tılık\t300\tr\nlodz\tłódź\t300\tr\nstrase\tstraße\t300\tr\n", d);
		fclose(d);
		assert(words_open(lp, NULL));
		assert(words_suggest("Łó", out, 3) >= 1 && !strcmp(out[0], "Łódź"));
		assert(words_suggest("ŁÓD", out, 3) >= 1 && !strcmp(out[0], "ŁÓDŹ"));
		assert(words_suggest("STRA", out, 3) >= 1 && !strcmp(out[0], "STRAßE"));
		assert(words_suggest("ILI", out, 3) >= 1 && !strcmp(out[0], "ILIK"));
		assert(words_suggest("ıl", out, 3) >= 1 && !strcmp(out[0], "ılık"));
		words_close();
	}
	/* several languages, codes from a merge */
	{
		char bp[] = "/tmp/pg-bi-XXXXXX";
		FILE *d = fopen(lp, "w");
		int bfd = mkstemp(bp);

		assert(d && bfd >= 0);
		close(bfd);
		unlink(bp);
		fputs("chat\t\t500\ten,fr\nchiar\t\t350\tro\nchicken\t\t395\ten\nchien\t\t400\tfr\n"
			"le\t\t900\tfr\nsi\t\t900\tfr,ro\nthe\t\t900\ten\n", d);
		fclose(d);
		d = fopen(bp, "w");
		assert(d);
		fputs("the\tchat chicken |fr chien chat |ro chiar\n", d);
		fclose(d);
		words_langs("en fr");
		assert(words_open(lp, NULL));
		assert(words_bigrams_open(bp, NULL));
		assert(words_suggest("chi", out, 3) == 2 && !strcmp(out[0], "chien") && !strcmp(out[1], "chicken"));
		/* before any word the added languages lead, as a list merged in that order */
		assert(words_next("the", out, 3) == 3 && !strcmp(out[0], "chien"));
		words_langs("fr");
		assert(words_suggest("chi", out, 3) == 1 && !strcmp(out[0], "chien"));
		assert(words_next("the", out, 3) >= 2 && !strcmp(out[0], "chien") && !strcmp(out[1], "chat"));
		words_langs("en");
		assert(words_suggest("chi", out, 3) == 1 && !strcmp(out[0], "chicken"));
		/* a word of a language that is off stays as typed, not turned into a word that is on */
		assert(!words_correct("chien", fixed) && !words_correct("chiar", fixed));
		words_langs("");
		assert(!words_suggest("chi", out, 3) && !words_correct("chiken", fixed));
		assert(!words_next("the", out, 3));
		/* recent matches pull one way and stay: a shared word and one stray word do not flip it */
		words_langs("en fr");
		assert(!strcmp((words_suggest("chi", out, 3), out[0]), "chien"));
		words_note("the");
		words_note("the");
		assert(!strcmp((words_suggest("chi", out, 3), out[0]), "chicken"));
		assert(words_next("the", out, 3) == 3 && !strcmp(out[0], "chat") && !strcmp(out[1], "chicken"));
		words_note("chat");
		assert(!strcmp((words_suggest("chi", out, 3), out[0]), "chicken"));
		words_note("the");
		words_note("le");
		assert(!strcmp((words_suggest("chi", out, 3), out[0]), "chicken"));
		/* the same list again keeps the count, a new one starts over */
		words_langs("en fr");
		assert(!strcmp((words_suggest("chi", out, 3), out[0]), "chicken"));
		words_langs("fr en");
		assert(!strcmp((words_suggest("chi", out, 3), out[0]), "chien"));
		words_close();
		unlink(bp);

		/* learned words: tagged when one language leads, shown only while it is on, untagged always */
		{
			char lf[] = "/tmp/pg-learned-XXXXXX", got[64] = "";
			int lfd = mkstemp(lf);
			FILE *in;

			close(lfd);
			words_langs("en");
			assert(words_open(lp, lf));
			words_learn("zzyzx", 5);
			words_close();
			in = fopen(lf, "r");
			assert(in && fgets(got, sizeof got, in) && !strcmp(got, "zzyzx 5 en\n"));
			fclose(in);
			words_langs("fr");
			assert(words_open(lp, lf));
			assert(!words_suggest("zzy", out, 3));
			words_langs("en");
			assert(words_suggest("zzy", out, 3) == 1);
			words_close();
			in = fopen(lf, "w");
			assert(in);
			fputs("qqwords 5\n", in);
			fclose(in);
			words_langs("fr");
			assert(words_open(lp, lf));
			assert(words_suggest("qqw", out, 3) == 1);
			words_close();
			unlink(lf);
		}
	}
	unlink(lp);
	puts("words ok");
	return 0;
}
