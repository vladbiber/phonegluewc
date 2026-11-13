#!/bin/bash
# The edge swipes: the right key on release, nothing below the threshold, other touches stay the app's.
# Headless, neutral clients only. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-edge.XXXXXX")
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g"} >"$W/build.log" 2>&1 || { tail -5 "$W/build.log"; echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
mkdir -p "$W/cfg/phonegluewc" "$W/snap"
conf() { printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75 transform=%s\n' "$1" >"$W/cfg/phonegluewc/config.conf"; }
cat >"$W/tl.sh" <<TL
TOUCHLOG_TITLE=\$1 exec "$W/touchlog" >"$W/log-\$2" 2>&1
TL
printf 'cp "%s/log-$1" "%s/snap/$2" 2>/dev/null\n' "$W" "$W" >"$W/snap.sh"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
: >"$W/all.log"
session() { # NAME [ENV...]: runs $W/$NAME.script to its end
	local n=$1; shift
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/$n.script" PHONEGLUEWC_SCREENTEXT= "$@"
	comp_wait 300
	cat "$W/gw.log" >>"$W/all.log"
	grep -q 'AddressSanitizer\|runtime error' "$W/gw.log" && { grep -m3 'AddressSanitizer\|runtime error' "$W/gw.log"; fails=$((fails + 1)); }
	comp_stop
}
fails=0
ok() { if eval "$2"; then echo "ok $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
snap() { echo "x sh $W/snap.sh $1 $2"; echo "w 150"; }
app() { echo "x sh $W/tl.sh $1 $2"; echo "w 1500"; }
# drag X0 Y X1 [X2...]: one finger, lifted by the caller
drag() { local y=$2; echo "d 0 $1 $y"; echo f; shift 2; for x in "$@"; do echo "m 0 $x $y"; echo f; done; }
up() { echo "u 0"; echo f; echo "w 300"; }
pillopen() { echo "d 0 0.5 0.995"; echo f; for s in 1 2 3 4 5 6 7 8; do echo "m 0 0.5 $(python3 -c "print(0.995-0.5*$s/8)")"; echo f; done; echo "w 250"; echo "u 0"; echo f; echo "w 700"; }
pillclose() { echo "d 0 0.5 0.995"; echo f; echo "u 0"; echo f; echo "w 700"; }

state() { grep "^FT $1 " "$W/all.log" | grep -q " $2\( \|$\)"; }
keys() { grep -c '^key ' "$W/snap/$1" 2>/dev/null; }
hit() { grep -c "^$2" "$W/snap/$1" 2>/dev/null; }

conf 0
# past the threshold; x is a share of the 392 wide screen, 72 px is 0.184
{ echo "w 2500"; app plain plain; snap plain s0
  drag 0.985 0.5 0.96 0.90 0.86; echo "p small"; shot small; snap plain s1
  echo "m 0 0.72 0.5"; echo f; echo "p armed"; shot armed; echo "m 0 0.60 0.5"; echo f; echo "p far"; snap plain s2
  up; echo "p released"; snap plain s3
  drag 0.985 0.5 0.95 0.90; up; echo "p below"; snap plain s4
  drag 0.985 0.5 0.90 0.70 0.90; echo "p backagain"; up; echo "p cancelled"; snap plain s5
  drag 0.895 0.5 0.80 0.60; echo "p inside"; up; snap plain s6
  echo "d 0 0.985 0.5"; echo f; echo "p tapwait"; echo "u 0"; echo f; echo "w 300"; snap plain s7
  drag 0.985 0.5; echo "m 0 0.985 0.56"; echo f; echo "m 0 0.985 0.62"; echo f; echo "p vertical"; up; snap plain s8
  echo "d 0 0.985 0.5"; echo f; echo "w 400"; echo "p rested"; echo "m 0 0.70 0.5"; echo f; echo "p restdrag"; up; snap plain s9
  echo "d 0 0.985 0.02"; echo f; echo "m 0 0.7 0.02"; echo f; echo "p statusbar"; up
  echo "d 0 0.985 0.99"; echo f; echo "p bottombar"; echo "m 0 0.7 0.99"; echo f; up; echo "w 500"; pillclose; snap plain s10
  drag 0.985 0.5 0.85; echo "d 1 0.5 0.3"; echo f; echo "m 0 0.70 0.5"; echo f; echo "p twofingers"; echo "u 1"; echo f; up; echo "p aftertwo"; snap plain s11
  drag 0.985 0.5 0.70; echo "d 1 0.5 0.3"; echo f; echo "p twoarmed"; echo "u 1"; echo f; up; snap plain s12
  # the swipe in the overview moved the row to the free card: the app is on the left
  pillopen; echo "p overview"; drag 0.985 0.5 0.70; echo "p ovdrag"; up; snap plain s13; echo "w 800"; echo "d 0 0.03 0.5"; echo f; echo "u 0"; echo f; echo "w 900"; echo "p ovclosed"
  drag 0.985 0.5 0.70; up; snap plain s14; echo "x true"; echo "w 300"; } >"$W/one.script"
session one
{ echo "w 2500"; app Waydroid wd; snap wd d0; drag 0.985 0.5 0.70; up; snap wd d1; echo "x true"; echo "w 300"; } >"$W/two.script"
session two
{ echo "w 2500"; app foot ft; snap ft f0; drag 0.985 0.5 0.70; echo "p term"; up; echo "p termup"; snap ft f1; echo "x true"; echo "w 300"; } >"$W/three.script"
session three
{ echo "w 2500"; drag 0.985 0.5 0.70; echo "p nowin"; up; echo "p nowinup"; echo "x true"; echo "w 300"; } >"$W/four.script"
session four
# the screen turned: touch comes in panel terms, here the right edge the user sees is v=0
conf 90
{ echo "w 2500"; app plain rot; snap rot r0; echo "d 0 0.5 0.01"; echo f; echo "m 0 0.5 0.1"; echo f; echo "m 0 0.5 0.2"; echo f; echo "p rotzone"; shot rotated; up; snap rot r1; echo "x true"; echo "w 300"; } >"$W/five.script"
session five
conf 0
# mouse as finger
{ echo "w 2500"; app plain mo; snap mo m0; echo "M 0.985 0.5"; echo "w 50"; echo "B 1"; echo "w 50"; echo "M 0.90 0.5"; echo "w 50"; echo "M 0.70 0.5"; echo "w 50"; echo "p mouse"; echo "B 0"; echo "w 300"; snap mo m1; echo "x true"; echo "w 300"; } >"$W/six.script"
session six PHONEGLUEWC_MOUSE_FINGER=1
# locked: no gesture at all
{ echo "w 2500"; drag 0.01 0.5 0.3; echo "p lockleft"; up; echo "x true"; echo "w 300"; } >"$W/seven.script"
session seven PHONEGLUEWC_RELOCK=1 PHONE_AUTH_MOCK=test
# the left edge: the keyboard, with or without a field. With it up, the side above it is the zone
{ echo "w 2500"; app plain kb; drag 0.015 0.5 0.1; echo "p lbelow"; up; echo "w 600"; echo "g kb0"
  drag 0.015 0.5 0.1 0.3; echo "p larmed"; shot left; snap kb k0; up; echo "w 900"; echo "g kb1"; snap kb k1
  echo "d 0 0.5 0.8"; echo f; echo "u 0"; echo f; echo "w 500"; snap kb k2
  drag 0.015 0.2 0.1 0.3; up; echo "w 900"; echo "g kb2"
  drag 0.015 0.5 0.3; up; echo "w 900"; echo "g kb3"; pillopen; echo "g kb4"; pillclose; echo "w 900"; echo "g kb5"
  drag 0.015 0.5 0.3; up; echo "w 900"; echo "g kb6"; echo "x true"; echo "w 300"; } >"$W/eight.script"
session eight
cat >"$W/field.sh" <<FIELD
KBD_OUT=$W/field.txt QT_QUICK_BACKEND=software exec qs -p $SRC/tests/kbd-field
FIELD
{ echo "w 1500"; echo "x sh $W/field.sh"; echo "w 2500"; echo "d 0 0.5 0.2"; echo f; echo "u 0"; echo f; echo "w 900"; echo "g f1"
  drag 0.015 0.2 0.1 0.3; up; echo "w 900"; echo "g f2"; echo "w 1000"; echo "g f3"
  drag 0.015 0.5 0.1 0.3; up; echo "w 900"; echo "g f4"
  echo "d 0 0.5 0.8"; echo f; echo "u 0"; echo f; echo "w 500"; echo "x cp $W/field.txt $W/field-typed.txt"; echo "w 100"
  echo D; echo "w 1500"; echo "g f5"
  drag 0.015 0.2 0.1 0.3; up; echo "w 900"; echo "g f6"; echo "x true"; echo "w 300"; } >"$W/nine.script"
session nine
{ echo "w 3000"; drag 0.015 0.5 0.3; echo "p loginleft"; up; echo "w 600"; echo "g login"; echo "x true"; echo "w 300"; } >"$W/ten.script"
session ten PHONEGLUEWC_GREETER=1 PHONE_AUTH_MOCK=test

for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done

ok "no key before the release"            '[ "$(keys s0)" = 0 ] && [ "$(keys s1)" = 0 ] && [ "$(keys s2)" = 0 ]'
ok "the indicator grows, then changes"    'grep -q "^FT small .* edge=1,0," "$W/all.log" && grep -q "^FT armed .* edge=1,1," "$W/all.log"'
ok "release past the threshold is Alt+Left" '[ "$(keys s3)" = 2 ] && grep -q "^key 105 1" "$W/snap/s3" && grep -B1 "^key 105 1" "$W/snap/s3" | grep -q "^mods 8$"'
ok "the app sees alt go again"            '[ "$(tail -1 "$W/snap/s3")" = "mods 0" ]'
ok "the indicator goes away"              'grep -q "^FT released .* edge=0," "$W/all.log"'
ok "below the threshold sends nothing"    '[ "$(keys s4)" = 2 ] && grep -q "^FT backagain .* edge=1,0," "$W/all.log" '
ok "back below it before release cancels" '[ "$(keys s5)" = 2 ]'
ok "a drag 40 px in goes to the app"      '[ "$(keys s6)" = 2 ] && [ "$(hit s6 "touch down")" -gt "$(hit s5 "touch down")" ] && [ "$(hit s6 "touch motion")" -gt "$(hit s5 "touch motion")" ]'
ok "a tap in the zone reaches the app"    '[ "$(keys s7)" = 2 ] && [ "$(hit s7 "touch down")" -gt "$(hit s6 "touch down")" ] && [ "$(hit s7 "touch up")" -gt "$(hit s6 "touch up")" ]'
ok "a vertical drag in the zone is the apps" '[ "$(keys s8)" = 2 ] && [ "$(hit s8 "touch motion")" -gt "$(hit s7 "touch motion")" ]'
ok "a finger that rested is the apps"     '[ "$(keys s9)" = 2 ] && [ "$(hit s9 "touch motion")" -gt "$(hit s8 "touch motion")" ]'
ok "the corners stay with the bars"       '[ "$(keys s10)" = 2 ] && state bottombar gesture=3 && ! state statusbar gesture=5'
ok "a second finger stops it"             '[ "$(keys s11)" = 2 ] && [ "$(keys s12)" = 2 ] && grep -q "^FT twoarmed .* edge=0," "$W/all.log"'
ok "off in the overview"                  '[ "$(keys s13)" = 2 ] && ! state ovdrag gesture=5 && state overview overview=1'
ok "still works after all that"           'state ovclosed overview=0 && [ "$(keys s14)" = 4 ]'
ok "Waydroid gets KEY_BACK, no alt"       '[ "$(keys d1)" = 2 ] && grep -q "^key 158 1" "$W/snap/d1" && ! grep -q "^mods 8" "$W/snap/d1"'
ok "a terminal gets no key, the touch is its" '[ "$(keys f1)" = 0 ] && [ "$(hit f1 "touch down")" -gt 0 ] && state term gesture=0 && grep -q "^FT term .* edge=0," "$W/all.log"'
ok "no window: nothing"                   'state nowin gesture=0 && state nowinup gesture=0'
ok "rotated: the edge the user sees"      '[ "$(keys r1)" = 2 ] && state rotzone gesture=5'
ok "mouse as finger"                      '[ "$(keys m1)" = 2 ] && state mouse gesture=5'
ok "off on the lock screen"               'state lockleft gesture=0 && state lockleft locked=1'
kbd() { grep -q "^GEOM $1 layer ns=phone-keyboard" "$W/all.log"; }
ok "left edge: below the threshold, no keyboard" '! kbd kb0 && grep -q "^FT lbelow .* edge=1,0," "$W/all.log"'
ok "left edge: same indicator, armed past it"    'grep -q "^FT larmed .* edge=1,1," "$W/all.log" && [ "$(keys k0)" = 0 ]'
ok "left edge: opens on release with no field"   'kbd kb1'
ok "a key with no field reaches the app"         '[ "$(keys k2)" -gt 0 ]'
ok "left edge: closes the same way"              '! kbd kb2'
ok "the overview hides a forced keyboard"        'kbd kb3 && ! kbd kb4 && ! kbd kb5'
ok "and it opens again afterwards"               'kbd kb6'
ok "a field opens it as before"                  'kbd f1'
ok "closed over an active field, it stays closed" '! kbd f2 && ! kbd f3'
ok "forced open over the field, keys go to it"   'kbd f4 && [ -s "$W/field-typed.txt" ]'
ok "the field going away does not fight it"      'kbd f5'
ok "and the gesture still closes it"             '! kbd f6'
ok "off on the login screen"                     'state loginleft gesture=0 && ! kbd login'
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
