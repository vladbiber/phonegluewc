/* languages for the keyboard: reads the model registry, downloads, verifies, installs and removes.
 * Runs only while asked, prints one fact per line for the keyboard, and takes no text being typed. */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include "langnames.h"

#ifndef DATADIR
#define DATADIR "/usr/local/share/phonegluewc/keyboard"
#endif
#define REGISTRY "https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/translations-models/records"
#define CDN "https://firefox-settings-attachments.cdn.mozilla.net/"
/* the https base of index.tsv: a tag, so a phone only gets new packs with a new build */
#define PACKS "https://raw.githubusercontent.com/vladbiber/phonegluewc-langpacks/v1"
#define MAX_FILE (300L * 1024 * 1024)
#define MAX_RECS 4096
#define LEN(a) (sizeof(a) / sizeof *(a))

typedef struct {
	char from[16], to[16], ver[16], type[12], hash[65], loc[420];
	long size;
	int android;
} Rec;

typedef struct {
	const Rec *f[4]; /* model lex vocab */
	long total;
} Pair;

static Rec *recs;
static int nrecs;
static char models[800], dataroot[800], cachedir[800], stage[900];
static const char *registry = REGISTRY, *cdn = CDN, *packs = PACKS, *proto = "=https";
static volatile sig_atomic_t stop;
static pid_t curl_pid;
static long prog_done, prog_total;

static void
onterm(int s)
{
	stop = 1;
}

static const char *
envor(const char *name, const char *fallback)
{
	const char *v = getenv(name);

	return v && *v ? v : fallback;
}

static void
paths(void)
{
	const char *home = envor("HOME", "/tmp"), *d = getenv("XDG_DATA_HOME"), *c = getenv("XDG_CACHE_HOME");
	char base[700];

	snprintf(base, sizeof base, "%s", d && *d ? d : "");
	if (!base[0])
		snprintf(base, sizeof base, "%s/.local/share", home);
	snprintf(dataroot, sizeof dataroot, "%s/phonekbd", base);
	if (getenv("PHONETEXT_MODELS"))
		snprintf(models, sizeof models, "%s", getenv("PHONETEXT_MODELS"));
	else
		snprintf(models, sizeof models, "%s/phonegluewc/translate", base);
	if (c && *c)
		snprintf(cachedir, sizeof cachedir, "%s/phonekbd", c);
	else
		snprintf(cachedir, sizeof cachedir, "%s/.cache/phonekbd", home);
	/* a different address also lifts the https rule, which only tests do */
	if (getenv("PHONEKBD_REGISTRY") || getenv("PHONEKBD_CDN") || getenv("PHONEKBD_PACKS"))
		proto = "=https,http,file";
	registry = envor("PHONEKBD_REGISTRY", REGISTRY);
	cdn = envor("PHONEKBD_CDN", CDN);
	packs = envor("PHONEKBD_PACKS", PACKS);
}

static int
mkdirs(const char *path)
{
	char tmp[1000];

	snprintf(tmp, sizeof tmp, "%s", path);
	for (char *p = tmp + 1; *p; p++)
		if (*p == '/') {
			*p = 0;
			if (mkdir(tmp, 0755) && errno != EEXIST)
				return -1;
			*p = '/';
		}
	return mkdir(tmp, 0755) && errno != EEXIST ? -1 : 0;
}

static int
rmone(const char *p, const struct stat *st, int kind, struct FTW *ftw)
{
	return remove(p);
}

static void
rmtree(const char *p)
{
	nftw(p, rmone, 16, FTW_DEPTH | FTW_PHYS);
}

/* --- untrusted names --- */
static int
validcode(const char *s)
{
	size_t n = strlen(s);

	if (n < 2 || n > 12 || !strcmp(s, "en"))
		return 0;
	for (; *s; s++)
		if (!((*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') || *s == '-'))
			return 0;
	return 1;
}

static int
validloc(const char *s)
{
	if (!*s || *s == '/' || strstr(s, ".."))
		return 0;
	for (; *s; s++)
		if (!((*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') || (*s >= '0' && *s <= '9') || strchr("/_.-", *s)))
			return 0;
	return 1;
}

static int
validhash(const char *s)
{
	int n = 0;

	for (; *s; s++, n++)
		if (!((*s >= '0' && *s <= '9') || (*s >= 'a' && *s <= 'f')))
			return 0;
	return n == 64;
}

static int
validutf8(const unsigned char *s, size_t n)
{
	for (size_t i = 0; i < n; ) {
		int extra = s[i] < 0x80 ? 0 : (s[i] & 0xe0) == 0xc0 ? 1 : (s[i] & 0xf0) == 0xe0 ? 2 : (s[i] & 0xf8) == 0xf0 ? 3 : -1;

		if (extra < 0 || i + (size_t)extra >= n)
			return 0;
		for (int e = 1; e <= extra; e++)
			if ((s[i + (size_t)e] & 0xc0) != 0x80)
				return 0;
		i += (size_t)extra + 1;
	}
	return 1;
}

/* --- sha256 --- */
static const uint32_t K[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be,
	0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa,
	0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85,
	0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
	0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f,
	0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};
#define R(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void
shablock(uint32_t *h, const unsigned char *p)
{
	uint32_t w[64], v[8];

	for (int i = 0; i < 16; i++)
		w[i] = (uint32_t)p[i * 4] << 24 | (uint32_t)p[i * 4 + 1] << 16 | (uint32_t)p[i * 4 + 2] << 8 | p[i * 4 + 3];
	for (int i = 16; i < 64; i++)
		w[i] = w[i - 16] + (R(w[i - 15], 7) ^ R(w[i - 15], 18) ^ (w[i - 15] >> 3)) + w[i - 7] + (R(w[i - 2], 17) ^ R(w[i - 2], 19) ^ (w[i - 2] >> 10));
	memcpy(v, h, sizeof v);
	for (int i = 0; i < 64; i++) {
		uint32_t a = v[0], e = v[4];
		uint32_t t1 = v[7] + (R(e, 6) ^ R(e, 11) ^ R(e, 25)) + ((e & v[5]) ^ (~e & v[6])) + K[i] + w[i];
		uint32_t t2 = (R(a, 2) ^ R(a, 13) ^ R(a, 22)) + ((a & v[1]) ^ (a & v[2]) ^ (v[1] & v[2]));

		memmove(v + 1, v, 7 * sizeof *v);
		v[4] += t1;
		v[0] = t1 + t2;
	}
	for (int i = 0; i < 8; i++)
		h[i] += v[i];
}

static int
sha256file(const char *path, char out[65])
{
	uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
	static unsigned char buf[65536];
	unsigned char tail[128];
	uint64_t bytes = 0;
	size_t n, rest = 0, tl;
	FILE *f = fopen(path, "rb");

	if (!f)
		return -1;
	while ((n = fread(buf + rest, 1, sizeof buf - rest, f)) > 0) {
		size_t off = 0;

		bytes += n;
		n += rest;
		for (; n - off >= 64; off += 64)
			shablock(h, buf + off);
		rest = n - off;
		memmove(buf, buf + off, rest);
	}
	fclose(f);
	memset(tail, 0, sizeof tail);
	memcpy(tail, buf, rest);
	tail[rest] = 0x80;
	tl = rest < 56 ? 64 : 128;
	for (int i = 0; i < 8; i++)
		tail[tl - 1 - (size_t)i] = (unsigned char)((bytes * 8) >> (i * 8));
	shablock(h, tail);
	if (tl == 128)
		shablock(h, tail + 64);
	for (int i = 0; i < 8; i++)
		sprintf(out + i * 8, "%08x", h[i]);
	return 0;
}

/* --- fetching: curl has no shell around it, and the address came through the checks above --- */
static int
fetch(const char *url, const char *dest, long maxsize, int counted)
{
	char limit[32];
	int st = 0;
	struct stat sb;

	snprintf(limit, sizeof limit, "%ld", maxsize);
	curl_pid = fork();
	if (curl_pid < 0)
		return -1;
	if (!curl_pid) {
		int null = open("/dev/null", O_RDWR);

		dup2(null, 0);
		dup2(null, 1);
		dup2(null, 2);
		execlp("curl", "curl", "--fail", "--silent", "--proto", proto, "--max-filesize", limit, "--connect-timeout", "15",
			"--speed-time", "30", "--speed-limit", "1", "--output", dest, "--", url, (char *)NULL);
		_exit(127);
	}
	for (;;) {
		struct timespec t = {0, 100 * 1000 * 1000};
		pid_t r = waitpid(curl_pid, &st, WNOHANG);

		if (r == curl_pid)
			break;
		if (stop)
			kill(curl_pid, SIGTERM);
		if (counted && !stat(dest, &sb)) {
			printf("P %ld %ld\n", prog_done + sb.st_size, prog_total);
			fflush(stdout);
		}
		nanosleep(&t, NULL);
	}
	curl_pid = 0;
	return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

/* --- the registry's JSON: only what is needed, and anything odd drops the record --- */
static const char *
ws(const char *p)
{
	while (*p == ' ' || *p == '\n' || *p == '\t' || *p == '\r')
		p++;
	return p;
}

static const char *
strend(const char *p)
{
	for (p++; *p && *p != '"'; p++)
		if (*p == '\\' && p[1])
			p++;
	return *p == '"' ? p : NULL;
}

/* past one value, NULL if malformed */
static const char *
skipval(const char *p)
{
	int depth = 0;

	p = ws(p);
	do {
		if (*p == '"') {
			if (!(p = strend(p)))
				return NULL;
			p++;
		} else if (*p == '{' || *p == '[') {
			if (++depth > 32)
				return NULL;
			p++;
		} else if (*p == '}' || *p == ']') {
			depth--;
			p++;
		} else if (!*p) {
			return NULL;
		} else if (depth) {
			p++;
		} else {
			while (*p && !strchr(",}] \n\t\r", *p))
				p++;
		}
	} while (depth > 0);
	return p;
}

static void
copystr(char *out, size_t size, const char *start, const char *end)
{
	size_t n = (size_t)(end - start - 1);

	if (n >= size || memchr(start + 1, '\\', n))
		n = 0;
	memcpy(out, start + 1, n);
	out[n] = 0;
}

static const char *
readobj(const char *p, Rec *r, int inner)
{
	p = ws(p);
	if (*p != '{')
		return NULL;
	p = ws(p + 1);
	while (*p != '}') {
		const char *ks, *ke, *v;

		if (*p != '"' || !(ke = strend(p)))
			return NULL;
		ks = p + 1;
		size_t kl = (size_t)(ke - ks);
		p = ws(ke + 1);
		if (*p != ':')
			return NULL;
		v = ws(p + 1);
#define KEY(s) (kl == sizeof(s) - 1 && !memcmp(ks, s, kl))
		if (*v == '"') {
			const char *e = strend(v);

			if (!e)
				return NULL;
			if (!inner && KEY("fromLang"))
				copystr(r->from, sizeof r->from, v, e);
			else if (!inner && KEY("toLang"))
				copystr(r->to, sizeof r->to, v, e);
			else if (!inner && KEY("version"))
				copystr(r->ver, sizeof r->ver, v, e);
			else if (!inner && KEY("fileType"))
				copystr(r->type, sizeof r->type, v, e);
			else if (inner && KEY("hash"))
				copystr(r->hash, sizeof r->hash, v, e);
			else if (inner && KEY("location"))
				copystr(r->loc, sizeof r->loc, v, e);
			else if (!inner && KEY("filter_expression")) {
				char f[160];

				copystr(f, sizeof f, v, e);
				r->android = strstr(f, "== 'Android'") ? 1 : !f[0] || strstr(f, "!= 'Android'") ? 0 : -1;
			}
			p = e + 1;
		} else if (inner && KEY("size")) {
			r->size = strtol(v, NULL, 10);
			if (!(p = skipval(v)))
				return NULL;
		} else if (!inner && KEY("attachment")) {
			if (!(p = readobj(v, r, 1)))
				return NULL;
		} else if (!(p = skipval(v))) {
			return NULL;
		}
		p = ws(p);
		if (*p == ',')
			p = ws(p + 1);
		else if (*p != '}')
			return NULL;
	}
	return p + 1;
}

static int
parseregistry(const char *path)
{
	FILE *f = fopen(path, "rb");
	struct stat st;
	char *buf;
	const char *p;

	if (!f)
		return -1;
	if (fstat(fileno(f), &st) || st.st_size <= 0 || st.st_size > 32L * 1024 * 1024 || !(buf = malloc((size_t)st.st_size + 1))) {
		fclose(f);
		return -1;
	}
	buf[fread(buf, 1, (size_t)st.st_size, f)] = 0;
	fclose(f);
	recs = calloc(MAX_RECS, sizeof *recs);
	nrecs = 0;
	if (!(p = strstr(buf, "\"data\"")) || !(p = strchr(p, '[')) || !recs) {
		free(buf);
		return -1;
	}
	p = ws(p + 1);
	while (p && *p == '{' && nrecs < MAX_RECS) {
		Rec r = {0};

		p = readobj(p, &r, 0);
		if (!p)
			break;
		p = ws(p);
		if (*p == ',')
			p = ws(p + 1);
		/* an alpha, a channel-only entry or a bad name never makes it in */
		if (!validcode(!strcmp(r.from, "en") ? r.to : r.from) || (strcmp(r.from, "en") && strcmp(r.to, "en")))
			continue;
		if (strchr(r.ver, 'a') || r.android < 0 || !validloc(r.loc) || !validhash(r.hash) || r.size <= 0 || r.size > MAX_FILE)
			continue;
		recs[nrecs++] = r;
	}
	free(buf);
	return nrecs ? 0 : -1;
}

static double
vernum(const char *v)
{
	return strtod(v, NULL);
}

/* one direction's files: separate vocabularies do not load here, so they do not count.
 * Among complete versions the phone build wins, then the newest. */
static int
pickpair(const char *from, const char *to, Pair *out)
{
	double best = -1;

	memset(out, 0, sizeof *out);
	for (int i = 0; i < nrecs; i++) {
		const Rec *r = &recs[i];

		if (strcmp(r->from, from) || strcmp(r->to, to) || strcmp(r->type, "model"))
			continue;
		const Rec *lex = NULL, *voc = NULL;
		for (int j = 0; j < nrecs; j++) {
			const Rec *q = &recs[j];

			if (strcmp(q->from, from) || strcmp(q->to, to) || strcmp(q->ver, r->ver) || q->android != r->android)
				continue;
			if (!strcmp(q->type, "lex"))
				lex = q;
			else if (!strcmp(q->type, "vocab"))
				voc = q;
		}
		double score = vernum(r->ver) + (r->android ? 1000 : 0);

		if (lex && voc && score > best) {
			best = score;
			out->f[0] = r;
			out->f[1] = lex;
			out->f[2] = voc;
			out->total = r->size + lex->size + voc->size;
		}
	}
	return best >= 0;
}

/* --- what is on the disk --- */
static int
pairinstalled(const char *from, const char *to)
{
	char p[1000];
	struct stat st;

	snprintf(p, sizeof p, "%s/%s-%s/model", models, from, to);
	if (!stat(p, &st))
		return 1;
	snprintf(p, sizeof p, "%s/model.%s%s.intgemm.alphas.bin", models, from, to);
	return !stat(p, &st);
}

static int
installed(const char *code)
{
	return pairinstalled("en", code) || pairinstalled(code, "en");
}

static const char *
langname(const char *code)
{
	for (size_t i = 0; i < LEN(lang_names); i++)
		if (!strcmp(lang_names[i].code, code))
			return lang_names[i].name;
	return code;
}

/* pack files by language from index.tsv: line "code name size sha256" */
typedef struct {
	char code[16], name[16], hash[65];
	long size;
} PackFile;
static PackFile packfiles[512];
static int npackfiles;

static void
parseindex(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[256];

	npackfiles = 0;
	if (!f)
		return;
	while (fgets(line, sizeof line, f) && npackfiles < (int)LEN(packfiles)) {
		PackFile p = {0};

		if (sscanf(line, "%15s %15s %ld %64s", p.code, p.name, &p.size, p.hash) != 4 || !validcode(p.code) || !validhash(p.hash)
				|| p.size <= 0 || p.size > MAX_FILE)
			continue;
		if (strcmp(p.name, "words.tsv") && strcmp(p.name, "bigrams.tsv") && strcmp(p.name, "letters"))
			continue;
		packfiles[npackfiles++] = p;
	}
	fclose(f);
}

static long
packsize(const char *code)
{
	long n = 0;

	for (int i = 0; i < npackfiles; i++)
		if (!strcmp(packfiles[i].code, code))
			n += packfiles[i].size;
	return n;
}

static int
cmpstr(const void *a, const void *b)
{
	return strcmp(langname(*(char *const *)a), langname(*(char *const *)b));
}

static void
listinstalledonly(void)
{
	DIR *d = opendir(models);
	struct dirent *e;

	while (d && (e = readdir(d))) {
		char a[32], b[32];

		if (sscanf(e->d_name, "%31[^.]", a) == 1 && e->d_name[0] != '.' && !strncmp(a, "en-", 3) && validcode(a + 3) && installed(a + 3))
			printf("L %s\t%s\tinstalled\t0\tinstalled\t%d\n", a + 3, langname(a + 3), packsize(a + 3) > 0);
		else if (sscanf(e->d_name, "%31[^-]-%31s", a, b) == 2 && !strcmp(b, "en") && validcode(a) && !pairinstalled("en", a))
			printf("L %s\t%s\tinstalled\t0\tinstalled\t0\n", a, langname(a));
		else if (!strcmp(e->d_name, "model.enro.intgemm.alphas.bin"))
			printf("L ro\t%s\tinstalled\t0\tinstalled\t0\n", langname("ro"));
	}
	if (d)
		closedir(d);
}

static void
cleanstale(void)
{
	DIR *d = opendir(models);
	struct dirent *e;

	while (d && (e = readdir(d)))
		if (!strncmp(e->d_name, ".stage-", 7)) {
			char p[1000];

			snprintf(p, sizeof p, "%s/%s", models, e->d_name);
			rmtree(p);
		}
	if (d)
		closedir(d);
}

/* the list, fresh when there is a network; a saved one otherwise */
static int
cmdlist(void)
{
	char reg[900], tmp[900], idx[900], idxtmp[900], url[1000];
	const char *state = "online";
	char *codes[256];
	int ncodes = 0;

	mkdirs(cachedir);
	cleanstale();
	snprintf(reg, sizeof reg, "%s/registry.json", cachedir);
	snprintf(tmp, sizeof tmp, "%s/registry.json.tmp", cachedir);
	snprintf(idx, sizeof idx, "%s/packs.tsv", cachedir);
	snprintf(idxtmp, sizeof idxtmp, "%s/packs.tsv.tmp", cachedir);
	if (!fetch(registry, tmp, 32L * 1024 * 1024, 0) && !parseregistry(tmp)) {
		rename(tmp, reg);
	} else {
		unlink(tmp);
		free(recs);
		recs = NULL;
		state = stop ? "cancelled" : "cached";
		if (parseregistry(reg))
			state = "offline";
	}
	if (packs[0]) {
		snprintf(url, sizeof url, "%s/index.tsv", packs);
		if (!fetch(url, idxtmp, 1024 * 1024, 0))
			rename(idxtmp, idx);
		else
			unlink(idxtmp);
	}
	parseindex(idx);
	printf("S %s\n", state);
	if (!strcmp(state, "offline")) {
		listinstalledonly();
		return 0;
	}
	for (int i = 0; i < nrecs; i++) {
		const char *c = !strcmp(recs[i].from, "en") ? recs[i].to : recs[i].from;
		int seen = 0;

		for (int j = 0; j < ncodes && !seen; j++)
			seen = !strcmp(codes[j], c);
		if (!seen && ncodes < (int)LEN(codes))
			codes[ncodes++] = (char *)c;
	}
	qsort(codes, (size_t)ncodes, sizeof *codes, cmpstr);
	for (int i = 0; i < ncodes; i++) {
		Pair a, b;
		int to = pickpair("en", codes[i], &a), from = pickpair(codes[i], "en", &b);
		long size = (to ? a.total : 0) + (from ? b.total : 0) + packsize(codes[i]);

		printf("L %s\t%s\t%s\t%ld\t%s\t%d\n", codes[i], langname(codes[i]), to && from ? "both" : from ? "toen" : to ? "fromen" : "none", size,
			installed(codes[i]) ? "installed" : to || from ? "available" : "unavailable", packsize(codes[i]) > 0);
	}
	return 0;
}

/* --- word data: base plus every pack, kept sorted for the keyboard's binary search --- */
typedef struct {
	char *key, *word, *line;
	int score;
	const char *code;
} Row;

static char *
slurp(const char *path, size_t *len)
{
	FILE *f = fopen(path, "rb");
	struct stat st;
	char *b;

	if (!f)
		return NULL;
	if (fstat(fileno(f), &st) || st.st_size < 0 || !(b = malloc((size_t)st.st_size + 1))) {
		fclose(f);
		return NULL;
	}
	*len = fread(b, 1, (size_t)st.st_size, f);
	b[*len] = 0;
	fclose(f);
	return b;
}

/* a pack is not trusted just because its hash matched an index */
static int
checkwords(const char *path)
{
	size_t n;
	char *b = slurp(path, &n), *p;
	int ok = b != NULL && n > 0 && !memchr(b, 0, n) && validutf8((unsigned char *)b, n);

	for (p = b; ok && *p; ) {
		char *nl = strchr(p, '\n'), *t1, *t2, *t3;

		if (!nl || !(t1 = memchr(p, '\t', (size_t)(nl - p))) || !(t2 = memchr(t1 + 1, '\t', (size_t)(nl - t1 - 1)))
				|| !(t3 = memchr(t2 + 1, '\t', (size_t)(nl - t2 - 1))))
			ok = 0;
		else if (t1 == p || t1 - p >= 64 || t2 - t1 - 1 >= 64 || nl - t3 != 2 || t3[1] != 'r' || atoi(t2 + 1) <= 0 || atoi(t2 + 1) > 1000)
			ok = 0;
		else
			p = nl + 1;
	}
	free(b);
	return ok;
}

static int
checkbigrams(const char *path)
{
	size_t n;
	char *b = slurp(path, &n), *p;
	int ok = b != NULL && !memchr(b, 0, n) && validutf8((unsigned char *)b, n);

	for (p = b; ok && *p; ) {
		char *nl = strchr(p, '\n'), *t;

		if (!nl || !(t = memchr(p, '\t', (size_t)(nl - p))) || t == p || t - p >= 64 || nl - p > 512)
			ok = 0;
		else
			p = nl + 1;
	}
	free(b);
	return ok;
}

static int
checkletters(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[64], base[8], low[8], up[8];
	int ok = f != NULL, rows = 0;

	while (ok && fgets(line, sizeof line, f)) {
		if (sscanf(line, "%7[^\t]\t%7[^\t]\t%7[^\n]", base, low, up) != 3 || strlen(base) != 1 || base[0] < 'a' || base[0] > 'z'
				|| !validutf8((unsigned char *)low, strlen(low)) || !validutf8((unsigned char *)up, strlen(up))
				|| !(low[0] & 0x80) || !(up[0] & 0x80) || ++rows > 40)
			ok = 0;
	}
	if (f)
		fclose(f);
	return ok;
}

static int
cmprow(const void *a, const void *b)
{
	const Row *x = a, *y = b;
	int c = strcmp(x->key, y->key);

	if (c)
		return c;
	if (x->score != y->score)
		return y->score - x->score;
	return strcmp(x->word, y->word);
}

static int
addwords(Row **rows, int *n, int *cap, char *b, const char *code)
{
	for (char *p = b; p && *p; ) {
		char *nl = strchr(p, '\n'), *t1, *t2, *t3;

		if (!nl)
			break;
		*nl = 0;
		if ((t1 = strchr(p, '\t')) && (t2 = strchr(t1 + 1, '\t')) && (t3 = strchr(t2 + 1, '\t'))) {
			if (*n == *cap && !(*rows = realloc(*rows, sizeof **rows * (size_t)(*cap *= 2))))
				return -1;
			*t1 = *t2 = *t3 = 0;
			(*rows)[(*n)++] = (Row){.key = p, .word = t1[1] ? t1 + 1 : p, .score = atoi(t2 + 1), .code = code};
		}
		p = nl + 1;
	}
	return 0;
}

static int
samerow(const Row *a, const Row *b)
{
	return !strcmp(a->key, b->key) && !strcmp(a->word, b->word);
}

static int
cmpname(const void *a, const void *b)
{
	return strcmp(*(char *const *)a, *(char *const *)b);
}

static int
listpacks(char *names[], int max)
{
	char dir[1000];
	DIR *d;
	struct dirent *e;
	int n = 0;

	snprintf(dir, sizeof dir, "%s/langs", dataroot);
	if (!(d = opendir(dir)))
		return 0;
	while ((e = readdir(d)) && n < max)
		if (e->d_name[0] != '.' && validcode(e->d_name))
			names[n++] = strdup(e->d_name);
	closedir(d);
	qsort(names, (size_t)n, sizeof *names, cmpname);
	return n;
}

static int
putfile(const char *name, char *body, size_t len)
{
	char path[1000], tmp[1000];
	FILE *f;
	int fd;

	snprintf(path, sizeof path, "%s/%s", dataroot, name);
	snprintf(tmp, sizeof tmp, "%s/.%s.tmp", dataroot, name);
	if ((fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644)) < 0 || !(f = fdopen(fd, "w")))
		return -1;
	if (fwrite(body, 1, len, f) != len) {
		fclose(f);
		unlink(tmp);
		return -1;
	}
	fflush(f);
	fsync(fileno(f));
	fclose(f);
	return rename(tmp, path);
}

static int
mergewords(char *names[], int n)
{
	char p[1000], *buf;
	const char *data = envor("PHONEKBD_DATA", DATADIR);
	size_t len, cap = 1 << 20, o = 0;
	Row *rows = malloc(sizeof *rows * 65536);
	int nr = 0, rcap = 65536;

	snprintf(p, sizeof p, "%s/words.tsv", data);
	if (!rows || !(buf = slurp(p, &len)) || addwords(&rows, &nr, &rcap, buf, "en"))
		return -1;
	for (int i = 0; i < n; i++) {
		snprintf(p, sizeof p, "%s/langs/%s/words.tsv", dataroot, names[i]);
		if (!(buf = slurp(p, &len)) || addwords(&rows, &nr, &rcap, buf, names[i]))
			return -1;
	}
	qsort(rows, (size_t)nr, sizeof *rows, cmprow);
	if (!(buf = malloc(cap)))
		return -1;
	/* the same word from several sources is one row, tagged with each: en,ro */
	for (int i = 0; i < nr; i++) {
		char tag[128];
		int skip = 0;

		for (int j = i - 1; j >= 0 && !strcmp(rows[j].key, rows[i].key) && !skip; j--)
			skip = samerow(&rows[j], &rows[i]);
		if (skip)
			continue;
		snprintf(tag, sizeof tag, "%s", rows[i].code);
		/* sorted by score: this row holds the highest */
		for (int j = i + 1; j < nr && !strcmp(rows[j].key, rows[i].key); j++)
			if (samerow(&rows[j], &rows[i]) && !strstr(tag, rows[j].code) && strlen(tag) + strlen(rows[j].code) + 2 < sizeof tag)
				strcat(strcat(tag, ","), rows[j].code);
		if (o + 256 > cap && !(buf = realloc(buf, cap *= 2)))
			return -1;
		o += (size_t)sprintf(buf + o, "%s\t%s\t%d\t%s\n", rows[i].key, !strcmp(rows[i].word, rows[i].key) ? "" : rows[i].word, rows[i].score, tag);
	}
	return putfile("words.tsv", buf, o);
}

typedef struct { char *head, *nexts; int order, src; } Bi;

static int
cmpbi(const void *a, const void *b)
{
	const Bi *x = a, *y = b;
	int c = strcmp(x->head, y->head);

	return c ? c : x->order - y->order;
}

static int
mergebigrams(char *names[], int n)
{
	char p[1000], *buf;
	const char *data = envor("PHONEKBD_DATA", DATADIR);
	size_t len, cap = 1 << 18, o = 0;
	int nb = 0, bcap = 16384;
	Bi *bi = malloc(sizeof *bi * (size_t)bcap);

	/* English, then "|ro", "|fr" and so on: each language keeps its own order, shared words included */
	for (int i = -1; i < n; i++) {
		if (i >= 0)
			snprintf(p, sizeof p, "%s/langs/%s/bigrams.tsv", dataroot, names[i]);
		else
			snprintf(p, sizeof p, "%s/bigrams.tsv", data);
		if (!bi || !(buf = slurp(p, &len)))
			continue;
		for (char *l = buf, *nl; *l && (nl = strchr(l, '\n')); l = nl + 1) {
			char *t;

			*nl = 0;
			if (!(t = strchr(l, '\t')))
				continue;
			*t = 0;
			if (nb == bcap && !(bi = realloc(bi, sizeof *bi * (size_t)(bcap *= 2))))
				return -1;
			bi[nb] = (Bi){l, t + 1, nb, i};
			nb++;
		}
	}
	if (!bi)
		return -1;
	qsort(bi, (size_t)nb, sizeof *bi, cmpbi);
	if (!(buf = malloc(cap)))
		return -1;
	for (int i = 0; i < nb; ) {
		int j = i;

		if (o + 8192 > cap && !(buf = realloc(buf, cap *= 2)))
			return -1;
		o += (size_t)sprintf(buf + o, "%s\t", bi[i].head);
		size_t start = o, seg = o;
		int src = -1;
		for (; j < nb && !strcmp(bi[j].head, bi[i].head); j++) {
			char tmp[1024], *sv = NULL;

			snprintf(tmp, sizeof tmp, "%s", bi[j].nexts);
			if (bi[j].src != src) {
				src = bi[j].src;
				o += (size_t)sprintf(buf + o, "%s|%s", o > start ? " " : "", names[src]);
				seg = o + 1;
			}
			for (char *w = strtok_r(tmp, " ", &sv); w; w = strtok_r(NULL, " ", &sv)) {
				size_t wl = strlen(w);
				int dup = 0;

				for (char *q = buf + seg; q < buf + o && !dup; ) {
					char *sp = memchr(q, ' ', (size_t)(buf + o - q));
					size_t ql = sp ? (size_t)(sp - q) : (size_t)(buf + o - q);

					dup = ql == wl && !memcmp(q, w, wl);
					q += ql + 1;
				}
				/* shortcut: a head common to all languages can lose the last ones past 4000 bytes, raise it if a language goes quiet */
				if (!dup && o - start + wl + 2 < 4000)
					o += (size_t)sprintf(buf + o, "%s%s", o > start ? " " : "", w);
			}
		}
		buf[o++] = '\n';
		i = j;
	}
	return putfile("bigrams.tsv", buf, o);
}

static int
mergeletters(char *names[], int n)
{
	static char out[8192], keep[8192];
	char p[1000], *b;
	size_t len, o = 0, ko = 0;

	/* the password page keeps every letter ever installed: a password outlives its language */
	snprintf(p, sizeof p, "%s/password-letters", dataroot);
	if ((b = slurp(p, &len))) {
		if (len < sizeof keep)
			memcpy(keep, b, ko = len);
		free(b);
	}
	keep[ko] = 0;
	for (int i = 0; i < n; i++) {
		char line[64], *e;
		FILE *f;

		snprintf(p, sizeof p, "%s/langs/%s/letters", dataroot, names[i]);
		if (!(f = fopen(p, "r")))
			continue;
		while (fgets(line, sizeof line, f)) {
			if (!(e = strchr(line, '\n')))
				continue;
			len = (size_t)(e - line) + 1;
			line[len] = 0;
			if (!strstr(out, line) && o + len < sizeof out - 1) {
				memcpy(out + o, line, len);
				o += len;
				out[o] = 0;
			}
			if (!strstr(keep, line) && ko + len < sizeof keep - 1) {
				memcpy(keep + ko, line, len);
				ko += len;
				keep[ko] = 0;
			}
		}
		fclose(f);
	}
	if (ko && putfile("password-letters", keep, ko))
		return -1;
	return putfile("letters", out, o);
}

static int
cmdmerge(void)
{
	char *names[128], p[1000];
	int n;

	if (mkdirs(dataroot))
		return 1;
	n = listpacks(names, (int)LEN(names));
	if (!n) {
		/* back to the base; the letters of what was removed stay for passwords */
		snprintf(p, sizeof p, "%s/words.tsv", dataroot);
		unlink(p);
		snprintf(p, sizeof p, "%s/bigrams.tsv", dataroot);
		unlink(p);
		snprintf(p, sizeof p, "%s/letters", dataroot);
		unlink(p);
		return 0;
	}
	return mergewords(names, n) || mergebigrams(names, n) || mergeletters(names, n);
}

/* --- install and remove --- */
/* the on list follows what is installed; with no key the keyboard already takes everything */
static void
keylangs(const char *code, int add)
{
	const char *x = getenv("XDG_CONFIG_HOME"), *h = getenv("HOME");
	char p[900], tmp[920], line[512];
	FILE *in, *out;
	int fd;

	if (x && *x)
		snprintf(p, sizeof p, "%s/phonekbd/config", x);
	else
		snprintf(p, sizeof p, "%s/.config/phonekbd/config", h ? h : "/tmp");
	snprintf(tmp, sizeof tmp, "%s.tmp", p);
	if (!(in = fopen(p, "r")))
		return;
	if ((fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600)) < 0 || !(out = fdopen(fd, "w"))) {
		fclose(in);
		return;
	}
	while (fgets(line, sizeof line, in)) {
		const char *t = line + strspn(line, " \t");
		char *eq = strchr(line, '='), *sv = NULL;
		int have = 0;

		if (strncmp(t, "predict_languages", 17) || !strchr(" \t=", t[17]) || !eq) {
			fputs(line, out);
			continue;
		}
		eq[strcspn(eq, "#")] = 0;
		fputs("predict_languages =", out);
		for (char *c = strtok_r(eq + 1, " \t\r\n", &sv); c; c = strtok_r(NULL, " \t\r\n", &sv)) {
			have |= !strcmp(c, code);
			if (strcmp(c, code) || add)
				fprintf(out, " %s", c);
		}
		fprintf(out, "%s%s\n", add && !have ? " " : "", add && !have ? code : "");
	}
	fclose(in);
	if (fclose(out) == 0)
		rename(tmp, p);
}

static int
faildown(const char *msg)
{
	printf("E %s\n", msg);
	fflush(stdout);
	if (stage[0])
		rmtree(stage);
	return 1;
}

static int
getone(const char *url, const char *dest, long size, const char *hash)
{
	char got[65];
	struct stat st;
	int rc = fetch(url, dest, size + 1, 1);

	if (stop)
		return 3;
	if (rc == 6 || rc == 7 || rc == 28 || rc == 35 || rc == 56 || rc == 52 || rc == 18)
		return 4;
	if (rc)
		return 5;
	if (stat(dest, &st) || st.st_size != size || sha256file(dest, got) || strcmp(got, hash))
		return 6;
	prog_done += size;
	printf("P %ld %ld\n", prog_done, prog_total);
	fflush(stdout);
	return 0;
}

/* only what we tested: 6 encoder layers, 2 or 4 decoder layers, one shared vocabulary */
static int
modellayers(const char *path)
{
	FILE *f = fopen(path, "rb");
	static char buf[1 << 16];
	size_t n;
	char *a, *b;
	int enc, dec;

	if (!f)
		return 0;
	/* marian keeps its settings as text at the very end of the file */
	if (fseek(f, -(long)(sizeof buf - 1), SEEK_END))
		rewind(f);
	n = fread(buf, 1, sizeof buf - 1, f);
	fclose(f);
	buf[n] = 0;
	for (size_t i = 0; i < n; i++)
		if (!buf[i])
			buf[i] = ' ';
	a = strstr(buf, "enc-depth: ");
	b = strstr(buf, "dec-depth: ");
	if (!a || !b || !strstr(buf, "tied-embeddings-all: true"))
		return 0;
	enc = atoi(a + 11);
	dec = atoi(b + 11);
	return enc == 6 && (dec == 2 || dec == 4) ? dec : 0;
}

static int
getpair(const char *from, const char *to, const Pair *pr)
{
	static const char *names[3] = {"model", "lex", "vocab"};
	char dir[1000], dest[1100], url[1600], lay[1100];
	int rc, layers;
	FILE *f;

	snprintf(dir, sizeof dir, "%s/%s-%s", stage, from, to);
	if (mkdir(dir, 0755))
		return 5;
	for (int i = 0; i < 3; i++) {
		snprintf(dest, sizeof dest, "%s/%s", dir, names[i]);
		snprintf(url, sizeof url, "%s%s", cdn, pr->f[i]->loc);
		if ((rc = getone(url, dest, pr->f[i]->size, pr->f[i]->hash)))
			return rc;
	}
	snprintf(dest, sizeof dest, "%s/model", dir);
	if (!(layers = modellayers(dest)))
		return 7;
	snprintf(lay, sizeof lay, "%s/layers", dir);
	if (!(f = fopen(lay, "w")))
		return 5;
	fprintf(f, "%d\n", layers);
	return fclose(f) ? 5 : 0;
}

static int
downerr(int rc)
{
	return faildown(rc == 3 ? "Cancelled" : rc == 4 ? "No connection. Nothing was installed." : rc == 6 ? "A file failed its check. Nothing was installed."
		: rc == 7 ? "This language's model is not supported here. Nothing was installed." : "The download failed. Nothing was installed.");
}

static void
commitpair(const char *from, const char *to)
{
	char src[1100], dst[1000], old[1100];
	struct stat st;

	snprintf(src, sizeof src, "%s/%s-%s", stage, from, to);
	snprintf(dst, sizeof dst, "%s/%s-%s", models, from, to);
	if (stat(src, &st))
		return;
	snprintf(old, sizeof old, "%s/.stage-old-%s-%s", models, from, to);
	rename(dst, old);
	rename(src, dst);
	rmtree(old);
}

static int
cmdinstall(const char *code)
{
	char reg[900], idx[900], dir[1100], dest[1200], url[1600];
	struct statvfs vfs;
	Pair to, from;
	int hasto, hasfrom, rc;

	if (!validcode(code))
		return faildown("Bad language name.");
	signal(SIGTERM, onterm);
	signal(SIGINT, onterm);
	mkdirs(models);
	cleanstale();
	snprintf(reg, sizeof reg, "%s/registry.json", cachedir);
	snprintf(idx, sizeof idx, "%s/packs.tsv", cachedir);
	if (parseregistry(reg))
		return faildown("Open the language list first.");
	parseindex(idx);
	hasto = pickpair("en", code, &to);
	hasfrom = pickpair(code, "en", &from);
	if (!hasto && !hasfrom)
		return faildown("This language has no model that works here.");
	prog_total = (hasto ? to.total : 0) + (hasfrom ? from.total : 0) + packsize(code);
	if (!statvfs(models, &vfs) && (unsigned long long)vfs.f_bavail * vfs.f_frsize < (unsigned long long)prog_total + (1 << 20))
		return faildown("Not enough free space.");
	snprintf(stage, sizeof stage, "%s/.stage-%s", models, code);
	if (mkdir(stage, 0755))
		return faildown("Cannot write the language folder.");
	printf("P 0 %ld\n", prog_total);
	fflush(stdout);
	if ((hasto && (rc = getpair("en", code, &to))) || (hasfrom && (rc = getpair(code, "en", &from))))
		return downerr(rc);
	/* the keyboard's words for this language, when a pack exists */
	if (packsize(code) > 0) {
		snprintf(dir, sizeof dir, "%s/pack", stage);
		if (mkdir(dir, 0755))
			return downerr(5);
		for (int i = 0; i < npackfiles; i++) {
			if (strcmp(packfiles[i].code, code))
				continue;
			snprintf(dest, sizeof dest, "%s/%s", dir, packfiles[i].name);
			snprintf(url, sizeof url, "%s/%s/%s", packs, code, packfiles[i].name);
			if ((rc = getone(url, dest, packfiles[i].size, packfiles[i].hash)))
				return downerr(rc);
		}
		snprintf(dest, sizeof dest, "%s/words.tsv", dir);
		if (!checkwords(dest))
			return downerr(6);
		snprintf(dest, sizeof dest, "%s/bigrams.tsv", dir);
		if (!checkbigrams(dest))
			return downerr(6);
		snprintf(dest, sizeof dest, "%s/letters", dir);
		if (!checkletters(dest))
			return downerr(6);
	}
	if (stop)
		return downerr(3);
	/* from here on nothing can be half there: each step is a rename */
	signal(SIGTERM, SIG_IGN);
	signal(SIGINT, SIG_IGN);
	if (packsize(code) > 0) {
		char lang[1000];

		snprintf(lang, sizeof lang, "%s/langs", dataroot);
		mkdirs(lang);
		snprintf(lang, sizeof lang, "%s/langs/%s", dataroot, code);
		rmtree(lang);
		if (rename(dir, lang))
			return downerr(5);
		if (cmdmerge()) {
			rmtree(lang);
			cmdmerge();
			return downerr(5);
		}
	}
	if (hasto)
		commitpair("en", code);
	if (hasfrom)
		commitpair(code, "en");
	rmtree(stage);
	snprintf(dir, sizeof dir, "%s/langs/%s/words.tsv", dataroot, code);
	if (!access(dir, R_OK))
		keylangs(code, 1);
	printf("D\n");
	return 0;
}

static int
cmdremove(const char *code)
{
	char p[1100];
	static const char *flat[] = {"model.%s%s.intgemm.alphas.bin", "vocab.%s%s.spm", "lex.50.50.%s%s.s2t.bin"};

	if (!validcode(code))
		return faildown("Bad language name.");
	snprintf(p, sizeof p, "%s/en-%s", models, code);
	rmtree(p);
	snprintf(p, sizeof p, "%s/%s-en", models, code);
	rmtree(p);
	for (size_t i = 0; i < LEN(flat); i++) {
		char name[128];

		snprintf(name, sizeof name, flat[i], "en", code);
		snprintf(p, sizeof p, "%s/%s", models, name);
		unlink(p);
		snprintf(name, sizeof name, flat[i], code, "en");
		snprintf(p, sizeof p, "%s/%s", models, name);
		unlink(p);
	}
	snprintf(p, sizeof p, "%s/langs/%s", dataroot, code);
	rmtree(p);
	if (cmdmerge())
		return faildown("Could not update the word list.");
	keylangs(code, 0);
	printf("D\n");
	return 0;
}

int
main(int argc, char **argv)
{
	signal(SIGPIPE, SIG_IGN);
	umask(022);
	paths();
	if (argc == 2 && !strcmp(argv[1], "list"))
		return cmdlist();
	if (argc == 2 && !strcmp(argv[1], "merge"))
		return cmdmerge();
	if (argc == 3 && !strcmp(argv[1], "install"))
		return cmdinstall(argv[2]);
	if (argc == 3 && !strcmp(argv[1], "remove"))
		return cmdremove(argv[2]);
	if (argc == 4 && !strcmp(argv[1], "sha256")) {
		char got[65];

		return sha256file(argv[2], got) || strcmp(got, argv[3]);
	}
	fprintf(stderr, "usage: phonekbd-lang list | install CODE | remove CODE | merge\n");
	return 2;
}
