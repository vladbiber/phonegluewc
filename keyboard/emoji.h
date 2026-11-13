#ifndef EMOJI_H
#define EMOJI_H
#include <stdint.h>
#include <ft2build.h>
#include FT_FREETYPE_H

#define EMOJI_GROUPS 9
#define EMOJI_SEQ 48
#define EMOJI_TONES 5
#define EMOJI_RECENT 24

enum { EMOJI_NONE, EMOJI_COLOR, EMOJI_MONO };

typedef struct {
	const char *seq, *tone, *words;
	int group;
} Emoji;

/* loads font and data; returns the font kind. Everything goes in emoji_close, so call it when the panel closes */
int emoji_open(FT_Library ft, const char *data, const char *state_dir);
void emoji_close(void);
const char *emoji_font_path(void);
int emoji_count(void);
const Emoji *emoji_at(int i);
/* the group's first drawable emoji, NULL if none */
const char *emoji_first(int group);
/* indices into emoji_at, whole word matches first */
int emoji_search(const char *query, int *out, int max);
/* tone 0..4 on an emoji with a template; 0 if the font cannot draw it */
int emoji_toned(const Emoji *e, int tone, char *out, int size);
/* premultiplied ARGB, valid until the next call that misses the cache */
const uint32_t *emoji_glyph(const char *seq, int size, int *w, int *h);
int emoji_recent_count(void);
const char *emoji_recent(int i);
void emoji_recent_add(const char *seq);
void emoji_recent_forget(void);
#endif
