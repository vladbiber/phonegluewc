/* words read off the frozen screen, in reading order; no toolkit needed, so it can be tested alone */
#ifndef OCR_H
#define OCR_H

#define OCR_MIN_CONF 40

typedef struct {
	int x, y, w, h; /* image pixels */
	int block; /* one block per paragraph */
	int line;
	int text; /* offset into the Ocr text */
} OcrWord;

typedef struct {
	int x, y, w, h;
	int first, last; /* words */
	char *src, *dst; /* dst is the translation, or NULL */
	unsigned bg, fg;
} OcrBlock;

typedef struct {
	OcrWord *words;
	int nwords;
	OcrBlock *blocks;
	int nblocks;
	char *text;
} Ocr;

/* parses `tesseract ... tsv` output; takes a copy of what it needs */
int ocr_parse(Ocr *o, const char *tsv);
void ocr_free(Ocr *o);
/* selected words, spaces between words and newlines between lines; malloc'd */
char *ocr_selection(const Ocr *o, int a, int b);
/* the word nearest to a point, or -1 past maxdist */
int ocr_nearest(const Ocr *o, int x, int y, int maxdist);
/* one line of text per block for the translator; malloc'd */
char *ocr_blocks_text(const Ocr *o);
/* 'r' when the screen reads Romanian, 'e' otherwise */
char ocr_language(const Ocr *o);
/* percent-encodes for a URL query; malloc'd */
char *url_encode(const char *s);

#endif
