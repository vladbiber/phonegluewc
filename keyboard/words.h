#ifndef WORDS_H
#define WORDS_H
#define WORD_MAX 64

/* where a letter's key sits, in key widths; filled by the caller */
extern float key_pos[26][2];

int words_open(const char *dict, const char *learned);
void words_close(void);
/* best first, in the typed word's case */
int words_suggest(const char *typed, char out[][WORD_MAX], int max);
/* 1 when typed should be replaced by fixed as soon as the word ends */
int words_correct(const char *typed, char *fixed);
void words_learn(const char *word, int weight);
/* the languages on, as "en ro"; a word of none of them neither shows nor corrects */
void words_langs(const char *codes);
int words_bigrams_open(const char *data, const char *learned);
/* a word was written, learning on or off: only pulls suggestions towards its language, kept in memory */
void words_note(const char *word);
/* the word before the one being typed; words_suggest favours what tends to follow it */
void words_context(const char *prev);
/* words likely after prev, "<s>" at a sentence start; common words fill what it leaves */
int words_next(const char *prev, char out[][WORD_MAX], int max);
void words_pair(const char *prev, const char *next);
int words_swipe(const float (*path)[2], int n, char out[][WORD_MAX], int max);
int fold_word(const char *word, char *out, int size);
int utf8_len(const char *s);
#endif
