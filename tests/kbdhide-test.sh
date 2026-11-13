#!/bin/bash
# When the keyboard hides and comes back: every way of leaving the app hides it, coming back shows it only for a focused field.
# Headless, a real Qt field. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-kbdhide.XXXXXX")
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
STRIP=0.985; FIELD="0.5 0.2"
# up from the pill, the finger kept down
follow() { local y=$STRIP i; echo "d 0 0.5 $y"; echo f; for i in 1 2 3 4 5; do y=$(python3 -c "print(round($y-0.04,4))"); echo "m 0 0.5 $y"; echo f; done; echo "w 120"; }
back() { local y=$(python3 -c "print(round($STRIP-0.2,4))") i; for i in 1 2 3 4 5; do y=$(python3 -c "print(round($y+0.04,4))"); echo "m 0 0.5 $y"; echo f; echo "w 40"; done; echo "u 0"; echo f; echo "w 1200"; }
pull() { local x=$1 y=0.004 i; echo "d 0 $x $y"; echo f; for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y+0.06,4))"); echo "m 0 $x $y"; echo f; echo "w 30"; done; echo "u 0"; echo f; echo "w 1200"; }
edge() { local x=0.004 i; echo "d 0 $x 0.5"; echo f; for i in 1 2 3 4 5 6 7 8 9 10; do x=$(python3 -c "print(round($x+0.04,4))"); echo "m 0 $x 0.5"; echo f; echo "w 30"; done; echo "u 0"; echo f; echo "w 1200"; }
{ echo "w 2500"; echo "x sh $W/field.sh"; echo "w 4000"; tap $FIELD 1200; mark up
  echo "w 6000"; shot idle; mark idle
  follow; mark follow; shot follow; back; mark cancel
  drag 0.5 $STRIP; mark overview; shot overview; pull 0.85; mark ovpanel; tap 0.5 0.9 1500; tap 0.5 0.45 1500; mark cardback; shot cardback
  flick 0.5 $STRIP; mark flick; echo "x phonegluewc-msg workspace 1"; echo "w 1500"; mark flickback
  echo "x phonegluewc-msg workspace 2"; echo "w 900"; mark ws2; echo "x phonegluewc-msg workspace 1"; echo "w 1500"; mark wsback
  echo "x sh -c 'env TOUCHLOG_TITLE=other $W/touchlog & echo \$! >$W/other.pid'"; echo "w 1500"; mark window
  echo "x sh -c 'kill \$(cat $W/other.pid)'"; echo "w 1500"; mark windowback
  pull 0.85; mark panel; shot panel; tap 0.5 0.9 1500; mark panelback
  echo "x sh -c 'kill \$(cat $W/field.pid)'"; echo "w 1500"; mark closed
  edge; mark edge; tap 0.5 0.5 900; mark edgetap
  drag 0.5 $STRIP; mark edgeov; tap 0.5 0.45 1200
  edge; mark edge2; echo "K 116 1"; echo "w 60"; echo "K 116 0"; echo "w 2000"; mark locked
  echo "x true"; echo "w 300"; } >"$W/kh.script"
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONE_AUTH_MOCK=test PHONEGLUEWC_FAKETOUCH="$W/kh.script"
comp_wait 1500
L=$W/gw.log
grep -q 'AddressSanitizer\|runtime error' "$L" && { grep -m3 'AddressSanitizer\|runtime error' "$L"; fails=$((fails + 1)); }
comp_stop
state() { grep "^FT $1 " "$L" | grep -q " $2\( \|$\)"; }
# the keyboard's own surface, mapped or not
kbd() { grep -q "^GEOM $1 layer ns=phone-keyboard " "$L"; }
alive() { [ -e "$W/alive-$1" ]; }
ok "a tap on the field opens the keyboard"                 'kbd up'
ok "it stays up while idle"                                 'kbd idle'
ok "hidden as soon as the finger pulls the overview"       '! kbd follow'
ok "back to the same app with the field focused: back"     'state cancel overview=0 && kbd cancel'
ok "hidden in the overview"                                 'state overview overview=1 && ! kbd overview'
ok "a card tap back into the app: back"                    'state cardback overview=0 && kbd cardback'
ok "hidden after a flick to the free workspace"            'state flick ws=1 && ! kbd flick'
ok "back on the app: back"                                  'kbd flickback'
ok "hidden on another workspace, back on return"           '! kbd ws2 && kbd wsback'
ok "hidden when another window takes focus"                '! kbd window'
ok "back when that window closes"                           'kbd windowback'
ok "hidden under quick settings"                            'grep -q "^GEOM panel layer ns=phone-panel" "$L" && ! kbd panel'
ok "back after the panel, field still focused"             '! grep -q "^GEOM panelback layer ns=phone-panel" "$L" && kbd panelback'
ok "hidden when the app closes"                             '! kbd closed && ! alive closed'
ok "the left edge opens it with no field, a tap leaves it up" 'kbd edge && kbd edgetap'
ok "leaving for the overview hides that one too"           '! kbd edgeov'
ok "hidden when the screen locks"                           'kbd edge2 && grep -q "^FT locked .*locked=1" "$L" && ! kbd locked || { grep "^FT locked" "$L"; false; }'
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
# after 6 s of nothing: the white pill and the chevron beside it, in the strip under the keys
peak() { magick "$SHOTS/idle.png" -crop "$1" -format "%[fx:int(255*maxima.g)]" info:; }
ok "after idling the white pill shows in the strip"        '[ "$(peak 300x14+390+2358)" -gt 200 ] && [ "$(peak 60x14+200+2358)" -lt 60 ]'
ok "and the down chevron beside it"                        '[ "$(peak 70x50+760+2340)" -gt 120 ]'
# the bar's clock and battery stay: on the app, under the finger, in the overview (above the cards), after
# the corners only: the card's own name sits centred in that same band
bar() { local l r; l=$(magick "$SHOTS/$1.png" -alpha off -colorspace Gray -crop 330x90+0+10 +repage -format "%[fx:int(255*maxima)]" info:); r=$(magick "$SHOTS/$1.png" -alpha off -colorspace Gray -crop 200x90+880+10 +repage -format "%[fx:int(255*maxima)]" info:); echo $((l > r ? l : r)); }
echo "  bar brightness: app $(bar idle) follow $(bar follow) overview $(bar overview) back $(bar cardback)"
ok "the bar stays under the finger and in the overview" '[ "$(bar idle)" -gt 200 ] && [ "$(bar follow)" -gt 200 ] && [ "$(bar overview)" -gt 200 ] && [ "$(bar cardback)" -gt 200 ]'
ok "pull-down from the top still opens quick settings in the overview" 'grep -q "^GEOM ovpanel layer ns=phone-panel" "$L"'
[ -z "${KH_LOG:-}" ] || cp "$L" "$KH_LOG"
[ "$fails" = 0 ] && echo "all passed" || { echo "failed: $fails"; exit 1; }
