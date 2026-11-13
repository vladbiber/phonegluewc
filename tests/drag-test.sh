#!/bin/bash
# Dragging in the overview: an icon from the tray onto a card, a window onto a tile. Through the touch hook.
# Headless, neutral clients only. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-drag.XXXXXX")
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
	case " ${NAV_ONLY:-$n} " in *" $n "*) ;; *) return ;; esac
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/$n.script" PHONEGLUEWC_SCREENTEXT="$W/hold.sh" "$@"
	comp_wait 1500
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
rel() { python3 - "$(geom "$1" "$2")" "$(geom "$1" "$3")" "$4" <<'PY'
import sys
a=list(map(int,sys.argv[1].split(',')));b=list(map(int,sys.argv[2].split(',')))
r=sys.argv[3]
ok={'left':a[0]+a[2]<=b[0],'above':a[1]+a[3]<=b[1]}[r]
if not ok: print('geometry',a,b,r,file=sys.stderr)
sys.exit(0 if ok else 1)
PY
}
# the windows of workspace WS fill the screen, none over another
fills() { python3 - "$W/all.log" "$1" "$2" <<'PY'
import re,sys
log,label,ws=sys.argv[1:]
b=[]
for l in open(log,errors='replace'):
    m=re.match(rf'GEOM {label} client title=\S+ ws={ws} geom=(-?\d+),(-?\d+),(\d+),(\d+)',l)
    if m: b.append(tuple(map(int,m.groups())))
for i,a in enumerate(b):
    for c in b[i+1:]:
        if a[0]<c[0]+c[2] and c[0]<a[0]+a[2] and a[1]<c[1]+c[3] and c[1]<a[1]+a[3]: print('overlap',a,c,file=sys.stderr); sys.exit(1)
area=sum(a[2]*a[3] for a in b)
if not 0.85*393*873<area<=393*873+2: print('area',area,b,file=sys.stderr); sys.exit(1)
PY
}
mkdir -p "$W/data/applications"
de() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=sh %s %s\n' "$1" "$2" "$3" >"$W/data/applications/$4.desktop"; }
printf 'alpha.desktop\nslow.desktop\nsolo.desktop\n' >"$W/cfg/phonegluewc/pinned-apps"
de Alpha "$W/tl.sh" alpha alpha
printf 'n=$(cat "%s/delay"); sleep "$n"; exec sh "%s/tl.sh" slow\n' "$W" "$W" >"$W/late.sh"
de Slow "$W/late.sh" x slow
# what a single instance app does: its second process asks the first and leaves
printf 'echo asked >>"%s/solo-asked"; exit 0\n' "$W" >"$W/solo.sh"
de Solo "$W/solo.sh" x solo
echo 3 >"$W/delay"
slotw() { python3 -c "print(round((82.4 + 76 * $1) / 392.73, 3))"; }
Y=0.929
# on a card, in fractions of the screen the card stands for
cx() { python3 -c "print(round(0.074 + $1 * 0.852, 4))"; }
cy() { python3 -c "print(round(0.005 + $1 * 0.853, 4))"; }
glide() { # FROMX FROMY TOX TOY, a few steps
	python3 -c "
for i in range(1,7): print(f'm 0 {$1+($3-$1)*i/6:.4f} {$2+($4-$2)*i/6:.4f}'); print('f')"; }
# holds a tray icon, picks it up and takes it to X Y
iconto() { local s; s=$(slotw "$1"); echo "d 0 $s $Y"; echo f; echo "w 700"; glide "$s" $Y "$s" 0.90; echo "w 300"; glide "$s" 0.90 "$2" "$3"; echo "w 150"; }
# holds a window on the card and takes it to X Y
carry() { echo "d 0 $1 $2"; echo f; echo "w 350"; glide "$1" "$2" "$3" "$4"; echo "w 150"; }
drop() { up "${1:-700}"; }

# an icon: the popup without moving, a card, the free card, nothing
{ echo "w 2500"; app a; open
  echo "d 0 $(slotw 0) $Y"; echo f; echo "w 700"; up 300; shot drag-popup; echo "g p1"; tap 0.02 0.885 400
  iconto 0 "$(cx 0.5)" "$(cy 0.85)"; shot drag-icon; drop 1500; echo "g i1"; echo "p i1"; shot drag-dropped
  iconto 0 0.5 0.995; drop 900; echo "g i2"
  iconto 0 0.5 0.885; drop 900; echo "g i3"
  iconto 0 0.975 0.47; echo "w 600"; echo "p i4edge"; echo "g i4edge"; glide 0.975 0.47 0.5 0.47; shot drag-free; drop 1500; echo "g i4"; echo "p i4"; shot drag-free-dropped; echo "x true"; echo "w 300"; } >"$W/icon.script"
session icon
ok "holding without moving leaves the popup, no launch" '[ "$(count p1)" = 1 ]'
ok "an icon on a card: beside the window, half under the finger" 'has i1 alpha && [ "$(wsof i1 alpha)" = 0 ] && rel i1 a alpha above'
ok "and the overview stays open"          'state i1 overview=1'
ok "on nothing: nothing launches"         '[ "$(count i2)" = 2 ] && [ "$(count i3)" = 2 ]'
ok "resting at the edge turns the cards"  '[ "$(curws i4edge)" = 1 ]'
ok "on the free card: alone there"        '[ "$(count i4)" = 3 ] && [ "$(wsof i4 alpha)" = 0 ] && grep "^GEOM i4 client title=alpha ws=1 " "$W/all.log" >/dev/null'

# from home: holding a tray icon opens the cards under the finger, the edge turns them, the drop opens it there
HY=0.947
{ echo "w 2500"; app a; msg 2; echo "g h0"; echo "p h0"
  echo "d 0 $(slotw 0) $HY"; echo f; echo "w 700"; glide "$(slotw 0)" $HY "$(slotw 0)" 0.90; echo "w 400"; echo "p h1"; shot drag-home-lift
  glide "$(slotw 0)" 0.90 0.025 0.47; echo "w 900"; echo "g h2"; echo "p h2"; glide 0.025 0.47 "$(cx 0.5)" "$(cy 0.85)"; echo "w 150"; shot drag-home-carry
  drop 1500; echo "g h3"; echo "p h3"; shot drag-home-dropped; echo "x true"; echo "w 300"; } >"$W/home.script"
session home
ok "home: the held icon opens the cards"  'state h0 overview=0 && state h1 overview=1'
ok "home: resting at the edge turns to the left card" '[ "$(curws h2)" = 0 ]'
ok "home: dropped there, it opens beside the window" 'has h3 alpha && [ "$(wsof h3 alpha)" = 0 ] && rel h3 a alpha above'

# a late window lands where it was dropped even if the row shifted and the user moved on;
# after the timeout it gets the normal place
{ echo "w 2500"; app a; app b; app c; msg 2; open
  iconto 1 "$(cx 0.2)" "$(cy 0.5)"; drop 300; tap 0.02 0.885 300; echo "x sh $W/k.sh a"; echo "w 500"; msg 3; echo "p l0"; echo "w 3500"; echo "g l1"; echo "p l1"
  echo "x sh -c 'echo 22 >$W/delay'"; echo "w 300"; echo "x sh $W/k.sh slow"; echo "w 800"; open
  iconto 1 "$(cx 0.8)" "$(cy 0.5)"; drop 300; tap 0.02 0.885 300; echo "w 23500"; echo "g l2"; echo "x true"; echo "w 300"; } >"$W/late.script"
echo 3 >"$W/delay"
session late
ok "a late window lands on the dropped card after the row shifted" '[ "$(wsof l1 slow)" = "$(wsof l1 b)" ] && [ "$(wsof l1 b)" = 0 ] && rel l1 slow b left && fills l1 0'
ok "whoever moved on is not pulled there" '[ "$(curws l1)" = 2 ] || [ "$(curws l1)" != "$(wsof l1 slow)" ]'
ok "after the timeout, normal placement"  'has l2 slow && [ "$(wsof l2 slow)" != "$(wsof l2 b)" ] && [ "$(wsof l2 slow)" != "$(wsof l2 c)" ]'

# a single instance app: nothing is launched into place, nothing moves, and a window it opens
# from its old process is not taken for the dropped one
{ echo "w 2500"; app a; open
  iconto 2 "$(cx 0.5)" "$(cy 0.85)"; drop 800; echo "g s1"; tap 0.02 0.885 300; app other; echo "g s2"; echo "x true"; echo "w 300"; } >"$W/single.script"
session single
ok "a single instance app moves and splits nothing" '[ "$(count s1)" = 1 ] && fills s1 0 && [ -s "$W/solo-asked" ]'
ok "its other window opens in the normal place" '[ "$(wsof s2 other)" != "$(wsof s2 a)" ]'

# a card at the limit, and a full row
{ echo "w 2500"; app a; open
  iconto 0 "$(cx 0.5)" "$(cy 0.85)"; drop 1200; iconto 0 "$(cx 0.5)" "$(cy 0.85)"; drop 1200; iconto 0 "$(cx 0.25)" "$(cy 0.2)"; drop 1200; echo "g f0"; echo "p f0"; shot drag-four
  iconto 0 "$(cx 0.75)" "$(cy 0.2)"; shot drag-limit; drop 1200; echo "g f1"; echo "x true"; echo "w 300"; } >"$W/limit.script"
session limit
ok "four tiles on one card"               '[ "$(count f0)" = 4 ] && [ "$(grep -c "^GEOM f0 client .* ws=0 " "$W/all.log")" = 4 ] && fills f0 0'
ok "a card at the limit refuses an icon, visibly" '[ "$(count f1)" = 4 ] && grep -q "button tilefull" "$W/all.log"'
{ echo "w 2500"; for n in 1 2 3 4 5 6 7 8 9; do app w$n; done; open
  echo "w 800"; iconto 0 "$(cx 0.5)" "$(cy 0.85)"; drop 800; echo "g n1"; echo "x true"; echo "w 300"; } >"$W/nine.script"
session nine
ok "a full row refuses an icon, visibly"  '[ "$(count n1)" = 9 ] && grep -q "button nofree" "$W/all.log"'

# tiles: across cards, each side, the swap, last window off, back to the live layout
{ echo "w 2500"; app a; app b; app c; msg 2; open; echo "g t0"
  # b from its card, resting at the edge to reach a's card, then a's right half
  carry "$(cx 0.5)" "$(cy 0.5)" 0.02 0.47; echo "w 600"; echo "g t1a"; glide 0.02 0.47 "$(cx 0.9)" "$(cy 0.5)"; shot drag-side; drop; echo "g t1"; echo "p t1"
  carry "$(cx 0.75)" "$(cy 0.5)" "$(cx 0.04)" "$(cy 0.5)"; drop; echo "g t2"
  carry "$(cx 0.25)" "$(cy 0.5)" "$(cx 0.96)" "$(cy 0.5)"; drop; echo "g t3"
  carry "$(cx 0.75)" "$(cy 0.5)" "$(cx 0.25)" "$(cy 0.09)"; drop; echo "g t4"
  carry "$(cx 0.5)" "$(cy 0.25)" "$(cx 0.5)" "$(cy 0.96)"; drop; echo "g t5"
  carry "$(cx 0.5)" "$(cy 0.25)" "$(cx 0.5)" "$(cy 0.75)"; shot drag-swap; drop; echo "g t6"; shot drag-tiles
  carry "$(cx 0.5)" "$(cy 0.25)" 0.5 0.995; drop; echo "g t7"
  # into the free card, past c
  carry "$(cx 0.5)" "$(cy 0.75)" 0.98 0.47; echo "w 600"; echo "g t8a"; echo "p t8a"; echo "w 600"; echo "g t8b"; glide 0.98 0.47 0.5 0.47; drop; echo "g t8"; echo "p t8"
  tap 0.5 0.47 700; echo "g t9"; echo "p t9"; echo "x true"; echo "w 300"; } >"$W/tile.script"
session tile
ok "carry to another card by the edge, then its right half" 'state t1 ws=0 && [ "$(wsof t1 b)" = 0 ] && [ "$(wsof t1 a)" = 0 ] && rel t1 a b left'
ok "the emptied card closed up"           'row t1 0 a=0 b=0 c=1'
ok "left of a tile"                       'rel t2 b a left && fills t2 0'
ok "right of a tile"                      'rel t3 a b left && fills t3 0'
ok "above a tile"                         'rel t4 b a above && fills t4 0'
ok "below a tile"                         'rel t5 a b above && fills t5 0'
ok "the centre swaps"                     'rel t6 b a above && fills t6 0'
ok "off every card: stays"                'rel t7 b a above'
ok "last window of a tile pair onto the free card: its own workspace" '[ "$(wsof t8 a)" != "$(wsof t8 b)" ] && [ "$(wsof t8 a)" != "$(wsof t8 c)" ]'
ok "the card left behind fills again though nobody looks at it" '[ "$(geom t8 b)" = "$(grep "^GEOM t8 mon " "$W/all.log" | tail -1 | sed "s/.* w=\([^ ]*\).*/\1/")" ]'
ok "one free one on the right after all"  'row t8 "$(curws t8)"'
ok "the live layout agrees after leaving" '[ "$(geom t9 a)" = "$(geom t8 a)" ] && state t9 overview=0'

# mouse as a finger: the same drag
mdown() { echo "M $1 $2"; echo "w 30"; echo "B 1"; echo "w 30"; }
mglide() { python3 -c "
for i in range(1,7): print(f'M {$1+($3-$1)*i/6:.4f} {$2+($4-$2)*i/6:.4f}'); print('w 20')"; }
{ echo "w 2500"; app a; app b; msg 2; mdown 0.5 0.995; mglide 0.5 0.995 0.5 0.6; echo "w 300"; echo "B 0"; echo "w 700"; echo "p m0"
  s=$(slotw 0); mdown "$s" $Y; echo "w 700"; mglide "$s" $Y "$s" 0.9; echo "w 300"; mglide "$s" 0.9 "$(cx 0.5)" "$(cy 0.85)"; echo "B 0"; echo "w 1500"; echo "g m1"
  mdown "$(cx 0.5)" "$(cy 0.25)"; echo "w 350"; mglide "$(cx 0.5)" "$(cy 0.25)" "$(cx 0.5)" "$(cy 0.75)"; echo "B 0"; echo "w 700"; echo "g m2"
  mopen() { mdown 0.5 0.995; mglide 0.5 0.995 0.5 0.6; echo "w 300"; echo "B 0"; echo "w 700"; }
  mclick() { mdown "$1" "$2"; echo "B 0"; echo "w ${3:-900}"; }
  mclick "$s" $Y; echo "p m3"; echo "g m3"
  mopen; mdown "$s" $Y; echo "w 700"; echo "B 0"; echo "w 300"; mclick 0.323 0.73 1500; echo "p m4"; echo "g m4"
  mopen; mclick 0.86 0.885 1500; echo "p m5"; echo "g m5"; echo "x true"; echo "w 300"; } >"$W/mouse.script"
session mouse PHONEGLUEWC_MOUSE_FINGER=1
ok "mouse: an icon on a card"             'state m0 overview=1 && rel m1 b alpha above'
ok "mouse: a tile swap"                   'rel m2 alpha b above'
ok "mouse: a tap on an open app goes to it" 'state m3 overview=0 && [ "$(count m3)" = 3 ]'
ok "mouse: New window starts another"     '[ "$(count m4)" = 4 ] && state m4 overview=0'
ok "mouse: close all closes them"         '[ "$(count m5)" = 0 ] && state m5 overview=0'

for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
[ -n "${DRAG_LOG:-}" ] && cp "$W/all.log" "$DRAG_LOG"
comp_cores
[ "$fails" = 0 ] && echo "drag: all passed" || echo "drag: failed: $fails"
exit "$((fails > 0))"
