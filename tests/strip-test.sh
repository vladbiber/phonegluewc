#!/bin/bash
# The gesture strip under the keys: the bar's gestures start there, the keys and the hide area stay the keyboard's.
# Headless, a real Qt field. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-strip.XXXXXX")
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
mkdir -p "$W/cfg/phonegluewc"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'echo $$ >"%s/field.pid"\nKBD_OUT=%s/field.txt QT_QUICK_BACKEND=software exec qs -p %s/tests/kbd-field\n' "$W" "$W" "$SRC" >"$W/field.sh"
# what the field holds at this step
printf 'tr -d "\\n" <"%s/field.txt" >"%s/text-$1" 2>/dev/null; kill -0 "$(cat %s/field.pid)" 2>/dev/null && echo alive >"%s/alive-$1"\n' "$W" "$W" "$W" "$W" >"$W/snap.sh"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
fails=0
ok() { if eval "$2"; then echo "ok $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
tap() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-500}"; }
# a quick flick up from X, Y
flick() { local y=$2 i; echo "d 0 $1 $y"; echo f; for i in 1 2 3 4 5 6; do y=$(python3 -c "print(round($y-0.06,4))"); echo "m 0 $1 $y"; echo f; done; echo "u 0"; echo f; echo "w 900"; }
# drag up from X, Y and rest
drag() { local y=$2 i; echo "d 0 $1 $y"; echo f; for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y-0.05,4))"); echo "m 0 $1 $y"; echo f; done; echo "w 300"; echo "u 0"; echo f; echo "w 900"; }
mark() { echo "p $1"; echo "g $1"; echo "x sh $W/snap.sh $1"; echo "w 150"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
# the strip is the last 26 of 873; the bottom key row ends just above it
STRIP=0.985; KEYROW=0.968; PILLX=0.5; ASIDEX=0.2; CHEVX=0.74; FIELD="0.5 0.2"
{ echo "w 2500"; echo "x sh $W/field.sh"; echo "w 4000"; tap $FIELD 1200; mark up; shot strip-keyboard
  # z, then the space bar at the very bottom of its row
  tap 0.2 0.91; tap 0.5 $KEYROW; mark typed
  tap $PILLX $STRIP; tap $ASIDEX $STRIP; mark pilltap
  # the hide area: a swipe does nothing, a tap hides
  flick $CHEVX $STRIP; mark chevswipe
  tap $CHEVX $STRIP 900; mark chevtap
  # shortcut: a new tap in the same Qt field does not bring it back after hiding, the next focus does; keyboard-test notes the same
  echo "x phonegluewc-msg workspace 2"; echo "w 900"; echo "x phonegluewc-msg workspace 1"; echo "w 900"; tap $FIELD 1200; mark again
  flick $ASIDEX $STRIP; mark flick; shot strip-flicked
  echo "x phonegluewc-msg workspace 1"; echo "w 900"; tap $FIELD 1200; mark back
  flick $PILLX $STRIP; mark pillflick
  echo "x phonegluewc-msg workspace 1"; echo "w 900"; tap $FIELD 1200; mark back2
  drag $PILLX $STRIP; mark held; shot strip-overview
  echo "x true"; echo "w 300"; } >"$W/strip.script"
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/strip.script"
comp_wait 1500
L=$W/gw.log
grep -q 'AddressSanitizer\|runtime error' "$L" && { grep -m3 'AddressSanitizer\|runtime error' "$L"; fails=$((fails + 1)); }
comp_stop
state() { grep "^FT $1 " "$L" | grep -q " $2\( \|$\)"; }
kbd() { grep "^GEOM $1 mon " "$L" | grep -qv ' w=0,36,393,837 '; }
text() { cat "$W/text-$1" 2>/dev/null; }
alive() { [ -e "$W/alive-$1" ]; }
ok "the keyboard is up"                       'kbd up && state up overview=0'
ok "the bottom key row still types"           '[ "$(text typed | tr Z z)" = "z " ]'
ok "a tap on the pill or beside it never types" '[ "$(text pilltap)" = "$(text typed)" ] && kbd pilltap && state pilltap ws=0'
ok "a swipe from the hide area does nothing"  '[ "$(text chevswipe)" = "$(text typed)" ] && kbd chevswipe && state chevswipe ws=0 && state chevswipe overview=0'
ok "a tap on the hide area hides the keyboard" '! kbd chevtap && state chevtap ws=0'
ok "the next focus brings it back"            'kbd again'
ok "a flick from the strip leaves the app, keyboard hidden, app alive" 'state flick ws=1 && ! kbd flick && alive flick'
ok "back on the app the field brings it back" 'state back ws=0 && kbd back'
ok "a flick from the pill itself leaves too"  'state pillflick ws=1 && ! kbd pillflick && alive pillflick'
ok "drag and rest from the pill opens the overview, keyboard hidden" 'state held overview=1 && ! kbd held && alive held'

# the hidden bar: over the app, never a strip of its own; at phone size and at the laptop window's size
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
bar() { # NAME MODE SCALE
	printf 'remember_layout = false\noutput = * mode=%s scale=%s\n' "$2" "$3" >"$W/cfg/phonegluewc/config.conf"
	{ echo "w 2500"; tap 0.5 0.995 300; shot "bar-$1-empty"; echo "w 3500"; echo "x env TOUCHLOG_TITLE=app $W/touchlog"; echo "w 1500"
	  shot "bar-$1-off"; tap 0.5 0.995 300; shot "bar-$1-app"; echo "p $1"; echo "x true"; echo "w 300"; } >"$W/bar-$1.script"
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/bar-$1.script"
	comp_wait 1500
	cat "$W/gw.log" >>"$W/bars.log"
	comp_stop
}
bar phone 1080x2400 2.75
bar laptop 450x1000 1.15
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
# 1080x2400: the pill's centre under the keys, drawn by the compositor over the keyboard's strip
px() { magick "$SHOTS/$1.png" -format "%[fx:int(255*p{$2,$3}.g)]" info:; }
ok "the white pill shows centred in the strip" '[ "$(px strip-keyboard 540 2365)" -gt 200 ] && [ "$(px strip-keyboard 300 2365)" -lt 60 ]'
ok "and is gone with the keyboard"            '[ "$(px strip-flicked 540 2365)" -lt 60 ]'
# identical but for the pill: nothing else on screen changed, and the last row stays the app's beside the pill
same() { local g; g=$(magick "$SHOTS/bar-$1-off.png" "$SHOTS/bar-$1-app.png" -compose difference -composite -trim -format '%w %h %Y' info:); set -- $g "$2"; echo "     changed: $1x$2 at y $3"; [ "$1" -lt 400 ] && [ "$2" -lt 30 ] && [ "$3" -gt "$4" ]; }
lastrow() { local h; h=$(magick "$SHOTS/$1.png" -format %h info:); px "$1" 20 $((h - 1)); }
ok "phone size: the bar lies over the app, no strip" 'same phone 2300 && [ "$(lastrow bar-phone-app)" -gt 100 ] && grep -q "^FT phone .*bar=1,1.00" "$W/bars.log"'
ok "laptop size: the same"                    'same laptop 950 && [ "$(lastrow bar-laptop-app)" -gt 100 ] && grep -q "^FT laptop .*bar=1,1.00" "$W/bars.log"'
[ -z "${STRIP_LOG:-}" ] || cp "$L" "$STRIP_LOG"
[ "$fails" = 0 ] && echo "all passed" || { echo "failed: $fails"; exit 1; }
