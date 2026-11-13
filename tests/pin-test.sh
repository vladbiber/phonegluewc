#!/bin/bash
# Pin and unpin from the tray and the menu, headless, across restarts of the whole session.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-pin.XXXXXX")
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g"} >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1

CFG=$W/cfg/phonegluewc
# not in $W itself: the shell rescans its apps when the parent of the data dir changes
O=$W/out; mkdir -p "$O"
mkdir -p "$CFG" "$W/state/phonegluewc" "$W/data/applications" "$W/data/icons/hicolor/scalable/apps"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$CFG/config.conf"
printf '# mine\na.desktop\nb.desktop\n' >"$CFG/pinned-apps"
printf '{"a":10,"c":5,"d":3,"e":2}' >"$W/state/phonegluewc/app-usage.json"
# each app has its own colour, so a capture says which app sits in which slot
COLORS="a=2060e0 b=20c060 c=e0a020 d=c02080 e=20c0c0 f=8040e0 g=a0a020"
for kv in $COLORS; do
	id=${kv%=*}
	printf '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#%s"/></svg>\n' "${kv#*=}" >"$W/data/icons/hicolor/scalable/apps/t$id.svg"
	printf '[Desktop Entry]\nType=Application\nName=App %s\nExec=%s\nIcon=t%s\n' "$id" "env TOUCHLOG_TITLE=$id $W/touchlog" "$id" >"$W/data/applications/$id.desktop"
done
cat >"$W/slots.py" <<'PY'
import sys
d = open(sys.argv[1], "rb").read().split(b"\n", 3)
w, h = map(int, d[1].split()); px = d[3]
colors = dict((k, tuple(bytes.fromhex(v))) for k, v in (kv.split("=") for kv in sys.argv[2].split()))
out = ""
for i in range(4):
    x = int((44.35 + 76 * i) * 2.75); y = int((872.73 - 46) * 2.75)
    p = px[(y * w + x) * 3:(y * w + x) * 3 + 3]
    best = min(colors, key=lambda k: sum(abs(a - b) for a, b in zip(colors[k], p)))
    out += best if sum(abs(a - b) for a, b in zip(colors[best], p)) < 40 else "-"
print(out)
PY

Y=0.929                             # middle of a tray icon
t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-600}"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w 1200"; echo "p $3"; echo "u 0"; echo f; echo "w 400"; echo "p $3-up"; }
shot() { echo "x $SRC/tests/wshot $O/$1.ppm"; echo "w 400"; }
# script lines have a length limit
cat >"$W/keep" <<EOF
cp "$CFG/pinned-apps" "$O/\$1.pinned"; cp "$CFG/unpinned-apps" "$O/\$1.unpinned" 2>/dev/null
EOF
keep() { echo "x sh $W/keep $1"; echo "w 200"; }
slot() { python3 -c "print(round((44.35 + 76 * $1) / 392.73, 3))"; }
# where the action of the popup is, above a tray slot: clamped to the screen edges
act() { python3 -c "print(round(max(127, min(392.73 - 127, 44.35 + 76 * $1)) / 392.73, 3))"; }
ACTY=0.849
pillopen() { echo "d 0 0.5 0.995"; echo f; for s in 1 2 3 4 5 6 7 8; do echo "m 0 0.5 $(python3 -c "print(0.995-0.5*$s/8)")"; echo f; done; echo "w 250"; echo "u 0"; echo f; echo "w 700"; }

COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD"
: >"$W/all.log"
session() { # NAME [ENV...]: runs $W/$NAME.script to its end
	local n=$1; shift
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/$n.script" "$@"
	comp_wait 400
	cat "$W/gw.log" >>"$W/all.log"
	comp_stop
}

{ echo "w 2500"; echo "p home"; shot s0
  hold "$(slot 3)" $Y hold; shot popup; keep held; t "$(act 3)" $ACTY; echo "p pinned"; shot s1; keep pinned
  hold "$(slot 0)" $Y hold2; shot popup2; t "$(act 0)" $ACTY; echo "p unpinned"; shot s2; keep unpinned
  hold "$(slot 2)" 0.954 low; t 0.5 0.4; echo "p dismissed"; shot s3; keep dismissed
  t "$(slot 0)" $Y 1000; echo "p launched"; echo "x true"; echo "w 300"; } >"$W/one.script"
session one
USAGE1=$(cat "$W/state/phonegluewc/app-usage.json")

MOSTA="0.148 0.225"; MOSTE="0.851 0.225"; MENUCLOSE="0.9 0.094"
# the menu popup: add to home, new window, uninstall, pin; pin is the fourth row
{ echo "w 2500"; echo "p back"; shot r0
  t 0.887 $Y; echo "p menu"; shot menu; hold $MOSTA menuhold; shot menupop; t 0.324 0.274; echo "p menupin"; keep menupin
  t $MENUCLOSE; shot r1
  hold "$(slot 3)" $Y hold3; t "$(act 3)" $ACTY; shot r2; keep four
  t 0.887 $Y; hold $MOSTE full; shot full; t 0.675 0.274; keep fullact; echo "p fulldismiss"; t $MENUCLOSE
  hold "$(slot 3)" $Y ovhold; t 0.5 0.4; echo "p ovno"
  t "$(slot 0)" $Y 1000; echo "p app"; pillopen; echo "p ov"; hold "$(slot 1)" $Y inov; shot inov; t 0.5 0.3 ; echo "p ovafter"; echo "x true"; echo "w 300"; } >"$W/two.script"
session two

# the same with the mouse the laptop window turns into a finger
mhold() { echo "M $1 $2"; echo "w 100"; echo "B 1"; echo "w 1200"; echo "p $3"; echo "B 0"; echo "w 400"; }
mtap() { echo "M $1 $2"; echo "w 100"; echo "B 1"; echo "w 100"; echo "B 0"; echo "w ${3:-600}"; }
{ echo "w 2500"; shot m0; mhold "$(slot 3)" $Y mouse; shot mouse; mtap "$(act 3)" $ACTY; keep mouse; shot m1
  mtap "$(slot 0)" $Y 1000; echo "p mouselaunch"; pillopen; t 0.5 0.3 1000; echo "x true"; echo "w 300"; } >"$W/three.script"
session three PHONEGLUEWC_MOUSE_FINGER=1
USAGE3=$(cat "$W/state/phonegluewc/app-usage.json")

# a write that cannot happen says so; a config dir that went away comes back
CHMOD=$(command -v chmod)
printf '%s 555 %s\n' "$CHMOD" "$CFG" >"$W/ro"; printf '%s 755 %s\n' "$CHMOD" "$CFG" >"$W/rw"
{ echo "w 4000"; echo "x sh $W/ro"; echo "w 300"; hold "$(slot 0)" $Y sf; t "$(act 0)" $ACTY; shot failed; echo "p failed"; echo "x sh $W/rw"; echo "w 300"; keep failed; t 0.5 0.4; echo "p failgone"
  echo "x true"; echo "w 300"; } >"$W/four.script"
session four
# first run on a new install: there is no config dir at all yet
{ echo "w 4000"; hold "$(slot 0)" $Y gone; t "$(act 0)" $ACTY; echo "p recreated"; echo "x true"; echo "w 300"; } >"$W/five.script"
# only the shell sees it, the compositor keeps the phone size
mkdir -p "$W/freshbin"; printf '#!/bin/sh\nXDG_CONFIG_HOME="%s/fresh" exec "%s" "$@"\n' "$W" "$(command -v qs)" >"$W/freshbin/qs"; chmod +x "$W/freshbin/qs"
session five PATH="$W/freshbin:$BUILD:$W/sysbin"
FRESH=$(cat "$W/fresh/phonegluewc/pinned-apps" 2>/dev/null)

for f in "$O"/*.ppm; do python3 -c "from PIL import Image; import sys; Image.open(sys.argv[1]).save(sys.argv[2])" "$f" "$SHOTS/$(basename "${f%.ppm}").png" 2>/dev/null; done
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
state() { grep "^FT $1 " "$W/all.log" | grep -q " $2\( \|$\)"; }
slots() { python3 -I "$W/slots.py" "$O/$1.ppm" "$COLORS"; }
pins() { grep -v '^#' "$O/$1.pinned" | sed 's/\.desktop$//' | tr '\n' ' '; }
ok "pins come first, then what is used"     '[ "$(slots s0)" = abcd ]'
ok "a hold in the tray opens the popup"     'state hold pin=1 && state hold-up pin=1'
ok "a hold is no bar or overview gesture"   'state hold gesture=0 && state hold overview=0 && state low gesture=0'
ok "the low edge of the middle icon is the icon" 'state low pin=1'
ok "pin: goes last, order and comment stay" '[ "$(cat "$O/pinned.pinned")" = "$(printf "# mine\na.desktop\nb.desktop\nd.desktop")" ] && state pinned pin=0'
ok "pin: the tray shows it after the pins"  '[ "$(slots s1)" = abdc ]'
ok "unpin: leaves the file, usage stays out" '[ "$(pins unpinned)" = "b d " ] && [ "$(sed s/.desktop// "$O/unpinned.unpinned")" = a ]'
ok "unpin: the most used app does not return" '[ "$(slots s2)" = bdce ]'
ok "a tap outside dismisses without a change" 'state dismissed pin=0 && [ "$(pins dismissed)" = "b d " ] && [ "$(slots s3)" = bdce ]'
ok "no hold launched anything"              'state dismissed counts=000000000 && state hold-up counts=000000000'
ok "a tap on the tray still launches"       'state launched counts=100000000 && python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(d.get(\"b\")!=1 or d[\"a\"]!=10)" "$USAGE1"'
ok "after a restart the unpinned app stays out" '[ "$(slots r0)" = bdce ]'
ok "a hold in the menu pins, the menu stays" 'state menuhold pin=1 && state menupin pin=0 && state menupin menu=1 && [ "$(pins menupin)" = "b d a " ] && [ ! -s "$O/menupin.unpinned" ]'
ok "pinned again it is back in the tray"    '[ "$(slots r1)" = bdac ]'
ok "pinning replaces the filled slots first" '[ "$(pins four)" = "b d a c " ] && [ "$(slots r2)" = bdac ]'
ok "a full tray says so and changes nothing" 'state full pin=1 && [ "$(pins fullact)" = "b d a c " ]'
ok "a tap closes that popup, the menu stays"   'state fulldismiss pin=0 && state fulldismiss menu=1'
ok "a hold on a full tray can still unpin"  'state ovhold pin=1 && state ovno pin=0'
ok "a hold in the overview drags no card"   'state inov pin=1 && state inov gesture=0 && state inov overview=1 && state inov counts=100000000'
ok "mouse as finger: hold then click pins or unpins" 'state mouse pin=1 && state mouse gesture=0 && [ "$(pins mouse)" = "b d a " ]'
ok "mouse as finger: a click still launches" 'state mouselaunch counts=100000000 && python3 -c "import json,sys; sys.exit(json.loads(sys.argv[1])[\"b\"]<3)" "$USAGE3"'
ok "a failed write stays open and keeps the file" 'state failed pin=1 && [ "$(pins failed)" = "b d a " ] && state failgone pin=0'
ok "the first pin creates a missing config dir" '[ -n "$FRESH" ] && state recreated pin=0'
ok "no stray temp files"                    '[ -z "$(ls -A "$CFG" "$W/fresh/phonegluewc" | grep -v -e config.conf -e pinned-apps -e unpinned-apps -e phonegluewc: -e "^$")" ]'
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
