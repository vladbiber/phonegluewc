#!/bin/bash
# Moving things in quick settings, through the laptop's mouse and through touch; panel limits. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-qs.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync sleep"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
# the log's tray= field reports the quick panel in this copy
sed -i 's/ft_layer("phone-tray")/ft_layer("phone-panel")/' "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/fakeapp" "$SRC/tests/fakeapp.c" "$BUILD/touchlog-xdg-protocol.c" $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0) -lwayland-client || { echo "FAIL fakeapp"; exit 1; }
COMP=$BUILD/phonegluewc

# every pull, page and order change lands in the log
SH=$W/shell; cp -a "$SRC/shell" "$SH"
sed -i 's|^    property var closing: ({})|&\n    onPullChanged: console.log("PULL " + pull)\n    onSideChanged: console.log("SIDE " + side)|' "$SH/Status.qml"
sed -i 's|^    property int page: 0|&\n    onPageChanged: console.log("PAGE " + page)|' "$SH/QuickSettings.qml"
sed -i 's|^    readonly property int count: rows.length|&\n    onRowsChanged: console.log("ROWS " + rows.map(r => r.name).join(" "))|' "$SH/AppModel.qml"
sed -i 's|^    readonly property var ids: .*|&\n    onIdsKeyChanged: console.log("IDS " + idsKey)|' "$SH/QuickModel.qml"
for k in '"PULL "' '"PAGE "' '"ROWS "' '"IDS "'; do grep -q "$k" "$SH"/*.qml || { echo "FAIL log not injected: $k"; exit 1; }; done

mkdir -p "$W/fakebin" "$W/fake" "$W/cfg/phonegluewc"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep wf-recorder fbcli; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
printf '#!/bin/sh\necho "settings $*" >>%s/set.log\n' "$W" >"$W/fakebin/phonesettings"; chmod +x "$W/fakebin/phonesettings"
for p in systemctl loginctl reboot poweroff shutdown halt suspend rtcwake; do printf '#!/bin/sh\necho "POWER $0 $*" >>%s/power.log\n' "$W" >"$W/fakebin/$p"; chmod +x "$W/fakebin/$p"; done
S=$W/sys; mkdir -p "$S/power_supply/BAT0" "$S/backlight/f"; echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"; echo 100 >"$S/backlight/f/max_brightness"; echo 60 >"$S/backlight/f/brightness"
CONF=$W/cfg/phonegluewc/phone.conf
printf '#!/bin/sh\nFAKEAPP_LOG="%s/fake.log" exec "%s/fakeapp" "$@"\n' "$W" "$W" >"$W/f"; chmod +x "$W/f"
fake() { echo "x exec $W/f $*"; echo "w 500"; }
cat >"$W/rss.sh" <<EOF
p=\$(cat "$W/pid"); q=\$(pgrep -P \$p -x qs)
echo "\$1 qs=\$(awk '/VmRSS/{print \$2}' /proc/\$q/status 2>/dev/null) kB" >>"$W/rss"
EOF
rss() { echo "w 1500"; echo "x sh $W/rss.sh $1"; echo "w 300"; }

# the same finger, by mouse or by touch
MODE=touch
down() { if [ $MODE = mouse ]; then echo "M $1 $2"; echo "w 30"; echo "B 1"; else echo "d 0 $1 $2"; echo f; fi; }
to() { if [ $MODE = mouse ]; then echo "M $1 $2"; else echo "m 0 $1 $2"; echo f; fi; }
up() { if [ $MODE = mouse ]; then echo "B 0"; else echo "u 0"; echo f; fi; }
walk() { python3 -c "
for s in range(1,$5+1): print('%.4f %.4f' % ($1+($3-$1)*s/$5, $2+($4-$2)*s/$5))" | while read -r a b; do to "$a" "$b"; echo "w ${6:-30}"; done; }
# pick X0 Y0 X1 Y1 [REST]: rest on it, carry it there, let go; "w 0" would stop the hook's timer, so 0 rests 1 ms
pick() { local r=${5:-320}; down "$1" "$2"; echo "w $((r > 0 ? r : 1))"; walk "$1" "$2" "$3" "$4" 12; echo "w 200"; up; echo "w 600"; }
# the same, the finger stays down
carry() { down "$1" "$2"; echo "w ${5:-320}"; walk "$1" "$2" "$3" "$4" 12; echo "w 300"; }
t() { down "$1" "$2"; echo "w 40"; up; echo "w ${3:-600}"; }
holdat() { down "$1" "$2"; echo "w ${3:-900}"; to "$(awk "BEGIN{print $1+0.005}")" "$(awk "BEGIN{print $2+0.003}")"; echo "w 40"; up; echo "w 600"; }
swipe() { down "$2" "$1"; walk "$2" "$1" "$3" "$1" 6 16; up; echo "w 700"; }
open() { down 0.75 0.012; walk 0.75 0.012 0.75 0.6 10; echo "w 200"; up; echo "w 900"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 300"; }
keep() { echo "x cp $CONF $W/$1"; echo "w 100"; }
mk() { echo "p $1"; }
# where things are, as fractions of the screen; the same at both sizes
X0=0.267; X1=0.733; R0=0.3985; R1=0.481; R2=0.5635
slot() { case $1 in 0) echo "$X0 $R0";; 1) echo "$X1 $R0";; 2) echo "$X0 $R1";; 3) echo "$X1 $R1";; 4) echo "$X0 $R2";; 5) echo "$X1 $R2";; esac; }
PENCIL="0.904 0.621"; BRIGHT=0.2585; VOL=0.3225; EMPTY="0.5 0.8"

run() { local n=$1 mode=$2 scale=$3; shift 3
	printf 'remember_layout = false\noutput = * mode=%s scale=%s\n' "$mode" "$scale" >"$W/cfg/phonegluewc/config.conf"
	SANDBOX_PATH="$W/fakebin:$BUILD"
	comp_start "$@" QT_QUICK_BACKEND=software FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="${SHELLDIR:-$SH}" PHONEGLUEWC_FAKETOUCH="$W/script"
	# a crash fails inside comp_wait and comp_stop; the long touch script needs more than 3 minutes on a loaded machine
	comp_wait 4000
	comp_stop
	mv "$W/gw.log" "$W/$n.log"
}

# the whole of it, at one size through one input
moves() {
	echo "w 3000"; rss "$1 closed"; open; mk s0; shot "$1-open"; rss "$1 open"
	# to every position in turn, and back to the first
	local i
	for i in 1 2 3 4 5; do pick $(slot $((i-1))) $(slot $i); mk "d$i"; keep "$1-d$i"; done
	carry $(slot 5) $(slot 2); shot "$1-carried"; mk carried; up; echo "w 600"; keep "$1-d6"
	pick $(slot 2) $(slot 0); mk d7; keep "$1-d7"
	# dropped anywhere else: home again, panel open
	pick $(slot 0) $EMPTY; mk out1; keep "$1-out1"
	pick $(slot 0) 0.5 0.01; mk out2; keep "$1-out2"
	echo "x sh -c 'wc -l <$W/fake/calls.log >$W/$1-calls0'"; echo "w 100"
	pick $(slot 0) 0.5 $BRIGHT; mk out3; keep "$1-out3"
	pick $(slot 0) 0.5 $VOL; mk out4; keep "$1-out4"
	echo "x sh -c 'wc -l <$W/fake/calls.log >$W/$1-calls1'"; echo "w 100"
	# a quick throw upward after resting: was a swipe that closes
	down $(slot 0); echo "w 320"; walk $(slot 0) 0.267 0.05 5 16; up; echo "w 900"; mk thrown; keep "$1-out5"
	# resting on something that cannot move, a small shift, letting go; under the 650 ms hold that opens settings
	# 0.62 was the page dots, whose tap turns the page
	holdat 0.15 0.1 450; mk rest1; holdat $EMPTY; mk rest2; holdat 0.5 0.66; mk rest3
	shot "$1-after"; mk still
	# sideways: the tiles first, then the panels
	swipe $R1 0.8 0.3; mk page1; shot "$1-page2"
	swipe $R1 0.3 0.8; mk page0
	swipe $R1 0.3 0.8; mk swapped; shot "$1-swapped"; swipe 0.75 0.8 0.3; mk back
	swipe 0.135 0.2 0.7; mk swapbig; shot "$1-swapbig"; swipe 0.75 0.8 0.3; mk back2
	# rest at the edge with a tile: the page turns under it, every 500 ms while it rests
	carry $(slot 1) 0.975 $R1; echo "w 900"; mk edge; shot "$1-edge"; up; echo "w 600"; keep "$1-edge"; mk edged
	swipe $R1 0.3 0.8
	# reorder mode
	t $PENCIL 500; mk edit; shot "$1-edit"
	swipe 0.8 0.8 0.3; mk e-noswap; shot "$1-noswap"
	down $EMPTY; walk 0.5 0.8 0.5 0.5 4 16; up; echo "w 700"; mk e-noclose
	t $EMPTY; mk e-notap
	pick $(slot 3) $(slot 1) 0; mk e-now; keep "$1-e-now"
	t 0.46 0.374 500; keep "$1-e-removed"
	t 0.267 0.722 500; keep "$1-e-added"; shot "$1-added"
	pick 0.5 $VOL 0.5 0.235 0; mk b1; keep "$1-b1"; shot "$1-b1"
	pick 0.25 0.135 0.25 0.52 0; mk b2; keep "$1-b2"; shot "$1-b2"
	t 0.837 0.954 500; mk e-done; shot "$1-done"
	# closed and open again
	t $EMPTY 900; mk closed; rss "$1 closed2"; open; mk reopen; shot "$1-reopen"
	# holding a tile with a page, not moving, is its settings; and that closes
	echo "x sh -c 'echo $1 >>$W/set.log'"; echo "w 100"
}
: >"$CONF"; { moves touch; down $(slot 0); echo "w 900"; up; echo "w 900"; mk held; } >"$W/script"
MODE=touch; { moves touch; down $(slot 0); echo "w 900"; up; echo "w 900"; mk held; } >"$W/script"
run touch 1080x2400 2.75
cp "$CONF" "$W/touch-final"
# a new life of the shell: the order is still there
MODE=touch; { echo "w 3000"; open; mk open; shot restart; } >"$W/script"
run restart 1080x2400 2.75
: >"$CONF"
MODE=mouse; { moves mouse; down $(slot 0); echo "w 900"; up; echo "w 900"; mk held; } >"$W/script"
run mouse 450x1000 1.15 PHONEGLUEWC_MOUSE_FINGER=1 PHONE_NO_HOLE=1 PHONE_CAMERA=center
cp "$CONF" "$W/mouse-final"
# names nobody knows, written by hand, in both lists
printf 'quick_tiles = bogus, airplane ,data,,nope\nquick_blocks = nope,volume\n' >"$CONF"
MODE=touch; { echo "w 3000"; open; mk open; shot unknown; pick $(slot 0) $(slot 1); mk moved; keep unknown-after; } >"$W/script"
run unknown 1080x2400 2.75
rm -f "$CONF"

# ---- the limits, active apps list ----
closeb() { t 0.806 "$(awk "BEGIN { printf \"%.4f\", (124 + 72 * $1) / 872.7 }")" "${2:-700}"; }
rowt() { awk "BEGIN { printf \"%.4f\", (124 + 72 * $1) / 872.7 }"; }
# 1: no usable icon: our letter, never the checker
{ echo "w 3000"; fake -t sample.badname -B; fake -t sample.nothing -E; echo "w 1500"; open; t 0.15 0.954 900; shot lim-icons; mk icons; } >"$W/script"
run icons 1080x2400 2.75
# the control run below takes the same shot
mv "$W/lim-icons.ppm" "$W/lim-icons-ours.ppm"
cp -a "$SH" "$W/shell-c"; python3 - "$W/shell-c/AppList.qml" <<'P'
import sys
s=open(sys.argv[1]).read(); assert 'root.goodTray(row.modelData.trayIcon)' in s
s=s.replace('root.goodTray(row.modelData.trayIcon) ? row.modelData.trayIcon : ""','row.modelData.trayIcon').replace(' && root.goodTray(row.modelData.trayIcon)','')
open(sys.argv[1],'w').write(s)
P
SHELLDIR=$W/shell-c run icons-control 1080x2400 2.75
# 2: tap Close, shut the panel at once: the fallback TERM still goes
{ echo "w 3000"; fake -t sample.term; echo "w 1500"; open; t 0.15 0.954 900; closeb 0 60; t 0.1 0.0688 60; t $EMPTY 900; mk shut; echo "w 2500"; mk later; } >"$W/script"
run term 1080x2400 2.75
# 3: the list changes under a pressed row: nothing moves until the finger lifts, the tap hits what was pressed
{ echo "w 3000"; fake -a sample.mid -n 1; fake -a sample.zed -n 1; echo "w 1500"; open; t 0.15 0.954 900; mk before; shot lim-before
  down 0.4 "$(rowt 0)"; echo "w 100"; mk pressed; fake -a sample.aaa -n 1; echo "w 3800"; shot lim-during; mk during; up; echo "w 900"; mk tapped; shot lim-after; } >"$W/script"
run shift 1080x2400 2.75
for p in $(awk '$2=="start" { print $3 }' "$W/fake.log" 2>/dev/null); do
	[ "$(cat /proc/$p/comm 2>/dev/null)" = fakeapp ] && kill -9 "$p" 2>/dev/null
done

cp "$W"/*.log "$SHOTS/" 2>/dev/null; for f in "$W"/*.ppm; do magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
fails=0
ok() { if ( eval "$2" ); then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
panel() { grep "^FT $2 " "$W/$1.log" | grep -q " tray=$3 "; }
# the lowest the panel went between two marks, and the side it ended on
lowest() { python3 -I - "$W/$1.log" "$2" "$3" <<'P'
import sys,re
on=False; low=1.0
for l in open(sys.argv[1],errors="replace"):
    if l.startswith("FT "+sys.argv[2]+" "): on=True; continue
    if l.startswith("FT "+sys.argv[3]+" "): break
    m=re.search(r"PULL ([0-9.e-]+)",l)
    if on and m: low=min(low,float(m.group(1)))
print(low)
P
}
held() { [ "$(lowest "$1" "$2" "$3")" = 1.0 ]; }
lastk() { python3 -I - "$W/$1.log" "$2" "$3" <<'P'
import sys
last=""
for l in open(sys.argv[1],errors="replace"):
    if l.startswith("FT "+sys.argv[2]+" "): break
    if sys.argv[3]+" " in l and "qml" in l.lower(): last=l.split(sys.argv[3]+" ",1)[1].strip()
print(last)
P
}
tiles() { grep '^quick_tiles' "$W/$1" | sed 's/^[^=]*= *//' | tr , ' '; }
at() { tiles "$1" | awk -v want="$2" '{ for (i = 1; i <= NF; i++) if ($i == want) print i - 1 }'; }
same() { [ "$(tiles "$1")" = "$(tiles "$2")" ]; }
blocks() { grep '^quick_blocks' "$W/$1" | sed 's/^[^=]*= *//'; }
isqs() { [ "$(python3 -I "$W/m.py" "$W/$1.ppm")" -gt 0 ]; }
# the white of the power button at the bottom right: this panel, this view
cat >"$W/m.py" <<'P'
import sys
d=open(sys.argv[1],"rb").read(); p=d.split(None,4); W,H=int(p[1]),int(p[2]); b=d[-W*H*3:]
n=0
for r in range(int(H*.93),int(H*.98),2):
    for c in range(int(W*.84),int(W*.96),2):
        n+=b[(r*W+c)*3]>220
print(n)
P
for m in touch mouse; do
	for i in 1 2 3 4 5; do
		ok "$m: drag to position $i lands there" '[ "$(at "$m-d$i" data)" = "$i" ]'
	done
	ok "$m: carried: others made room, then back to the first" '[ "$(at "$m-d6" data)" = 2 ] && [ "$(at "$m-d7" data)" = 0 ]'
	ok "$m: the tile follows, the tile under it moved" '[ -s "$W/$m-carried.ppm" ]'
	ok "$m: panel never closed through all those drags" 'held $m s0 still && panel $m still 1'
	for o in 1 2 3 4 5; do ok "$m: dropped outside ($o): order as it was" 'same "$m-d7" "$m-out$o"'; done
	# the panel's 3 s status poll also writes calls.log, so only a set counts
	ok "$m: dropping on the sliders moved neither" '! sed -n "$(($(cat "$W/$m-calls0")+1)),$(cat "$W/$m-calls1")p" "$W/fake/calls.log" | grep -q "set-volume\|brightnessctl.* set "'
	ok "$m: the quick throw up did not close it" 'panel $m thrown 1'
	ok "$m: rest and small shift keeps it open, everywhere" 'panel $m rest1 1 && panel $m rest2 1 && panel $m rest3 1 && isqs "$m-after"'
	ok "$m: a sideways swipe on the tiles turns the page" '[ "$(lastk $m page1 PAGE)" = 1 ] && panel $m page1 1 && isqs "$m-page2"'
	ok "$m: and back, then the panels swap from page one" '[ "$(lastk $m page0 PAGE)" = 0 ] && ! isqs "$m-swapped"'
	ok "$m: elsewhere the swipe swaps the panels" '! isqs "$m-swapbig"'
	ok "$m: resting at the edge turns the page, tile goes there" '[ "$(lastk $m edge PAGE)" -ge 1 ] && { [ "$(at "$m-edge" airplane)" -ge 6 ] || [ "$(at "$m-edge" data)" -ge 6 ]; }'
	ok "$m: reorder mode: no swap, no close, no tap-close" 'panel $m e-noswap 1 && panel $m e-noclose 1 && panel $m e-notap 1 && held $m edit e-done'
	ok "$m: reorder mode: drags at once" '! same "$m-edge" "$m-e-now"'
	ok "$m: reorder mode: minus removes, plus adds" '[ "$(tiles "$m-e-removed" | wc -w)" = $(($(tiles "$m-e-now" | wc -w) - 1)) ] && [ "$(tiles "$m-e-added" | wc -w)" = "$(tiles "$m-e-now" | wc -w)" ] && ! same "$m-e-removed" "$m-e-added"'
	ok "$m: volume moved above brightness" 'b=$(blocks "$m-b1"); [ "${b%%,*}" = big ] && case "$b" in *volume,brightness*) ;; *) false ;; esac'
	ok "$m: the two big tiles moved down" '[ "$(blocks "$m-b2" | cut -d, -f1)" != big ]'
	ok "$m: closes and reopens with the order" 'panel $m closed 0 && panel $m reopen 1'
	# plus put data last, so the held tile varies; statusbar-test checks each tile's page
	ok "$m: holding a tile without moving: its settings, closed" 'panel $m held 0 && awk -v m=$m "\$0 == m { on = 1; next } /^(touch|mouse)\$/ { on = 0 } on && /^settings [a-z]/" "$W/set.log" | grep -q .'
done
ok "after a shell restart the order is the same" '[ "$(lastk restart open IDS | cut -d" " -f1-5)" = "$(tiles touch-final | cut -d" " -f1-5)" ]'
ok "the blocks too: saved, atomically by the conf writer" '[ "$(blocks touch-final)" = "$(blocks touch-b2)" ]'
ok "unknown names are ignored, the known ones keep order" '[ "$(lastk unknown open IDS | cut -d" " -f1-2)" = "airplane data" ]'
ok "and moving after that saves only known names" '[ "$(at unknown-after airplane)" = 1 ] && ! tiles unknown-after | grep -qE "bogus|nope"'
magenta() { python3 -I - "$1" <<'P'
import sys
d=open(sys.argv[1],"rb").read(); p=d.split(None,4); W,H=int(p[1]),int(p[2]); b=d[-W*H*3:]
print(sum(b[i]>200 and b[i+1]<60 and b[i+2]>200 for i in range(0,len(b),3)))
P
}
ok "limit 1: a tray item with no usable icon draws no checker" '[ "$(magenta "$W/lim-icons-ours.ppm")" = 0 ] && [ "$(magenta "$W/lim-icons.ppm")" -gt 0 ]'
ok "limit 2: panel shut soon after Close: TERM still sent" 'panel term shut 0 && grep -q "^sample.term term" "$W/fake.log"'
ok "limit 3: the list changed during the press" 'grep ROWS "$W/shift.log" | grep -q "sample.aaa"'
ok "limit 3: nothing moved under the finger" 'cmp -s "$W/lim-before.ppm" "$W/lim-during.ppm"'
ok "limit 3: the tap hit the pressed row" 'grep "^FT tapped " "$W/shift.log" | grep -q "focus=sample.mid"'
ok "no power action in any of this" '[ ! -e "$W/power.log" ]'
ok "no compositor crash" '[ ! -e "$W/crashes" ]'
for n in touch restart mouse unknown icons term shift; do
	ok "no QML error ($n)" '! grep -E "ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|file://.*qml:[0-9]+" "$W/$n.log" | grep -q .'
done
ok "no core files" '! ls "$W"/core.* >/dev/null 2>&1'
cat "$W/rss"
echo "control, checker pixels without the check: $(magenta "$W/lim-icons.ppm")"
[ "$fails" = 0 ] && { echo "all passed"; exit 0; }; echo "$fails failed"; exit 1
