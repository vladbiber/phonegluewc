#!/bin/bash
# The top bar and quick panel at phone size, headless, on stubbed radios and a fake /sys. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
REALHOME=$HOME
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-bar.XXXXXX")
SANDBOX_EXTRA="timeout notify-send date mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
# the log's tray= field reports the quick panel in this copy
sed -i 's/ft_layer("phone-tray")/ft_layer("phone-panel")/' "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
cc -w -I"$BUILD" -o "$W/fakeapp" "$SRC/tests/fakeapp.c" "$BUILD/touchlog-xdg-protocol.c" $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0) -lwayland-client || { echo "FAIL fakeapp"; exit 1; }

mkdir -p "$W/cfg/phonegluewc" "$W/state/phonegluewc" "$W/nosys"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' > "$W/cfg/phonegluewc/config.conf"
# the pixel counts below are measured over Black, not the shipped default wallpaper
echo "wallpaper = " >"$W/cfg/phonegluewc/phone.conf"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" rx="12" fill="#20c060"/></svg>\n' >"$W/icon.svg"

# fake /sys
S=$W/sys; mkdir -p "$S/power_supply/BAT0" "$S/backlight/panel" "$S/leds/white:torch" "$S/leds/aw20036:white"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
echo 1000 >"$S/backlight/panel/max_brightness"; echo 500 >"$S/backlight/panel/brightness"; echo 0 >"$S/leds/white:torch/brightness"; echo 0 >"$S/leds/aw20036:white/brightness"

# radios and sound that only remember what they were told; every call lands in $L
L=$W/calls; ST=$W/stub; mkdir -p "$ST" "$W/stubs"
: >"$L"; echo enabled >"$ST/wifi"; echo connected >"$ST/gsm"; echo yes >"$ST/bt"; echo 0 >"$ST/mute"; echo 0.40 >"$ST/vol"
for r in wlan bluetooth nfc gps; do echo unblocked >"$ST/rf_$r"; done; echo off >"$ST/hotspot"; echo "'default'" >"$ST/dark"; echo balanced >"$ST/profile"
stub() { { echo '#!/bin/sh'; echo "L='$L' ST='$ST' S='$S'"; cat; } >"$W/stubs/$1"; chmod +x "$W/stubs/$1"; }
stub nmcli <<'X'
case "$*" in
"-t -f TYPE,STATE,CONNECTION dev") [ "$(cat $ST/wifi)" = enabled ] && echo 'wifi:connected:Test\: Net' || echo 'wifi:unavailable:'; echo "gsm:$(cat $ST/gsm):Carrier" ;;
"-t -f WIFI radio") cat $ST/wifi ;;
"-t -f ACTIVE,SIGNAL dev wifi list --rescan no") echo no:40; echo yes:72 ;;
"-t -f NAME,TYPE con show") echo 'Test\: Net:802-11-wireless'; echo Carrier:gsm ;;
"radio wifi off") echo "nmcli $*" >>$L; echo disabled >$ST/wifi ;;
"radio wifi on") echo "nmcli $*" >>$L; echo enabled >$ST/wifi ;;
"con down id Carrier") echo "nmcli $*" >>$L; echo disconnected >$ST/gsm ;;
"con up id Carrier") echo "nmcli $*" >>$L; echo connected >$ST/gsm ;;
"-t -f DEVICE,TYPE dev") echo wlan0:wifi; echo rmnet0:gsm ;;
"-g WIFI-PROPERTIES.AP dev show wlan0") echo yes ;;
"-t -f NAME,TYPE con show --active") echo Carrier:gsm ;;
"-t -f NAME con show --active") [ "$(cat $ST/hotspot)" = on ] && echo Hotspot; echo Carrier ;;
"device wifi hotspot") echo "nmcli $*" >>$L; echo on >$ST/hotspot ;;
"con down Hotspot") echo "nmcli $*" >>$L; echo off >$ST/hotspot ;;
*) echo "UNEXPECTED nmcli $*" >>$L ;;
esac
X
stub mmcli <<'X'
echo 'modem.generic.signal-quality.value : 75'; echo 'modem.3gpp.operator-name : Carrier'
X
stub bluetoothctl <<'X'
case "$*" in
show) printf 'Controller 00:00:00:00:00:00\n\tPowered: %s\n' "$(cat $ST/bt)" ;;
"devices Connected") echo 'Device 00:00:00:00:00:01 Test Buds' ;;
"power on") echo "bluetoothctl $*" >>$L; echo yes >$ST/bt ;;
"power off") echo "bluetoothctl $*" >>$L; echo no >$ST/bt ;;
*) echo "UNEXPECTED bluetoothctl $*" >>$L ;;
esac
X
stub wpctl <<'X'
case "$1" in
get-volume) [ "$(cat $ST/mute)" = 1 ] && echo "Volume: $(cat $ST/vol) [MUTED]" || echo "Volume: $(cat $ST/vol)" ;;
set-volume) echo "wpctl $*" >>$L; v=${3%\%}; echo "0.$v" >$ST/vol ;;
set-mute) echo "wpctl $*" >>$L
	case "$3" in toggle) [ "$(cat $ST/mute)" = 1 ] && echo 0 >$ST/mute || echo 1 >$ST/mute ;; *) echo "$3" >$ST/mute ;; esac ;;
set-default) echo "wpctl $*" >>$L ;;
status) cat <<S
PipeWire 'pipewire-0'
 └─ Clients:
        30. sample
Audio
 ├─ Devices:
 │      40. Sample Device  [alsa]
 ├─ Sinks:
 │  *   51. Speaker  [vol: 0.40]
 │      52. Test Buds  [vol: 0.70]
 ├─ Sources:
 │      60. Microphone
Video
 ├─ Sinks:
 │      70. Not Audio
S
;;
esac
X
stub brightnessctl <<'X'
echo "brightnessctl $*" >>$L
case "$*" in *white:torch*) case "$*" in *100%) echo 1 >"$S/leds/white:torch/brightness" ;; *) echo 0 >"$S/leds/white:torch/brightness" ;; esac ;; esac
case "$*" in *aw20036*) case "$*" in *100%) echo 255 >"$S/leds/aw20036:white/brightness" ;; *) echo 0 >"$S/leds/aw20036:white/brightness" ;; esac ;; esac
X
stub rfkill <<'X'
case "$*" in
"-rn -o TYPE,SOFT") for r in wlan bluetooth nfc gps; do echo "$r $(cat $ST/rf_$r)"; done; exit 0 ;;
"block all") for r in wlan bluetooth nfc gps; do echo blocked >$ST/rf_$r; done ;;
"unblock all") for r in wlan bluetooth nfc gps; do echo unblocked >$ST/rf_$r; done ;;
"block nfc"|"block gps") echo blocked >$ST/rf_$2 ;;
"unblock nfc"|"unblock gps"|"unblock bluetooth") echo unblocked >$ST/rf_$2 ;;
*) echo "UNEXPECTED rfkill $*" >>$L; exit 0 ;;
esac
echo "rfkill $*" >>$L
X
stub gsettings <<'X'
case "$*" in
"get org.gnome.desktop.interface color-scheme") cat $ST/dark ;;
"set org.gnome.desktop.interface color-scheme "*) echo "gsettings $*" >>$L; echo "'$4'" >$ST/dark ;;
*) echo "UNEXPECTED gsettings $*" >>$L ;;
esac
X
stub powerprofilesctl <<'X'
case "$1" in get) cat $ST/profile ;; set) echo "powerprofilesctl $*" >>$L; echo "$2" >$ST/profile ;; esac
X
# long running tools end by themselves: nothing a test started outlives it for long
long() { stub "$1" <<X
trap 'echo "$1 $2" >>\$L; exit 0' $2
echo "$1 \$*" >>\$L
i=0; while [ \$i -lt 400 ]; do sleep 0.2; i=\$((i+1)); done
X
}
long wlsunset TERM; long wf-recorder INT
for p in grim fbcli paplay; do stub $p <<'X'
echo "${0##*/} $*" >>$L
X
done
stub phonesettings <<'X'
echo "phonesettings $*" >>$L
X
for p in systemctl loginctl reboot poweroff shutdown halt suspend rtcwake; do stub $p <<'X'
echo "POWER $0 $*" >>$L
X
done

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-700}"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
# drag down from the bar to fraction $1 of the screen, finger still on the glass
pullto() { local x=${2:-0.75}; echo "d 0 $x 0.02"; echo f; python3 -c "
for s in range(1,9): print('m 0 $x %.3f\nf\nw 30' % (0.02+($1-0.02)*s/8))"; echo "w 200"; }
# the right half opens quick settings, the left half notifications
pull() { pullto 0.55; echo "u 0"; echo f; echo "w 800"; }
pulln() { pullto 0.55 0.25; echo "u 0"; echo f; echo "w 800"; }
# flick X Y0 Y1: no rest before the finger lifts
flick() { echo "d 0 $1 $2"; echo f; python3 -c "
for s in range(1,5): print('m 0 $1 %.3f\nf' % ($2+($3-$2)*s/4))"; echo "u 0"; echo f; echo "w 800"; }
# sideways: swipe Y X0 X1, swipen rests before lifting, flicks do not
flickx() { echo "d 0 $2 $1"; echo f; python3 -c "
for s in range(1,5): print('m 0 %.3f $1\nf' % ($2+($3-$2)*s/4))"; echo "u 0"; echo f; echo "w 800"; }
swipex() { echo "d 0 $2 $1"; echo f; python3 -c "
for s in range(1,9): print('m 0 %.3f $1\nf\nw 30' % ($2+($3-$2)*s/8))"; echo "w 200"; echo "u 0"; echo f; echo "w 800"; }
swipey() { echo "d 0 0.5 $1"; echo f; python3 -c "
for s in range(1,9): print('m 0 0.5 %.3f\nf\nw 30' % ($1+($2-$1)*s/8))"; echo "w 200"; echo "u 0"; echo f; echo "w 800"; }
# horizontal drag along a slider at height $1 from x $2 to $3
slide() { echo "d 0 $2 $1"; echo f; python3 -c "
for s in range(1,7): print('m 0 %.3f $1\nf' % ($2+($3-$2)*s/6))"; echo "u 0"; echo f; echo "w 700"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w 1100"; echo "u 0"; echo f; echo "w 800"; }
notify() { echo "x notify-send -a '$1' -i '$W/icon.svg' '$2' '$3'"; echo "w 500"; }
cat >"$W/rss.sh" <<EOF
p=\$(cat "$W/pid"); q=\$(pgrep -P \$p -x qs)
echo "\$1 \$2 pid=\$q qs=\$(awk '/VmRSS/{print \$2}' /proc/\$q/status 2>/dev/null) kB" >>"$W/rss"
EOF
rss() { echo "w 1500"; echo "x sh $W/rss.sh $1 $2"; echo "w 300"; }

COMP=$BUILD/phonegluewc
# run NAME SHELLDIR SYSDIR PATH: one compositor life through $W/script; a crash ends the test
run() {
	# SCENES="a b": only those, while working on them; a run like that is not a result
	case " ${SCENES:-$1} " in *" $1 "*) ;; *) return ;; esac
	SANDBOX_PATH="$4"
	comp_start ${RUN_ENV:-} QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$2" PHONE_SYS_DIR="$3" PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 1800
	comp_stop
	mv "$W/gw.log" "$W/$1.log"
}

# ---- baseline: the same shell without the bar, measured the same way ----
cp -a "$SRC/shell" "$W/shell-base"
python3 -c "
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r' *StatusBar \{[^\n]*\n *LazyLoader \{\n[^\n]*panelLoaded\n[^\n]*\n *\}\n','',s)
s=re.sub(r' *LazyLoader \{\n[^\n]*rotateOffer[^\n]*\n[^\n]*RotateButton[^\n]*\n *\}\n','',s)
s=re.sub(r' *IpcHandler \{\n *target: \"charge\"\n(?:[^\n]*\n)*? *\}\n','',s)
s=re.sub(r' *LazyLoader \{\n[^\n]*chargeShowing(?:[^\n]*\n)*?[^\n]*ChargeAnim[^\n]*\n *\}\n *\}\n','',s)
open(p,'w').write(s)" "$W/shell-base/shell.qml"
grep -q 'Status' "$W/shell-base/shell.qml" && { echo "FAIL baseline still loads the bar"; exit 1; }
{ echo "w 3000"; rss base idle; } >"$W/script"
run base "$W/shell-base" "$S" "$BUILD:$W/stubs"

# ---- nothing to report: no tools, empty /sys ----
{ echo "w 3000"; shot empty-bar; pull; echo "p e-open"; shot empty-panel; rss empty open; t 0.5 0.8 900; echo "p e-closed"; pulln; shot empty-notif; t 0.5 0.8 900; } >"$W/script"
run empty "$SRC/shell" "$W/nosys" "$BUILD"

# ---- everything present ----
echo 0 >"$W/state/phonegluewc/rotation-lock"; echo normal >"$W/state/phonegluewc/orientation"
{ echo "w 3000"; echo "x sh $SRC/tests/sandbox-probe.sh >$W/probe.txt 2>&1"; rss all idle; shot bar
  # the bar alone does not open anything; a short pull falls back
  t 0.5 0.02; echo "p tap"; pullto 0.08; echo "p short-held"; echo "u 0"; echo f; echo "w 800"; echo "p short"
  pullto 0.2; echo "p following"; shot following; echo "u 0"; echo f; echo "w 800"; echo "p slow-short"
  pullto 0.45; echo "u 0"; echo f; echo "w 800"; echo "p long"; shot panel-empty; rss all open; t 0.5 0.8 900; echo "p tapclosed"; rss all closed
  # release by velocity: a short flick opens, a flick back closes from past the limit
  flick 0.75 0.02 0.14; echo "p flick-open"; shot flick-open; t 0.5 0.8 900
  pullto 0.6; echo "p held-open"; for y in 0.56 0.52 0.48 0.44; do echo "m 0 0.75 $y"; echo f; done; echo "u 0"; echo f; echo "w 800"; echo "p flick-back"
  # where the swipe starts picks the view, the camera hole counts as left
  pullto 0.55 0.107; echo "u 0"; echo f; echo "w 800"; shot from-hole; t 0.5 0.8 900
  notify Messages 'Sample title' 'Sample body text'; notify Messages 'Second title' 'Second body'; notify Calendar 'Team lunch' 'Twelve thirty'; echo "w 5500"; shot bar-notif
  pulln; echo "p n-open"; shot notifications
  # sideways: short and slow falls back, past half or a flick switches, both ways
  swipex 0.75 0.8 0.6; shot x-short; swipex 0.75 0.9 0.2; shot x-long; flickx 0.75 0.2 0.5; shot x-flick; flickx 0.75 0.8 0.5; shot x-flick2; echo "p x-still"
  t 0.5 0.8 900; pull; echo "p open"; shot panel
  # from a big tile: a swipe switches views and toggles nothing
  echo "x wc -l <$L >$W/before-swipe"; echo "w 300"; flickx 0.135 0.2 0.5; shot x-tile; echo "x wc -l <$L >$W/after-swipe"; echo "w 300"; flickx 0.75 0.8 0.5
  # tiles, each twice where the second tap proves the first came back through the poll
  t 0.25 0.135 4000; t 0.25 0.135 4000
  t 0.75 0.135 4000; t 0.75 0.135 4000
  t 0.267 0.3985 4000; t 0.267 0.5635 4000; t 0.267 0.5635 4000
  # rotation is first on the second page of tiles
  flickx 0.481 0.8 0.3; t 0.267 0.3985 1000; flickx 0.481 0.3 0.8
  slide 0.2585 0.3 0.54; slide 0.3225 0.3 0.474; shot x-slider; t 0.08 0.3225 4000; shot muted
  slide 0.2585 0.5 0.1
  hold 0.25 0.135; echo "p held"; pull; t 0.757 0.954 800; echo "p geared"
  pulln; t 0.878 0.947 700; shot cleared; echo "p still-open"; t 0.5 0.8 900
  # swipe up: a slow short one stays, a long one or a short flick closes, and it works from a tile; the pill closes
  pull; swipey 0.8 0.72; echo "p up-short"; swipey 0.8 0.3; echo "p swiped"
  pull; flick 0.5 0.8 0.7; echo "p up-flick"
  pull; echo "x wc -l <$L >$W/before-up"; echo "w 300"; flick 0.267 0.3985 0.1; echo "p up-tile"; echo "x wc -l <$L >$W/after-up"; echo "w 300"
  pull; t 0.5 0.995 900; echo "p pilled"
  # a window starts below the bar, and only the bar takes touch up there
  echo "x exec $W/touchlog >>$W/tl.log 2>&1"; echo "w 1200"; shot window; t 0.1 0.03; echo "x echo BAR >>$W/tl.log"; echo "w 200"; t 0.5 0.3; echo "w 300"
  pullto 0.5; shot half-window; echo "u 0"; echo f; echo "w 800"; echo "p over-window"; shot over-window; t 0.5 0.8 900
  rss all end; } >"$W/script"
run all "$SRC/shell" "$S" "$BUILD:$W/stubs"
cp "$L" "$W/all-calls"
cp "$W/state/phonegluewc/rotation-lock" "$W/rotation-after"

# ---- the rotate offer: an old one at start stays quiet, a new one shows a button for a few seconds ----
mkdir -p "$W/stubs-rot"
printf '#!/bin/sh\n[ "$1" = rotate ] && { echo "msg $*" >>%s; exit 0; }\nexec %s/phonegluewc-msg "$@"\n' "$L" "$BUILD" >"$W/stubs-rot/phonegluewc-msg"
chmod +x "$W/stubs-rot/phonegluewc-msg"
OF=$W/state/phonegluewc/rotate-offer; echo "0 90" >"$OF"
mark() { echo "x echo $1 >>$L"; echo "w 100"; }
{ echo "w 3000"; mark O0; t 0.8829 0.8877; mark O1
  echo "x echo 1 90 >$OF"; echo "w 800"; shot rot-90; t 0.8829 0.8877; mark O2
  echo "x echo 2 270 >$OF"; echo "w 800"; shot rot-270; echo "w 4500"; shot rot-gone; t 0.1171 0.8877; mark O3
  echo "x echo 3 180 >$OF"; echo "w 800"; shot rot-180; t 0.5 0.8877; mark O4; } >"$W/script"
run rotate "$SRC/shell" "$S" "$W/stubs-rot:$BUILD:$W/stubs"

# ---- the same shell if the hole were centred: 540 minus the radius ----
cp -a "$SRC/shell" "$W/shell-mid"
sed -i 's/89.3 42.31/513.81 42.31/' "$W/shell-mid/camera-holes"
grep -q 513.81 "$W/shell-mid/camera-holes" || { echo "FAIL hole value not found"; exit 1; }
{ echo "w 3000"; for a in A B C D E F G H; do notify "App$a" Sample Text; done; shot mid-bar; pulln; shot mid-notif; flickx 0.75 0.8 0.5; shot mid-panel; rss mid open; } >"$W/script"
run mid "$W/shell-mid" "$S" "$BUILD:$W/stubs"

# ---- the laptop window's size and scale ----
printf 'remember_layout = false\noutput = * mode=450x1000 scale=1.15\n' > "$W/cfg/phonegluewc/config.conf"
{ echo "w 3000"; notify Messages Sample Text; shot lap-bar; pulln; shot lap-notif; flickx 0.75 0.8 0.5; shot lap-panel; rss lap open; } >"$W/script"
run lap "$SRC/shell" "$S" "$BUILD:$W/stubs"

# ---- the mouse as a finger, as on the laptop: both pulls, sideways, up, a tile ----
mdrag() { echo "M $1 $2"; echo "w 30"; echo "B 1"; echo "w 30"; python3 -c "
for s in range(1,9): print('M %.3f %.3f\nw 30' % ($1+($3-$1)*s/8, $2+($4-$2)*s/8))"; echo "w 200"; echo "B 0"; echo "w 800"; }
{ echo "w 3000"; notify Messages Sample Text; echo "w 5500"
  mdrag 0.25 0.015 0.25 0.6; echo "p m-left"; shot m-left; mdrag 0.8 0.75 0.2 0.75; shot m-switch
  mdrag 0.5 0.8 0.5 0.2; echo "p m-up"
  mdrag 0.75 0.015 0.75 0.6; echo "p m-right"; shot m-right; rss mouse open; echo "M 0.25 0.135"; echo "w 30"; echo "B 1"; echo "w 60"; echo "B 0"; echo "w 2000"; echo "M 0.5 0.8"; echo "w 30"; echo "B 1"; echo "w 60"; echo "B 0"; echo "w 900"; echo "p m-tap"; } >"$W/script"
N=$(wc -l <"$L")
RUN_ENV=PHONEGLUEWC_MOUSE_FINGER=1 run mouse "$SRC/shell" "$S" "$BUILD:$W/stubs"
tail -n +$((N+1)) "$L" >"$W/mouse-calls"

# ---- active apps: fake clients only, and every signal goes to a process this test started ----
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' > "$W/cfg/phonegluewc/config.conf"
cp -a "$SRC/shell" "$W/shell-apps"
sed -i 's|^    readonly property int count: rows.length|&\n    onRowsChanged: console.log(background ? "BGLIST " + JSON.stringify(rows.map(r => [r.name, r.kind, r.state])) : "ROWS " + JSON.stringify(rows.map(r => [r.name, r.state, r.windows.length, r.tray.length, r.pids.length])))|' "$W/shell-apps/AppModel.qml"
grep -q '"ROWS "' "$W/shell-apps/AppModel.qml" && grep -q '"BGLIST "' "$W/shell-apps/AppModel.qml" || { echo "FAIL rows log not injected"; exit 1; }
sed -i 's|^        text: "Tray apps " + Phone.runningCount$|&\n        onTextChanged: console.log("PILL " + text)\n        onVisibleChanged: console.log("PILL " + (visible ? text : "hidden"))|' "$W/shell-apps/Tray.qml"
grep -q '"PILL "' "$W/shell-apps/Tray.qml" || { echo "FAIL pill log not injected"; exit 1; }
cat >"$W/appstate.sh" <<EOF
pid=\$(awk -v n="\$1" '\$1==n && \$2=="start" { print \$3; exit }' "$W/fake.log")
if [ -n "\$pid" ] && [ -r /proc/\$pid/stat ] && [ "\$(sed 's/.*) //' /proc/\$pid/stat | awk '{ print \$1 }')" != Z ]; then
	echo "\$2 \$1 alive" >>"$W/alive"
	[ "\$3" = kill ] && [ "\$(cat /proc/\$pid/comm)" = fakeapp ] && kill "\$pid"
else
	echo "\$2 \$1 gone" >>"$W/alive"
fi
EOF
# through a script: the hook's script lines are short and a long one loses its last flags
printf '#!/bin/sh\nFAKEAPP_LOG="%s/fake.log" exec "%s/fakeapp" "$@"\n' "$W" "$W" >"$W/f"; chmod +x "$W/f"
fake() { echo "x exec $W/f $*"; echo "w 500"; }
note() { echo "x sh $W/appstate.sh $1 $2 ${3:-}"; echo "w 150"; echo "p $2"; }
rowy() { awk "BEGIN { printf \"%.4f\", (124 + 72 * $1) / 872.7 }"; }
closeb() { t 0.806 "$(rowy "$1")" "${2:-700}"; }
applist() { t 0.15 0.954 700; }
{ echo "w 3000"
  fake -a sample.notes -n 1; fake -a sample.multi -n 2; fake -a sample.both -n 1 -t sample.both
  fake -a sample.diffid -n 1 -t other.tray.id; fake -a sample.stubborn -n 1 -c -T; fake -a waydroid.sample -n 1 -c
  fake -a phonekbd -n 1; fake -t phonekbd
  fake -t sample.quit -m; fake -t sample.term; fake -t sample.traystuck -T
  echo "w 1500"; rss apps closed
  pull; echo "p button"; shot apps-button
  applist; echo "p list"; shot active-apps; rss apps open
  t 0.1 0.0688 600; shot apps-back; applist
  t 0.4 "$(rowy 0)" 900; echo "p activated"
  pull; applist
  closeb 0 1500; note sample.notes notes-closed
  # stubborn: a tap while it is still within the grace does nothing, Force stop comes later and needs its own tap
  closeb 3 500; note sample.stubborn st-closing; closeb 3 500; note sample.stubborn st-tapped
  echo "w 3500"; note sample.stubborn st-force; shot force-stop
  closeb 3 1500; note sample.stubborn st-killed
  closeb 3 4200; note waydroid.sample wd-after
  closeb 4 1500; note sample.quit quit-done
  closeb 4 2500; note sample.term term-done
  closeb 4 4200; note sample.traystuck ts-force; closeb 4 1500; note sample.traystuck ts-killed
  closeb 0 1500; note sample.multi multi-done
  closeb 0 4200; note sample.both both-force; closeb 2 1500; note sample.both both-killed
  note sample.diffid exiting kill; echo "w 1500"; note sample.diffid exited
  rss apps end; } >"$W/script"
run apps "$W/shell-apps" "$W/nosys" "$BUILD"

# ---- the overview's Tray apps pill: what runs without a window, each with Stop ----
# a fake VPN in nmcli, a fake background program under the one daemon name tests allow (sandbox.sh)
mkdir -p "$W/stubs-bg"
cat >"$W/stubs-bg/nmcli" <<EOF
#!/bin/sh
case "\$*" in
"-t -f NAME,TYPE connection show --active") [ -e "$W/vpn-down" ] || echo 'Test VPN:vpn'; echo 'Test\: Net:802-11-wireless' ;;
"connection down id Test VPN") echo "nmcli \$*" >>"$W/bg-calls"; : >"$W/vpn-down" ;;
esac
EOF
chmod +x "$W/stubs-bg/nmcli"
cp "$(command -v sleep)" "$W/phonetest-bgd"
cat >"$W/bgd.sh" <<EOF
[ "\$1" = start ] && { echo \$\$ >"$W/bgd.pid"; exec "$W/phonetest-bgd" 600; }
pid=\$(cat "$W/bgd.pid" 2>/dev/null)
if [ -n "\$pid" ] && [ "\$(cat /proc/\$pid/comm 2>/dev/null)" = phonetest-bgd ] && [ "\$(sed 's/.*) //' /proc/\$pid/stat | awk '{ print \$1 }')" != Z ]; then
	echo "\$2 bgd alive" >>"$W/alive"; [ "\$1" = kill ] && kill "\$pid"
else
	echo "\$2 bgd gone" >>"$W/alive"
fi
EOF
bgd() { echo "x sh $W/bgd.sh $1 $2"; echo "w 150"; echo "p $2"; }
{ echo "w 3000"
  fake -t sample.trayd; echo "w 1000"; fake -t sample.stuckbg -T; echo "w 1000"; fake -a sample.keep -n 1 -s; fake -a sample.win -n 1
  fake -a phonekbd -n 1; fake -t phonekbd; echo "x sh $W/bgd.sh start"; echo "w 1500"
  # the window of sample.keep closes from the footer's list; the process stays
  pull; applist; closeb 0 1500; note sample.keep keep-windowless
  t 0.1 0.0688 600; flick 0.5 0.8 0.7; echo "p bg-closed"
  y=0.995; echo "d 0 0.5 $y"; echo f; for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y-0.05,4))"); echo "m 0 0.5 $y"; echo f; done
  echo "w 250"; echo "u 0"; echo f; echo "w 3500"; echo "p bg-pill"; shot bg-pill
  t 0.176 0.9037 5000; echo "p bg-list"; shot bg-list; rss bgapps open
  # bottom up, so a row that leaves never moves the next one
  closeb 4 4000; echo "p vpn-down"
  closeb 3 1500; bgd state d-stopped
  closeb 2 1500; note sample.keep keep-stopped
  # the tray lists its newest icon first
  closeb 1 1500; note sample.trayd trayd-stopped
  closeb 0 500; note sample.stuckbg sb-stopping; echo "w 3500"; note sample.stuckbg sb-force; shot bg-force
  closeb 0 1500; note sample.stuckbg sb-killed
  echo "w 3500"; echo "p bg-empty"; shot bg-empty
  t 0.1 0.0688 900; echo "p bg-back"
  note sample.win win-kept; bgd kill bgd-left; } >"$W/script"
run bgapps "$W/shell-apps" "$W/nosys" "$BUILD:$W/stubs-bg"
# a missed Stop must not leave the fake program behind
p=$(cat "$W/bgd.pid" 2>/dev/null); [ -n "$p" ] && [ "$(cat /proc/$p/comm 2>/dev/null)" = phonetest-bgd ] && kill "$p"

# ---- every tile with fake tools, the log says which ones show ----
cp -a "$SRC/shell" "$W/shell-tiles"
sed -i 's|^    readonly property var ids: .*|&\n    onIdsKeyChanged: console.log("TILES " + idsKey)\n    onOrderChanged: console.log("ORDER " + order.join(" "))\n    Component.onCompleted: console.log("ORDER " + order.join(" "))|' "$W/shell-tiles/QuickModel.qml"
grep -q '"TILES "' "$W/shell-tiles/QuickModel.qml" || { echo "FAIL tiles log not injected"; exit 1; }
printf '#!/bin/sh\necho "app $1" >>%s\n' "$L" >"$W/appstub"; chmod +x "$W/appstub"
mkdir -p "$W/data/applications"
app() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s %s\nCategories=%s;\n' "$3" "$W/appstub" "$1" "$2" >"$W/data/applications/$1.desktop"; }
app s-calc Utility\;Calculator 'Sample Sums'; app s-clock Utility\;Clock 'Sample Time'; app s-cam Graphics\;Camera 'Sample Lens'; app s-qr Utility 'QR Reader'
app s-notes Office 'Sample Notes'; app localsend Network 'LocalSend'; app s-rec AudioVideo\;Recorder 'Sample Voice'
# tile N of the default order (row R, column C of five) sits on page N/6 of two columns and three rows
pullf() { pull; echo "w 1200"; CUR=0; }
qgo() { while [ "$CUR" -lt "$1" ]; do flickx 0.481 0.8 0.3; CUR=$((CUR+1)); done; while [ "$CUR" -gt "$1" ]; do flickx 0.481 0.3 0.8; CUR=$((CUR-1)); done; }
qxy() { local i=$((($1*5+$2)%6)); echo "$([ $((i%2)) = 0 ] && echo 0.267 || echo 0.733) $(echo "0.3985 0.481 0.5635" | cut -d" " -f$((i/2+1)))"; }
qt() { qgo $((($1*5+$2)/6)); t $(qxy "$1" "$2") "${3:-1400}"; }
qh() { qgo $((($1*5+$2)/6)); hold $(qxy "$1" "$2"); CUR=0; }
keep() { echo "x cp $W/cfg/phonegluewc/$1 $W/$2"; echo "w 100"; }
mark() { echo "x echo $1 >>$L"; echo "w 100"; }
PS="$BUILD/settings/pset"
# tf.sh [VALUE]: sets quick_tiles in phone.conf, or takes it out
printf 'f=%s/cfg/phonegluewc/phone.conf\ngrep -v "^quick_tiles" "$f" >"$f.t"; [ $# = 0 ] || echo "quick_tiles = $1" >>"$f.t"; mv "$f.t" "$f"\n' "$W" >"$W/tf.sh"
{ echo "w 3000"; pullf; echo "p full"; shot qs-full
  qt 0 0; qt 0 1; qt 0 1
  mark R1; qt 0 2; keep phone.conf r-vibrate; shot qs-vibrate; mark R2; qt 0 2; keep phone.conf r-silent; mark R3; qt 0 2; keep phone.conf r-normal; mark R4
  qt 0 3; keep phone.conf dnd-on; qt 0 3; keep phone.conf dnd-off
  qt 0 4; qt 0 4; qt 1 0; qt 1 0; qt 1 1; qt 1 2; qt 1 2; qt 1 3; shot qs-night; qt 1 3
  qt 2 1; qt 2 1; qt 2 2; qt 2 2; qt 2 3; qt 2 3; qt 2 4; qt 2 4
  # the tile asks first: Start, then a 3 second countdown
  qt 1 4 900; t 0.791 0.938 4500; echo "p rec-closed"; shot rec-bar; pullf; qt 1 4 1000
  qt 2 0 1500; echo "p shot-closed"; pullf
  for a in "3 0" "3 1" "3 2" "3 3" "3 4" "4 0" "4 1"; do qt $a 900; pullf; done
  qh 0 0; pullf; qh 0 2; pullf; qh 1 0; pullf; shot hr1; qh 1 1; echo "p hr1"; pullf; shot hr2; qh 1 2; echo "p hr2"; pullf; qh 2 1
  rss tiles closed
  # the order is a line of phone.conf; quick-test.sh does the dragging
  echo "x sh $W/tf.sh 'ringer, dnd,airplane'"; pull; echo "w 500"; echo "p reopened"; t 0.5 0.8 900
  echo "x sh $W/tf.sh garbage"; pull; echo "w 500"; echo "p corrupt"; t 0.5 0.8 900
  echo "x sh $W/tf.sh -"; pull; echo "w 500"; echo "p none"; shot no-tiles; t 0.5 0.8 900
  echo "x sh $W/tf.sh"; pull; echo "w 500"; echo "p removed"; t 0.5 0.8 900
  # the ringer set by the settings tool, and notifications obeying it
  echo "w 600"; mark A0; notify Sample one two; echo "w 900"; shot bar-normal
  echo "x $PS set phone ringer vibrate"; echo "w 800"; mark A1; notify Sample one two; echo "w 900"; shot bar-vibrate
  echo "x $PS set phone ringer silent"; echo "w 800"; mark A2; notify Sample one two; echo "w 900"; shot bar-silent
  echo "x $PS set phone ringer normal"; echo "w 800"; echo "x $PS set phone dnd on"; echo "w 800"; mark A3; notify Sample one two; echo "w 900"
  echo "x $PS set phone dnd off"; echo "w 800"; mark A4; notify Sample one two; echo "w 900"; mark A5
  # the battery's looks; touching the bar reads it again at once
  for b in "100 Discharging batt-100" "15 Discharging batt-15" "9 Charging batt-charge" "100 Charging batt-full"; do set -- $b
    echo "x echo $1 >$S/power_supply/BAT0/capacity"; echo "x echo $2 >$S/power_supply/BAT0/status"; t 0.5 0.02 1500; shot $3; done
  echo "x echo 62 >$S/power_supply/BAT0/capacity"; echo "x echo Discharging >$S/power_supply/BAT0/status"
  rss tiles end; } >"$W/script"
run tiles "$W/shell-tiles" "$S" "$BUILD:$W/stubs"
rm -rf "$W/data/applications"

# ---- a tool goes away, its tile goes with it ----
cp -a "$W/stubs" "$W/stubs-h"
{ echo "w 3000"; pull; echo "w 3500"; echo "p h-all"; shot hide-all
  for p in wf-recorder grim powerprofilesctl gsettings wlsunset rfkill nmcli paplay fbcli brightnessctl wpctl; do echo "x rm $W/stubs-h/$p"; echo "w 3700"; echo "p h-$p"; done
  shot hide-none; rss hide end; } >"$W/script"
run hide "$W/shell-tiles" "$S" "$BUILD:$W/stubs-h"

# ---- the other night light tool, and the real grim on the test compositor ----
mkdir -p "$W/stubs-g"; cp "$W/stubs/wlsunset" "$W/stubs-g/gammastep"; sed -i 's/wlsunset/gammastep/g' "$W/stubs-g/gammastep"
printf '#!/bin/sh\nexec %s "$@" 2>%s/grim.err\n' "$(command -v grim)" "$W" >"$W/stubs-g/grim"; chmod +x "$W/stubs-g/grim"
# the order is pinned, so the taps hold whatever tiles the shell adds: night top left, screenshot top right
{ echo "x sh $W/tf.sh night,screenshot"; echo "w 3000"; pull; echo "w 1200"; t 0.267 0.087 1400; shot gamma; t 0.267 0.087 1400; t 0.733 0.087 2500; echo "p grimmed"
  echo "x sh $W/tf.sh"; echo "w 300"; rss gamma end; } >"$W/script"
run gamma "$W/shell-tiles" "$W/nosys" "$BUILD:$W/stubs-g"

# ---- media controls and the output picker, with a fake player ----
{ echo "w 3000"; fake -a sample.player -P; echo "w 1000"; rss media closed; pull; echo "w 1500"; shot media; rss media open
  t 0.7555 0.7517 500; t 0.6537 0.7517 500; t 0.8676 0.7517 800; shot media-paused
  t 0.903 0.3225 500; shot sinks; t 0.5 0.8739 800; echo "p sink-picked"; shot sink-after; rss media end; } >"$W/script"
run media "$SRC/shell" "$S" "$BUILD:$W/stubs"

# ---- a screen too short for the full view: it scrolls, the bottom strip closes ----
printf 'remember_layout = false\noutput = * mode=540x960 scale=1.5\n' > "$W/cfg/phonegluewc/config.conf"
{ echo "w 3000"; pull; echo "w 1000"; shot small-compact; shot small-full; flick 0.5 0.7 0.5; echo "w 400"; shot small-scrolled; echo "p small-held"; flick 0.5 0.97 0.85; echo "p small-closed"; rss small end; } >"$W/script"
run small "$SRC/shell" "$S" "$BUILD:$W/stubs"

# ---- a wide clock face must still stay off the hole ----
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' > "$W/cfg/phonegluewc/config.conf"
cp -a "$SRC/shell" "$W/shell-wide"
sed -i 's/font.pixelSize: 14/font.pixelSize: 24/' "$W/shell-wide/StatusBar.qml"
grep -q 'pixelSize: 24' "$W/shell-wide/StatusBar.qml" || { echo "FAIL font value not found"; exit 1; }
{ echo "w 3000"; shot wide-bar; rss wide end; } >"$W/script"
run wide "$W/shell-wide" "$S" "$BUILD:$W/stubs"

# nothing a test started may outlive it; the name check keeps a reused pid safe
for p in $(awk '$2=="start" { print $3 }' "$W/fake.log" 2>/dev/null); do
	[ "$(cat /proc/$p/comm 2>/dev/null)" = fakeapp ] && kill -9 "$p" 2>/dev/null
done

cp "$W"/*.log "$W/fake.log" "$SHOTS/" 2>/dev/null; cp "$L" "$SHOTS/calls.txt"; cp "$W/grim.err" "$SHOTS/" 2>/dev/null
printf '%s\n' "$W"/*.ppm | SHOTS=$SHOTS xargs -P8 -I{} sh -c 'f={}; b=${f##*/}; magick "$f" "$SHOTS/${b%.ppm}.png"'
[ -n "${MEDIA:-}" ] && { cp "$SHOTS/bar-notif.png" "$SRC/docs/media/phone/statusbar.png"; cp "$SHOTS/panel.png" "$SRC/docs/media/phone/panel.png"; cp "$SHOTS/notifications.png" "$SRC/docs/media/phone/notifications.png"; cp "$SHOTS/active-apps.png" "$SHOTS/force-stop.png" "$SRC/docs/media/phone/"; }

fails=0
ok() { if ( eval "$2" ); then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
# panel= is the tray= field in this build
panel() { grep "^FT $2 " "$W/$1.log" | grep -q " tray=$3 "; }
called() { grep -qE "$1" "$L"; }
# px FILE X Y W H: how many pixels in that box are lighter than the near black sheet
px() { python3 -I - "$@" <<'P'
import sys
f,x,y,w,h=sys.argv[1],*map(int,sys.argv[2:6])
d=open(f,"rb").read(); p=d.split(None,4); W,H=int(p[1]),int(p[2]); b=d[-W*H*3:]
print(sum(max(b[(r*W+c)*3:(r*W+c)*3+3])>24 for r in range(y,y+h) for c in range(x,x+w)))
P
}
# which view a capture shows: notifications have nothing at top right, quick settings its status icons and the power button
isnotif() { [ "$(px "$W/$1.ppm" 150 0 400 99)" -gt 200 ] && [ "$(px "$W/$1.ppm" 950 0 130 99)" = 0 ]; }
isqs() { [ "$(px "$W/$1.ppm" 950 0 130 99)" -gt 50 ] && [ "$(px "$W/$1.ppm" 960 2230 100 100)" -gt 2000 ]; }
# the laptop size: the same corners at 450 wide
lapnotif() { [ "$(px "$W/$1.ppm" 60 0 160 40)" -gt 80 ] && [ "$(px "$W/$1.ppm" 395 0 55 40)" = 0 ]; }
lapqs() { [ "$(px "$W/$1.ppm" 395 0 55 40)" -gt 20 ] && [ "$(px "$W/$1.ppm" 400 930 40 40)" -gt 400 ]; }
# half-window at x=700: where the sheet ends going up from the window, and the dimmed grey there
edgeat() { python3 -I - "$W/$1.ppm" <<'P'
import sys
d=open(sys.argv[1],"rb").read(); p=d.split(None,4); W,H=int(p[1]),int(p[2]); b=d[-W*H*3:]
print(next((r+1 for r in range(1600,-1,-1) if max(b[(r*W+700)*3:(r*W+700)*3+3])<=24),-1))
P
}
greyat() { python3 -I - "$W/$1.ppm" <<'P'
import sys
d=open(sys.argv[1],"rb").read(); p=d.split(None,4); W,H=int(p[1]),int(p[2]); b=d[-W*H*3:]
print(b[(1600*W+700)*3])
P
}
green() { [ "$(python3 -I "$SRC/tests/colors.py" "$W/$1.ppm" 20c060)" = 1 ]; }
# 90,43 52x52 is the hole, 515,43 52x52 the centred one
hole_clear() { [ "$(px "$W/$1.ppm" 89 42 54 54)" = 0 ]; }
mid_clear() { [ "$(px "$W/$1.ppm" 513 42 54 54)" = 0 ]; }

ok "the sandbox holds no real path"    '! grep -E "^(HOME|PATH|TMPDIR|XDG_[A-Z_]*|DBUS_[A-Z_]*)=" "$W/probe.txt" | grep -qF "$REALHOME"'
ok "the compositor did not take wayland-0" 'grep -qx wayland-1 "$W/probe.txt" && ! grep -qx wayland-0 "$W/probe.txt"'
ok "no power command was ever called"  '! called "^POWER"'
ok "no unexpected radio command"       '! called "^UNEXPECTED"'
for r in base empty all mid lap mouse apps bgapps tiles hide gamma media small wide; do
	ok "qs stayed up, same process ($r)" '[ "$(grep "^$r " "$W/rss" | sed "s/.*pid=\([0-9]*\).*/\1/" | sort -u | grep -c "^[0-9]")" = 1 ] && ! grep -q "pid= " "$W/rss"'
	ok "no QML error ($r)" '! grep -E "ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|file://.*qml:[0-9]+" "$W/$r.log" | grep -q .'
done
ok "nothing is invented: the empty bar shows only the clock" '[ "$(px "$W/empty-bar.ppm" 400 0 680 99)" = 0 ]'
ok "nothing is invented: the empty panel has no tile or slider" '[ "$(px "$W/empty-panel.ppm" 0 420 1080 1600)" = 0 ]'
ok "no notifications: the words and no Clear" '[ "$(px "$W/empty-notif.ppm" 200 1100 680 200)" -gt 100 ] && [ "$(px "$W/empty-notif.ppm" 0 2200 1080 130)" = "$(px "$W/empty-notif.ppm" 400 2200 280 130)" ]'
ok "the panel opens and closes with nothing available" 'panel empty e-open 1 && panel empty e-closed 0'
ok "with data the bar shows icons"      '[ "$(px "$W/bar.ppm" 400 0 680 99)" -gt 200 ]'
ok "the clock is drawn"                 '[ "$(px "$W/bar.ppm" 150 0 250 99)" -gt 200 ]'
for s in bar bar-notif panel panel-empty notifications muted cleared; do ok "nothing under the camera hole ($s)" "hole_clear $s"; done
for s in mid-bar mid-panel mid-notif; do ok "nothing under a centred hole either ($s)" "mid_clear $s"; done
for s in lap-bar lap-panel lap-notif; do ok "nothing under the hole at laptop size ($s)" '[ "$(px "$W/$s.ppm" 37 17 23 23)" = 0 ]'; done
ok "a centred hole does not push icons out" '[ "$(px "$W/mid-bar.ppm" 600 0 480 99)" -gt 200 ]'
ok "a tap on the bar opens nothing"     'panel all tap 0'
ok "a short pull follows, then falls back" 'panel all short-held 1 && panel all short 0'
ok "the panel follows the finger"       'panel all following 1'
ok "a slow short pull falls back"       'panel all slow-short 0'
ok "a long pull stays open"             'panel all long 1'
ok "a tap on empty space closes, and it unloads" 'panel all tapclosed 0'
ok "a short flick opens"                'panel all flick-open 1 && isqs flick-open'
ok "a flick back closes from past the limit" 'panel all held-open 1 && panel all flick-back 0'
ok "right half pull: quick settings"    'isqs panel-empty && isqs panel'
ok "left half pull: notifications"      'isnotif notifications'
ok "a pull from the camera hole is left" 'isnotif from-hole'
ok "a slow short sideways swipe falls back" 'isnotif x-short'
ok "past half switches, and it keeps its side" 'isqs x-long'
ok "a sideways flick switches back, and forth" 'isnotif x-flick && isqs x-flick2'
ok "the panel stays open through switching" 'panel all x-still 1'
ok "a swipe from a tile switches and toggles nothing" 'isnotif x-tile && [ "$(cat "$W/before-swipe")" = "$(cat "$W/after-swipe")" ]'
ok "a slider drag does not switch"      'isqs x-slider'
ok "the sheet is under the finger, 1:1" '[ "$(edgeat half-window)" -ge 1140 ] && [ "$(edgeat half-window)" -le 1165 ]'
ok "what is behind dims in step"        'v=$(greyat half-window); [ "$v" -ge 80 ] && [ "$v" -le 105 ]'
ok "a real notification shows in the bar and the panel" 'green bar-notif && green notifications'
ok "the quick settings view has no notifications" '! green panel'
ok "clear empties the list, the panel stays" '! green cleared && panel all still-open 1'
ok "Wi-Fi tile: off, then on"           'called "^nmcli radio wifi off" && called "^nmcli radio wifi on"'
ok "Bluetooth tile: off, then on with rfkill" 'called "^bluetoothctl power off" && called "^rfkill unblock bluetooth" && called "^bluetoothctl power on"'
ok "mobile data goes through the profile" 'called "^nmcli con down id Carrier"'
ok "flashlight: on, then off"           'called "brightnessctl .*white:torch set 100%" && called "brightnessctl .*white:torch set 0"'
ok "rotation lock writes its file"      '[ "$(cat "$W/rotation-after")" = 1 ]'
ok "volume slider sets about half"      'called "^wpctl set-volume @DEFAULT_AUDIO_SINK@ (4[6-9]|5[0-3])%"'
ok "mute button"                        'called "^wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"'
ok "brightness slider sets about half"  'called "brightnessctl -q -d panel set (4[6-9]|5[0-3])%"'
ok "brightness cannot reach black"      '[ "$(grep -- "-d panel set" "$W/all-calls" | tail -1 | sed "s/.* //")" = 3% ]'
ok "a slider drag sends few commands"   '[ "$(grep -c "wpctl set-volume" "$L")" -le 3 ]'
ok "holding a tile opens its settings page, closes" 'called "^phonesettings wifi" && panel all held 0'
ok "the gear opens settings, closes"    'called "^phonesettings $" && panel all geared 0'
ok "a slow short swipe up stays open"   'panel all up-short 1'
ok "a swipe up closes"                  'panel all swiped 0'
ok "a short flick up closes"            'panel all up-flick 0'
ok "a flick up from a tile closes, no toggle" 'panel all up-tile 0 && [ "$(cat "$W/before-up")" = "$(cat "$W/after-up")" ]'
ok "mouse: left pull, switch, up, right pull, tap, close" 'lapnotif m-left && lapqs m-switch && panel mouse m-up 0 && lapqs m-right && panel mouse m-right 1 && panel mouse m-tap 0'
ok "mouse: a click on a tile toggles it" 'grep -q "^nmcli radio wifi" "$W/mouse-calls"'
ok "the pill closes"                    'panel all pilled 0'
# the strip takes the window's colour now, so its place is read from where a touch lands in it: 0.3 down, less the bar
ok "a window starts below the bar"      'y=$(sed "1,/^BAR/d" "$W/tl.log" | grep -m1 "touch down" | cut -d" " -f5); [ "$y" -ge 200 ] && [ "$y" -le 232 ]'
ok "the strip over a window is the window's colour" '[ "$(python3 -I - "$W/window.ppm" <<P
import sys
d=open(sys.argv[1],"rb").read(); p=d.split(None,4); W,H=int(p[1]),int(p[2]); b=d[-W*H*3:]
print(b[(50*W+540)*3:(50*W+540)*3+3].hex())
P
)" = 808080 ]'
ok "the clock stays above a window"     '[ "$(px "$W/window.ppm" 150 0 250 99)" -gt 200 ]'
ok "the panel opens over a window"      'panel all over-window 1'
ok "touch below the bar reaches the window, on the bar it does not" '! sed "/^BAR/q" "$W/tl.log" | grep -q "touch down" && sed "1,/^BAR/d" "$W/tl.log" | grep -q "touch down"'
# rows LABEL prints the list as it stood at that point: name state windows tray pids
rows() { python3 -I - "$W/apps.log" "$1" <<'P'
import json,sys
last=[]
for l in open(sys.argv[1],errors="replace"):
    if "ROWS " in l: last=json.loads(l.split("ROWS ",1)[1])
    elif l.startswith("FT "+sys.argv[2]+" "): break
for r in last: print(*r)
P
}
cnt() { rows "$1" | wc -l; }
row() { rows "$1" | grep -E "^$2 " | cut -d" " -f2-; }
state() { grep -qx "$1 $2 $3" "$W/alive"; }
said() { grep -q "^$1 $2 " "$W/fake.log"; }
ok "count is right with windows and tray items" '[ "$(cnt button)" = 9 ]'
ok "windows of one app are one row"     '[ "$(row list sample.multi | cut -d" " -f2)" = 2 ] && [ "$(rows list | grep -c sample.multi)" = 1 ]'
ok "same id, window and tray: one row"  '[ "$(row list sample.both)" = "idle 1 1 1" ]'
ok "same process, different id: one row" '[ "$(row list sample.diffid | cut -d" " -f1-3)" = "idle 1 1" ] && ! rows list | grep -q other.tray.id'
ok "tray only apps are listed"          '[ -n "$(row list sample.quit)" ] && [ -n "$(row list sample.term)" ]'
ok "system helpers never listed, by id or tray" '! grep "ROWS " "$W/apps.log" | grep -qi "phonekbd"'
ok "the fake helper was really running" 'said phonekbd start && [ "$(grep -c "^phonekbd start" "$W/fake.log")" = 4 ]'  # two in apps, two in bgapps
ok "the list opens, back returns to the panel" '[ "$(px "$W/active-apps.ppm" 0 320 1080 1700)" -gt 200 ] && [ "$(px "$W/apps-back.ppm" 0 1500 1080 500)" = 0 ]'
ok "the button shows in the panel"      '[ "$(px "$W/apps-button.ppm" 0 2200 400 140)" -gt 200 ]'
# the Tray apps pill: pill LABEL is its last text, bgrows LABEL the background list as name|kind|state, both before that point
pill() { sed "/^FT $1 /q" "$W/bgapps.log" | grep -o "PILL .*" | tail -1 | cut -d" " -f2-; }
bgrows() { python3 -I - "$W/bgapps.log" "$1" <<'P'
import json,sys
last=[]
for l in open(sys.argv[1],errors="replace"):
    if "BGLIST " in l: last=json.loads(l.split("BGLIST ",1)[1])
    elif l.startswith("FT "+sys.argv[2]+" "): break
for r in last: print("|".join(map(str,r)))
P
}
bgft() { grep "^FT $1 " "$W/bgapps.log" | grep -q " $2 "; }
ok "pill: closing a window that leaves its process running" 'state keep-windowless sample.keep alive && said sample.keep close'
ok "pill: shows in the overview, N is the list count" 'bgft bg-pill overview=1 && [ "$(px "$W/bg-pill.ppm" 44 2110 280 120)" -gt 200 ] && [ "$(pill bg-pill)" = "Tray apps $(bgrows bg-pill | wc -l)" ] && [ "$(bgrows bg-pill | wc -l)" = 5 ]'
ok "pill: tray, windowless app, daemon and VPN rows" '[ "$(bgrows bg-list | tr "\n" ";")" = "sample.stuckbg|Tray|idle;sample.trayd|Tray|idle;sample.keep|Running in background|idle;phonetest-bgd|Running in background|idle;Test VPN|VPN|idle;" ]'
ok "pill: no open window and no helper listed" '! grep "BGLIST " "$W/bgapps.log" | grep -qE "sample.win|phonekbd"'
ok "pill: opens its list in the panel" 'panel bgapps bg-list 1'
ok "pill: a VPN disconnects through nmcli and leaves" 'grep -qx "nmcli connection down id Test VPN" "$W/bg-calls" && ! bgrows vpn-down | grep -q "^Test VPN|"'
ok "pill: Stop ends a daemon and a windowless app" 'grep -qx "d-stopped bgd gone" "$W/alive" && state keep-stopped sample.keep gone'
ok "pill: one that ignores TERM gets Force stop, then is killed" 'state sb-force sample.stuckbg alive && bgrows sb-force | grep -qx "sample.stuckbg|Tray|force" && state sb-killed sample.stuckbg gone'
ok "pill: Stop on a tray app" 'state trayd-stopped sample.trayd gone && said sample.trayd term'
ok "pill: empty at the end, back leaves the overview open" '[ -z "$(bgrows bg-empty)" ] && panel bgapps bg-back 0 && bgft bg-back overview=1'
ok "pill: the open window was never touched" 'state win-kept sample.win alive && ! said sample.win close'
ok "tapping a row goes to its window and closes the panel" 'grep "^FT activated " "$W/apps.log" | grep -q "focus=sample.notes tray\|focus=sample.notes " && panel apps activated 0'
ok "polite close: asked, gone, list updated" 'said sample.notes close && state notes-closed sample.notes gone && [ "$(cnt notes-closed)" = 8 ]'
ok "no Force stop for an app that obeyed" '! grep "ROWS " "$W/apps.log" | grep -qE "\"sample.(notes|multi|quit|term)\",\"force\""'
ok "a stubborn app: asked, Closing first" 'said sample.stubborn close && [ "$(row st-closing sample.stubborn | cut -d" " -f1)" = closing ] && state st-closing sample.stubborn alive'
ok "a tap on Closing kills nothing"     'state st-tapped sample.stubborn alive'
ok "Force stop appears after the grace, app untouched so far" '[ "$(row st-force sample.stubborn | cut -d" " -f1)" = force ] && state st-force sample.stubborn alive'
ok "Force stop works on its own tap"    'state st-killed sample.stubborn gone && [ -z "$(row st-killed sample.stubborn)" ]'
ok "an Android window: close asked, no pid, no Force stop" 'said waydroid.sample close && [ "$(row wd-after waydroid.sample)" = "idle 1 0 0" ] && state wd-after waydroid.sample alive && ! grep "ROWS " "$W/apps.log" | grep -q "\"waydroid.sample\",\"force\""'
ok "tray app with Quit: uses it, no signal" 'said sample.quit quit-menu && ! said sample.quit term && state quit-done sample.quit gone'
ok "tray app without a menu: SIGTERM"   'said sample.term term && state term-done sample.term gone'
ok "tray app ignoring SIGTERM: Force stop, then gone" 'said sample.traystuck term-ignored && [ "$(row ts-force sample.traystuck | cut -d" " -f1)" = force ] && state ts-force sample.traystuck alive && state ts-killed sample.traystuck gone'
ok "every window of an app is asked to close" '[ "$(grep -c "^sample.multi close " "$W/fake.log")" = 2 ] && state multi-done sample.multi gone'
ok "window closed but process left: one row, Force stop" '[ "$(rows both-force | grep -c "^sample.both")" = 1 ] && [ "$(row both-force sample.both | cut -d" " -f1)" = force ] && state both-killed sample.both gone'
ok "count updates when an app exits by itself" 'state exiting sample.diffid alive && state exited sample.diffid gone && [ "$(cnt exited)" = 1 ]'

# appctl.sh on its own, on processes this test started; no bus and no real pid gets a signal
ctl() { env -i PATH="$W/stubs-bg:$PATH" PHONE_BG_DAEMONS=phonetest-bgd HOME="$W/home" XDG_RUNTIME_DIR="$W/nosys" sh "$SRC/shell/appctl.sh" "$@"; }
startof() { sed 's/.*) //' "/proc/$1/stat" | awk '{ print $20 }'; }
cp "$(command -v sleep)" "$W/phonekbd"
sleep 300 & A=$!; sleep 300 & Q=$!; "$W/phonekbd" 300 & K=$!
for i in 1 2 3 4 5; do [ "$(cat /proc/$K/comm)" = phonekbd ] && [ "$(cat /proc/$A/comm)" = sleep ] && break; sleep 0.1; done
AS=$(startof "$A"); printf '%s\tsample.ok\n%s\tsample.kbd\n1\troot.init\n2\troot.kernel\n999999999\tsample.dead\n%s\tsample.shell\n' "$A" "$K" "$Q" >"$W/winfile"
ctl scan "$Q" "$W/winfile" >"$W/scan.txt"
ok "scan: own process gets its pid and start" 'grep -qx "$(printf "w\tsample.ok\t%s\t%s" "$A" "$AS")" "$W/scan.txt"'
ok "scan: helpers and the shell are hidden" 'grep -qx "$(printf "hide\tsample.kbd")" "$W/scan.txt" && grep -qx "$(printf "hide\tsample.shell")" "$W/scan.txt"'
ok "scan: root owned and dead pids get none" 'grep -qx "$(printf "w\troot.init")" "$W/scan.txt" && grep -qx "$(printf "w\troot.kernel")" "$W/scan.txt" && grep -qx "$(printf "w\tsample.dead")" "$W/scan.txt"'
ok "alive: the start time must match"   '[ "$(ctl alive "$A:$AS")" = "$A:$AS" ] && [ -z "$(ctl alive "$A:1")" ]'
rm -f "$W/vpn-down"; ctl scan "$Q" "$W/winfile" bg "$A:$AS" "$A:1" "$K:$(startof "$K")" >"$W/scanbg.txt"
ok "scan bg: the same process once, never a helper, the VPN by name" 'grep -qx "$(printf "b\t%s\t%s" "$A" "$AS")" "$W/scanbg.txt" && [ "$(grep -c "^b" "$W/scanbg.txt")" = 1 ] && grep -qx "$(printf "v\tTest VPN")" "$W/scanbg.txt" && ! grep -q "^d" "$W/scanbg.txt"'
ctl signal KILL "$A:1"; sleep 0.2
ok "signal: a reused pid (other start time) is refused" '[ -d "/proc/$A" ] && [ "$(startof "$A")" = "$AS" ]'
ctl signal KILL "$K:$(startof "$K")"; sleep 0.2
ok "signal: a helper is refused"        '[ "$(startof "$K")" != "" ]'
ctl signal HUP "$A:$AS"; sleep 0.2
ok "signal: only TERM and KILL"         '[ "$(startof "$A")" = "$AS" ]'
ctl signal TERM "$A:$AS"; wait "$A" 2>/dev/null
ok "signal: the right pid and start goes through" '[ ! -d "/proc/$A" ]'
kill -9 "$Q" "$K" 2>/dev/null; wait "$Q" "$K" 2>/dev/null

# ---- the tiles ----
# after LABEL: the calls logged between two marks
between() { sed -n "/^$1\$/,/^$2\$/p" "$L" | grep -v "^[AR][0-9]\$"; }
cf() { grep -q "^$2 *= *$3\$" "$W/$1"; }
# which tiles, or the saved order, as they stood at a label
asof() { python3 -I - "$W/$1.log" "$2" "$3" <<'Q'
import sys
last=""
for l in open(sys.argv[1],errors="replace"):
    if sys.argv[3]+" " in l and "console" not in l and l.find(sys.argv[3]+" ")>=0 and ("qml" in l or l.startswith(sys.argv[3])): last=l.split(sys.argv[3]+" ",1)[1].strip()
    elif l.startswith("FT "+sys.argv[2]+" "): break
print(last)
Q
}
has() { case " $(asof "$1" "$2" TILES) " in *" $3 "*) return 0 ;; *) return 1 ;; esac; }
for c in "mobile data off:^nmcli con down id Carrier" "airplane on:^rfkill block all" "airplane off:^rfkill unblock all" \
	"hotspot on:^nmcli device wifi hotspot" "hotspot off:^nmcli con down Hotspot" \
	"light mode, apps told:^gsettings set org.gnome.desktop.interface color-scheme prefer-light" "dark mode, apps told:^gsettings set org.gnome.desktop.interface color-scheme prefer-dark" \
	"night light on:^wlsunset -S 00:00 -s 00:01 -d 1 -t 3500" "night light off:^wlsunset TERM" \
	"recording on:^wf-recorder -f .*/home/Videos/Screen recordings/Screen recording [0-9-]* [0-9-]*\.mp4\$" "recording off:^wf-recorder INT" \
	"screenshot:^grim .*/home/Pictures/Screenshots/screenshot-[0-9-]*\.png" \
	"saver on:^powerprofilesctl set power-saver" "saver off:^powerprofilesctl set balanced" \
	"NFC off:^rfkill block nfc" "NFC on:^rfkill unblock nfc" "location off:^rfkill block gps" "location on:^rfkill unblock gps" \
	"flashlight on:brightnessctl -q --class=leds -d white:torch set 100%" "flashlight off:brightnessctl -q --class=leds -d white:torch set 0" \
	"Glyph on:^brightnessctl -q --class=leds -d aw20036:white set 100%" "Glyph off:^brightnessctl -q --class=leds -d aw20036:white set 0" \
	"calculator app:^app s-calc" "clock app:^app s-clock" "camera app:^app s-cam" "QR app:^app s-qr" "notes app:^app s-notes" "sharing app:^app localsend" "recorder app:^app s-rec" \
	"hold data:^phonesettings mobile" "hold ringer:^phonesettings sound" "hold hotspot:^phonesettings wifi" "hold rotation:^phonesettings display" "hold dark:^phonesettings look" "hold saver:^phonesettings battery" \
	"other night tool on:^gammastep -O 3500" "other night tool off:^gammastep TERM" \
	"output picker:^wpctl set-default 52"; do
	ok "exact command: ${c%%:*}" 'called "${c#*:}"'
done
ok "a tile closes the panel only when it opens something else" 'panel tiles rec-closed 0 && panel tiles shot-closed 0 && panel tiles full 1'
ok "ringer: vibrate saved, media volume untouched" 'cf r-vibrate ringer vibrate && ! between R1 R2 | grep -q "^wpctl"'
ok "ringer: silent saved, media volume untouched" 'cf r-silent ringer silent && ! between R2 R3 | grep -q "^wpctl"'
ok "ringer: back to normal, media volume untouched" 'cf r-normal ringer normal && ! between R3 R4 | grep -q "^wpctl"'
ok "do not disturb is saved, both ways"  'cf dnd-on dnd on && cf dnd-off dnd off'
ok "normal: a notification plays the sound" 'between A0 A1 | grep -qE "^paplay .*/notify.wav\$" && ! between A0 A1 | grep -q "^fbcli"'
ok "the settings tool sets vibrate: it vibrates, media volume untouched" '! between A0 A2 | grep -q "^wpctl" && between A1 A2 | grep -qx "fbcli -E message-new-instant" && ! between A1 A2 | grep -q "^paplay"'
ok "silent: neither sound nor vibration" '! between A2 A3 | grep -qE "^(paplay|fbcli)" || [ "$(between A2 A3 | grep -cE "^(paplay|fbcli)")" = 0 ]'
ok "do not disturb: neither"             '[ "$(between A3 A4 | grep -cE "^(paplay|fbcli)")" = 0 ]'
ok "do not disturb off: sound again"     'between A4 A5 | grep -q "^paplay"'
ok "the notification sound is a real wav" 'python3 -c "import wave,sys; w=wave.open(sys.argv[1]); assert w.getnframes()>1000" "$SRC/shell/notify.wav"'
ok "no app, no shortcut tile"            '! has hide h-all calc && ! has hide h-all notes && ! has hide h-all share'
ok "with apps, every shortcut tile shows" 'for i in calc clock camera qr notes share recorder; do has tiles full $i || return 1; done'
gone() { tool=$1 tids=$2; ok "$1 gone: ${2// /, } hidden" 'for i in $tids; do has hide h-all $i && ! has hide "h-$tool" $i || return 1; done'; }
gone wf-recorder record; gone grim screenshot; gone powerprofilesctl saver; gone wlsunset night
gone rfkill "airplane nfc location"; gone nmcli "hotspot data"; gone fbcli dnd; gone brightnessctl "torch glyph"; gone wpctl ringer
ok "the rest of the tiles stay while one goes" 'has hide h-grim record || has hide h-grim saver'
ok "with every tool gone no tile is left" '[ -z "$(asof hide h-wpctl TILES | tr -d " " | sed "s/rotation//;s/dark//")" ]'
ok "the camera hole is clear of every new view" 'for s in qs-full sinks media small-compact; do [ $s = small-compact ] && continue; hole_clear $s || return 1; done'
ok "the tile list holds still while the panel is used" '[ "$(sed -n "/^FT full /,/^FT rec-closed /p" "$W/tiles.log" | grep -c "qml.*TILES")" = 0 ]'
ok "the saved order is read, spaces and all" '[ "$(asof tiles reopened ORDER)" = "ringer dnd airplane" ]'
ok "an unreadable order falls back to the default" '[ "$(asof tiles corrupt ORDER | cut -d" " -f1-3)" = "data airplane ringer" ]'
ok "a dash means no tiles, by choice"    '[ -z "$(asof tiles none ORDER)" ]'
ok "no order line: the default"          '[ "$(asof tiles removed ORDER | cut -d" " -f1-3)" = "data airplane ringer" ]'
fakesaid() { grep -q "^sample.player $1 " "$W/fake.log"; }
ok "media: next, previous and pause reach the player" 'fakesaid mpris-Next && fakesaid mpris-Previous && fakesaid mpris-Pause'
ok "media: the card is drawn from the player" '[ "$(px "$W/media.ppm" 60 1600 960 280)" -gt 2000 ] && [ "$(px "$W/panel.ppm" 60 1600 960 280)" = 0 ]'
ok "media: the play button follows the player" '! cmp -s "$W/media.ppm" "$W/media-paused.ppm"'
ok "output picker opens and closes"      '[ "$(px "$W/sinks.ppm" 60 1860 960 340)" -gt 2000 ] && panel media sink-picked 1'
ok "a short screen: the full view scrolls" '! cmp -s "$W/small-full.ppm" "$W/small-scrolled.ppm" && panel small small-held 1'
ok "a short screen: the bottom strip closes" 'panel small small-closed 0'
ok "a wide font: the clock stays off the hole" 'hole_clear wide-bar'
ok "the real grim saved a real screenshot" 'f=$(ls "$W"/home/Pictures/Screenshots/*.png 2>/dev/null | head -1); [ -n "$f" ] && case "$(magick identify -format "%wx%h" "$f")" in 1080x240[0-2]) ;; *) false ;; esac'
ok "the test tools ran only as stubs"    '! called "^UNEXPECTED" && ! called "^POWER"'
ok "no recorder or night tool left behind" 'for f in quick-record quick-night; do [ ! -e "$W/state/phonegluewc/$f.pid" ] || return 1; done'
seg() { grep -q "^$2\$" "$L" && sed -n "/^$1\$/,/^$2\$/p" "$L"; }
ok "rotate: an offer from before the start shows nothing" 'seg O0 O1 >/dev/null && ! seg O0 O1 | grep -q "^msg"'
ok "rotate: a new offer's button turns the screen" 'seg O1 O2 | grep -qx "msg rotate 90"'
ok "rotate: the button leaves after a few seconds" 'seg O2 O3 >/dev/null && ! seg O2 O3 | grep -q "^msg"'
ok "rotate: upside down it sits in the middle" 'seg O3 O4 | grep -qx "msg rotate 180"'

ok "no core files"                    '! ls "$W"/core.* >/dev/null 2>&1'
cat "$W/rss" | sed 's/pid=[0-9]* //'
[ -n "${TOUCH_VERBOSE:-}" ] && { cat "$L"; grep -hE "ReferenceError|TypeError|WARN|qml" "$W/all.log" | cut -c1-180 | head -30; }
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
