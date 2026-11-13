#!/bin/bash
# Navigation: one free workspace on the right, flick against hold from the bottom, the hidden bar.
# Headless, neutral clients only. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-nav.XXXXXX")
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
geom() { grep "^GEOM $1 client title=$2 " "$W/all.log" | sed 's/.* geom=\([^ ]*\).*/\1/' | tail -1; }
mon() { grep "^GEOM $1 mon " "$W/all.log" | tail -1; }
touches() { grep -c "^touch $2" "$W/snap/$1" 2>/dev/null; }

# one free workspace: first, middle, last, current, during the carousel
{ echo "w 2500"; for a in a b c d; do app $a; done; echo "g s1"
  die a; echo "g s2"; die c; echo "g s3"
  app e; echo "g s4"; die e; echo "g s5"
  msg 1; echo "g s5b"; die b; echo "g s6"
  app f; app h; echo "g s7"
  open; echo "p ov7"; echo "g s7b"; shot row-overview
  echo "d 0 0.8 0.4"; echo f; for x in 0.7 0.55 0.4; do echo "m 0 $x 0.4"; echo f; done; echo "u 0"; echo f
  die f 100; echo "p carousel"; echo "w 700"; echo "g s8"; shot row-after-close
  closeov; echo "p closed8"; echo "g s9"
  echo "x phonegluewc-msg move 9"; echo "w 700"; echo "g s10"
  app i; echo "g s11"; msg 1; echo "x phonegluewc-msg move 9"; echo "w 700"; echo "g s11b"; msg 3; open
  echo "d 0 0.5 0.3"; echo f; echo "w 400"; echo "m 0 0.3 0.3"; echo f; echo "m 0 0.06 0.3"; echo f; echo "p carrying"; up 800; echo "p dropped"; echo "g s12"; shot row-dropped
  closeov; echo "w 500"; echo "g s13"
  die h; die d; die i; echo "g s14"; echo "p home"; echo "x true"; echo "w 300"; } >"$W/row.script"
session row
ok "open four: a row with the free one to the right" 'row s1 3 a=0 b=1 c=2 d=3'
ok "first closed: the rest shift left, current follows" 'row s2 2 b=0 c=1 d=2'
ok "middle closed"                       'row s3 1 b=0 d=1'
ok "a new app takes the free one"        'row s4 2 b=0 d=1 e=2'
ok "current closed: nearest on its left" 'row s5 1 b=0 d=1'
ok "msg goes by the new numbers"         'row s5b 0 b=0 d=1'
ok "current closed at the left end: the free one" 'row s6 1 d=0'
ok "new apps after that"                 'row s7 2 d=0 f=1 h=2'
ok "closed during the carousel: still one free" 'row s8 2 d=0 h=1'
ok "still fine after the overview"       'row s9 2 d=0 h=1'
ok "a move to 9 lands next to the others, and the left one goes to the free one" 'row s11b 3 h=0 i=1 d=2'
ok "carrying the last window off closes the gap" 'row s12 1 h=0 i=1 d=1'
ok "and both share the screen outside the overview" 'row s13 1 h=0 i=1 d=1 && [ "$(geom s13 i)" != "$(geom s13 d)" ]'
ok "all closed: the free one alone"      'row s14 0'

# all nine taken, then a tenth
{ echo "w 2500"; for a in 1 2 3 4 5 6 7 8 9; do app n$a; done; echo "g f1"; swipe 0.05 6; up; echo "p fullflick"; echo "g f2"; shot full-toast
  app n10; echo "g f3"; echo "p tenth"; die n3; echo "g f4"; swipe 0.05 6; up; echo "p freeagain"; echo "g f5"; echo "x true"; echo "w 300"; } >"$W/full.script"
session full
ok "nine fill the row"                   'row f1 8 n1=0 n9=8'
ok "a flick with none free stays"        'row f2 8 && state fullflick overview=0 && state fullflick visible=0'
ok "and says so"                         'grep -q "button nofree" "$W/all.log"'
ok "a tenth joins the current workspace" 'row f3 8 n9=8 n10=8'
ok "one closed: the free one is back"    'row f4 7 n1=0 n9=7'
ok "and the flick goes there"            'state freeagain ws=8 && state freeagain overview=0'

# flick against hold
{ echo "w 2500"; app a; echo "g h0"
  for s in "0.044 5" "0.11 3" "0.2 2"; do set -- $s; swipe $1 $2; up; echo "p flick$1"; msg 1; done
  # one release at each speed over about 30% of the screen: px/ms is step * 872 / 32
  for s in "0.006 50" "0.012 25" "0.022 14" "0.03 10" "0.06 5" "0.1 3"; do set -- $s; swipe $1 $2; up; echo "p speed$1"; closeov; msg 1; done
  swipe 0.05 8; echo "w 250"; up; echo "p hold-long"; closeov
  swipe 0.02 4; echo "w 250"; up; echo "p hold-short"; closeov
  swipe 0.05 3; echo "w 200"; echo "m 0 0.5 0.75"; echo f; echo "m 0 0.5 0.70"; echo f; up; echo "p hold-then-go"; closeov
  swipe 0.003 12; up; echo "p slow-short"; msg 1
  swipe 0.012 30; up; echo "p slow-long"; closeov
  swipe 0.05 4; echo "m 0 0.5 0.9"; echo f; echo "m 0 0.5 0.98"; echo f; up; echo "p backdown"
  msg 2; swipe 0.05 6; up; echo "p onfree"; echo "g h9"; swipe 0.05 8; echo "w 250"; up; echo "p onfreehold"; echo "x true"; echo "w 300"; } >"$W/flick.script"
session flick
for s in 0.044 0.11 0.2; do
	ok "flick at step $s goes to the free workspace" "state flick$s ws=1 && state flick$s overview=0 && state flick$s visible=0"
done
for s in 0.006 0.012 0.022 0.03; do
	ok "released at step $s (slow to medium) opens the overview" "state speed$s overview=1 && state speed$s ws=0"
done
for s in 0.06 0.1; do
	ok "released at step $s (fast) goes to the free workspace" "state speed$s ws=1 && state speed$s overview=0"
done
ok "swipe and hold opens the overview"   'state hold-long overview=1 && state hold-long ws=0'
ok "a short hold too"                    'state hold-short overview=1 && state hold-short ws=0'
ok "a hold stays a hold when it goes on" 'state hold-then-go overview=1 && state hold-then-go ws=0'
ok "slow and short falls back"           'state slow-short overview=0 && state slow-short ws=0'
ok "slow and long opens by position"     'state slow-long overview=1 && state slow-long ws=0'
ok "pulled back down cancels"            'state backdown overview=0 && state backdown ws=0'
ok "a flick on the free one stays there" 'state onfree ws=1 && state onfree overview=0 && state onfree visible=0'
ok "a hold on the free one opens the overview" 'state onfreehold overview=1'

# the hidden bar
{ echo "w 2500"; app a; snap a b0; echo "g b1"; echo "p hidden"; shot bar-hidden
  tap 0.5 0.995; echo "p tapped"; shot bar-shown; echo "g b2"; echo "w 3300"; echo "p expired"
  tap 0.5 0.995; tap 0.5 0.5; echo "p dismissed"; snap a b1
  tap 0.5 0.97; echo "p above"; snap a b2
  echo "d 0 0.5 0.995"; echo f; echo "m 0 0.5 0.985"; echo f; echo "p swipe1"; echo "m 0 0.5 0.95"; echo f; echo "p swipe2"; echo "m 0 0.5 0.9"; echo f; echo "p swipe3"; echo "w 250"; up; echo "p swiped"; closeov; echo "w 3400"; echo "p swipeend"
  snap a b3; echo "d 0 0.5 0.995"; echo f; echo "w 600"; echo "p holding"; up; echo "p heldup"; snap a b4; echo "w 3300"; echo "p heldgone"
  tap 0.5 0.995; app b; echo "p opened"; echo "g b5"; echo "x true"; echo "w 300"; } >"$W/bar.script"
session bar
ok "the window has the whole height"     '[ "$(geom b1 a | awk -F, "{print \$2+\$4}")" = 873 ]'
ok "the usable area reaches the edge"    'mon b1 | grep -q " w=[0-9]*,[0-9]*,[0-9]*,[0-9]* " && { read -r y h <<<"$(mon b1 | sed "s/.* w=[0-9]*,\([0-9]*\),[0-9]*,\([0-9]*\) .*/\1 \2/")"; [ $((y + h)) = 873 ] || { mon b1 | cut -c1-120; false; }; }'
ok "hidden by default"                   'state hidden bar=0,0.00'
ok "a tap shows it"                      'state tapped bar=1,1.00'
ok "without moving anything"             '[ "$(geom b2 a)" = "$(geom b1 a)" ]'
ok "it hides by itself"                  'state expired bar=0,0.00'
ok "a tap elsewhere hides it"            'state dismissed bar=0,0.00'
ok "and reaches the app"                 '[ "$(($(touches b1 down) - $(touches b0 down)))" = 1 ]'
ok "above the zone is the app's"         '[ "$(($(touches b2 down) - $(touches b1 down)))" = 1 ] && state above bar=0,0.00'
ok "a swipe never shows it"              'state swipe1 bar=0,0.00 && state swipe2 bar=0,0.00 && state swipe3 bar=0,0.00 && state swiped bar=0,0.00 && state swipeend bar=0,0.00'
ok "the swipe stayed ours"               '[ "$(touches b3 down)" = "$(touches b2 down)" ]'
ok "holding shows it and starts screen text" 'state holding bar=1,1.00 && [ -s "$W/held" ]'
ok "and that was not an app touch"       '[ "$(touches b4 down)" = "$(touches b3 down)" ]'
ok "gone after the hold too"             'state heldgone bar=0,0.00'
ok "opening an app hides it"             'state opened bar=0,0.00'

# a mouse: hover shows, stays, and is no touch
{ echo "w 2500"; app a; echo "M 0.5 0.5"; echo "w 100"; snap a m0; echo "M 0.5 0.995"; echo "w 400"; echo "p hover"; echo "w 3300"; echo "p hoverstay"; snap a m1
  echo "M 0.5 0.5"; echo "w 300"; echo "p left"; echo "w 3300"; echo "p leftgone"; snap a m2; echo "x true"; echo "w 300"; } >"$W/hover.script"
session hover PHONEGLUEWC_MOUSE_FINGER=1
ok "hover shows the bar"                 'state hover bar=1,1.00'
ok "it stays while the pointer does"     'state hoverstay bar=1,1.00'
ok "then hides after a few seconds"      'state left bar=1,1.00 && state leftgone bar=0,0.00'
ok "hover is not a touch"                '[ "$(touches m2 down)" = 0 ] && [ "$(touches m2 motion)" = 0 ]'

# tapping an open app goes to its window; "New window" makes another
mkdir -p "$W/data/applications"
printf 'alpha.desktop\norg.t.beta.desktop\ngamma.desktop\n' >"$W/cfg/phonegluewc/pinned-apps"
de() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=sh %s %s\n%s\n' "$1" "$W/tl.sh" "$2" "${4:-}" >"$W/data/applications/$3.desktop"; }
de Alpha alpha alpha
de Beta betawin org.t.beta StartupWMClass=betawin
de Gamma gammawin gamma
slot() { python3 -c "print(round((82.4 + 76 * $1) / 392.73, 3))"; }
Y=0.929
gows() { echo "x phonegluewc-msg workspace $1"; echo "w 500"; }
count() { grep "^GEOM $1 client title=$2 " "$W/all.log" | wc -l; }
{ echo "w 2500"; tap "$(slot 0)" $Y 1500; echo "g r1"
  gows 2; tap "$(slot 1)" $Y 1500; echo "g r2"
  gows 3; tap "$(slot 0)" $Y 900; echo "g r3"; echo "p r3"
  gows 3; tap "$(slot 1)" $Y 900; echo "g r4"
  gows 3; echo "d 0 $(slot 0) $Y"; echo f; echo "w 700"; up 300; shot reuse-popup; tap 0.323 0.721 1500; echo "g r5"; echo "p r5"
  gows 4; tap "$(slot 0)" $Y 900; echo "g r6"
  gows 1; gows 4; tap "$(slot 0)" $Y 900; echo "g r7"
  gows 4; tap "$(slot 2)" $Y 1500; echo "g r8"; gows 5; tap "$(slot 2)" $Y 1500; echo "g r9"
  gows 2; open; tap "$(slot 0)" $Y 900; echo "g r10"; echo "p r10"
  gows 6; echo "M $(slot 1) $Y"; echo "w 60"; echo "x true"; echo "w 300"; } >"$W/reuse.script"
session reuse
ok "first tap opens the app"               'row r1 0 alpha=0'
ok "a window class counts as the app"      'row r2 1 alpha=0 betawin=1'
ok "tapping an open app goes to its window" 'row r3 0 alpha=0 betawin=1 && [ "$(count r3 alpha)" = 1 ]'
ok "by its window class as well"           'row r4 1 alpha=0 betawin=1 && [ "$(count r4 betawin)" = 1 ]'
ok "New window starts a second one, alone" '[ "$(count r5 alpha)" = 2 ] && grep "^GEOM r5 mon" "$W/all.log" | grep -q " ws=2 "'
ok "tap goes to the most recently used"    'grep "^GEOM r6 mon" "$W/all.log" | grep -q " ws=2 "'
ok "and that follows the use"              'grep "^GEOM r7 mon" "$W/all.log" | grep -q " ws=0 "'
ok "a window that matches nothing launches again" '[ "$(count r8 gammawin)" = 1 ] && grep -q . "$W/log-gammawin"'
ok "and again, each on its own" '[ "$(count r9 gammawin)" = 2 ]'
ok "from the overview too, and it closes"  'state r10 overview=0 && state r10 ws=0'

# close all: polite, no confirmation, whoever refuses stays
printf 'echo $$ >"%s/pid-$1"; TOUCHLOG_CLOSES=1 TOUCHLOG_TITLE=$1 exec "%s/touchlog" >"%s/log-$1" 2>&1\n' "$W" "$W" "$W" >"$W/tlc.sh"
capp() { echo "x sh $W/tlc.sh $1"; echo "w 1500"; }
CLOSEX=0.86; CLOSEY=0.885
{ echo "w 2500"; open; shot closeall-none; closeov; capp a; app b; capp c; echo "g c0"; open; echo "p c0"; shot closeall
  tap $CLOSEX $CLOSEY 1500; echo "p c1"; echo "g c1"; shot closeall-refused
  closeov; echo "g c2"; echo "x true"; echo "w 300"; } >"$W/close.script"
session close
ok "close all leaves the one that refuses" 'row c1 1 b=0 && ! grep -q "^GEOM c1 client title=[ac] " "$W/all.log"'
ok "you are on the free one, cards still up" 'state c1 overview=1 && state c1 ws=1'
ok "no signal: it is alive"                '[ "$(count c2 b)" = 1 ]'
{ echo "w 2500"; capp a; capp c; open; tap $CLOSEX $CLOSEY 1500; echo "p d1"; echo "g d1"; echo "x true"; echo "w 300"; } >"$W/close2.script"
session close2
ok "all gone: the overview closes on the free one" 'row d1 0 && state d1 overview=0 && state d1 visible=0'

# the tray apps pill: the panel's own list, directly; nothing running hides it, and it counts only what runs without a window
cp "$(command -v sleep)" "$W/phonetest-bgd"
{ echo "w 2500"; open; tap 0.14 $CLOSEY 800; echo "g t0"; closeov; app a; capp c; echo "x $W/phonetest-bgd 60"; echo "w 300"; open; shot trayapps-row; echo "g t1"
  tap 0.14 $CLOSEY 900; shot trayapps-open; echo "g t2"; echo "p t2"
  tap 0.06 0.075 900; echo "g t3"; echo "p t3"; echo "x true"; echo "w 300"; } >"$W/running.script"
session running
ok "nothing running: no tray apps pill"    '! grep -q "^GEOM t0 layer ns=phone-panel" "$W/all.log"'
ok "the pill opens the list over the overview" 'grep -q "^GEOM t2 layer ns=phone-panel" "$W/all.log" && state t2 overview=1'
ok "back leaves the list and the panel, the overview stays" '! grep -q "^GEOM t3 layer ns=phone-panel" "$W/all.log" && state t3 overview=1'

for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
[ -z "${NAV_LOG:-}" ] || cp "$W/all.log" "$NAV_LOG"
[ "$fails" = 0 ] && echo "all passed" || { echo "failed: $fails"; exit 1; }
