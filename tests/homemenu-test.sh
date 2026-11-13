#!/bin/bash
# Swipe up on bare home: the app menu number goes up once per swipe; sideways, short, over an app, in the overview: not.
# Hold on empty home space opens the editor; on a widget, the bottom strip, an app, the overview or in a swipe: not.
# Headless, neutral clients only.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-hm.XXXXXX")
. "$SRC/tests/sandbox.sh"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
# the log's tray= field reports the editor in this copy
sed -i 's/ft_layer("phone-tray")/ft_layer("phone-screens")/' "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
mkdir -p "$W/cfg/phonegluewc"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'echo $$ >"%s/pid-$1"; TOUCHLOG_TITLE=$1 exec "%s/touchlog" >"%s/log-$1" 2>&1\n' "$W" "$W" "$W" >"$W/tl.sh"
printf 'kill $(cat "%s/pid-$1")\n' "$W" >"$W/k.sh"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
: >"$W/all.log"
fails=0
session() { # NAME [ENV...]
	local n=$1; shift
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/$n.script" "$@"
	comp_wait 1500
	cat "$W/gw.log" >>"$W/all.log"
	grep -q 'AddressSanitizer\|runtime error' "$W/gw.log" && { grep -m3 'AddressSanitizer\|runtime error' "$W/gw.log"; fails=$((fails + 1)); }
	comp_stop
}
ok() { if eval "$2"; then echo "ok $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
seq_() { grep "^FT $1 " "$W/all.log" | tail -1 | sed 's/.* menuseq=\([0-9]*\).*/\1/'; }
# drag from X0,Y0 to X1,Y1 in 6 steps, 32 ms apart
drag() { local i; echo "d 0 $1 $2"; echo f; for i in 1 2 3 4 5 6; do echo "m 0 $(python3 -c "print(round($1+($3-$1)*$i/6,4), round($2+($4-$2)*$i/6,4))")"; echo f; done; echo "u 0"; echo f; echo "w 500"; }

# the menu covers home once it opens: a tap on the bottom strip closes it
closemenu() { echo "d 0 0.5 0.995"; echo f; echo "u 0"; echo f; echo "w 900"; }
{ echo "w 3000"; echo "p start"
  drag 0.5 0.7 0.5 0.4; echo "p up"; closemenu; echo "p closed"
  drag 0.5 0.7 0.5 0.1; echo "p upfar"; closemenu
  drag 0.2 0.7 0.9 0.55; echo "p sideways"
  drag 0.5 0.7 0.5 0.66; echo "p short"
  echo "x sh $W/tl.sh app"; echo "w 1500"; drag 0.5 0.7 0.5 0.4; echo "p overapp"
  echo "x sh $W/k.sh app"; echo "w 800"
  echo "d 0 0.5 0.995"; echo f; for y in 0.93 0.86 0.79 0.72 0.65 0.6; do echo "m 0 0.5 $y"; echo f; done; echo "w 300"; echo "u 0"; echo f; echo "w 1000"; echo "p ovopen"
  drag 0.5 0.75 0.5 0.45; echo "p inov"
  echo "x true"; echo "w 300"; } >"$W/touch.script"
session touch
ok "nothing at the start"                         '[ "$(seq_ start)" = 0 ]'
ok "a swipe up on bare home: once"                '[ "$(seq_ up)" = 1 ]'
ok "the shell opens the app menu, the strip closes it" 'grep -q "^FT up .* menu=1 " "$W/all.log" && grep -q "^FT closed .* menu=0 " "$W/all.log"'
ok "a longer swipe still counts once"             '[ "$(seq_ upfar)" = 2 ]'
ok "mostly sideways: no"                          '[ "$(seq_ sideways)" = 2 ]'
ok "shorter than 60 px: no"                       '[ "$(seq_ short)" = 2 ]'
ok "over an app: no"                              '[ "$(seq_ overapp)" = 2 ]'
ok "in the overview: no"                          'grep -q "^FT ovopen .*overview=1" "$W/all.log" && [ "$(seq_ inov)" = 2 ]'

{ echo "w 3000"; echo "M 0.5 0.7"; echo "B 1"; for y in 0.65 0.6 0.55 0.5 0.45 0.4; do echo "M 0.5 $y"; echo "w 32"; done; echo "B 0"; echo "w 500"; echo "p mouse"
  echo "x true"; echo "w 300"; } >"$W/mouse.script"
session mouse PHONEGLUEWC_MOUSE_FINGER=1
ok "the mouse as a finger: once"                  '[ "$(seq_ mouse)" = 1 ]'

# hold: one session each, the editor stays open once it opens
ed() { grep "^FT $1 " "$W/all.log" | tail -1 | grep -q " tray=$2 "; }
hold() { echo "d 0 $1 $2"; echo f; echo "w 1100"; echo "u 0"; echo f; echo "w 900"; }
for c in "top 0.5 0.075" "middle 0.5 0.5" "lower 0.3 0.85"; do
	set -- $c
	{ echo "w 3000"; hold $2 $3; echo "p held-$1"; echo "x true"; echo "w 300"; } >"$W/h-$1.script"
	session h-$1
done
ok "hold on empty space at the top opens the editor"   'ed held-top 1'
ok "hold in the middle opens the editor"               'ed held-middle 1 && [ "$(grep "^FT held-middle " "$W/all.log" | sed "s/.* editseq=\([0-9]*\).*/\1/")" = 1 ]'
ok "hold low on home opens the editor"                 'ed held-lower 1'

{ echo "w 3000"
  hold 0.3 0.15; echo "p onclock"
  hold 0.3 0.23; echo "p ondate"
  hold 0.5 0.995; echo "p onstrip"; echo "w 3500"
  echo "d 0 0.5 0.6"; echo f; for i in 1 2 3; do echo "m 0 0.5 $(python3 -c "print(0.6-0.003*$i)")"; echo f; echo "w 120"; done; echo "m 0 0.8 0.6"; echo f; echo "w 900"; echo "u 0"; echo f; echo "w 500"; echo "p swiped"
  echo "x sh $W/tl.sh app"; echo "w 1500"; hold 0.5 0.5; echo "p overapp"
  echo "x sh $W/k.sh app"; echo "w 800"
  echo "d 0 0.5 0.995"; echo f; for y in 0.93 0.86 0.79 0.72 0.65 0.6; do echo "m 0 0.5 $y"; echo f; done; echo "w 300"; echo "u 0"; echo f; echo "w 1000"; echo "p hov"
  hold 0.5 0.85; echo "p hinov"
  echo "x true"; echo "w 300"; } >"$W/nohold.script"
session nohold
ok "hold on a widget: no editor"                       'ed onclock 0 && ed ondate 0'
ok "hold on the bottom strip: no editor"               'ed onstrip 0'
ok "a finger that moves first: no editor"              'ed swiped 0'
ok "hold over an app: no editor"                       'ed overapp 0'
ok "hold in the overview: no editor"                   'grep -q "^FT hov .*overview=1" "$W/all.log" && ed hinov 0 && [ "$(grep "^FT hinov " "$W/all.log" | sed "s/.* editseq=\([0-9]*\).*/\1/")" = 0 ]'

{ echo "w 3000"; echo "M 0.5 0.5"; echo "B 1"; echo "w 1100"; echo "B 0"; echo "w 900"; echo "p mhold"; echo "x true"; echo "w 300"; } >"$W/mhold.script"
session mhold PHONEGLUEWC_MOUSE_FINGER=1
ok "the mouse held on home opens the editor"           'ed mhold 1'

# the editor's open and close animation: slowed, and off; a finger during the close reaches home
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "wshot build failed"; exit 1; }
magick -size 1080x2400 xc:'#203080' "$W/home/blue.png"
CONF=$W/cfg/phonegluewc
px() { magick "$W/$1.ppm" -format "%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)]" -crop "1x1+$2+$3" +repage info: 2>/dev/null; }
anim() { # NAME CONFIG-LINE PHONE-LINE CLOSE-WAIT
	printf 'remember_layout = false\n%s\noutput = * mode=1080x2400 scale=2.75\n' "$2" >"$CONF/config.conf"
	printf 'wallpaper = %s\n%s\n' "$W/home/blue.png" "$3" >"$CONF/phone.conf"
	{ echo "w 3000"; hold 0.5 0.5; echo "w $4"; echo "p $1-open"; echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 800"
	  echo "d 0 0.5 0.03"; echo f; echo "u 0"; echo f; echo "w 300"; echo "p $1-closing"
	  drag 0.5 0.7 0.5 0.4; echo "p $1-swipe"; echo "w $4"; echo "p $1-closed"; echo "x true"; echo "w 300"; } >"$W/$1.script"
	session "$1"
}
anim slow "animation_duration = 3000" "" 4500
anim off "animation_duration = 3000" "animations = off" 300
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$CONF/config.conf"; rm -f "$CONF/phone.conf"
ok "slowed: the editor ends open"                      'ed slow-open 1'
ok "slowed: it stays up while it shrinks back"         'ed slow-closing 1'
ok "slowed: a swipe during the close reaches home"     '[ "$(seq_ slow-swipe)" = 1 ]'
ok "slowed: then it is gone"                           'ed slow-closed 0'
ok "off: open and closed at once"                      'ed off-open 1 && ed off-closing 0'
for n in slow off; do
	ok "$n: black around the card, home inside it"   '[ "$(px $n 40 2300)" = 0,0,0 ] && case "$(px $n 540 1000)" in 3[1-3],4[7-9],12[6-9]) true ;; *) false ;; esac'
done
ok "on and off end in the same picture"                '[ "$(magick compare -metric AE -fuzz 3% "$W/slow.ppm" "$W/off.ppm" null: 2>&1 | cut -d" " -f1)" -lt 30000 ]'

comp_cores
[ "$fails" = 0 ] && echo "homemenu: all passed" || echo "homemenu: failed: $fails"
rm -rf "$W"
[ "$fails" = 0 ]
