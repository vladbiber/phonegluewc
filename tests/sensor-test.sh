#!/bin/bash
# The sysfs accelerometer fallback on a fake /sys/bus/iio: the mount matrix turns the chip's axes into the panel's.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-sensor.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
printf '#!/bin/sh\necho "$3" >>%s/sent\n' "$W" >"$W/bin/phonegluewc-msg"; chmod +x "$W/bin/phonegluewc-msg"
FAILS=0
# case NAME X Y Z MATRIXFILE MATRIX EXPECTED: one reading, what the helper sends
case_() {
	local d=$W/$1/iio:device0
	mkdir -p "$d"; echo "$2" >"$d/in_accel_x_raw"; echo "$3" >"$d/in_accel_y_raw"; echo "$4" >"$d/in_accel_z_raw"
	[ -n "$5" ] && echo "$6" >"$d/$5"
	rm -f "$W/sent"
	( env -u FAKE_STATE PATH="$W/bin:$PATH" PHONE_IIO_DIR="$W/$1" sh "$SRC/phonegluewc-sensor" & p=$!; sleep 1; [ "$p" -gt 0 ] && kill "$p" )
	got=$(cat "$W/sent" 2>/dev/null)
	if [ "$got" = "$7" ]; then echo "ok   $1: $7"; else echo "FAIL $1: wanted '$7', got '$got'"; FAILS=$((FAILS+1)); fi
}
case_ upright 0 1000 0 "" "" normal
case_ upside 0 -1000 0 "" "" bottom-up
case_ leftup -1000 0 0 "" "" left-up
case_ rightup 1000 0 0 "" "" right-up
case_ flat 30 20 1000 "" "" ""
case_ tilted 400 1000 300 "" "" normal
# a chip mounted a quarter turn: its x is the panel's y
case_ matrix 1000 0 0 in_accel_mount_matrix "0, -1, 0; 1, 0, 0; 0, 0, 1" normal
case_ matrix2 0 1000 0 in_accel_mount_matrix "0, -1, 0; 1, 0, 0; 0, 0, 1" left-up
case_ plainname 0 1000 0 mount_matrix "-1, 0, 0; 0, -1, 0; 0, 0, 1" bottom-up
case_ fractions 0 800 0 in_accel_mount_matrix "0.0, 0.5, 0.0; -0.5, 0.0, 0.0; 0.0, 0.0, 1.0" right-up
echo; echo "$FAILS failed"; [ "$FAILS" = 0 ]
