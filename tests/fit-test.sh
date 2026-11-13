#!/bin/bash
# Windows wider than the screen: all of it visible, input lands right, normal windows untouched.
# Headless, one fake client. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-fit.XXXXXX")
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g"} >"$W/build.log" 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/fitapp" "$SRC/tests/fitapp.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
mkdir -p "$W/cfg/phonegluewc"
conf() { printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75 transform=%s\n' "$1" >"$W/cfg/phonegluewc/config.conf"; }
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD"
: >"$W/all.log"
session() { # NAME [ENV...]: runs $W/$NAME.script to its end
	local n=$1; shift
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/$n.script" "$@"
	comp_wait 400
	cat "$W/gw.log" >>"$W/all.log"
	grep -q 'AddressSanitizer\|runtime error' "$W/gw.log" && { grep -m3 'AddressSanitizer\|runtime error' "$W/gw.log"; fails=$((fails + 1)); }
	comp_stop
}
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 500"; }
# the app starts in its own helper: script lines are short
app() { printf '%s FIT_MIN=%s FIT_BIG=%s exec "%s/fitapp" >"%s/log-%s" 2>&1\n' '' "$2" "$3" "$W" "$W" "$1" >"$W/run-$1.sh"; echo "x sh $W/run-$1.sh"; echo "w 2000"; }
tap() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w 400"; }
pillopen() { echo "d 0 0.5 0.995"; echo f; for s in 1 2 3 4 5 6 7 8; do echo "m 0 0.5 $(python3 -c "print(0.995-0.5*$s/8)")"; echo f; done; echo "w 250"; echo "u 0"; echo f; echo "w 900"; }
# nearest log line of a kind: near FILE KIND X Y [TOL]
near() { awk -v k="$2" -v x="$3" -v y="$4" -v t="${5:-3}" '$1==k && $2=="down" { d=$3-x; e=$4-y; if (d<0) d=-d; if (e<0) e=-e; if (d<=t && e<=t) f=1 } END { exit !f }' "$W/log-$1"; }
geom() { grep "^GEOM $1 client" "$W/all.log" | head -1; }

conf 0
# screen is 392.7x872.7, the window area starts at 36; 900 wide in 392 is 0.437
{ echo "w 2500"; app dec 900 0; echo "g dec"; shot dec
  tap 0.995 0.5
  tap 0.9 0.11
  echo "d 0 0.9 0.2"; echo f; echo "m 0 0.5 0.2"; echo f; echo "m 0 0.5 0.01"; echo f; echo "u 0"; echo f; echo "w 300"
  tap 0.5 0.54; shot popup; tap 0.53 0.56; echo "w 300"
  pillopen; echo "g card"; shot card; echo "x true"; echo "w 300"; } >"$W/one.script"
session one
ok "a declared minimum is drawn at scale 0.437" 'geom dec | grep -q "fit=0.437"; [ $? = 0 ]'
ok "the client is asked for the height that fills the area" 'grep -q "^size 900 19[0-9][0-9]" "$W/log-dec"'
ok "it never left the area" '! grep -q "^size 900 2000" "$W/log-dec"'
ok "a tap at the far right edge reaches the surface there" 'near dec body 893 916 4'
ok "the subsurface takes its tap at its own coordinates" 'near dec sub 7 37 4'
ok "a tap reaches the body at its surface coordinate" 'near dec body 448 995 4'
ok "a drag keeps mapping back" 'grep -q "^motion 44[0-9] 31[0-9]" "$W/log-dec"'
ok "a drag off the window keeps mapping back" 'grep -q "^motion 44[0-9] -[0-9]" "$W/log-dec"'
ok "the popup opens where the tap was" 'grep -q "^popup at 4[45][0-9] 99[0-9] 100 60" "$W/log-dec"'
ok "the popup takes its tap at its own coordinates" 'grep -q "^popup down" "$W/log-dec"'
python3 - "$W" >"$W/pix.out" <<'PY'
import sys
w=sys.argv[1]
def load(n):
    d=open(f"{w}/{n}.ppm","rb").read(); p=d.split(maxsplit=4)
    W,H=int(p[1]),int(p[2]); return W,H,p[4][-W*H*3:]
def px(i,x,y):
    W,H,b=i; o=(y*W+x)*3; return tuple(b[o:o+3])
red=lambda c:c[0]>180 and c[1]<70 and c[2]<70
green=lambda c:c[1]>180 and c[0]<70 and c[2]<70
blue=lambda c:c[2]>180 and c[0]<70 and c[1]<70
yellow=lambda c:c[0]>180 and c[1]>180 and c[2]<70
d=load("dec"); y=1200
xs=[x for x in range(d[0]) if red(px(d,x,y))]
gs=[x for x in range(d[0]) if green(px(d,x,y))]
print("dec-red",min(xs),max(xs),"green",min(gs),max(gs))
bx=[x for x in range(d[0]) if blue(px(d,x,int((36+130*.4356)*2.75)))]
print("dec-blue",min(bx),max(bx))
ys=[v for v in range(d[1]) if red(px(d,d[0]-5,v))]
print("dec-rows",min(ys),max(ys))
p=load("popup")
pts=[(x,yy) for yy in range(0,p[1],2) for x in range(0,p[0],2) if yellow(px(p,x,yy))]
print("popup",min(a for a,_ in pts),max(a for a,_ in pts),min(b for _,b in pts),max(b for _,b in pts))
c=load("card"); y=c[1]//2
xs=[x for x in range(c[0]) if red(px(c,x,y))]
gs=[x for x in range(c[0]) if green(px(c,x,y))]
print("card-red",min(xs),max(xs),"green",min(gs),max(gs))
PY
cat "$W/pix.out" | sed 's/^/  /'
rng() { awk -v k="$1" -v n="$2" -v a="$3" -v b="$4" '$1==k { if ($n>=a && $n<=b) f=1 } END { exit !f }' "$W/pix.out"; }
# right column: 20 client px are 24 physical at this scale, at the very edge of 1080
ok "the whole width is visible: red column at the right edge" 'rng dec-red 2 1050 1060 && rng dec-red 3 1078 1080'
ok "the left column is at the left edge" 'rng dec-red 5 0 1 && rng dec-red 6 20 28'
ok "the subsurface is drawn scaled and in place" 'rng dec-blue 2 960 975 && rng dec-blue 3 1030 1050'
ok "the window fills the area down to the screen edge" 'rng dec-rows 2 95 105 && rng dec-rows 3 2395 2400'
ok "the popup is drawn at the tap, at the same scale" 'rng popup 2 530 548 && rng popup 3 650 670 && rng popup 4 1285 1310 && rng popup 5 1355 1385'
ok "the card shows the whole window, not shrunk twice" 'card=$(grep "^GEOM card client" "$W/all.log" | sed "s/.*cardwin=//;s/ .*//"); cx=${card%%,*}; r=${card#*,}; r=${r#*,}; cw=${r%%,*}; awk -v l=$cx -v w=$cw "\$1==\"card-red\" { l*=2.75; w*=2.75; d=\$3-(l+w); if (d<0) d=-d; g=\$5-l; if (g<0) g=-g; exit !(d<=4 && g<=4) }" "$W/pix.out"'
{ echo "w 2500"; app big 0 700; echo "g big"; tap 0.995 0.5; echo "x true"; echo "w 300"; } >"$W/two.script"
session two
ok "an undeclared minimum is found from what the client commits" 'geom big | grep -q "fit=0.56"; [ $? = 0 ]'
ok "and the far right tap lands there too" 'near big body 696 713 4'
{ echo "w 2500"; app normal 0 0; echo "g normal"; tap 0.995 0.5; tap 0.5 0.5; echo "x true"; echo "w 300"; } >"$W/three.script"
session three
ok "a normal window stays at scale 1" 'geom normal | grep -q "fit=1.000"; [ $? = 0 ]'
ok "and its surface is exactly the area" 'geom normal | grep -q "surf=393,837"; [ $? = 0 ]'
ok "and a tap is not scaled" 'near normal body 196 400 3'
# tiled: the slot is narrower than the area, the same rule holds, side by side or stacked
d() { echo "d 0 $1 $2"; echo f; }
m() { echo "m 0 $1 $2"; echo f; }
{ echo "w 2500"; app tilea 0 0; app tileb 500 0; pillopen
  d 0.5 0.3; echo "w 400"; m 0.3 0.3; m 0.05 0.3; echo "w 300"; echo "u 0"; echo f; echo "w 900"; tap 0.05 0.5; echo "w 900"
  echo "g tile"; shot tile; echo "x true"; echo "w 300"; } >"$W/tile.script"
session tile
echo "  $(grep "^GEOM tile client" "$W/all.log" | sed "s/.*geom=/geom=/;s/ fs=.*fit/ fit/" | tr '\n' ';')"
ok "tiled, a window wider than its slot shrinks there" 'grep "^GEOM tile client" "$W/all.log" | grep -q "surf=500,.* fit=0\."'
ok "tiled, its neighbour stays at scale 1" 'grep "^GEOM tile client" "$W/all.log" | grep -q "fit=1.000"'
conf 90
# landscape: the area is about 872 wide, 900 still does not fit; user right edge is panel v near 0
{ echo "w 2500"; app rot 900 0; echo "g rot"; tap 0.5 0.003; echo "x true"; echo "w 300"; } >"$W/four.script"
session four
ok "rotated, it fits the new width" 'geom rot | grep -q "fit=0.9[67]"; [ $? = 0 ]'
ok "rotated, the far edge tap lands there" 'awk "\$1==\"body\" && \$3>=885" "$W/log-rot" | grep -q .'
conf 0
for n in dec popup card tile; do [ -f "$W/$n.ppm" ] && magick "$W/$n.ppm" "$SHOTS/fit-$n.png" 2>/dev/null; done
[ "$fails" = 0 ] && echo "all passed" || echo "$fails failed"
[ -z "${KEEP:-}" ] || { rm -rf "$KEEP"; cp -r "$W" "$KEEP"; }
rm -rf "$W"
[ "$fails" = 0 ]
