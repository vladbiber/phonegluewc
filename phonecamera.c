/* phonecamera: posts a live activity to the dynamic camera. Lines of JSON over a unix socket;
 * the shell checks everything, this only spells it. See docs/CONFIGURATION.md. */
#define _GNU_SOURCE
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <unistd.h>

#define MAX 4000

static char msg[MAX + 96];
static size_t used;

static void die(const char *what)
{
	fprintf(stderr, "phonecamera: %s\n", what);
	exit(1);
}

static void add(const char *s)
{
	size_t n = strlen(s);
	if (used + n >= MAX)
		die("too long");
	memcpy(msg + used, s, n);
	used += n;
	msg[used] = 0;
}

static void add_str(const char *s)
{
	char u[8];
	add("\"");
	for (; *s; s++) {
		if (*s == '"' || *s == '\\') {
			u[0] = '\\';
			u[1] = *s;
			u[2] = 0;
			add(u);
		} else if ((unsigned char)*s < 0x20) {
			snprintf(u, sizeof u, "\\u%04x", *s);
			add(u);
		} else {
			u[0] = *s;
			u[1] = 0;
			add(u);
		}
	}
	add("\"");
}

static void field_str(const char *k, const char *v)
{
	add(",\"");
	add(k);
	add("\":");
	add_str(v);
}

static void field_raw(const char *k, const char *v)
{
	add(",\"");
	add(k);
	add("\":");
	add(v);
}

static void usage(void)
{
	fputs("usage: phonecamera post|update --id ID [--kind live|call|nav|transfer] [--icon NAME]\n"
		"         [--head TEXT] [--title TEXT] [--text TEXT] [--tail TEXT] [--progress 0..1]\n"
		"         [--button ID:LABEL]... [--ttl SECONDS] [--app DESKTOP_ID] [--elapsed]\n"
		"         [--state incoming|active] [--muted 0|1] [--speaker 0|1] [--wait]\n"
		"       phonecamera end ID\n"
		"       phonecamera timer SECONDS | stopwatch | cancel timer|stopwatch | poll\n", stderr);
	exit(2);
}

static int number(const char *s)
{
	char *end;
	strtod(s, &end);
	return *s && !*end;
}

/* the caller is gone or the shell is: either way the activity ends with this connection */
static void hold(int sock, pid_t caller)
{
	int pfd = syscall(SYS_pidfd_open, caller, 0);
	struct pollfd p[2] = {{sock, POLLIN, 0}, {pfd, POLLIN, 0}};
	char sink[512];
	if (fork() > 0)
		_exit(0);
	setsid();
	for (int i = 0; i < 3; i++)
		close(i);
	while (poll(p, pfd >= 0 ? 2 : 1, -1) >= 0) {
		if (p[1].revents)
			break;
		if (p[0].revents && read(sock, sink, sizeof sink) <= 0)
			break;
	}
	_exit(0);
}

int main(int argc, char **argv)
{
	const char *op, *path = getenv("PHONECAMERA_SOCK"), *run = getenv("XDG_RUNTIME_DIR");
	struct sockaddr_un addr = {.sun_family = AF_UNIX};
	char reply[512], buttons[1024] = "";
	int wait_events = 0, s;
	pid_t caller = getppid();
	ssize_t n;

	if (argc < 2)
		usage();
	op = argv[1];
	add("{\"op\":");
	add_str(op);
	if (!strcmp(op, "post") || !strcmp(op, "update")) {
		for (int i = 2; i < argc; i++) {
			const char *a = argv[i];
			if (!strcmp(a, "--wait")) {
				wait_events = 1;
				continue;
			}
			if (!strcmp(a, "--elapsed")) {
				field_raw("elapsed", "true");
				continue;
			}
			if (strncmp(a, "--", 2) || ++i >= argc)
				usage();
			a += 2;
			if (!strcmp(a, "progress") || !strcmp(a, "ttl")) {
				if (!number(argv[i]))
					die("not a number");
				field_raw(a, argv[i]);
			} else if (!strcmp(a, "muted") || !strcmp(a, "speaker")) {
				field_raw(a, strcmp(argv[i], "1") ? "false" : "true");
			} else if (!strcmp(a, "button")) {
				char *colon = strchr(argv[i], ':');
				if (!colon)
					usage();
				*colon = 0;
				size_t mark = used;
				add("{\"id\":");
				add_str(argv[i]);
				add(",\"label\":");
				add_str(colon + 1);
				add("}");
				if (strlen(buttons) + (used - mark) + 2 >= sizeof buttons)
					die("too long");
				if (*buttons)
					strcat(buttons, ",");
				strcat(buttons, msg + mark);
				used = mark;
				msg[used] = 0;
			} else if (!strcmp(a, "id") || !strcmp(a, "kind") || !strcmp(a, "icon") || !strcmp(a, "head")
					|| !strcmp(a, "title") || !strcmp(a, "text") || !strcmp(a, "tail") || !strcmp(a, "app")
					|| !strcmp(a, "state")) {
				field_str(a, argv[i]);
			} else {
				usage();
			}
		}
		if (*buttons) {
			add(",\"buttons\":[");
			add(buttons);
			add("]");
		}
	} else if (!strcmp(op, "end") && argc == 3) {
		field_str("id", argv[2]);
	} else if (!strcmp(op, "timer") && argc == 3 && number(argv[2])) {
		field_raw("seconds", argv[2]);
	} else if (!strcmp(op, "cancel") && argc == 3) {
		field_str("what", argv[2]);
	} else if (strcmp(op, "stopwatch") && strcmp(op, "poll")) {
		usage();
	}
	add("}\n");

	if (snprintf(addr.sun_path, sizeof addr.sun_path, "%s%s", path ? path : run ? run : "/tmp",
			path ? "" : "/phonegluewc-camera.sock") >= (int)sizeof addr.sun_path)
		die("socket path too long");
	if ((s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0)) < 0 || connect(s, (void *)&addr, sizeof addr) < 0)
		die("the dynamic camera is not running");
	signal(SIGPIPE, SIG_IGN);
	if (write(s, msg, used) != (ssize_t)used)
		die("write failed");

	struct pollfd p = {s, POLLIN, 0};
	if (poll(&p, 1, 3000) <= 0 || (n = read(s, reply, sizeof reply - 1)) <= 0)
		die("no answer");
	reply[n] = 0;
	if (strstr(reply, "\"error\"")) {
		fputs(reply, stderr);
		return 1;
	}
	if (wait_events) {
		while ((n = read(s, reply, sizeof reply)) > 0)
			if (fwrite(reply, 1, n, stdout) != (size_t)n || fflush(stdout))
				break;
	} else if (!strcmp(op, "post")) {
		hold(s, caller);
	}
	return 0;
}
