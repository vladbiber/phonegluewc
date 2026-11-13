#!/bin/bash
# A swipe from the bottom never closes an app, through touch and through the pointer; only a deliberate card flick does.
# Headless, neutral clients only. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-noclose.XXXXXX")
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
mkdir -p "$W/cfg/phonegluewc" "$W/snap"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'echo $$ >"%s/pid-$1"; TOUCHLOG_CLOSES=1 TOUCHLOG_TITLE=$1 exec "%s/touchlog" >"%s/log-$1" 2>&1\n' "$W" "$W" "$W" >"$W/tl.sh"
printf 'kill $(cat "%s/pid-$1")\n' "$W" >"$W/k.sh"
printf 'cp "%s/log-$1" "%s/snap/$2" 2>/dev/null\n' "$W" "$W" >"$W/snap.sh"
printf '#!/bin/sh\necho held >>"%s/held"\n' "$W" >"$W/hold.sh"; chmod +x "$W/hold.sh"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
: >"$W/all.log"
fails=0
session() { # NAME [ENV...]: runs $W/$NAME.script to its end
	local n=$1; shift
	case " ${ANIM_ONLY:-$n} " in *" $n "*) ;; *) return ;; esac
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/$n.script" PHONEGLUEWC_SCREENTEXT="$W/hold.sh" "$@"
	comp_wait "${NOCLOSE_WAIT:-3000}"
	cat "$W/gw.log" >>"$W/all.log"
	grep -q 'AddressSanitizer\|runtime error' "$W/gw.log" && { grep -m3 'AddressSanitizer\|runtime error' "$W/gw.log"; fails=$((fails + 1)); }
	comp_stop
}
ok() { if eval "$2"; then echo "ok $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
app() { echo "x sh $W/tl.sh $1"; echo "w 1500"; }
die() { echo "x sh $W/k.sh $1"; echo "w ${2:-800}"; }
msg() { echo "x phonegluewc-msg workspace $1"; echo "w 700"; }
snap() { echo "x sh $W/snap.sh $1 $2"; echo "w 150"; }
# swipe up from the bar: steps of DY, each 32 ms apart
swipe() { local dy=$1 n=$2 y=0.995 i; echo "d 0 0.5 $y"; echo f; for ((i = 0; i < n; i++)); do y=$(python3 -c "print(round($y-$dy,4))"); echo "m 0 0.5 $y"; echo f; done; }
up() { echo "u 0"; echo f; echo "w ${1:-700}"; }
open() { swipe 0.05 8; echo "w 250"; up; }
closeov() { echo "d 0 0.5 0.995"; echo f; up; }
tap() { echo "d 0 $1 $2"; echo f; up "${3:-300}"; }
state() { grep "^FT $1 " "$W/all.log" | grep -q " $2\( \|$\)"; }
# LABEL CUR name=ws...: the row has no gap, exactly one free one, these places
row() { python3 - "$W/all.log" "$@" <<'PY'
import re,sys
log,label,cur=sys.argv[1:4]
want=dict(a.split('=') for a in sys.argv[4:])
ws=None; c={}
for l in open(log,errors='replace'):
    if l.startswith(f'GEOM {label} mon'): ws=int(re.search(r' ws=(\d+)',l).group(1))
    m=re.match(rf'GEOM {label} client title=(\S+) ws=(\d+)',l)
    if m: c[m.group(1)]=int(m.group(2))
occ=sorted(set(c.values()))
bad=[]
if occ!=list(range(len(occ))): bad.append(f'gap {occ}')
if ws!=int(cur): bad.append(f'current {ws}, wanted {cur}')
if ws>len(occ): bad.append(f'beyond the free one {ws}')
for k,v in want.items():
    if c.get(k)!=int(v): bad.append(f'{k}={c.get(k)} wanted {v}')
if bad: print(label,bad,c,file=sys.stderr)
sys.exit(1 if bad else 0)
PY
}
geom() { grep "^GEOM $1 client title=$2 " "$W/all.log" | tail -1 | sed 's/.* geom=\([^ ]*\).*/\1/'; }
wsof() { grep "^GEOM $1 client title=$2 " "$W/all.log" | tail -1 | sed 's/.* ws=\([0-9]*\).*/\1/'; }
curws() { grep "^GEOM $1 mon " "$W/all.log" | tail -1 | sed 's/.* ws=\([0-9]*\) .*/\1/'; }
count() { grep -c "^GEOM $1 client " "$W/all.log"; }
has() { [ "$(grep -c "^GEOM $1 client title=$2 " "$W/all.log")" -ge 1 ]; }
# LABEL "a b" RELATION: a is left of / above b, from the live or card geometry
# ALIVE LABEL: the pid of the client captured at its start, looked at after each try
printf 'if kill -0 "$(cat "%s/pid-a")" 2>/dev/null; then echo "$1 alive" >>"%s/alive"; else echo "$1 dead" >>"%s/alive"; sh "%s/tl.sh" a & sleep 0.3; fi\n' "$W" "$W" "$W" "$W" >"$W/alive.sh"
alive() { echo "x sh $W/alive.sh $1"; echo "w 450"; }
# pressing, moving and lifting, the same for both: DEV=touch or mouse
dn() { if [ "$DEV" = touch ]; then echo "d 0 $1 $2"; echo f; else echo "M $1 $2"; echo "B 1"; fi; }
mv_() { if [ "$DEV" = touch ]; then echo "m 0 $1 $2"; echo f; else echo "M $1 $2"; fi; }
lift() { if [ "$DEV" = touch ]; then echo "u 0"; echo f; else echo "B 0"; fi; }
# SWIPE FROM TO STEPS: straight up from FROM to TO, each step one or two ticks
sw() { local i; dn 0.5 "$1"; for ((i = 1; i <= $3; i++)); do mv_ 0.5 "$(python3 -c "print(round($1+($2-$1)*$i/$3,4))")"; done; lift; }
# back to the app: whatever a try left open, four fingers are not involved
home_() { dn 0.5 0.995; lift; echo "w 350"; echo "x phonegluewc-msg workspace 1"; echo "w 350"; }
script() { # DEV
	DEV=$1; echo "w 2500"; app a
	local from to st t
	# one swipe from the bar, every speed and length
	for from in 0.995; do for to in 0.97 0.9 0.75 0.5 0.2 0.02; do for st in 1 3 10 30; do
		sw "$from" "$to" "$st"; echo "w 500"; alive "one-$from-$to-$st"; home_
	done; done; done
	# a pause on the way, then on up
	for to in 0.8 0.5 0.2; do dn 0.5 0.995; mv_ 0.5 $to; echo "w 300"; mv_ 0.5 0.1; mv_ 0.5 0.03; lift; echo "w 500"; alive "pause-$to"; home_; done
	# a second swipe at once, from the bar and from just above it, at each moment of the settle
	for t in 1 40 120 300; do for from in 0.995 0.95 0.89 0.8; do
		[ "$t" -ge 300 ] && [ "$(python3 -c "print(int($from<0.875))")" = 1 ] && continue # on a settled card: that one is deliberate
		dn 0.5 0.995; mv_ 0.5 0.8; echo "w 200"; mv_ 0.5 0.75; lift; echo "w $t"; sw "$from" 0.1 3; echo "w 500"; alive "double-$t-$from"; home_
		sw 0.995 0.3 3; echo "w $t"; sw "$from" 0.1 3; echo "w 500"; alive "afterflick-$t-$from"; home_
	done; done
	# a swipe up while the overview opens from the first one, and off to the sides
	for t in 1 30 60 100; do
		dn 0.5 0.995; mv_ 0.5 0.7; lift; echo "w $t"; dn 0.3 0.9; mv_ 0.35 0.6; mv_ 0.4 0.2; lift; echo "w 500"; alive "side-$t"; home_
	done
	alive end
	# a short accident in the settled overview comes back, the same flick longer closes
	open_; echo "w 500"; dn 0.5 0.5; mv_ 0.5 0.47; mv_ 0.5 0.44; lift; echo "w 600"; alive shortflick
	echo "g sf"; dn 0.5 0.5; mv_ 0.5 0.4; mv_ 0.5 0.3; mv_ 0.5 0.2; echo "w 300"; mv_ 0.5 0.45; lift; echo "w 600"; alive letgo
	dn 0.5 0.6; for t in 1 2 3 4 5 6 7 8; do mv_ 0.5 "$(python3 -c "print(round(0.6-0.08*$t,3))")"; [ "$t" = 4 ] && echo "g mid"; done; lift; echo "w 900"; alive closed
	echo "x true"; echo "w 300"
}
open_() { dn 0.5 0.995; mv_ 0.5 0.8; echo "w 250"; mv_ 0.5 0.75; lift; echo "w 400"; }
trial() { # DEV
	rm -f "$W/alive"; script "$1" >"$W/$1.script"
	if [ "$1" = touch ]; then session touch; else session mouse PHONEGLUEWC_MOUSE_FINGER=1; fi
	cp "$W/alive" "$W/alive-$1"
	[ -n "${NOCLOSE_LOG:-}" ] && cp "$W/alive" "$NOCLOSE_LOG-$1"
	local dead tried; dead=$(grep -E ' dead$' "$W/alive" | grep -v '^closed ' | cut -d' ' -f1 | tr '\n' ' '); tried=$(grep -vc '^closed ' "$W/alive")
	echo "noclose: $1: $tried tries, client dead after: ${dead:-none}"
	ok "$1: nothing from the bottom closes the app" '[ -z "$dead" ] && [ "$tried" -ge 50 ]'
	ok "$1: the card follows a deliberate flick" 'grep -q "^GEOM mid mon" "$W/all.log"'
	ok "$1: a deliberate card flick closes it" 'grep -q "^closed dead" "$W/alive"'
}
for d in touch mouse; do case " ${ANIM_ONLY:-$d} " in *" $d "*) trial $d ;; esac; done
comp_cores
[ "$fails" = 0 ] && echo "noclose: all passed" || echo "noclose: failed: $fails"
exit "$((fails > 0))"
