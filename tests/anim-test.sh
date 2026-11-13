#!/bin/bash
# Open, close and flick animations through the touch hook, and frame times.
# Headless, neutral clients only. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-anim.XXXXXX")
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
printf 'echo $$ >"%s/pid-$1"; TOUCHLOG_CONF=1 TOUCHLOG_TITLE=$1 exec "%s/touchlog" >"%s/log-$1" 2>&1\n' "$W" "$W" "$W" >"$W/tl.sh"
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
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_FRAMELOG=1 PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/$n.script" PHONEGLUEWC_SCREENTEXT="$W/hold.sh" "$@"
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
mkdir -p "$W/data/applications"
de() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=sh %s %s\n' "$1" "$2" "$3" >"$W/data/applications/$4.desktop"; }
printf 'alpha.desktop\nslow.desktop\nthird.desktop\n' >"$W/cfg/phonegluewc/pinned-apps"
de Alpha "$W/tl.sh" alpha alpha
printf 'sleep 1; exec sh "%s/tl.sh" slow\n' "$W" >"$W/late.sh"
de Slow "$W/late.sh" x slow
de Third "$W/tl.sh" third third
Y=0.929
# the tray on the home screen, and with the close all button beside it
home() { python3 -c "print(round((82.4 + 76 * $1) / 392.73, 3))"; }
slotw() { python3 -c "print(round((44.4 + 28 + 62 * $1) / 392.73, 3))"; }
samples() { local i; for ((i = 0; i < $2; i++)); do echo "g $1"; done; }
press() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; }
# LABEL TITLE icon|centre|none [X Y]: the samples of one window, from its first frame to the end
grows() { python3 - "$W/all.log" "$@" <<'PY'
import re,sys
log,label,title,how=sys.argv[1:5]
s=[]
for l in open(log,errors='replace'):
    m=re.match(rf'GEOM {label} client title={title} ws=\d+ geom=(\d+),(\d+),(\d+),(\d+) .* anim=(\d),([\d.]+),([\d.]+) node=(-?\d+),(-?\d+)',l)
    if m: s.append(dict(g=list(map(int,m.groups()[:4])),a=int(m[5]),z=float(m[7]),x=int(m[8]),y=int(m[9])))
if not s: print('no samples',label,title,file=sys.stderr); sys.exit(1)
f,e=s[0],s[-1]
cx,cy=f['x']+f['g'][2]*f['z']/2,f['y']+f['g'][3]*f['z']/2
bad=[]
if how=='icon':
    px,py=float(sys.argv[5])*393,float(sys.argv[6])*873
    # a sample comes a frame or two into the motion: it must lie on the way from the press to the full window
    z0=56/f['g'][2]; t=(f['z']-z0)/(1-z0)
    if f['z']>=.6: bad.append('starts big')
    if abs(cx-(px+(f['g'][0]+f['g'][2]/2-px)*t))>30 or abs(cy-(py+(f['g'][1]+f['g'][3]/2-py)*t))>30: bad.append(f'not on the way from {px:.0f},{py:.0f}')
elif how=='centre':
    if not .7<=f['z']<1: bad.append('no zoom from the centre')
    if abs(cx-(f['g'][0]+f['g'][2]/2))>12 or abs(cy-(f['g'][1]+f['g'][3]/2))>12: bad.append('not centred')
elif how=='none':
    if f['a'] or f['z']!=1: bad.append('animated')
if e['a'] or (e['x'],e['y'])!=tuple(e['g'][:2]) or e['z']!=1: bad.append('not settled')
active=sum(x['a'] for x in s)
if active>26: bad.append(f'{active} ticks')
if any(b['z']<a['z']-.001 for a,b in zip(s,s[1:])): bad.append('shrinks')
print(f"  {label}: first scale {f['z']:.2f} centre {cx:.0f},{cy:.0f}, active {active} ticks, {'ok' if not bad else bad}")
sys.exit(1 if bad else 0)
PY
}
closes() { grep "^GEOM $1 mon " "$W/all.log" | sed 's/.*closes=\([0-9]*\).*/\1/' | sort -n | tail -1; }
closes_last() { grep "^GEOM $1 mon " "$W/all.log" | tail -1 | sed 's/.*closes=\([0-9]*\).*/\1/'; }
ov() { grep "^GEOM $1 mon " "$W/all.log" | tail -1 | sed 's/.* ov=\([0-9]*\) .*/\1/'; }

# the tray at home; the tray over a window with a slow app, nothing changes before its buffer; a terminal launch; a close
{ echo "w 2500"; press "$(home 0)" $Y; samples a1 70; echo "g a1end"
  open; press "$(slotw 1)" $Y; echo "w 500"; echo "g a2wait"; echo "w 300"; samples a2 90; echo "g a2end"
  echo "x sh $W/tl.sh term"; samples a3 80; echo "g a3end"
  echo "x sh $W/k.sh term"; samples c1 8; echo "w 400"; echo "g c1end"; echo "w 300"; } >"$W/open.script"
session open
ok "from the home tray it grows from the icon, full size in time" "grows a1 alpha icon $(home 0) $Y"
ok "a slow app: overview and workspace wait for its first buffer" '[ "$(ov a2wait)" = 1 ] && [ "$(curws a2wait)" = 0 ] && [ "$(count a2wait)" = 1 ]'
ok "from the overview tray it grows from the icon and the overview is gone" "grows a2 slow icon $(slotw 1) $Y && [ \"\$(ov a2end)\" = 0 ] && [ \"\$(curws a2end)\" = 1 ]"
ok "launched from a terminal it grows from the centre, the old window fades" 'grows a3 term centre && [ "$(closes a3)" -ge 1 ] && [ "$(closes_last a3end)" = 0 ] && [ "$(curws a3end)" = 2 ]'
ok "a close keeps the last buffer for the animation, then frees it" '[ "$(closes c1)" -ge 1 ] && [ "$(closes_last c1end)" = 0 ] && [ "$(count c1end)" = 2 ]'

# captures of the motion: a few shots after the press, the shots themselves slow it a little
{ echo "w 2500"; press "$(home 0)" $Y; for i in 1 2 3 4 5 6 7 8; do echo "x $SRC/tests/wshot $W/anim-open$i.ppm"; echo "w 45"; done; echo "w 700"
  echo "x sh $W/k.sh alpha"; for i in 1 2 3; do echo "x $SRC/tests/wshot $W/anim-close$i.ppm"; echo "w 50"; done; echo "w 600"; } >"$W/mid.script"
session mid

# a flick from an app: it goes on from under the finger to a small card that fades, nothing else moves
magick -size 1080x2400 xc:'#14344a' -fill '#3a7ca5' -draw 'circle 540,1200 540,500' -fill '#e8b04a' -draw 'rectangle 0,1180 1080,1220' -draw 'rectangle 520,0 560,2400' "$W/wall.png"
flickconf() { printf 'wallpaper = %s\n' "$W/wall.png" >"$W/cfg/phonegluewc/phone.conf"; }
flickscript() { # NAME: app, drag that shrinks it, release
	{ echo "w 2500"; app a; echo "d 0 0.5 0.995"; echo f; y=0.995
	  # about 1.2 px/ms: a flick has to clear PILL_FLICK
	  for i in 1 2 3 4 5 6; do y=$(python3 -c "print(round($y-0.07,4))"); echo "m 0 0.5 $y"; echo f; echo "g $1"; done; }
}
flickconf
{ flickscript fl; echo "u 0"; for i in $(seq 1 45); do echo "g fl"; done; echo "w 300"; echo "g flend"; echo "p flend"; } >"$W/flick.script"
session flick
cp "$W/log-a" "$W/flick-client.log" 2>/dev/null
cp "$W/gw.log" "$W/flick.gw" 2>/dev/null
cont() { python3 - "$W/all.log" <<'PY'
import re,sys
r=[]
for l in open(sys.argv[1],errors='replace'):
    m=re.match(r'GEOM fl mon .* ws=(\d+) ov=(\d) card=(-?\d+),(-?\d+),(\d+),(\d+) card0=(-?\d+),(-?\d+),(\d+),(\d+)',l)
    if m: r.append(list(map(int,m.groups())))
step=[]
for a,b in zip(r,r[1:]):
    pa=a[2:6] if a[0]==r[0][0] else a[6:10]
    pb=b[2:6] if b[0]==r[0][0] else b[6:10]
    step.append(max(abs(x-y) for x,y in zip(pa,pb)))
after=[x[6:10] for x in r if x[0]!=r[0][0] and x[1]==1]
w=[c[2] for c in after]
print('  largest step',max(step),'at',step.index(max(step)),'of',len(step),'release widths',w[:6],'...',w[-3:])
sys.exit(0 if max(step)<=90 and w==sorted(w,reverse=True) and w[-1]<170 and after[-1][1]<after[0][1] else 1)
PY
}
ok "the leaving window goes on from the finger, shrinks and rises, no jump at the release" cont
ok "the flick lands on the free workspace, overview closed" '[ "$(curws flend)" = 1 ] && [ "$(ov flend)" = 0 ]'
ok "no resize reaches the client during the flick" '[ "$(grep "^conf " "$W/flick-client.log" | grep -v " 0 0$" | sed -n "2,\$p" | sort -u | wc -l)" -le 1 ] && [ "$(grep "^conf " "$W/flick-client.log" | grep -v " 0 0$" | sort -u | wc -l)" = 1 ]'
ok "the app is alive after the flick" 'kill -0 "$(cat "$W/pid-a")" 2>/dev/null || grep -q "client title=a ws=0" "$W/all.log"'

# interrupted: a new swipe in flight takes over, the app stays one card to the left
{ flickscript fi; echo "u 0"; for i in 1 2 3 4; do echo "g fi"; done; swipe 0.035 6 2>/dev/null; echo "w 300"; echo "u 0"; echo "w 900"; echo "g fiend"; echo "p fiend"; } >"$W/flickint.script"
session flickint
ok "a new swipe during the flick takes over: overview on the free card, the app on its left" '[ "$(ov fiend)" = 1 ] && [ "$(curws fiend)" = 1 ] && grep -q "GEOM fiend mon .* card0=-[0-9]" "$W/all.log"'

# the same motion stretched in time so that single frames can be looked at
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\nanimation_duration = 4000\n' >"$W/cfg/phonegluewc/config.conf"
capture() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 60"; }
grab() { echo "x $SRC/tests/wshot $W/$1.ppm"; }  # no time passes: the finger keeps its speed
{ echo "w 2500"; app a; echo "d 0 0.5 0.995"; echo f; y=0.995
  for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y-0.035,4))"); echo "m 0 0.5 $y"; echo f
    case $i in 3|6) grab exit-drag$i;; esac; done
  echo "u 0"; for i in 0 1 2 3 4 5 6 7; do capture exit-rel$i; echo "w 500"; done; echo "w 3000"; capture exit-end; } >"$W/exitframes.script"
session exitframes
# and cancelled: a drag that falls back by the same curve
{ echo "w 2500"; app a; echo "d 0 0.5 0.995"; echo f; y=0.995
  for i in 1 2 3 4 5 6; do y=$(python3 -c "print(round($y-0.02,4))"); echo "m 0 0.5 $y"; echo f; done
  for i in 1 2 3 4; do y=$(python3 -c "print(round($y+0.008,4))"); echo "m 0 0.5 $y"; echo f; done
  grab exit-cancel0; echo "u 0"; for i in 1 2 3 4; do capture exit-cancel$i; echo "w 700"; done; echo "w 3000"; capture exit-cancelend; } >"$W/exitcancel.script"
session exitcancel
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
for f in "$W"/exit-*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
rm -f "$W/cfg/phonegluewc/phone.conf"

# phone.conf: off is instant, and changing it applies without a restart
echo 'animations = off' >"$W/cfg/phonegluewc/phone.conf"
{ echo "w 2500"; press "$(home 0)" $Y; samples o1 50
  echo "x sh $W/tl.sh term"; samples o2 50
  echo "x sh $W/k.sh term"; samples o3 8; echo "w 200"
  echo "x sh -c 'echo animations = on >$W/cfg/phonegluewc/phone.conf'"; echo "w 700"
  echo "x sh $W/tl.sh back"; samples o4 60; echo "w 200"; } >"$W/off.script"
session off
rm -f "$W/cfg/phonegluewc/phone.conf"
ok "animations = off opens at once, from the tray and from a terminal" 'grows o1 alpha none && grows o2 term none'
ok "animations = off closes at once" '[ "$(closes o3)" = 0 ]'
ok "turning it back on applies without a restart" 'grows o4 back centre'

# a new touch during each motion takes over
{ echo "w 2500"; app a; echo "x sh $W/tl.sh b"; echo "w 300"; swipe 0.05 8; echo "w 250"; echo "g i0"; up; echo "g i1"; echo "p i1"
  closeov; echo "x sh $W/tl.sh c"; echo "w 250"; echo "x sh $W/k.sh c"; echo "w 30"; swipe 0.05 8; echo "w 250"; echo "g i2"; up
  closeov; echo "x sh $W/tl.sh d"; echo "w 250"; echo "d 0 0.5 0.995"; echo f; echo "m 0 0.5 0.9"; echo f; echo "m 0 0.5 0.8"; echo f; up; echo "g i3"; echo "w 500"; echo "g i4"; } >"$W/inter.script"
session inter
ok "a swipe during the opening takes over: the overview shows, at the usual card" '[ "$(ov i0)" = 1 ] && [ "$(count i1)" = 2 ]'
ok "a swipe during the closing takes over" '[ "$(ov i2)" = 1 ] && [ "$(closes_last i4)" = 0 ]'
ok "a flick during the opening lands on the free workspace" '[ "$(ov i4)" = 0 ] && [ "$(curws i4)" = "$(count i4)" ]'

# frames: the phone size, and the size of the laptop window. The scene renderer is GL only and ignores
# WLR_RENDERER=pixman, so this is the GPU of the machine; forcing software GL crashes Mesa here at startup
frames() { # LABEL
	python3 - "$W/gw.frames" "$1" <<'PY'
import re,sys
c=[];g=[];u=[];gl=0
for l in open(sys.argv[1],errors='replace'):
    m=re.match(r'FRAME commit=([\d.]+) gap=([\d.]+) cpu=([\d.]+) gl=(\d)',l)
    # a frame with nothing new to draw costs nothing and says nothing
    if m and float(m[1])>=1: c.append(float(m[1])); g.append(float(m[2])); u.append(float(m[3])); gl=int(m[4])
if not c: print('  no frames'); sys.exit(1)
# a gap over 100 ms is the screen standing still between two motions
c.sort(); u.sort(); g=sorted(x for x in g if x<100)
p=lambda a,q:a[int(len(a)*q)]
print(f"anim: {sys.argv[2]}: {len(c)} drawn frames, render ms p50 {p(c,.5):.1f} p95 {p(c,.95):.1f} max {c[-1]:.1f} (waited for GL: {bool(gl)}); cpu ms per frame p50 {p(u,.5):.1f}; gap between frames in motion ms p50 {p(g,.5):.1f} p95 {p(g,.95):.1f} max {g[-1]:.1f}, over 20 ms: {sum(x>20 for x in g)}")
PY
}
loop() { echo "w 2500"; for i in 1 2 3 4 5 6; do echo "x sh $W/tl.sh f$i"; echo "w 450"; echo "x sh $W/k.sh f$i"; echo "w 450"; done; app a; for i in 1 2 3; do swipe 0.05 8; echo "w 250"; up; closeov; echo "w 300"; done; }
[ -s "$W/flick.gw" ] && [ -n "${FLICK_FRAMES:-}" ] && cp "$W/flick.gw" "$FLICK_FRAMES"
[ -s "$W/flick.gw" ] && python3 - "$W/flick.gw" <<'PY'
import re,sys
c=[];g=[];u=[];on=0
for l in open(sys.argv[1],errors='replace'):
    if l.startswith('GEOM fl mon'): on=1
    if l.startswith('GEOM flend'): break
    m=re.match(r'FRAME commit=([\d.]+) gap=([\d.]+) cpu=([\d.]+)',l)
    if on and m and float(m[1])>0: c.append(float(m[1])); g.append(float(m[2])); u.append(float(m[3]))
c.sort(); g.sort(); u.sort(); p=lambda a,q:a[min(len(a)-1,int(len(a)*q))]
print(f"anim: flick out of an app, 1080x2400, from the drag to the end: {len(c)} drawn frames, render ms p50 {p(c,.5):.2f} max {c[-1]:.2f}; cpu ms p50 {p(u,.5):.2f} max {u[-1]:.2f}; gap ms p50 {p(g,.5):.1f} p95 {p(g,.95):.1f} max {g[-1]:.1f}")
PY
loop >"$W/frames.script"
if case " ${ANIM_ONLY:-frames} " in *" frames "*) true ;; *) false ;; esac; then
	: >"$W/all.log"; session frames; grep -m1 'GL renderer: ' "$W/all.log"; grep '^FRAME ' "$W/all.log" >"$W/gw.frames"; frames "1080x2400 headless, Intel GPU"
	printf 'remember_layout = false\noutput = * mode=450x1000 scale=1.15\n' >"$W/cfg/phonegluewc/config.conf"
	cp "$W/frames.script" "$W/frames2.script"
	: >"$W/all.log"; session frames2; grep -m1 'GL renderer: ' "$W/all.log"; grep '^FRAME ' "$W/all.log" >"$W/gw.frames"; frames "450x1000 headless, Intel GPU"
fi
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
comp_cores
[ "$fails" = 0 ] && echo "anim: all passed" || echo "anim: failed: $fails"
exit "$((fails > 0))"
