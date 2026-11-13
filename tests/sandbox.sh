# Sourced by the headless tests, with SRC and W set. Nothing started here can reach the user's
# files, apps, session bus or live compositor: the environment is empty, HOME and the runtime
# dir are private, D-Bus has nothing to activate, and PATH holds only the programs listed here.
PID=
BUS=
trap 'comp_kill; rm -rf "$W"' EXIT
mkdir -p "$W/home" "$W/run" "$W/tmp" "$W/sysbin" "$W/cfg" "$W/state" "$W/data" "$W/cache"
chmod 700 "$W/run"
# never the name of the live session, even in a private dir: hold the lock on wayland-0
exec 9>"$W/run/wayland-0.lock"
flock -n 9 || { echo "cannot lock wayland-0 in $W/run"; exit 1; }
for p in sh bash env sort seq file id find cat cp mv rm ls mkdir sed awk grep tr head tail wc sleep true false kill pgrep \
	dbus-run-session dbus-daemon dbus-send qs wl-copy wl-paste tesseract ${SANDBOX_EXTRA:-}; do
	c=$(command -v "$p") && ln -sf "$c" "$W/sysbin/$p"
done
cat >"$W/bus.conf" <<BUS
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=$W/run</listen>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
BUS

# sandbox [NAME=VALUE...] COMMAND: SANDBOX_PATH goes in front of the listed programs
sandbox() {
	env -i HOME="$W/home" USER=phone LANG=C.UTF-8 TMPDIR="$W/tmp" PATH="${SANDBOX_PATH:+$SANDBOX_PATH:}$W/sysbin" \
		XDG_RUNTIME_DIR="$W/run" XDG_CONFIG_HOME="$W/cfg" XDG_STATE_HOME="$W/state" XDG_DATA_HOME="$W/data" \
		XDG_DATA_DIRS="$W/data" XDG_CACHE_HOME="$W/cache" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$W/run/no-system-bus" \
		WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 PHONE_COMPATIBLE="${PHONE_COMPATIBLE-nothing,spacewar}" \
		ASAN_OPTIONS=detect_leaks=0 PHONE_BG_DAEMONS="${PHONE_BG_DAEMONS:-phonetest-bgd}" "$@"
}

comp_kill() {
	[ -n "$PID" ] && { kill "$PID" 2>/dev/null; sleep 1; kill -9 "$PID" 2>/dev/null; }
	PID=
}

# any crash ends the test: a test cannot pass over a dead compositor or a core file
comp_cores() {
	for c in "$W"/core.*; do
		[ -e "$c" ] || continue
		mkdir -p "$SRC/tests/crashes"; mv "$c" "$SRC/tests/crashes/"
		echo "FAIL core file kept: $SRC/tests/crashes/${c##*/} ($(file -b "$SRC/tests/crashes/${c##*/}" | grep -o "execfn: '[^']*'"))"
		found=1
	done
	[ -z "${found:-}" ] || { PID=; exit 1; }
}
comp_crashed() {
	echo "FAIL $1"
	tail -"${2:-12}" "$W/gw.log" | cut -c1-200
	PID=
	sleep 1
	comp_cores
	exit 1
}

# comp_start [NAME=VALUE...]: runs $COMP $COMP_ARGS with cwd in the test dir, so core files land there
comp_start() {
	: >"$W/pid"; : >"$W/gw.log"
	(cd "$W" && sandbox "$@" dbus-run-session --config-file="$W/bus.conf" -- \
		sh -c 'echo $$ >"$0"; exec ${PHONE_WRAP:-} "$@"' "$W/pid" "$COMP" -d ${COMP_ARGS:-}) >"$W/gw.log" 2>&1 &
	BUS=$!
	for i in $(seq 50); do [ -s "$W/pid" ] && break; sleep 0.1; done
	PID=$(cat "$W/pid")
	SOCK=
	for i in $(seq 400); do
		SOCK=$(sed -n "s/.*Running compositor on wayland display '\(wayland-[0-9]*\)'.*/\1/p" "$W/gw.log")
		[ -n "$SOCK" ] && break
		kill -0 "$PID" 2>/dev/null || comp_crashed "compositor died during start"
		sleep 0.1
	done
	[ -n "$SOCK" ] && [ "$SOCK" != wayland-0 ] || { echo "bad socket '$SOCK'"; exit 1; }
	[ -S "$W/run/$SOCK" ] || { echo "socket $SOCK is not ours"; exit 1; }
}

# comp_wait TENTHS: until the fake touch script ends; the compositor must live through it
comp_wait() {
	for i in $(seq "$1"); do
		kill -0 "$PID" 2>/dev/null || { wait "$BUS"; comp_crashed "compositor died mid test, exit status $?"; }
		grep -q 'FT done' "$W/gw.log" && return 0
		sleep 0.1
	done
	echo "FAIL the touch script did not finish"; tail -5 "$W/gw.log" | cut -c1-200; exit 1
}

# comp_stop: a normal SIGTERM exit is status 0, anything else is a shutdown crash
comp_stop() {
	kill "$PID" 2>/dev/null
	for i in $(seq 80); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
	kill -0 "$PID" 2>/dev/null && { kill -9 "$PID"; PID=; echo "FAIL compositor hung on exit"; exit 1; }
	wait "$BUS"; rc=$?
	[ "$rc" = 0 ] || comp_crashed "compositor exit status $rc" 25
	PID=
	sleep 0.3
	comp_cores
}
