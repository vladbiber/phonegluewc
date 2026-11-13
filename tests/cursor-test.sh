#!/bin/sh
# Runs the laptop window nested in a private compositor and reads the pointer image it asks its parent for:
# it must keep one through move, press and release, and a phone build must never ask for one.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/phonegluewc-cursor.XXXXXX")
. "$SRC/tests/sandbox.sh"
# the parent only needs a seat that offers a pointer: the headless build advertises none for a virtual pointer
mkdir "$W/src"; cp -a "$SRC"/* "$W/src"/ 2>/dev/null; rm -f "$W/src"/phonegluewc.o
sed -i 's/^\twlr_cursor_attach_input_device(cursor, device);$/&\n\twlr_seat_set_capabilities(seat, seat->capabilities | WL_SEAT_CAPABILITY_POINTER);/' "$W/src/phonegluewc.c"
make -s -C "$W/src" phonegluewc >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
cp "$W/src/phonegluewc" "$W/outer"
cp "${CURSOR_TEST_BIN:-$SRC/phonegluewc}" "$W/inner"
COMP=$W/outer
COMP_ARGS=
INNER=
HOLD=
fails=0
trap 'kill "$INNER" "$HOLD" 2>/dev/null; comp_kill; rm -rf "$W"' EXIT
ptr() { kill -0 "$PID" || comp_crashed "outer compositor died"; kill -0 "$INNER" || { echo "FAIL window died"; tail -5 "$W/inner.log" | cut -c1-200; exit 1; }
	sandbox WAYLAND_DISPLAY="$SOCK" "$SRC/tests/vptr" "$@"; sleep 0.4; }
# window ENV...: the nested compositor, talking only to the private outer socket
window() {
	[ "$SOCK" != wayland-0 ] || exit 1
	(cd "$W" && exec env -i HOME="$W/home" PATH="$W/sysbin" XDG_RUNTIME_DIR="$W/run" XDG_CONFIG_HOME="$W/cfg" XDG_STATE_HOME="$W/state" \
		XDG_DATA_HOME="$W/data" XDG_DATA_DIRS="$W/data" XDG_CACHE_HOME="$W/cache" WAYLAND_DISPLAY="$SOCK" WAYLAND_DEBUG=client \
		WLR_BACKENDS=wayland WLR_WL_OUTPUTS=1 WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 PHONEGLUEWC_SHELL= "$@" "$W/inner" -d) >"$W/inner.log" 2>&1 &
	INNER=$!
	for i in $(seq 100); do grep -q "Running compositor on wayland display" "$W/inner.log" && break; sleep 0.1; done
	sleep 1
}
last() { grep 'wl_pointer#[0-9]*\.set_cursor' "$W/inner.log" | tail -1; }
# check LABEL WANT: visible means the latest request carries a surface
check() {
	case "$(last)" in *wl_surface*) got=visible ;; "") got=none ;; *) got=hidden ;; esac
	if [ "$got" = "$2" ]; then echo "ok   $1: $got"; else echo "FAIL $1: $got, wanted $2"; fails=$((fails+1)); fi
}

comp_start PHONEGLUEWC_SHELL=
# keeps the seat's pointer alive across the short vptr runs
sandbox WAYLAND_DISPLAY="$SOCK" "$SRC/tests/vptr" sleep 120000 &
HOLD=$!
sleep 0.5
window PHONEGLUEWC_MOUSE_FINGER=1
ptr abs 0.5 0.5; ptr abs 0.5 0.55; check "laptop hover" visible
ptr press; check "laptop while pressed" visible
ptr abs 0.6 0.6; check "laptop while dragging" visible
ptr release; check "laptop after release" visible
ptr abs 0.4 0.4; check "laptop moved after click" visible
n=$(grep 'wl_pointer#[0-9]*\.set_cursor' "$W/inner.log" | grep -c nil)
echo "     requests with no image in the whole laptop run: $n"
kill "$INNER"; sleep 0.5

window
ptr abs 0.5 0.5; ptr abs 0.5 0.55; ptr press; ptr release; ptr abs 0.4 0.4; check "phone after a click" hidden
kill "$INNER" "$HOLD"; sleep 0.5
comp_stop
[ "$fails" = 0 ] && echo PASS || { echo "FAILED $fails"; exit 1; }
