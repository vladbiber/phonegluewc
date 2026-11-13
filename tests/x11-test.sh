#!/bin/bash
# X11 apps through xwayland-satellite: no X server until the first client, an xterm maps as a toplevel and goes on
# close, a killed satellite comes back on the next client, socket and lock are gone after exit, xwayland = off opens none.
# The Settings switch writes xwayland = off/on, captured dark and light (SHOTS=DIR keeps the PNGs).
# Headless; the X display is :1 or higher, never the laptop's :0.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-x11.XXXXXX")
export SANDBOX_EXTRA="xterm xwayland-satellite Xwayland xkbcomp ps mktemp readlink dirname chmod ln touch"
. "$SRC/tests/sandbox.sh"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "build failed"; exit 1; }
mkdir -p "$W/cfg/phonegluewc"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD"
fails=0
ok() { if eval "$2"; then echo "ok $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
satpid() { sed -n 's/.*started xwayland-satellite, pid \([0-9]*\).*/\1/p' "$W/gw.log" | tail -1; }

# an xterm that records the pid of what runs in it; killing that closes the window
printf 'exec xterm -T x11probe-$1 -e sh -c "echo \\$\\$ >%s/xt-$1; exec sleep 60"\n' "$W" >"$W/xt.sh"
printf 'kill $(cat %s/xt-$1)\n' "$W" >"$W/xtclose.sh"
# the satellite pid comes from the compositor's own log line, nothing found by name
printf 'kill $(sed -n "s/.*started xwayland-satellite, pid \\([0-9]*\\).*/\\1/p" %s/gw.log | tail -1)\n' "$W" >"$W/killsat.sh"
cat >"$W/mem.sh" <<MEM
s=\$(sed -n "s/.*started xwayland-satellite, pid \([0-9]*\).*/\1/p" $W/gw.log | tail -1)
x=\$(ps --ppid "\$s" -o pid= | head -1)
for p in \$s \$x; do echo "\$(cat /proc/\$p/comm) \$(grep -E '^(Rss|Pss):' /proc/\$p/smaps_rollup | tr -s ' ' | tr '\n' ' ')"; done >$W/mem
MEM

printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
{ echo "w 3000"; echo "p before"
  echo "x sh $W/xt.sh one"; echo "w 5000"; echo "g mapped"; echo "x sh $W/mem.sh"; echo "w 800"
  echo "x sh $W/xtclose.sh one"; echo "w 1500"; echo "g closed"
  echo "x sh $W/killsat.sh"; echo "w 1500"; echo "p satdead"
  echo "x sh $W/xt.sh two"; echo "w 5000"; echo "g again"
  echo "x sh $W/xtclose.sh two"; echo "w 1000"; echo "x true"; echo "w 300"; } >"$W/on.script"
comp_start PHONEGLUEWC_SHELL= PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_SENSOR= PHONEGLUEWC_FAKETOUCH="$W/on.script"
D=
for i in $(seq 50); do D=$(sed -n 's/.*X11 apps on DISPLAY \(:[0-9]*\) .*/\1/p' "$W/gw.log"); [ -n "$D" ] && break; sleep 0.1; done
[ -n "$D" ] && [ "$D" != :0 ] || { echo "FAIL bad X display '$D'"; exit 1; }
N=${D#:}
sleep 1
ok "the X socket and lock exist ($D)"                '[ -S /tmp/.X11-unix/X$N ] && [ "$(tr -d " \n" </tmp/.X$N-lock)" = "$PID" ]'
ok "no X server before the first client"             '[ -z "$(ps --ppid "$PID" -o comm= | grep -i xwayland)" ]'
comp_wait 400
SAT1=$(grep -m1 'started xwayland-satellite, pid' "$W/gw.log" | sed 's/.*pid \([0-9]*\).*/\1/')
cp "$W/gw.log" "$W/on.log"
comp_stop
ok "the xterm maps as a toplevel"                    'grep -q "^GEOM mapped client title=x11probe-one " "$W/on.log"'
ok "it is gone after closing"                        '! grep -q "^GEOM closed client title=x11probe-one " "$W/on.log"'
ok "a killed satellite starts again on the next client" '[ "$(grep -c "started xwayland-satellite, pid" "$W/on.log")" = 2 ] && grep -q "^GEOM again client title=x11probe-two " "$W/on.log"'
ok "socket and lock removed on exit"                 '[ ! -e /tmp/.X11-unix/X$N ] && [ ! -e /tmp/.X$N-lock ]'
ok "no satellite left running"                       '! kill -0 "$SAT1" 2>/dev/null && ! kill -0 "$(satpid)" 2>/dev/null'
echo "memory while one xterm runs:"; sed 's/^/  /' "$W/mem" 2>/dev/null

printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\nxwayland = off\n' >"$W/cfg/phonegluewc/config.conf"
{ echo "w 1500"; echo "x sh $W/xt.sh off"; echo "w 2500"; echo "g off"; echo "x true"; echo "w 300"; } >"$W/off.script"
comp_start PHONEGLUEWC_SHELL= PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_SENSOR= PHONEGLUEWC_FAKETOUCH="$W/off.script"
comp_wait 200
cp "$W/gw.log" "$W/off.log"
comp_stop
ok "xwayland = off: no X display, the xterm cannot open" '! grep -q "X11 apps on DISPLAY" "$W/off.log" && ! grep -q "x11probe-off" "$W/off.log"'

# the Settings switch, Apps page, in a dark and a light theme
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot build failed"; exit 1; }
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
SW=393; SH=873
tp() { awk -v x="$1" -v y="$2" -v sw="$SW" -v sh="$SH" 'BEGIN { printf "d 0 %.4f %.4f\nf\nu 0\nf\nw 900\n", x/sw, y/sh }'; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
have() { printf '%s && echo %s >>%s\n' "$1" "$2" "$W/marks" >"$W/have-$2.sh"; echo "x sh $W/have-$2.sh"; echo "w 300"; }
: >"$W/marks"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'theme=dark\n' >"$W/cfg/phonegluewc/phone.conf"
XROW=${XROW:-356}
{ echo "w 2500"; echo "x $SRC/settings/phonesettings apps"; echo "w 3500"; shot x11-dark
  tp 196 $XROW; have "grep -qx 'xwayland = off' $W/cfg/phonegluewc/config.conf" sw-off; shot x11-dark-off
  echo "x $SRC/settings/pset set phone theme light"; echo "w 1200"; shot x11-light-off
  tp 196 $XROW; have "grep -qx 'xwayland = on' $W/cfg/phonegluewc/config.conf" sw-on; shot x11-light
  echo "x true"; echo "w 300"; } >"$W/set.script"
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL= PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_SENSOR= PHONEGLUEWC_FAKETOUCH="$W/set.script"
comp_wait 400
comp_stop
for f in "$W"/x11-*.ppm; do magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
ok "Settings: the X11 switch writes xwayland = off" 'grep -qx sw-off "$W/marks"'
ok "Settings: and back to on, in the light theme"  'grep -qx sw-on "$W/marks"'
ok "Settings: captured dark and light"             '[ -s "$SHOTS/x11-dark.png" ] && [ -s "$SHOTS/x11-light.png" ]'

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; cp "$W/on.log" "$W/off.log" "$SRC/tests/" 2>/dev/null; exit 1; }
