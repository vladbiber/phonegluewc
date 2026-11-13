#!/bin/bash
# The app menu, headless at phone size: sort modes, custom order with folders, search, Android apps. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-menu.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
# the log gets what the grid shows, folders in brackets
sed -i 's|^    readonly property var shown2: .*|&\n    onShown2Changed: console.log("MENU " + shown2.map(it => it.folder !== undefined ? "[" + it.folder + ":" + it.apps.map(e => e.id).join(",") + "]" : it.entry.id).join(" "))|' "$BUILD/shell/AppMenu.qml"
grep -q '"MENU "' "$BUILD/shell/AppMenu.qml" || { echo "FAIL menu log not injected"; exit 1; }
COMP=$BUILD/phonegluewc
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || { echo "FAIL touchlog"; exit 1; }
wayland-scanner client-header "$SRC/tests/input-method-unstable-v2.xml" "$BUILD/input-method-protocol.h"
wayland-scanner private-code "$SRC/tests/input-method-unstable-v2.xml" "$BUILD/input-method-protocol.c"
cc -w -I"$BUILD" -o "$W/imlog" "$SRC/tests/imlog.c" "$BUILD/input-method-protocol.c" -lwayland-client || { echo "FAIL imlog"; exit 1; }

mkdir -p "$W/fakebin" "$W/fake" "$W/cfg/phonegluewc" "$W/state/phonegluewc" "$W/data/applications"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep wlsunset wf-recorder fbcli fuser \
	systemctl loginctl reboot poweroff shutdown halt suspend rtcwake sudo doas pkexec; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
printf '#!/bin/sh\necho "waydroid $*" >>%s/fake/calls.log\n' "$W" >"$W/fakebin/waydroid"; chmod +x "$W/fakebin/waydroid"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
CONF=$W/cfg/phonegluewc/phone.conf
ORDER=$W/state/phonegluewc/menu-order.json
desk() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n' "$2" "$3" >"$W/data/applications/$1.desktop"; }
for n in Browser Calendar Camera Notes Terminal Weather; do
	id=$(echo "$n" | tr A-Z a-z)
	desk "$id" "$n" "env TOUCHLOG_TITLE=$id $W/touchlog"
done
desk stiri "Știri" "env TOUCHLOG_TITLE=stiri $W/touchlog"
# an Android app the way Waydroid writes it; its Exec is not what launches it here
desk waydroid.com.example.chess Chess "waydroid-not-this com.example.chess"
echo '{"notes":5,"camera":2}' >"$W/state/phonegluewc/app-usage.json"

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-700}"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
# hold at $1 $2, then carry to $3 $4 and lift
drag() { echo "d 0 $1 $2"; echo f; echo "w 750"; python3 -c "
for s in range(1,9): print('m 0 %.4f %.4f\nf\nw 30' % ($1+($3-$1)*s/8, $2+($4-$2)*s/8))"; echo "w 250"; echo "p ${5:-carry}"; echo "u 0"; echo f; echo "w 700"; }
# the grid: 4 columns, rows 100 px apart from y 155 of 872.7
COL=(0.148 0.383 0.6175 0.852); ROW=(0.1776 0.2922 0.4068)
MORE="0.887 0.92"; CHIP="0.15 0.094"; SORTY=(0.158 0.213 0.268 0.323)
sort() { t $CHIP 500; t 0.2 "${SORTY[$1]}" 800; }
keep() { echo "x cp $ORDER $W/$1.order"; echo "w 200"; }
run() {
	SANDBOX_PATH="$W/fakebin:$BUILD"
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 600
	cp "$W/gw.log" "$W/$1.log"
	comp_stop
}

{ echo "w 3000"; t $MORE 1200; echo "p used"; shot m-used
  sort 1; echo "p az"; shot m-az
  sort 2; echo "p za"
  sort 3; echo "p custom"; keep seeded
  # the first app onto the third's icon: a folder; then the fourth onto that folder
  drag ${COL[0]} ${ROW[0]} ${COL[2]} ${ROW[0]} make; shot m-folder
  drag ${COL[2]} ${ROW[0]} ${COL[1]} ${ROW[0]} fill
  # off the icon, low in a cell: only a move
  drag ${COL[0]} ${ROW[0]} ${COL[1]} 0.3438 move; keep moved
  # a drop outside the grid changes nothing
  drag ${COL[0]} ${ROW[0]} 0.5 0.97 outside
  echo "p before-open"; t ${COL[0]} ${ROW[0]} 900; echo "p folder-open"; shot m-folder-open
  # out of the folder card, to above it
  drag 0.171 0.533 0.5 0.15 takeout; keep taken
  t 0.5 0.2 700; echo "p folder-closed"
  t 0.9 0.094 900; echo "p closed"
  echo "x exec $W/imlog stiri >$W/im.log 2>&1"; echo "w 600"
  t $MORE 1200; t 0.35 0.947 1200; echo "p searched"; shot m-search
  t ${COL[0]} ${ROW[0]} 1200; echo "p launched"
  echo "p end"; } >"$W/script"
run one

# again: the order is read back; an id of an app not installed survives a save
python3 -I - "$ORDER" <<'P'
import json, sys
p = sys.argv[1]; v = json.load(open(p)); v.insert(0, "gone.app"); open(p, "w").write(json.dumps(v))
P
cp "$ORDER" "$W/before2.order"
# a swipe up on bare home opens the menu; the close button shuts it again
{ echo "w 3000"; echo "d 0 0.5 0.6"; echo f; for y in 0.57 0.53 0.49 0.45 0.41; do echo "m 0 0.5 $y"; echo f; echo "w 30"; done; echo "u 0"; echo f; echo "w 1200"; echo "p swiped"
  t 0.9 0.094 900; echo "p swipe-closed"
  t $MORE 1200; echo "p reopened"
  drag ${COL[1]} ${ROW[0]} ${COL[3]} 0.3438 move2; keep after2
  sort 1; echo "p az2"; t ${COL[3]} ${ROW[0]} 1200; echo "p chess"
  echo "p end"; } >"$W/script"
run two

# a pull down from the top of the list closes the menu; a long list to scroll first
for i in $(seq -w 1 40); do desk "extra$i" "Extra $i" true; done
# slow pull from $1 to $2 in 8 steps, held still before letting go
pull() { echo "d 0 0.5 $1"; echo f; python3 -c "
for s in range(1,9): print('m 0 0.5 %.4f\nf\nw 60' % ($1+($2-$1)*s/8))"; echo "w ${3:-400}"; }
{ echo "w 3000"; t $MORE 1200
  pull 0.25 0.6; echo "p pulling"; shot m-pull; echo "u 0"; echo f; echo "w 1200"; echo "p pulled"
  t $MORE 1200; pull 0.25 0.32; echo "u 0"; echo f; echo "w 1000"; echo "p short"
  pull 0.7 0.3 300; echo "u 0"; echo f; echo "w 1500"; echo "p scrolled"
  pull 0.3 0.75; echo "u 0"; echo f; echo "w 1200"; echo "p midlist"
  # back at the top now: a quick short flick closes
  echo "d 0 0.5 0.25"; echo f; for y in 0.28 0.31 0.34; do echo "m 0 0.5 $y"; echo f; echo "w 16"; done; echo "u 0"; echo f; echo "w 1200"; echo "p flicked"
  echo "p end"; } >"$W/script"
run three

printf '%s\n' "$W"/*.ppm | SHOTS=$SHOTS xargs -P8 -I{} sh -c 'f={}; b=${f##*/}; magick "$f" "$SHOTS/${b%.ppm}.png"' 2>/dev/null

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
# the grid as the menu last logged it before the FT line $2 of run $1
menu() { awk -v l="FT $2 " 'index($0, "MENU ") { m = substr($0, index($0, "MENU ") + 5) } index($0, l) == 1 { print m; exit }' "$W/$1.log"; }
state() { grep -a "^FT $2 " "$W/$1.log" | grep -q " $3\( \|$\)"; }
ids() { python3 -I -c 'import json,sys; print(" ".join(x if isinstance(x, str) else "[%s:%s]" % (x["folder"], ",".join(x["apps"])) for x in json.load(open(sys.argv[1]))))' "$1"; }
AZ="browser calendar camera waydroid.com.example.chess notes stiri terminal weather"
ZA="weather terminal stiri notes waydroid.com.example.chess camera calendar browser"
[ -n "${MENU_VERBOSE:-}" ] && { grep -a '^FT \|MENU ' "$W/one.log" "$W/two.log" | cut -c1-200; for f in "$W"/*.order; do echo "$f: $(cat "$f")"; done; }
ok "the menu opens"                         'state one used menu=1'
ok "most used first, the rest A to Z"       '[ "$(menu one used)" = "notes camera browser calendar waydroid.com.example.chess stiri terminal weather" ]'
ok "A to Z, Știri among the S"               '[ "$(menu one az)" = "$AZ" ]'
ok "Z to A"                                  '[ "$(menu one za)" = "$ZA" ]'
ok "the sort mode is kept in phone.conf, one line" 'state two reopened menu=1 && [ "$(grep -c "^menu_sort" "$CONF")" = 1 ] && grep -q "^menu_sort = az$" "$CONF"'
ok "Custom starts from what was on screen"  '[ "$(ids "$W/seeded.order")" = "$ZA" ]'
ok "an app dropped on another makes a folder" '[ "$(menu one fill)" = "terminal [Folder:stiri,weather] notes waydroid.com.example.chess camera calendar browser" ]'
ok "an app dropped on a folder joins it"     '[ "$(menu one move)" = "terminal [Folder:stiri,weather,notes] waydroid.com.example.chess camera calendar browser" ]'
ok "off an icon it only moves"               '[ "$(ids "$W/moved.order")" = "[Folder:stiri,weather,notes] waydroid.com.example.chess camera calendar browser terminal" ]'
ok "a drop outside the grid changes nothing" '[ "$(menu one before-open)" = "$(menu one outside)" ]'
ok "a tap opens the folder"                  'state one folder-open menu=1'
ok "dragged out of the card it leaves the folder" '[ "$(ids "$W/taken.order")" = "[Folder:weather,notes] stiri waydroid.com.example.chess camera calendar browser terminal" ]'
ok "a tap beside the folder leaves the menu open" 'state one folder-closed menu=1'
ok "the close button closes the menu"        'state one closed menu=0'
ok "search ignores accents: stiri finds Știri" '[ "$(menu one searched)" = "stiri" ]'
ok "the search field sits low on the screen" 'grep -q committed "$W/im.log"'
ok "a search result opens its app"           'state one launched menu=0 && grep -q "\"stiri\":1" "$W/state/phonegluewc/app-usage.json"'
ok "the custom order comes back after a restart" '[ "$(menu two reopened)" = "$(ids "$W/taken.order")" ]'
ok "an id of an app not installed survives a save" '[ "$(ids "$W/after2.order" | awk "{print \$NF}")" = gone.app ]'
ok "a swipe up on home opens the menu"       'state two swiped menu=1 && state two swipe-closed menu=0'
ok "an Android app launches through waydroid" 'grep -qx "waydroid app launch com.example.chess" "$W/fake/calls.log"'
ok "pulled down at the top, the menu closes"  'state three pulling menu=1 && state three pulled menu=0'
ok "a short pull at the top springs back"    'state three short menu=1'
ok "a pull from mid-list scrolls, never closes" 'state three scrolled menu=1 && state three midlist menu=1'
ok "a quick flick down at the top closes"    'state three flicked menu=0'
ok "no crash, no warning from the menu"      '! grep -a "Segmentation\|Aborted\|core dumped\|AppMenu.qml\|AppCell.qml" "$W/one.log" "$W/two.log" "$W/three.log" | grep -q .'
ok "no core files"                           '! ls "$W"/core.* "$BUILD"/core.* >/dev/null 2>&1'
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
exit 0
