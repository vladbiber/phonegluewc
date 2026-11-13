#!/bin/bash
# Home pages as a grid: sideways swipes on home, variants from the editor, an app put on home from its hold popup,
# and the tray's settings in portrait and turned. Headless, a private copy. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-grid.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync magick"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
COMP=$BUILD/phonegluewc
FAILS=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }

C=$W/cfg/phonegluewc
mkdir -p "$C" "$W/fakebin" "$W/fake" "$W/home/Pictures" "$W/data/applications"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$C/config.conf"
printf 'animations = on\n' >"$C/phone.conf"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
magick -size 1080x2400 gradient:'#203080-#000000' "$W/home/Pictures/blue.png"
magick -size 1080x2400 gradient:'#205030-#000000' "$W/home/Pictures/green.png"
for n in Alpha Bravo Charlie Delta Echo Foxtrot Golf; do
	printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\n' $n >"$W/data/applications/${n,,}.desktop"
done
# the old file: no x, no y
printf '{"home":{"active":0,"screens":[{"wallpaper":"%s","widgets":[]},{"wallpaper":"%s","widgets":[]}]}}\n' \
	"$W/home/Pictures/blue.png" "$W/home/Pictures/green.png" >"$C/screens.json"

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-700}"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w ${3:-1100}"; echo "u 0"; echo f; echo "w 700"; }
swipe() { echo "d 0 $1 $2"; echo f; python3 -c "
for s in range(1,9): print('m 0 %.3f %.3f\nf\nw 25' % ($1+($3-$1)*s/8, $2+($4-$2)*s/8))"; echo "u 0"; echo f; echo "w 900"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
save() { echo "x cp $C/screens.json $W/$1.json"; echo "w 150"; }
# bare home under the home window, and on it
NEXT="0.8 0.55 0.2 0.55"; PREV="0.2 0.55 0.8 0.55"; PREVTOP="0.2 0.15 0.8 0.15"
# portrait tray with four apps and more: slot 0, and the hold popup's top row above it
SLOT="0.113 0.947"; POPTOP="0.349 0.668"
CARD="0.5 0.40"; ADDVAR="0.939 0.434"; TRAYBTN="0.694 0.78"
{ echo "w 3500"; save s0; shot grid-home0
  swipe $NEXT; save s1; shot grid-home1
  swipe $PREVTOP; save s2
  swipe $PREV; save s3
  hold 0.5 0.55; shot grid-editor
  t $ADDVAR 900; shot grid-variant; save s4
  t $CARD 900; save s5
  swipe $NEXT; save s6
  swipe $PREV; save s7
  hold $SLOT 900; shot grid-pin; t $POPTOP 900; save s8; shot grid-app
  hold $SLOT 900; t $POPTOP 900; save s9
  hold 0.5 0.55; t $TRAYBTN 900; shot grid-tray
  t 0.422 0.159 500; t 0.47 0.244 500; t 0.18 0.30 500; shot grid-tray-set; echo "x cp $C/phone.conf $W/conf"
  t 0.05 0.07 700; t 0.5 0.95 1200; echo "g trayp"; shot grid-tray6
  echo "x echo left-up >$W/fake/orientation"; echo "w 2000"; echo "g trayl"; shot grid-tray6-land
  echo "p done"; } >"$W/script"
SANDBOX_PATH="$W/fakebin:$BUILD"
comp_start FAKE_STATE="$W/fake" QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 900
comp_stop
cp "$W/gw.log" "$SHOTS/homegrid.log" 2>/dev/null
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
grep -E 'ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|qml:.*rror' "$W/gw.log" | cut -c1-200 | sort -u | head

# NAME EXPR: a python expression over the saved file j, and h = j["home"]
js() { python3 -c "
import json,sys
try: j=json.load(open('$W/$1.json'))
except Exception: sys.exit(1)
h=j['home']; cells=[(s['x'],s['y']) for s in h['screens']] if all('x' in s for s in h['screens']) else None
sys.exit(0 if ($2) else 1)" 2>/dev/null; }
for n in s1 s2 s3 s4 s5 s6 s7 s8 s9; do printf '  %s: %s\n' $n "$(python3 -c "
import json; h=json.load(open('$W/$n.json'))['home']; print('active', h['active'], 'picks', h.get('picks'), [(s.get('x'),s.get('y'),len(s['widgets'])) for s in h['screens']])" 2>/dev/null)"; done
ok "the old file reads as two pages and a swipe on bare home turns to the next" 'js s1 "cells == [(0,0),(1,0)] and h[\"active\"] == 1"'
ok "a swipe on the home window turns back"     'js s2 "h[\"active\"] == 0"'
ok "nothing before the first page"             'js s3 "h[\"active\"] == 0"'
ok "the editor adds a variant under page 1"    'js s4 "cells == [(0,0),(0,1),(1,0)]"'
ok "picking it makes it the page"              'js s5 "h[\"active\"] == 1 and h[\"picks\"] == [1,0]"'
ok "swipes skip variants, back lands on the picked one" 'js s6 "h[\"active\"] == 2" && js s7 "h[\"active\"] == 1"'
ok "the hold popup puts the app on this home screen" 'js s8 "[w.get(\"app\") for w in h[\"screens\"][1][\"widgets\"] if w[\"type\"] == \"app\"] == [\"alpha\"] and not any(w[\"type\"] == \"app\" for s in h[\"screens\"][::2] for w in s[\"widgets\"])"'
ok "and takes it off again"                    'js s9 "not any(w[\"type\"] == \"app\" for w in h[\"screens\"][1][\"widgets\"])"'
ok "the tray settings are kept"                'grep -q "^tray_count = 6" "$W/conf" && grep -q "^tray_labels = on" "$W/conf" && grep -q "^tray_plate = on" "$W/conf"'
trayp=$(sed -n 's/^GEOM trayp layer ns=phone-tray .*box=\([-0-9,]*\).*/\1/p' "$W/gw.log")
trayl=$(sed -n 's/^GEOM trayl layer ns=phone-tray .*box=\([-0-9,]*\).*/\1/p' "$W/gw.log")
echo "  tray portrait=$trayp landscape=$trayl"
ok "six with names: a taller tray at the bottom" '[ "$trayp" = "0,731,393,126" ]'
ok "turned: the column at the right edge"      'echo "$trayl" | awk -F, '"'"'{ exit !($1 + $3 == 873 && $2 == 0 && $3 < 200) }'"'"''
comp_cores
[ "$FAILS" = 0 ] && echo "homegrid: all passed" || echo "homegrid: failed: $FAILS"
exit "$((FAILS > 0))"
