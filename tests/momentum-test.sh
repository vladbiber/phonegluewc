#!/bin/bash
# Carousel momentum: a stronger sideways swipe carries across more cards, clamped at both ends.
# Headless, neutral clients only. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-mom.XXXXXX")
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
printf 'echo $$ >"%s/pid-$1"; TOUCHLOG_TITLE=$1 exec "%s/touchlog" >"%s/log-$1" 2>&1\n' "$W" "$W" "$W" >"$W/tl.sh"
printf 'kill $(cat "%s/pid-$1")\n' "$W" >"$W/k.sh"
printf 'cp "%s/log-$1" "%s/snap/$2" 2>/dev/null\n' "$W" "$W" >"$W/snap.sh"
printf '#!/bin/sh\necho held >>"%s/held"\n' "$W" >"$W/hold.sh"; chmod +x "$W/hold.sh"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
: >"$W/all.log"
fails=0
session() { # NAME [ENV...]: runs $W/$NAME.script to its end
	local n=$1; shift
	case " ${MOM_ONLY:-$n} " in *" $n "*) ;; *) return ;; esac
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/$n.script" PHONEGLUEWC_SCREENTEXT="$W/hold.sh" "$@"
	comp_wait 1500
	cat "$W/gw.log" >>"$W/all.log"; [ -n "${MOM_DBG:-}" ] && grep "^FT vel" "$W/gw.log"
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
ws() { grep "^FT $1 " "$W/all.log" | tail -1 | sed 's/.* ws=\([0-9]*\) .*/\1/'; }
ov() { state "$1" overview=1; }
cardx() { grep "^GEOM $1 mon " "$W/all.log" | tail -1 | sed 's/.* card=\(-\{0,1\}[0-9]*\),.*/\1/'; }
# sideways: from X, N steps of DX, each 32 ms apart, then lift
side() { local x=$1 dx=$2 n=$3 i; echo "d 0 $x 0.45"; echo f; for ((i = 0; i < n; i++)); do x=$(python3 -c "print(round($x+$dx,4))"); echo "m 0 $x 0.45"; echo f; done; [ -n "${4:-}" ] && echo "w $4"; echo "u 0"; echo f; }
settle() { echo "w 1500"; echo "p $1"; echo "g $1"; }

{ echo "w 2500"; for a in 1 2 3 4 5 6 7; do app n$a; done; open; echo "p start"; echo "g start"
  side 0.6 -0.008 15 200; settle slowshort
  side 0.2 0.02 30 200; settle slowlong
  side 0.4 0.05 4; for i in $(seq 1 40); do echo "g gs"; done; settle gentle
  side 0.1 0.2 3; settle strong
  side 0.1 0.2 3; for i in $(seq 1 60); do echo "g es"; done; settle endleft
  side 0.9 -0.25 3; settle right1
  side 0.9 -0.25 3; settle right2
  side 0.9 -0.25 3; settle right3
  side 0.9 -0.25 3; settle endright
  side 0.1 0.2 3; echo "d 0 0.5 0.45"; echo f; echo "u 0"; echo f; settle caught
  echo "x true"; echo "w 300"; } >"$W/mom.script"
session mom
s=$(ws start)
ok "seven apps, the overview on the last one"             '[ "$s" = 6 ] && ov start'
ok "the opening drag ends exactly in the layout: card 37,42 318x707, smaller neighbours one span away" 'grep "^GEOM start mon " "$W/all.log" | tail -1 | grep -q "card=37,42,318,707 card0=-244,91,273,608 card2=363,91,273,608"'
ok "a short slow drag settles back on the same card"     '[ "$(ws slowshort)" = 6 ] && [ "$(cardx slowshort)" = 37 ]'
ok "a long slow drag settles on the nearest card"        '[ "$(ws slowlong)" = 5 ] && [ "$(cardx slowlong)" = 37 ]'
ok "a gentle flick moves exactly one"                    '[ "$(ws gentle)" = 4 ]'
ok "a strong flick moves two or three"                   'd=$(( $(ws gentle) - $(ws strong) )); [ $d -ge 2 ] && [ $d -le 3 ] && [ "$(cardx strong)" = 37 ]'
ok "the left end clamps: first card, settled, no bounce" '[ "$(ws endleft)" = 0 ] && [ "$(cardx endleft)" = 37 ]'
# the cards are narrower now: three flicks may already reach the end, the fourth must stay there
ok "the right end clamps on the free card"               '[ "$(ws right2)" -lt 7 ] && [ "$(ws endright)" = 7 ] && [ "$(cardx endright)" = 37 ] && ov endright'
ok "a tap catches the moving cards: overview stays, settled on a card, nothing opened" 'ov caught && [ "$(cardx caught)" = 37 ] && [ "$(ws caught)" -lt "$(ws endright)" ]'
steps() { python3 - "$W/all.log" "$1" "$2" <<'PY'
import re,sys
xs=[int(m.group(1)) for l in open(sys.argv[1],errors='replace') for m in [re.match(rf'GEOM {sys.argv[2]} mon .* card=(-?\d+),',l)] if m]
# a step near a whole card is the cards renumbering in place, not motion
cut=max([i+1 for i,(a,b) in enumerate(zip(xs,xs[1:])) if abs(b-a)>170] or [0])
d=[b-a for a,b in zip(xs,xs[1:]) if abs(b-a)<=170]
print(f'  {sys.argv[2]}: card x {xs[:6]} ... {xs[-3:]}, steps {d[:10]}')
if sys.argv[3]=='speed':
    # the finger moved 19.6 px per 32 ms: near 10 per 16 ms frame, the first frame after the lift spans 32 ms
    sys.exit(0 if max(abs(x) for x in d) <= 22 else 1)
# the end of the row: towards the card's place, never past it, no swing
t=xs[cut:]; td=[b-a for a,b in zip(t,t[1:])]
sys.exit(0 if max(t)<=37 and all(x>=0 for x in td) and t[-1]==37 else 1)
PY
}
ok "the cards leave the finger at its speed, no jump at the release" 'steps gs speed'
ok "the end of the row gives a little and settles back without a bounce" 'steps es end'
echo "  landed: start $s slowshort $(ws slowshort) slowlong $(ws slowlong) gentle $(ws gentle) strong $(ws strong) endleft $(ws endleft) right $(ws right1) $(ws right2) $(ws right3) endright $(ws endright) caught $(ws caught)"

# the mouse as a finger: the same speeds give the same landings
mside() { local x=$1 dx=$2 n=$3 i; echo "M $x 0.45"; echo "B 1"; for ((i = 0; i < n; i++)); do x=$(python3 -c "print(round($x+$dx,4))"); echo "M $x 0.45"; done; echo "B 0"; }
{ echo "w 2500"; for a in 1 2 3 4 5 6; do app n$a; done
  echo "M 0.5 0.995"; echo "B 1"; for y in 0.95 0.9 0.85 0.8 0.75 0.7; do echo "M 0.5 $y"; echo "w 16"; done; echo "w 300"; echo "B 0"; echo "w 900"; echo "p mstart"
  mside 0.4 0.025 8; settle mgentle
  mside 0.1 0.1 6; settle mstrong
  echo "x true"; echo "w 300"; } >"$W/mouse.script"
session mouse PHONEGLUEWC_MOUSE_FINGER=1
ok "mouse: gentle moves one, strong two or three"        'ov mstart && [ $(( $(ws mstart) - $(ws mgentle) )) = 1 ] && d=$(( $(ws mgentle) - $(ws mstrong) )) && [ $d -ge 2 ] && [ $d -le 3 ]'
echo "  mouse landed: start $(ws mstart) gentle $(ws mgentle) strong $(ws mstrong)"

comp_cores
[ "$fails" = 0 ] && echo "momentum: all passed" || echo "momentum: failed: $fails"
rm -rf "$W"
[ "$fails" = 0 ]
