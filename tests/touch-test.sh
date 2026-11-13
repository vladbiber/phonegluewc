#!/bin/sh
# Plays a fake touchscreen through a patched copy of phonegluewc, headless, and checks
# what the clients and the compositor did. Never touches the live session.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/phonegluewc-touch.XXXXXX")
cp -a "$SRC"/* "$W"/ 2>/dev/null
rm -rf "$W"/core.* "$W"/phonegluewc.o "$W"/tests/crashes
. "$SRC/tests/sandbox.sh"
python3 "$SRC/tests/touch-hook.py" "$W/phonegluewc.c"
make -C "$W" phonegluewc ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$W/touchlog-xdg-protocol.h"
wayland-scanner private-code /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml "$W/touchlog-xdg-protocol.c"
cc -w -I"$W" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$W/touchlog-xdg-protocol.c" -lwayland-client || exit 1

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
# state LABEL KEY=VALUE: the compositor's state at a script checkpoint
state() { grep "^FT $1 " "$W/gw.log" | grep -q " $2\( \|$\)"; }

# four fingers start at 0.3..0.6 of the width; swipe DX DY in screen fractions
fingers() { for i in 0 1 2 3; do echo "d $i 0.$((3+i)) 0.5"; echo f; done; }
swipe() { python3 - "$1" "$2" <<'PY'
import sys
dx,dy=map(float,sys.argv[1:])
for s in range(1,17):
    for i in range(4): print(f"m {i} {0.3+i/10+dx*s/16:.4f} {0.5+dy*s/16:.4f}")
    print("f")
PY
}
lift() { for i in 0 1 2 3; do echo "u $i"; echo f; done; echo "w 500"; }

run() { # NAME CLIENTARGS CONFIG SCRIPT
	mkdir -p "$W/cfg/phonegluewc"
	printf 'remember_layout = false\n%s\n' "$3" > "$W/cfg/phonegluewc/config.conf"
	: > "$W/client.log"
	printf '#!/bin/sh\nexec %s/touchlog %s >%s/client.log 2>&1\n' "$W" "$2" "$W" >"$W/client.sh"; chmod +x "$W/client.sh"
	COMP=$W/phonegluewc COMP_ARGS="-s $W/client.sh"
	comp_start PHONEGLUEWC_FAKETOUCH="$4" PHONEGLUEWC_SHELL= PHONEGLUEWC_KEYBOARD= ${PHONEGLUEWC_MOUSE_FINGER:+PHONEGLUEWC_MOUSE_FINGER=1}
	comp_wait 200
	comp_stop
	[ -n "${TOUCH_VERBOSE:-}" ] && { grep '^FT' "$W/gw.log"; tail -30 "$W/client.log"; }
}

# 1. a touch-aware window: tap, drag, then the fourth finger takes the touches back
S=$W/s1
{ echo "w 1500"; echo "p start"; echo "d 0 0.5 0.5"; echo f; echo "m 0 0.51 0.5"; echo f; echo "u 0"; echo f; echo "p tap"
  fingers; echo "p four"; swipe -0.45 0; echo "p drag"; lift; echo "p ws2"
  fingers; swipe 0.45 0; lift; echo "p ws1"
  fingers; swipe 0 -0.35; lift; echo "p overview"
  echo "d 0 0.5 0.5"; echo f; echo "u 0"; echo f; echo "w 500"; echo "p overviewtap"
  fingers; echo "c 0"; echo f; echo "p cancelled"; lift; echo "p after"; } > "$S"
run touch "" "" "$S"
C=$W/client.log
ok "seat advertises touch"           'state start caps=7 || state start caps=5'
ok "client gets the tap"             'grep -q "touch down 0" "$C" && grep -q "touch up 0" "$C" && grep -q "touch motion 0" "$C"'
ok "no fake pointer click on client" '! grep -q "pointer button" "$C"'
ok "fourth finger cancels client"    'grep -q "touch cancel" "$C"'
ok "fourth finger starts the gesture" 'state four gesture=1 && state four fingers=4'
ok "client gets no fourth finger"    '! grep -q "touch down 3" "$C"'
ok "left swipe goes to workspace 2"  'state ws2 ws=1 && state ws2 gesture=0'
ok "right swipe comes back"          'state ws1 ws=0'
ok "up swipe opens the overview"     'state overview overview=1'
ok "tap reaches the overview"        'state overviewtap overview=0 || state overviewtap fingers=0'
ok "fingers are all released"        'state after fingers=0 && state after gesture=0 && state after emu=-1'

# 2. a window without touch support gets a mouse from the first finger only
S=$W/s2
{ echo "w 1500"; echo "d 0 0.5 0.5"; echo f; echo "p down"; echo "m 0 0.52 0.5"; echo f; echo "u 0"; echo f; echo "p up"; } > "$S"
run notouch notouch "" "$S"
ok "emulated press and release"      'grep -q "pointer button 272 1" "$C" && grep -q "pointer button 272 0" "$C"'
ok "emulated motion"                 'grep -q "pointer motion" "$C"'
ok "emulation ends"                  'state up emu=-1'

# 3. a rotated screen: the touch follows the rotation
S=$W/s3
{ echo "w 1500"; echo "p start"; echo "d 0 0.25 0.1"; echo f; echo "p down"; echo "u 0"; echo f; echo "p up"; } > "$S"
run rotated "" "output = * transform=90 scale=1" "$S"
ok "first touch follows the rotation" 'state down pts0=648,320' || grep '^FT down' "$W/gw.log" | cut -c1-120

# 4. the pill: phone size from here on
PHONE="output = * mode=1080x2400 scale=2.75"
# pillpull ID Y0 Y1 STEPS: drag a finger up the middle of the screen
pull() { python3 - "$1" "$2" "$3" <<'PY'
import sys
a,b,n=float(sys.argv[1]),float(sys.argv[2]),int(sys.argv[3])
for s in range(1,n+1):
    print(f"m 0 0.5 {a+(b-a)*s/n:.4f}"); print("f")
PY
}
down() { echo "d 0 $1 $2"; echo f; }
up0() { echo "u 0"; echo f; }
S=$W/s4
{ echo "w 1500"; echo "p start"
  # a drag that follows the finger, is held, and goes far enough: opens
  down 0.5 0.99; echo "p pressed"; pull 0.99 0.85 8; echo "p partway"; pull 0.85 0.55 8; echo "p far"; echo "w 300"; up0; echo "w 600"; echo "p open"
  # pill tap closes it
  down 0.5 0.99; up0; echo "w 600"; echo "p tapclosed"
  # a short slow drag settles closed
  down 0.5 0.99; pull 0.99 0.93 3; echo "w 300"; up0; echo "w 600"; echo "p shortslow"
  # far, then back down fast: settles closed
  down 0.5 0.99; pull 0.99 0.5 8; echo "w 200"; pull 0.5 0.8 3; up0; echo "w 600"; echo "p flickdown"
  # the touch system cancels: settles closed
  down 0.5 0.99; pull 0.99 0.6 8; echo "c 0"; echo f; echo "w 600"; echo "p cancelled"
  # a window above the zone still gets its touches, the corners of the bar do not
  down 0.05 0.995; up0; echo "p corner"
  down 0.5 0.5; up0; echo "p client"
  # a short fast flick leaves for the free workspace
  down 0.5 0.99; pull 0.99 0.87 2; up0; echo "w 600"; echo "p flick"; } > "$S"
run pill "" "$PHONE" "$S"
ok "zone is grabbed, the app sees nothing" 'state pressed gesture=3 && state pressed emu=-1 && test "$(grep -c "touch down 0" "$C")" = 1'
ok "overview follows the finger"     'grep "^FT partway" "$W/gw.log" | grep -q "visible=1 .*dim=0\.[1-9]" && grep "^FT partway" "$W/gw.log" | grep -qv "dim=1.00"'
ok "dragged far, opens fully"        'state far dim=1.00 && state open overview=1 && state open dim=1.00'
# no bar and no tray here: the tray strip stays under the cards
ok "cards fit a phone"               'state open card=383,5'
ok "tap on the pill closes"          'state tapclosed visible=0'
ok "short slow drag settles closed"  'state shortslow visible=0 && state shortslow overview=0'
ok "short flick goes to the free one" 'state flick overview=0 && state flick visible=0 && state flick ws=1'
ok "flick back down settles closed"  'state flickdown visible=0'
ok "cancel settles closed"           'state cancelled visible=0 && state cancelled fingers=0 && state cancelled gesture=0'
ok "the app gets touches again"      'state client gesture=0 && test "$(grep -c "touch down 0" "$C")" = 1'

# 5. apps open alone, the overview turns and carries them, a drop tiles
S=$W/s5
{ echo "w 1500"; echo "p first"; echo "x exec $W/touchlog >/dev/null 2>&1"; echo "w 1500"; echo "p second"
  echo "x exec $W/touchlog >/dev/null 2>&1"; echo "w 1500"; echo "p third"
  # open: swipe the cards to the middle workspace, then a short swipe that goes back
  down 0.5 0.99; pull 0.99 0.55 8; echo "w 250"; up0; echo "w 600"; echo "p open"
  down 0.5 0.3; for x in 0.45 0.35 0.25 0.15; do echo "m 0 $x 0.3"; echo f; done; up0; echo "w 600"; echo "p swiped"
  down 0.5 0.3; echo "m 0 0.47 0.3"; echo f; echo "w 200"; echo "m 0 0.46 0.3"; echo f; echo "w 200"; up0; echo "w 600"; echo "p swipeback"
  fingers; swipe 0 0.2; lift; echo "p fourclose"; } > "$S"
run place "" "$PHONE" "$S"
ok "first app on the empty workspace" 'state first counts=100000000 && state first ws=0'
ok "second app gets its own workspace" 'state second counts=110000000 && state second ws=1'
ok "third app gets its own workspace"  'state third counts=111000000 && state third ws=2'
ok "swipe left turns the cards"      'state swiped ws=3 && state swiped overview=1'
ok "short swipe stays"               'state swipeback ws=3 && state swipeback gesture=0'
[ -n "${TOUCH_VERBOSE:-}" ] && grep '^FT' "$W/gw.log"

S=$W/s6
{ echo "w 1500"; echo "x exec $W/touchlog >/dev/null 2>&1"; echo "w 1500"; echo "p two"
  down 0.5 0.99; pull 0.99 0.55 8; echo "w 250"; up0; echo "w 600"; echo "p open"
  down 0.5 0.3; echo "w 400"; echo "m 0 0.3 0.3"; echo f; echo "m 0 0.005 0.3"; echo f; echo "p carrying"; up0; echo "w 600"; echo "p dropped"
  fingers; swipe 0 0.2; lift; echo "p fourclose"; } > "$S"
run tile "" "$PHONE" "$S"
ok "dragging a window"               'state carrying gesture=4 && state two counts=110000000'
ok "dropping tiles the two"          'state dropped counts=200000000 && state dropped overview=1'
ok "four fingers still close the overview" 'state fourclose overview=0 || state fourclose visible=0'

# laptop test mode: a fake mouse stands in for the finger
S=$W/s7
mdrag() { echo "M $1 $2"; echo "w 30"; echo "B 1"; echo "w 30"; for y in 0.9 0.8 0.7 0.6 0.5; do echo "M $1 $y"; done; echo "w 250"; echo "B 0"; echo "w 700"; }
{ echo "w 1500"; echo "M 0.5 0.5"; echo "B 1"; echo "w 30"; echo "M 0.52 0.5"; echo "B 0"; echo "w 300"; echo "p mousetap"
  mdrag 0.5 0.995; echo "p mousepill"
  echo "M 0.5 0.5"; echo "F 1"; echo "B 1"; echo "w 30"; echo "p mousefour"; for y in 0.55 0.6 0.65 0.7; do echo "M 0.5 $y"; done; echo "B 0"; echo "F 0"; echo "w 700"; echo "p mousefourdone"; } > "$S"
export PHONEGLUEWC_MOUSE_FINGER=1
run mouse "" "$PHONE" "$S"
unset PHONEGLUEWC_MOUSE_FINGER
C=$W/client.log
ok "a mouse click is a finger on the client" 'grep -q "touch down 0" "$C" && grep -q "touch up 0" "$C" && ! grep -q "pointer button" "$C"'
ok "a mouse drag from the bar opens the overview" 'state mousepill overview=1'
ok "F4 and the mouse make four fingers" 'state mousefour fingers=4 && state mousefour gesture=1'
ok "and they close the overview"     'state mousefourdone overview=0 || state mousefourdone visible=0'

[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
