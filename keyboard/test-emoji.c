/* self check for emoji.c: ./test-emoji data/emoji.tsv [font]; no font to test with is a failure, not a pass */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "emoji.h"
#include "words.h"

int
main(int argc, char **argv)
{
	FT_Library ft;
	char dir[] = "/tmp/emoji-test.XXXXXX", toned[EMOJI_SEQ], path[64];
	int found[64], n, w, h, kind, nochar = 0, opaque = 0, pizza = 0;
	const uint32_t *g;
	struct timespec a, b;

	assert(argc > 1);
	assert(!FT_Init_FreeType(&ft));
	assert(mkdtemp(dir));
	if (argc > 2)
		setenv("PHONEKBD_EMOJI_FONT", argv[2], 1);

	/* no font: a clear answer, and no leftovers */
	setenv("PHONEKBD_EMOJI_FONT", "none", 1);
	assert(emoji_open(ft, argv[1], dir) == EMOJI_NONE);
	assert(emoji_count() == 0);
	emoji_close();
	/* a font without emoji is refused rather than drawing blanks */
	if (!access("/usr/share/fonts/noto/NotoSans-Regular.ttf", R_OK)) {
		setenv("PHONEKBD_EMOJI_FONT", "/usr/share/fonts/noto/NotoSans-Regular.ttf", 1);
		assert(emoji_open(ft, argv[1], dir) == EMOJI_NONE);
	}
	if (argc > 2)
		setenv("PHONEKBD_EMOJI_FONT", argv[2], 1);
	else
		unsetenv("PHONEKBD_EMOJI_FONT");

	clock_gettime(CLOCK_MONOTONIC, &a);
	kind = emoji_open(ft, argv[1], dir);
	clock_gettime(CLOCK_MONOTONIC, &b);
	if (kind == EMOJI_NONE) {
		puts("emoji NOT tested: no emoji font on this machine");
		return 77;
	}
	printf("font %s: %s, %d drawable, opened in %ld ms\n", emoji_font_path(), kind == EMOJI_COLOR ? "colour" : "mono",
		emoji_count(), (b.tv_sec - a.tv_sec) * 1000 + (b.tv_nsec - a.tv_nsec) / 1000000);
	assert(emoji_count() > 500);

	assert(emoji_first(0) && !strcmp(emoji_first(0), "😀"));
	n = emoji_search("pizza", found, 64);
	assert(n >= 1);
	for (int i = 0; i < n; i++)
		pizza |= !strcmp(emoji_at(found[i])->seq, "🍕");
	assert(pizza);
	/* the Romanian word, typed without diacritics */
	n = emoji_search("inima", found, 64);
	assert(n >= 1);
	n = emoji_search("zzqxv", found, 64);
	assert(n == 0);

	if (kind == EMOJI_COLOR) {
		const Emoji *wave = NULL;

		for (int i = 0; i < emoji_count(); i++)
			if (!strcmp(emoji_at(i)->seq, "👋"))
				wave = emoji_at(i);
		assert(wave && wave->tone[0]);
		assert(emoji_toned(wave, 2, toned, sizeof toned) && !strcmp(toned, "👋🏽"));
		/* a joined sequence comes from the GSUB reader, a flag from its pair */
		assert(emoji_glyph("👩‍💻", 80, &w, &h));
		assert(emoji_glyph("🇷🇴", 80, &w, &h));
		assert(emoji_glyph("#️⃣", 80, &w, &h));
		g = emoji_glyph("😀", 80, &w, &h);
		assert(g && w <= 80 && h <= 80 && w > 60 && h > 60);
		for (int i = 0; i < w * h; i++) {
			nochar += !g[i];
			opaque += g[i] >> 24 == 255;
		}
		/* round face: transparent corners around solid colour */
		assert(nochar > 0 && opaque > w * h / 3);
		/* more glyphs than the cache: the oldest make room */
		for (int i = 0; i < emoji_count(); i += 10)
			emoji_glyph(emoji_at(i)->seq, 60, &w, &h);
		assert(emoji_glyph("😀", 80, &w, &h));
	}

	emoji_recent_add("😀");
	emoji_recent_add("🍕");
	emoji_recent_add("😀");
	assert(emoji_recent_count() == 2 && !strcmp(emoji_recent(0), "😀"));
	for (int i = 0; i < 40; i++)
		emoji_recent_add(emoji_at(i)->seq);
	assert(emoji_recent_count() == EMOJI_RECENT);
	emoji_recent_add("🍕");
	emoji_close();
	assert(emoji_count() == 0);
	assert(emoji_open(ft, argv[1], dir) == kind);
	assert(emoji_recent_count() == EMOJI_RECENT && !strcmp(emoji_recent(0), "🍕"));
	emoji_close();

	/* cleared from outside while open: not written back */
	assert(emoji_open(ft, argv[1], dir) == kind);
	emoji_recent_add("😀");
	snprintf(path, sizeof path, "%s/emoji-recent", dir);
	unlink(path);
	snprintf(path, sizeof path, "%s/emoji-cleared", dir);
	fclose(fopen(path, "w"));
	emoji_close();
	snprintf(path, sizeof path, "%s/emoji-recent", dir);
	assert(access(path, F_OK));

	unlink(path);
	snprintf(path, sizeof path, "%s/emoji-cleared", dir);
	unlink(path);
	rmdir(dir);
	FT_Done_FreeType(ft);
	puts("emoji ok");
	return 0;
}
