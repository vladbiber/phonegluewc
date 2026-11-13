/* self-check for the tesseract tsv parsing and helpers */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ocr.h"

static const char tsv[] =
	"level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n"
	"1\t1\t0\t0\t0\t0\t0\t0\t1080\t2400\t-1\t\n"
	"2\t1\t1\t0\t0\t0\t10\t10\t500\t100\t-1\t\n"
	"5\t1\t1\t1\t1\t1\t10\t10\t100\t30\t95.5\tHello\n"
	"5\t1\t1\t1\t1\t2\t120\t10\t100\t30\t90.0\tworld\n"
	"5\t1\t1\t1\t2\t1\t10\t50\t100\t30\t91.0\tacesta\n"
	"5\t1\t1\t1\t2\t2\t120\t50\t20\t30\t10.0\tjunk\n"
	"5\t1\t1\t1\t2\t3\t150\t50\t20\t30\t96.0\t|\n"
	"5\t1\t2\t1\t1\t1\t10\t200\t200\t40\t88.0\tși\n"
	"5\t1\t2\t1\t1\t2\t220\t200\t100\t40\t88.0\teste\n";

int
main(void)
{
	Ocr o;
	char *s;

	assert(!ocr_parse(&o, tsv));
	assert(o.nwords == 5);
	assert(o.nblocks == 2);
	assert(o.blocks[0].x == 10 && o.blocks[0].w == 210 && o.blocks[0].h == 70);
	assert(!strcmp(o.blocks[0].src, "Hello world acesta"));
	s = ocr_selection(&o, 0, 2);
	assert(!strcmp(s, "Hello world\nacesta"));
	free(s);
	s = ocr_selection(&o, 3, 1);
	assert(!strcmp(s, "world\nacesta\nși"));
	free(s);
	assert(ocr_nearest(&o, 15, 15, 5) == 0);
	assert(ocr_nearest(&o, 1000, 2000, 10) == -1);
	assert(ocr_nearest(&o, 115, 60, 200) == 2);
	s = ocr_blocks_text(&o);
	assert(!strcmp(s, "Hello world acesta\nși este\n"));
	free(s);
	assert(ocr_language(&o) == 'r');
	s = url_encode("a b&ș");
	assert(!strcmp(s, "a%20b%26%C8%99"));
	free(s);
	ocr_free(&o);
	assert(!ocr_parse(&o, "5\t1\t1\t1\t1\t1\t1\t1\t9\t9\t90\tTu\n5\t1\t1\t1\t1\t2\t11\t1\t9\t9\t90\tsi\n"
		"5\t1\t1\t1\t1\t3\t21\t1\t9\t9\t90\teu,\n5\t1\t1\t1\t1\t4\t31\t1\t9\t9\t90\tsunt\n"
		"5\t1\t1\t1\t1\t5\t41\t1\t9\t9\t90\tSi,\n5\t1\t1\t1\t1\t6\t51\t1\t9\t9\t90\tsimplu\n"));
	s = ocr_selection(&o, 0, 5);
	assert(!strcmp(s, "Tu și eu, sunt Și, simplu"));
	free(s);
	ocr_free(&o);
	assert(!ocr_parse(&o, "5\t1\t1\t1\t1\t1\t1\t1\t9\t9\t90\tthe\n5\t1\t1\t1\t1\t2\t11\t1\t9\t9\t90\tsi\n"));
	s = ocr_selection(&o, 0, 1);
	assert(!strcmp(s, "the si"));
	free(s);
	ocr_free(&o);
	assert(!ocr_parse(&o, "garbage\nmore\n"));
	assert(!o.nwords && !o.nblocks);
	ocr_free(&o);
	puts("ocr ok");
	return 0;
}
