/* the lock screen PIN: a salted slow hash in the state dir, a wait after wrong tries, and a per-boot password flag */
#define _GNU_SOURCE
#include <crypt.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define FREE_TRIES 5
#define FIRST_WAIT 30
#define MAX_WAIT (24 * 3600)

static char dir[PATH_MAX - 32], pinf[PATH_MAX], triesf[PATH_MAX], flagf[PATH_MAX];

static int
paths(void)
{
	const char *s = getenv("XDG_STATE_HOME"), *h = getenv("HOME"), *r = getenv("PHONE_RUNTIME_DIR");
	int n;

	/* the laptop window and the tests keep their own; a boot clears either */
	if (!r || !*r)
		r = getenv("XDG_RUNTIME_DIR");
	if (s && *s == '/')
		n = snprintf(dir, sizeof dir, "%s/phonegluewc", s);
	else if (h && *h == '/')
		n = snprintf(dir, sizeof dir, "%s/.local/state/phonegluewc", h);
	else
		return -1;
	if (n < 0 || (size_t)n >= sizeof dir)
		return -1;
	snprintf(pinf, sizeof pinf, "%s/pin", dir);
	snprintf(triesf, sizeof triesf, "%s/pin-tries", dir);
	/* no runtime dir means the password is always needed */
	if (r && *r == '/' && strlen(r) < sizeof flagf - 32)
		snprintf(flagf, sizeof flagf, "%s/phonegluewc-password-used", r);
	return 0;
}

static int
mkdirs(const char *p)
{
	char b[PATH_MAX];
	char *c;

	snprintf(b, sizeof b, "%s", p);
	for (c = b + 1; *c; c++)
		if (*c == '/') {
			*c = 0;
			if (mkdir(b, 0700) && errno != EEXIST)
				return -1;
			*c = '/';
		}
	return mkdir(b, 0700) && errno != EEXIST ? -1 : 0;
}

/* temp file, 0600, fsync, rename: a crash leaves the old file or the new one */
static int
save(const char *path, const char *text)
{
	char tmp[PATH_MAX];
	size_t len = strlen(text);
	int fd;

	if (mkdirs(dir))
		return -1;
	snprintf(tmp, sizeof tmp, "%s.XXXXXX", path);
	if ((fd = mkstemp(tmp)) < 0)
		return -1;
	if (fchmod(fd, 0600) || write(fd, text, len) != (ssize_t)len || fsync(fd)) {
		close(fd);
		unlink(tmp);
		return -1;
	}
	close(fd);
	if (rename(tmp, path)) {
		unlink(tmp);
		return -1;
	}
	return 0;
}

static int
load(const char *path, char *buf, size_t size)
{
	FILE *f = fopen(path, "r");
	size_t n;

	if (!f)
		return -1;
	n = fread(buf, 1, size - 1, f);
	fclose(f);
	buf[n] = 0;
	buf[strcspn(buf, "\n")] = 0;
	return 0;
}

/* only from stdin, never argv: the command line is readable by anyone */
static int
readpin(char out[8])
{
	char b[16];
	size_t n = fread(b, 1, sizeof b - 1, stdin), i;

	b[n] = 0;
	b[strcspn(b, "\r\n")] = 0;
	n = strlen(b);
	if (n < 4 || n > 6)
		return -1;
	for (i = 0; i < n; i++)
		if (b[i] < '0' || b[i] > '9')
			return -1;
	memcpy(out, b, n + 1);
	explicit_bzero(b, sizeof b);
	return 0;
}

static void
tries(long *fails, long *until)
{
	char b[64];

	*fails = *until = 0;
	if (!load(triesf, b, sizeof b) && sscanf(b, "%ld %ld", fails, until) != 2)
		*fails = *until = 0;
}

static long
waitleft(void)
{
	long fails, until, now = (long)time(NULL);

	tries(&fails, &until);
	if (until - now > MAX_WAIT)
		return MAX_WAIT;
	return until > now ? until - now : 0;
}

static int
haspin(void)
{
	return access(pinf, F_OK) == 0;
}

static int
passwordused(void)
{
	return *flagf && access(flagf, F_OK) == 0;
}

static int
setpin(void)
{
	static const char abc[] = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
	unsigned char rnd[16];
	char pin[8], salt[64], line[256];
	const char *h;
	int i, n;

	if (readpin(pin))
		return fprintf(stderr, "a PIN is 4 to 6 digits\n"), 2;
	if (getrandom(rnd, sizeof rnd, 0) != (ssize_t)sizeof rnd)
		return 1;
	n = snprintf(salt, sizeof salt, "$6$rounds=100000$");
	for (i = 0; i < 16; i++)
		salt[n + i] = abc[rnd[i] % 64];
	salt[n + 16] = 0;
	h = crypt(pin, salt);
	explicit_bzero(pin, sizeof pin);
	if (!h || strncmp(h, "$6$", 3))
		return fprintf(stderr, "crypt failed\n"), 1;
	snprintf(line, sizeof line, "%s\n", h);
	if (save(pinf, line))
		return perror("phonepin"), 1;
	unlink(triesf);
	return 0;
}

static int
check(void)
{
	char pin[8], want[256], b[64];
	const char *h;
	long fails, until, now = (long)time(NULL), w;
	int good;

	if (!haspin())
		return 4;
	if ((w = waitleft()) > 0)
		return printf("wait=%ld\n", w), 2;
	if (readpin(pin))
		good = 0;
	else {
		if (load(pinf, want, sizeof want))
			return 1;
		h = crypt(pin, want);
		good = h && !strncmp(h, "$6$", 3) && !strcmp(h, want);
	}
	explicit_bzero(pin, sizeof pin);
	if (good) {
		unlink(triesf);
		return 0;
	}
	tries(&fails, &until);
	fails++;
	w = fails < FREE_TRIES ? 0 : FIRST_WAIT << (fails - FREE_TRIES > 12 ? 12 : fails - FREE_TRIES);
	if (w > MAX_WAIT)
		w = MAX_WAIT;
	snprintf(b, sizeof b, "%ld %ld\n", fails, now + w);
	if (save(triesf, b))
		return perror("phonepin"), 1;
	printf("wait=%ld\n", w);
	return 1;
}

int
main(int argc, char **argv)
{
	long fails, until;
	int fd;

	umask(077);
	if (argc != 2 || paths())
		return fprintf(stderr, "usage: phonepin set|clear|check|status|unlocked, the PIN on stdin\n"), 2;
	if (!strcmp(argv[1], "set"))
		return setpin();
	if (!strcmp(argv[1], "check"))
		return check();
	if (!strcmp(argv[1], "clear")) {
		unlink(triesf);
		return unlink(pinf) && errno != ENOENT;
	}
	if (!strcmp(argv[1], "status")) {
		tries(&fails, &until);
		printf("pin=%d password=%d wait=%ld fails=%ld\n", haspin(), passwordused(), waitleft(), fails);
		return 0;
	}
	if (!strcmp(argv[1], "unlocked")) {
		/* the password was right: PINs work until the next boot, and the wrong tries are forgiven */
		unlink(triesf);
		if (!*flagf || (fd = open(flagf, O_WRONLY | O_CREAT | O_CLOEXEC, 0600)) < 0)
			return 1;
		close(fd);
		return 0;
	}
	return fprintf(stderr, "usage: phonepin set|clear|check|status|unlocked\n"), 2;
}
