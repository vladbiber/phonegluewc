#!/bin/bash
# The grid overview (overview = grid): two portrait columns, two rows in view over the wallpaper, the tray kept;
# a fullscreen_apps window gets one wide card; scroll with momentum, tap opens, sideways closes, a held window or tray
# icon drops on a card; the carousel back with overviewmode. Headless, through the touch hook. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-grid.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/fakeapp" "$SRC/tests/fakeapp.c" "$BUILD/touchlog-xdg-protocol.c" $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0) -lwayland-client || { echo "FAIL fakeapp"; exit 1; }
COMP=$BUILD/phonegluewc
FAILS=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }

C=$W/cfg/phonegluewc
mkdir -p "$C" "$W/data/applications"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\nfullscreen_apps = wide\n' >"$C/config.conf"
printf 'animations = on\noverview = grid\n' >"$C/phone.conf"
printf '[Desktop Entry]\nType=Application\nName=Icon\nExec=%s -n 1 -a icon\n' "$W/fakeapp" >"$W/data/applications/icon.desktop"
printf 'icon.desktop\n' >"$C/pinned-apps"
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
up() { echo "u 0"; echo f; echo "w ${1:-700}"; }
tap() { echo "d 0 $1 $2"; echo f; echo "w 40"; up "${3:-900}"; }
open() { local y=0.995 i; echo "d 0 0.5 $y"; echo f; for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y-0.05,4))"); echo "m 0 0.5 $y"; echo f; done; echo "w 250"; up 1200; }
# FROMX FROMY TOX TOY STEPS MS: a straight move, MS apart
move() { python3 -c "
for i in range(1,$5+1): print(f'm 0 {$1+($3-$1)*i/$5:.4f} {$2+($4-$2)*i/$5:.4f}'); print('f'); print('w $6')"; }
# a new app on the free workspace
app() { echo "x phonegluewc-msg workspace $1"; echo "w 700"; echo "x $W/fakeapp -n 1 -a $2"; echo "w 1500"; }
g() { echo "g $1"; echo "p $1"; }
SANDBOX_PATH="$BUILD"
run() { local n=$1; shift
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/$n.script" "$@"
	comp_wait 900
	comp_stop
	cp "$W/gw.log" "$SHOTS/grid-$n.log"; cat "$W/gw.log" >>"$W/all.log"
}
fling() { echo "d 0 0.5 $1"; echo f; move 0.5 $1 0.5 $2 6 16; echo "u 0"; echo f; }
# the cards: ws0 ws1 / wide ws2 / ws3 ws4 / ws5; the overview opens scrolled to the current one, at the end
{ echo "w 3500"; app 0 a0; app 1 a1; app 2 wide; app 3 a3; app 4 a4; app 5 a5
  open; g open; shot open
  fling 0.30 0.62; echo "w 30"; g fling; echo "w 1500"; g settled; shot settled
  tap 0.712 0.246 1200; g tapped
  open; g reopen
  # sideways off the current card (a1) closes it; a0 is current at once, in its own place
  echo "d 0 0.712 0.246"; echo f; move 0.712 0.246 0.35 0.25 6 16; echo "u 0"; echo f; echo "w 30"; g closing; shot closing; echo "w 1500"; g closed
  # a0 held, then onto the right half of a3's card: it joins a3
  echo "d 0 0.285 0.246"; echo f; echo "w 450"; move 0.285 0.246 0.443 0.732 8 30; echo "w 200"; shot carry; up 1500; g dropped; shot dropped
  # a tray icon onto the card right of the second row (a4 by then): it opens there
  echo "d 0 0.405 0.947"; echo f; echo "w 700"; move 0.405 0.947 0.405 0.90 6 30; echo "w 300"; move 0.405 0.90 0.712 0.246 8 30; echo "w 200"; shot icon; up 3000; g icon
  echo "x phonegluewc-msg do overviewmode carousel"; echo "w 1500"; g carousel; shot carousel
  echo "p done"; } >"$W/main.script"
run main
for f in "$W"/*.ppm; do magick "$f" "$SHOTS/grid-$(basename "${f%.ppm}").png" 2>/dev/null; done
L=$W/all.log
box() { grep "^GEOM $1 grid ws=$2 " "$L" | tail -1 | sed 's/.* box=\([^ ]*\).*/\1/'; }
scroll() { grep "^GEOM $1 grid ws=0 " "$L" | tail -1 | sed 's/.* scroll=//'; }
st() { grep "^GEOM $1 mon " "$L" | tail -1 | sed 's/.* st=//' | cut -d, -f"$2"; }
card() { grep "^GEOM $1 mon " "$L" | tail -1 | sed 's/.* card=\([^ ]*\) .*/\1/'; }
curws() { grep "^GEOM $1 mon " "$L" | tail -1 | sed 's/.* ws=\([0-9]*\) .*/\1/'; }
ov() { grep "^GEOM $1 mon " "$L" | tail -1 | sed 's/.* ov=\([0-9]*\) .*/\1/'; }
wsof() { grep "^GEOM $1 client title=$2 " "$L" | tail -1 | sed 's/.* ws=\([0-9]*\) .*/\1/'; }
has() { grep -q "^GEOM $1 client title=$2 " "$L"; }
# the layout of the open grid, checked against what it should be
layout() { python3 - "$(box open 0)" "$(box open 1)" "$(box open 2)" "$(box open 3)" "$(box open 5)" <<'PY'
import sys
a,b,w,c,e=[list(map(int,x.split(','))) for x in sys.argv[1:]]
bad=[]
if a[1]!=b[1] or a[2:]!=b[2:] or b[0]-(a[0]+a[2])!=12: bad.append('row one')
if abs(a[2]/a[3]-393/873)>0.01: bad.append('portrait aspect')
if w[0]!=a[0] or w[2]!=2*a[2]+12 or not w[3]<w[2] or w[1]!=a[1]+a[3]+12: bad.append('wide card')
if c[1]!=w[1]+w[3]+12 or c[0]!=a[0] or e[1]!=c[1]+c[3]+12: bad.append('rows after it')
if not 34<=e[1] and e[1]+e[3]<=749: bad.append('current in view above the tray')
if 2*a[3]+12>749-36: bad.append('two rows do not fit')
if bad: print(bad,a,b,w,c,e,file=sys.stderr)
sys.exit(1 if bad else 0)
PY
}
for n in open fling settled tapped reopen closing closed dropped icon carousel; do echo "  $n: ws=$(curws $n) ov=$(ov $n) card=$(card $n) scroll=$(scroll $n)"; done
ok "no QML error, no sanitizer report"                  '! grep -E "Failed to load|TypeError|ReferenceError|runtime error|AddressSanitizer" "$L" | grep -q .'
ok "two portrait columns, the wide app one wide row"    'layout'
ok "opens scrolled to the current card, the tray kept"  '[ "$(scroll open)" -gt 0 ] && [ "$(card open)" = "$(box open 5)" ] && grep -q "^GEOM open layer ns=phone-tray" "$L"'
ok "a fling keeps going after the finger"               '[ "$(st fling 6)" = 1 ] && [ "$(scroll settled)" -lt "$(scroll fling)" ] && [ "$(scroll settled)" -ge 0 ] && [ "$(st settled 6)" = 0 ]'
ok "a tap opens that card"                              '[ "$(ov tapped)" = 0 ] && [ "$(curws tapped)" = 1 ]'
ok "it reopens with that card in view"                  '[ "$(card reopen)" = "$(box reopen 1)" ]'
ok "sideways closes the window"                         '! has closed a1 && [ "$(wsof closed a3)" = 2 ]'
ok "the next card is in its own place at once"          '[ "$(curws closing)" = 0 ] && [ "$(card closing)" = "$(box closing 0)" ]'
ok "a held window joins a card, the current one shown" '[ "$(wsof dropped a0)" = "$(wsof dropped a3)" ] && [ "$(curws dropped)" = 0 ] && grep "^FT dropped " "$L" | grep -q "counts=12"'
ok "a tray icon dropped on a card opens there"          'has icon icon && [ "$(wsof icon icon)" = "$(wsof icon a4)" ]'
ok "the fullscreen app kept its wide card"              'grep "^GEOM icon grid ws=$(wsof icon wide) " "$L" | grep -q "wide=1"'
ok "overviewmode carousel brings the carousel back"     '! grep -q "^GEOM carousel grid" "$L" && [ "$(card carousel | cut -d, -f3)" -gt 300 ]'
ok "no core files"                                      '[ -z "$(comp_cores)" ]'
[ "$FAILS" = 0 ] && echo "grid: all passed" || echo "grid: failed: $FAILS"
exit "$((FAILS > 0))"
