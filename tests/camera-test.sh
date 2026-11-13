#!/bin/bash
# The dynamic camera, headless at phone size, on fakes only. SHOTS=DIR keeps the captures. SCENES="a b" runs only those.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-cam.XXXXXX")
SANDBOX_EXTRA="timeout notify-send date readlink sync python3 basename dirname stat touch chmod mktemp"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=${CAMERA_BUILD:-$W/build}; mkdir -p "$BUILD"
if [ ! -x "$BUILD/phonegluewc" ] || [ -z "${CAMERA_BUILD:-}" ]; then
	cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
	python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
	make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer -g"} >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
fi
cc -Wall -o "$BUILD/phonecamera" "$SRC/phonecamera.c" || { echo "FAIL phonecamera"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
# script lines have a length limit: the commands are short names on the sandbox PATH
cp "$SRC/tests/wshot" "$W/stubs/wshot" 2>/dev/null || { mkdir -p "$W/stubs"; cp "$SRC/tests/wshot" "$W/stubs/wshot"; }
mkdir -p "$W/s"
cp "$SRC/tests/fake-player.py" "$W/fake-player.py"
# an app that says where it was touched
XS=$(pkg-config --variable=pkgdatadir wayland-protocols)/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header "$XS" "$BUILD/touchlog-xdg-protocol.h"; wayland-scanner private-code "$XS" "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || { echo "FAIL touchlog"; exit 1; }
printf 'echo $$ >"%s/pid-$1"; TOUCHLOG_TITLE=$1 exec "%s/touchlog" >"%s/log-$1" 2>&1\n' "$W" "$W" "$W" >"$W/tl.sh"
# album art: a small gradient png
python3 - "$W/art.png" <<'P'
import sys, zlib, struct
n = 96
raw = b"".join(b"\0" + bytes(c for x in range(n) for c in (200 - y, 40 + x, 90 + x + y // 2)) for y in range(n))
def ch(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))
P

mkdir -p "$W/cfg/phonegluewc" "$W/state/phonegluewc"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"

# fake /sys and tools that only remember
S=$W/sys; mkdir -p "$S/power_supply/BAT0" "$S/backlight/panel" "$S/leds/white:torch"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
echo 1000 >"$S/backlight/panel/max_brightness"; echo 500 >"$S/backlight/panel/brightness"; echo 0 >"$S/leds/white:torch/brightness"
L=$W/calls; ST=$W/stub; mkdir -p "$ST" "$W/stubs"; : >"$L"; : >"$ST/active"; echo 0.40 >"$ST/vol"; : >"$ST/bt"; : >"$ST/streams"
stub() { { echo '#!/bin/sh'; echo "L='$L' ST='$ST' S='$S'"; cat; } >"$W/stubs/$1"; chmod +x "$W/stubs/$1"; }
stub nmcli <<'X'
case "$*" in
"-t -f NAME,TYPE con show --active") cat "$ST/active" ;;
*) ;;
esac
X
stub bluetoothctl <<'X'
case "$*" in
show) printf 'Controller 0\n\tPowered: yes\n' ;;
"devices Connected") cat "$ST/bt" ;;
esac
X
stub wpctl <<'X'
case "$1" in
get-volume) echo "Volume: $(cat "$ST/vol")" ;;
status) printf 'Audio\n ├─ Sinks:\n │  *   51. Speaker  [vol: 0.40]\n │      52. Test Buds  [vol: 0.70]\n ├─ Sources:\n\n └─ Streams:\n'; cat "$ST/streams" ;;
set-default) echo "wpctl $*" >>"$L" ;;
esac
X
stub brightnessctl <<'X'
echo "brightnessctl $*" >>"$L"
case "$*" in *100%) echo 1 >"$S/leds/white:torch/brightness" ;; *) echo 0 >"$S/leds/white:torch/brightness" ;; esac
X
for p in systemctl loginctl reboot poweroff shutdown halt suspend rtcwake; do stub "$p" <<'X'
echo "POWER $0 $*" >>"$L"
X
done
stub phonesettings <<'X'
echo "phonesettings $*" >>"$L"
X
stub wf-recorder <<'X'
echo "wf-recorder $*" >>"$L"
trap 'echo "wf-recorder stopped" >>"$L"; exit 0' INT
i=0; while [ $i -lt 400 ]; do sleep 0.2; i=$((i+1)); done
X
: >"$S/fake-video"; : >"$ST/cam"
stub fuser <<'X'
[ -s "$ST/cam" ]
X

# the shell under test logs what it is doing, one line whenever that changes
probe() {
	python3 - "$1" <<'P'
import sys
d=sys.argv[1]
p=d+'/Dyn.qml'; s=open(p).read().rstrip()
assert s.endswith('}')
s=s[:-1]+'''
    // what no touch can reach in a test: the password, the two power keys
    FileView {
        path: Quickshell.env("CAM_DO")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const w = text().trim();
            if (w === "unlock") Auth.answered(true);
            else if (w === "lock") Phone.lockOpen = true;
            else if (w === "flash") Phone.flashOn = true;
            else if (w === "rec") Status.recording = true;
        }
    }
    property string probeLast: ""
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            const m = root.main, b = root.bubble;
            const t = JSON.stringify({ main: m ? m.id : "", title: m ? m.title || "" : "", tail: m ? m.tail || "" : "", sub: m ? m.sub || "" : "", icon: m ? m.icon || "" : "", buttons: m ? (m.buttons || []).length : 0,
                bubble: b ? b.id : "", open: root.open, moving: root.moving, wanted: root.windowWanted, hx: root.hx, hd: root.hd, known: root.holeKnown, side: root.side,
                L: Math.round(root.pL * 100) / 100, R: Math.round(root.pR * 100) / 100, T: Math.round(root.pT * 100) / 100, B: Math.round(root.pB * 100) / 100, r: Math.round(root.radius * 100) / 100,
                S: Math.round(root.pillStart * 100) / 100, E: Math.round(root.pillEnd * 100) / 100, count: root.items.length, on: root.on, pull: Status.pull > 0, panel: Status.panelLoaded, sheet: Status.side, hy: root.hy, lock: Phone.lockOpen, hidden: root.hidden, fullHidden: root.fullHidden, fade: root.fullFade, fake: root.fake, head: m ? m.head || "" : "", bars: root.barsRun, noExpand: m ? !!m.noExpand : false, notifs: Status.notifs.length, cameraW: Status.cameraHole.width, conns: Status.s.conns || "" });
            if (t !== root.probeLast) {
                root.probeLast = t;
                console.log("CAM " + t);
            }
        }
    }
}
'''
open(p,'w').write(s)
p=d+'/StatusBar.qml'; s=open(p).read().rstrip()
s=s[:-1]+'''
    property string probeLast: ""
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            const t = JSON.stringify({ clockX: leftGroup.x, clockOp: clock.opacity, slots: root.notifSlots, rightX: rightGroup.x, rightEnd: rightGroup.x + rightGroup.width, notifs: root.notifShown.length });
            if (t !== root.probeLast) {
                root.probeLast = t;
                console.log("BAR " + t);
            }
        }
    }
}
'''
open(p,'w').write(s)
P
}
shell_for() {
	rm -rf "$W/shell"; cp -a "$SRC/shell" "$W/shell"; probe "$W/shell"
}

pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }

# state at a label: the last CAM and BAR lines before it, as shell-friendly python
at() { python3 "$W/at.py" "$W/$SCENE.log" "$1" "$2"; }
cat >"$W/at.py" <<'P'
import json, sys
log, label, expr = sys.argv[1:4]
cam = {}; bar = {}; found = False
for l in open(log, errors='replace'):
    i = l.find('CAM {')
    if i >= 0:
        try: cam = json.loads(l[i + 4:])
        except ValueError: pass
    i = l.find('BAR {')
    if i >= 0:
        try: bar = json.loads(l[i + 4:])
        except ValueError: pass
    if 'FT ' + label + ' ' in l:
        found = True
        break
if not found:
    print('no label', label, file=sys.stderr); sys.exit(2)
class D(dict):
    __getattr__ = dict.get
try:
    r = eval(expr, {'c': D(cam), 'b': D(bar), 'abs': abs, 'min': min, 'max': max})
except Exception as e:
    print('error', e, file=sys.stderr); sys.exit(2)
sys.exit(0 if r else 1)
P
# what the fake touch script says
t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-700}"; }
# the same in logical pixels of the 392.7 by 872.7 screen
tl() { t "$(awk "BEGIN{printf \"%.4f\", $1/392.7}")" "$(awk "BEGIN{printf \"%.4f\", $2/872.7}")" "${3:-700}"; }
p() { echo "w ${2:-600}"; echo "p $1"; }
shot() { echo "x wshot $W/s/${1}.ppm"; echo "w 500"; }
cam() { echo "x phonecamera $*"; echo "w 500"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w 700"; echo "u 0"; echo f; echo "w 500"; }
drag() { echo "d 0 $1 $2"; echo f; python3 -c "
for s in range(1,9): print('m 0 %.3f %.3f\nf\nw 25' % ($1+($3-$1)*s/8, $2+($4-$2)*s/8))"; echo "u 0"; echo f; echo "w 700"; }

COMP=$BUILD/phonegluewc
reset() {
	rm -f "$W/cfg/phonegluewc/phone.conf"
	printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
}
# run NAME [ENV...]: one compositor life through $W/script
run() {
	SCENE=$1; shift
	case " ${SCENES:-$SCENE} " in *" $SCENE "*) ;; *) SCENE=; reset; return 1 ;; esac
	# the hook cuts a line at 128 without a word: a long command runs from a file instead
	rm -rf "$W/x"; mkdir -p "$W/x"
	awk -v d="$W/x" '/^x / && length > 127 { f = d "/" ++n; print substr($0, 3) >f; close(f); print "x sh " f; next } { print }' "$W/script" >"$W/script.n" && mv "$W/script.n" "$W/script"
	ok "$SCENE: script lines whole" "! awk 'length > 127 { f = 1 } END { exit !f }' $W/script"
	shell_for
	SANDBOX_PATH="$BUILD:$W/stubs:$SRC/settings"
	echo none >"$W/do"
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$W/shell" PHONE_SYS_DIR="$S" PHONEGLUEWC_FAKETOUCH="$W/script" PHONECAMERA_SOCK="$W/run/cam.sock" CAM_DO="$W/do" "$@"
	comp_wait 2400
	comp_stop
	mv "$W/gw.log" "$W/$SCENE.log"
	[ -z "${LOGS:-}" ] || { cp "$W/$SCENE.log" "$LOGS/"; cp "$W"/log-* "$W/player.log" "$LOGS/" 2>/dev/null; }
	for f in "$W"/s/*.ppm; do [ -e "$f" ] && mv "$f" "$SHOTS/"; done
	reset
	rm -f "$W"/pid-*; echo Discharging >"$S/power_supply/BAT0/status"; echo 62 >"$S/power_supply/BAT0/capacity"; echo 500 >"$S/backlight/panel/brightness"; echo 0 >"$S/leds/white:torch/brightness"; : >"$ST/active"; echo 0.40 >"$ST/vol"; : >"$ST/bt"; : >"$ST/streams"
	grep -a 'ReferenceError\|TypeError\|QQmlComponent\|Binding loop\|file:.*qml.*[Ee]rror' "$W/$SCENE.log" | cut -c1-220 | sort -u | head -12
	return 0
}


A() { if at "$2" "$3"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
# the camera's own circle, in panel pixels, shows only black or the bare root colour 205080 in this capture
black() { python3 - "$SHOTS/$1.ppm" "$2" "$3" "$4" <<'P'
import sys
f, x, y, d = sys.argv[1], *map(float, sys.argv[2:])
b = open(f, 'rb').read()
parts = b.split(None, 4); w, h = int(parts[1]), int(parts[2]); px = parts[4]
for j in range(int(y), int(y + d) + 1):
    for i in range(int(x), int(x + d) + 1):
        if (i + .5 - x - d / 2) ** 2 + (j + .5 - y - d / 2) ** 2 <= (d / 2 - 1) ** 2 and px[(j * w + i) * 3:(j * w + i) * 3 + 3] != b'\0\0\0' and sorted(px[(j * w + i) * 3:(j * w + i) * 3 + 3]) != [0x20, 0x50, 0x80]:
            sys.exit(1)
P
}
touches() { grep -c 'touch down' "$W/log-$1" 2>/dev/null; }
polled() { echo "x phonecamera poll"; echo "w 1500"; }
do_() { echo "x echo $1 >$W/do"; echo "w ${2:-600}"; }
pconf() { printf '%s\n' "$@" >"$W/cfg/phonegluewc/phone.conf"; }
tchk() { [ "$(touches "$1")" = "$2" ]; }
cat >"$W/player.sh" <<EOF
python3 $W/fake-player.py $W/art.png $W/player.log &
echo \$! >$W/player.pid
EOF
cat >"$W/poster.sh" <<EOF
# NAME then phonecamera arguments, stays connected until killed
n=\$1; shift
phonecamera post --id "\$n" "\$@" --wait >>"$W/out-\$n" 2>&1 &
echo \$! >"$W/poster-\$n"
EOF
killp() { echo "x kill \$(cat $W/$1)"; echo "w ${2:-700}"; }
HL=89.3; HT=42.31; HD=52.38

# ---- nothing active: no shape, touches reach the app, the sheet still pulls ----
{ echo "w 3000"; p idle; shot idle
  echo "x sh $W/tl.sh A"; echo "w 1800"; echo s; echo "w 900"; p fs
  t 0.107 0.029; p tapped
  cam post --id a --icon timer --head Sample --title Hello --tail 12%; p fsup; shot fs-hidden
  t 0.15 0.028 900; p fsopen
  echo "x sh $W/poster.sh ring --kind call --state incoming --title Alex"; p fscall 900; echo "x phonecamera end ring"; echo "w 700"
  echo s; echo "w 900"; p unfull; echo s; echo "w 900"
  echo "x phonecamera end a"; p fsgone 900; t 0.107 0.029; p tapped2
  echo s; echo "w 700"; drag 0.107 0.029 0.107 0.5; p pulled 500; drag 0.5 0.7 0.5 0.1; p shut 800; } >"$W/script"
run idle && {
	A "idle: no shape, no window" idle 'not c.wanted and c.main == "" and c.count == 0 and abs(c.R - c.L - c.hd) < 0.1'
	A "idle: the clock stays beside the hole" idle 'abs(b.clockX - 57.4545) < 0.01'
	ok "idle: a touch at the camera spot reaches the fullscreen app" 'grep -q "touch down 0 [0-9.]* [0-9.]*" "$W/log-A"'
	A "fullscreen: an activity stays out of sight" fsup 'c.main == "a" and c.fullHidden and c.fade == 0'
	A "fullscreen: a tap where the pill would be does not open it" fsopen 'not c.open'
	A "fullscreen: an incoming call shows, but does not open by itself" fscall 'c.main == "ring" and not c.open and not c.fullHidden and c.fade == 1'
	A "leaving fullscreen brings the activity back" unfull 'c.main == "a" and c.wanted and c.fade == 1'
	A "fullscreen: empty again means nothing" fsgone 'not c.wanted and c.main == "" and not c.moving'
	ok "in fullscreen a tap where the pill would be reaches the app" 'n=$(touches A); [ "$n" = 3 ]'
	A "the sheet pulls down from the camera spot" pulled 'c.panel'
}

# ---- music ----
{ echo "w 3000"; echo "x sh $W/player.sh"; echo "w 1800"; p up; shot m-compact
  tl 80 25 1000; p open; shot m-open
  tl 196 180 700; p paused; tl 196 180 700; p played; tl 262 180 900; p next; shot m-long
  tl 294 126 700; p seeked; tl 196 234 900; p sink
  tl 150 60 900; p tapcontent; echo "x kill \$(cat $W/player.pid)"; p died 1500; shot m-died; } >"$W/script"
run music && {
	A "music: compact from the owner" up 'c.main == "music" and c.title == "Night Drive" and c.bars and not c.open'
	A "music: tap expands" open 'c.open and c.R - c.L > 370'
	A "music: bars stop when paused" paused 'not c.bars'
	ok "music: pause, play, next and seek reach the player" 'grep -Eq "player (PlayPause|Pause)" "$W/player.log" && grep -q "player SetPosition" "$W/player.log" && grep -q "player Next" "$W/player.log"'
	A "music: next changes the title" next 'c.title.startswith("A much longer")'
	ok "music: the output row goes to the next device" 'grep -q "wpctl set-default 52" "$L"'
	A "music: its owner vanishing clears it" died 'c.main == "" and not c.wanted'
	A "music: back to the idle bar" died 'abs(b.clockX - 57.4545) < 0.01'
}

# ---- calls, through the small interface ----
{ echo "w 3000"; echo "x sh $W/poster.sh c --kind call --state incoming --title Alex"; p ringing 900; shot c-in
  tl 252 126 700; p answered
  cam update --id c --state active --elapsed; p active; t 0.5 0.8; p shut; shot c-active; tl 72 25 800; shot c-active-open; p reopened
  tl 90 126 500; tl 196 126 500; tl 302 126 500; p keys
  t 0.5 0.8; killp poster-c; p posterdied 900; } >"$W/script"
run call && {
	A "call: incoming opens by itself" ringing 'c.main == "c" and c.open'
	ok "call: answer goes to the program" 'grep -q "\"answer\"" "$W/out-c"'
	A "call: active shows the duration" active 'c.main == "c" and ":" in c.tail'
	A "call: outside collapses" shut 'not c.open'
	ok "call: mute, speaker, hang up go to the program" 'grep -q "\"mute\"" "$W/out-c" && grep -q "\"speaker\"" "$W/out-c" && grep -q "\"hangup\"" "$W/out-c"'
	A "call: the poster dying clears it" posterdied 'c.main == "" and not c.wanted'
}

# ---- what the system says, each of them comes and goes ----
BAT=$S/power_supply/BAT0
{ echo "w 3500"
  echo "x echo Charging >$BAT/status"; polled; p charge 100; shot e-charging; echo "w 3800"; p charged
  echo "x echo Discharging >$BAT/status"; echo "x echo 14 >$BAT/capacity"; polled; p low 100; shot e-low; echo "w 5400"; p lowgone
  echo "x echo 0.70 >$ST/vol"; polled; p vol 100; shot e-vol; echo "w 2000"; p volgone
  echo "x echo 800 >$S/backlight/panel/brightness"; polled; p bright 100; echo "w 2000"; p brightgone
  echo "x echo Device 00 Test Buds >$ST/bt"; polled; p bt 100; shot e-bt; echo "w 3700"; p btgone
  echo "x echo Tun:vpn >$ST/active"; polled; p vpn 100; shot e-vpn; echo "w 3200"; p vpngone
  echo "x : >$ST/active"; polled; p vpnoff 100; echo "w 3200"; p vpnoffgone
  echo "x echo Hotspot:802-11-wireless >$ST/active"; polled; p hot 100; shot e-hot; echo "x : >$ST/active"; polled; p hotgone 300
  echo "x echo '  71. in < Mic' >$ST/streams"; polled; p mic 100; shot e-mic; echo "x : >$ST/streams"; polled; p micgone 300
  echo "x echo 1 >$S/leds/white:torch/brightness"; polled; p torch 100; shot e-torch; tl 72 25 900; p torchopen; shot e-torch-open; tl 70 98 1500; p torchoff
  echo "x pset set phone ringer silent"; echo "w 800"; p silent 100; shot e-silent; echo "w 2800"; p silentgone
  echo "x pset set phone dnd on"; echo "w 800"; p dnd 100; shot e-dnd; echo "w 2800"; p dndgone
  do_ flash 800; p flash 100; shot e-shot; echo "w 2800"; p flashgone
  echo "x echo 1 >$ST/cam"; polled; p camuse 100; shot e-cam; echo "x : >$ST/cam"; polled; p camgone 300; } >"$W/script"

run events && {
	A "charging: appears" charge 'c.main == "charging" and c.tail == "62%"'; A "charging: goes by itself" charged 'c.main == ""'
	A "low battery: appears" low 'c.main == "lowbat" and c.tail == "14%"'; A "low battery: goes by itself" lowgone 'c.main == ""'
	A "volume: mini activity" vol 'c.main == "level" and c.title == "Volume"'; A "volume: gone" volgone 'c.main == ""'
	A "brightness: mini activity" bright 'c.main == "level" and c.title == "Brightness"'; A "brightness: gone" brightgone 'c.main == ""'
	A "earbuds: appears" bt 'c.main == "device" and c.title == "Device 00 Test Buds".split(" ", 2)[2]'; A "earbuds: gone" btgone 'c.main == ""'
	A "vpn: appears" vpn 'c.main == "vpn"'; A "vpn: gone" vpngone 'c.main == ""'
	A "vpn: its end shows" vpnoff 'c.main == "vpn" and c.title == "VPN disconnected"'; A "vpn: end goes" vpnoffgone 'c.main == ""'
	A "hotspot: while on" hot 'c.main == "hotspot"'; A "hotspot: clears with its source" hotgone 'c.main == ""'
	A "microphone: while in use" mic 'c.main == "mic"'; A "microphone: clears" micgone 'c.main == ""'
	A "flashlight: while on" torch 'c.main == "torch"'; A "flashlight: expanded has its button" torchopen 'c.open and c.buttons == 1'
	ok "flashlight: turn off runs the tool" 'grep -q "brightnessctl.*set 0" "$L"'
	A "ringer: change shows" silent 'c.main == "ringer" and c.title == "Silent"'; A "ringer: gone" silentgone 'c.main == ""'
	A "do not disturb: change shows" dnd 'c.main == "dnd"'; A "do not disturb: gone" dndgone 'c.main == ""'
	A "screenshot: shows" flash 'c.main == "shot" and c.noExpand'; A "screenshot: gone" flashgone 'c.main == ""'
	A "camera: while in use" camuse 'c.main == "cam"'; A "camera: clears" camgone 'c.main == ""'
}

# ---- timer, stopwatch, recording, posted activities, notifications, what opens what ----
# set -m: a job started by & otherwise ignores INT for good, the real path has no &
cat >"$W/rec.sh" <<EOF
set -m
wf-recorder -f x &
echo \$! >$W/state/phonegluewc/quick-record.pid
EOF
{ echo "w 3000"
  cam timer 3; p timer 300; shot t-timer; echo "w 3600"; p rang; echo "w 6200"; p ranggone
  cam stopwatch; p watch; tl 72 25 900; p watchopen; shot t-watch-open; tl 76 118 900; p watchstop
  echo "x sh $W/rec.sh"; do_ rec 900; p rec; shot t-rec; tl 72 25 900; shot t-rec-open; tl 76 118 1200; p recstop
  cam post --id nv --kind nav --icon navr --head "'In 200 m'" --title "'Turn right'" --tail "'200 m'"; p nav; shot t-nav; tl 72 25 900; shot t-nav-open; t 0.5 0.8; echo "x phonecamera end nv"; p navend 900
  cam post --id tr --kind transfer --icon transfer --head Transfer --title file.zip --progress 0.3; p tr; shot t-tr; cam update --id tr --progress 0.8; p tr2; tl 72 25 900; shot t-tr-open; t 0.5 0.8; cam end tr
  echo "x sh $W/poster.sh lv --icon note --head App --title Pizza --text Soon --tail 12m --button a:Fine"; p lv 900; tl 72 25 900; p lvopen; shot t-live-open; tl 76 112 800; p lvbtn; tl 250 60 800; t 0.5 0.8; killp poster-lv; p lvgone 800
  cam post --id ttl --title Short --ttl 2; p ttl 300; echo "w 2500"; p ttlgone
  echo "x notify-send -a Chat Alex 'Are you coming?'"; p notif 900; shot t-notif; t 0.5 0.8; p notifshut; echo "w 4800"; p notifgone
  echo "x notify-send -a Chat Alex Swipe"; echo "w 800"; drag 0.3 0.06 0.8 0.06; p swiped 200
  echo "x notify-send -a Chat Alex Tap"; echo "w 800"; tl 150 60 900; p tappednotif; drag 0.5 0.7 0.5 0.1
  echo "w 800"; do_ none 100; cam timer 300; p t1; tl 72 25 900; p t1o; drag 0.5 0.09 0.5 0.01; p swipeup; tl 72 25 900; t 0.5 0.8; p tapout; hold 0.15 0.028; p held; echo "x phonecamera cancel timer"; p t1gone 900
  echo "x pset set phone ringer vibrate"; echo "w 500"; hold 0.15 0.028; p heldpage; echo "x cp $L $W/after-hold"; echo "w 100"
  echo "w 3000"; echo "x pset set phone ringer normal"; echo "w 500"; tl 72 25 600; tl 250 60 900; p tapcontent; } >"$W/script"
run timers && {
	A "timer: counts" timer 'c.main == "timer" and ":" in c.tail'
	A "timer: finished says so" rang 'c.main == "timerdone"'; A "timer: then goes" ranggone 'c.main == ""'
	A "stopwatch: runs" watch 'c.main == "watch"'; A "stopwatch: stop from expanded" watchstop 'c.main == ""'
	A "recording: elapsed" rec 'c.main == "record"'; A "recording: stop from expanded" recstop 'c.main == ""'
	ok "recording: stop reaches the recorder" 'grep -q "wf-recorder stopped" "$L"'
	A "navigation: posted" nav 'c.main == "nv" and c.tail == "200 m"'; A "navigation: end clears" navend 'c.main == ""'
	A "transfer: percent" tr 'c.main == "tr" and c.tail == "30%"'; A "transfer: update" tr2 'c.tail == "80%"'
	A "third party: expanded with a button" lvopen 'c.open and c.buttons == 1'
	ok "third party: the button goes to the poster" 'grep -q "\"a\"" "$W/out-lv"'
	A "third party: poster dying clears" lvgone 'c.main == ""'
	A "third party: ttl appears" ttl 'c.main == "ttl"'; A "third party: ttl elapses" ttlgone 'c.main == ""'
	A "notification: pops out open" notif 'c.main == "notif" and c.open and c.title == "Alex"'
	A "notification: goes by itself and stays in the sheet" notifgone 'c.main == "" and c.notifs >= 1'
	A "notification: a sideways swipe dismisses" swiped 'c.main == "" and c.notifs == 1'
	A "swipe toward the camera collapses" swipeup 'c.main == "timer" and not c.open'
	A "tap outside collapses" tapout 'not c.open'
	ok "a hold opens its app directly" 'grep -q "phonesettings sound" "$W/after-hold"'
	ok "a further tap on the content opens it" '[ "$(grep -c "phonesettings sound" "$L")" -ge 2 ]'
	ok "third party: a tap on the content tells the poster" 'grep -q "\"open\"" "$W/out-lv"'
	A "the end of it leaves nothing" t1gone 'c.main == "" and not c.wanted'
}

# ---- priority, two at once, a third waits, swaps ----
{ echo "w 3000"
  cam post --id nv --kind nav --icon navr --title Turn; p one
  echo "x sh $W/player.sh"; echo "w 1500"; p two; shot p-two
  cam timer 300; p three; shot p-three
  echo "x sh $W/poster.sh c --kind call --state active --title Alex"; p call 900; t 0.5 0.8
  echo "x phonecamera end c"; echo "w 1000"
  drag 0.2 0.028 0.32 0.028; p swapped; shot p-swap
  drag 0.2 0.028 0.32 0.028; p swapped2
  cam cancel timer; p nomore; echo "x kill \$(cat $W/player.pid)"; p nomusic 1200; echo "x sh $W/player.sh"; p two2 1500; tl 134 25 900; p tapswap; shot p-tapswap; echo "x kill \$(cat $W/player.pid)"; echo "w 1200"; echo "x phonecamera end nv"; p none 900; } >"$W/script"
run priority && {
	A "one: alone" one 'c.main == "nv" and c.bubble == ""'
	A "music outranks navigation, navigation is the bubble" two 'c.main == "music" and c.bubble == "nv"'
	A "timer outranks music, navigation waits" three 'c.main == "timer" and c.bubble == "music" and c.count == 3'
	A "a call comes first" call 'c.main == "c" and c.bubble == "timer"'
	A "a sideways swipe swaps" swapped 'c.main == "music" and c.bubble == "timer"'
	A "tapping the bubble swaps" tapswap 'c.main == "nv" and c.bubble == "music"'
	A "what is left moves up" nomusic 'c.main == "nv" and c.bubble == ""'
	A "empty again" none 'c.main == "" and not c.wanted'
}

# ---- geometry: left, centre, right, unknown; even margins; the bar moves and returns ----
geo() { # NAME X
	local n=$1 x=$2
	{ echo "w 3000"; p base; shot g-$n-idle
	  cam post --id a --icon timer --head Sample --title Hello --tail 12%; p up; shot g-$n-compact
	  for i in 1 2 3 4 5; do echo "x notify-send -a App$i T$i B"; echo "w 300"; done; echo "w 900"; t 0.5 0.8 900; p notifs; shot g-$n-notifs; echo "w 4500"
	  echo "x phonecamera update --id a --title 'A title that is rather long indeed' --tail ''"; p wide 900; shot g-$n-wide
	  echo "x phonecamera update --id a --tail 12%"; echo "w 700"; p narrow 100; shot g-$n-narrow; echo "w 300"
	  case $n in left) tl 110 25 900 ;; far) tl 110 82 900 ;; center) tl 240 25 900 ;; right) tl 310 25 900 ;; esac; p open; shot g-$n-open
	  drag 0.5 0.7 0.5 0.9; t 0.5 0.8 900; echo "x phonecamera end a"; p back 1000; shot g-$n-back; } >"$W/script"
	printf 'root_color = 205080\n' >>"$W/cfg/phonegluewc/config.conf"
	pconf "camera_hole=$x,42.31,52.38"
}
geo left 89.3
run gleft && {
	A "left: even margins" up 'abs(c.T + 4 - c.hx - 0 + c.hx - 15.36) < 0.1 and abs(c.L + 4 - c.hx) < 0.01 and abs(c.B - c.T - c.hd - 8) < 0.01'
	A "left: stretches rightward only" up 'c.side == "left" and c.R > c.hx + c.hd + 20'
	A "left: the clock follows at the pill's end" up 'abs(b.clockX - round((c.E + 8) * 2.75) / 2.75) < 0.01'
	A "left: icons go before the clock" wide 'b.slots < 5 and b.clockX > 57'
	ok "left: the clock fades only with no icons left" 'grep -a "BAR " "$W/gleft.log" | python3 -c "
import sys, json
for l in sys.stdin:
    b = json.loads(l[l.find(\"BAR {\") + 4:])
    assert b[\"clockOp\"] > 0.99 or b[\"notifs\"] == 0 or b[\"slots\"] < 1"'
	A "left: expanded leaves 8 px each side" open 'c.open and abs(c.L - 8) < 0.01 and abs(c.R - (392 - 8)) < 0.01'
	A "left: the clock returns exactly" back 'abs(b.clockX - 57.4545) < 0.01 and c.main == ""'
	for f in idle; do :; done
	for f in compact notifs wide narrow open back; do ok "left: nothing over the camera in $f" "black g-left-$f $HL $HT $HD"; done
}
geo center 513.81
run gcenter && {
	A "centre: grows both ways around the hole" up 'c.side == "center" and c.L < c.hx - 4 and c.R > c.hx + c.hd + 4 and abs((c.hx - c.L) - (c.R - c.hx - c.hd)) < 0.01'
	A "centre: the clock stays in its corner" up 'b.clockX < 30'
	A "centre: the right group stays right" up 'b.rightX > c.R'
	A "centre: a long title stops short of the icons" wide 'b.rightX - 7 < c.R <= b.rightX - 5.9'
	A "centre: a short tail is not squeezed" narrow 'c.R - c.hx - c.hd > 45'
	A "centre: expanded covers the bar" open 'c.open and c.L < 9'
	A "centre: back" back 'c.main == ""'
	for f in compact notifs wide narrow open back; do ok "centre: nothing over the camera in $f" "black g-center-$f 513.81 $HT $HD"; done
}
geo right 938.32
run gright && {
	A "right: stretches leftward only" up 'c.side == "right" and c.L < c.hx - 20 and abs(c.R - c.hx - c.hd - 4) < 0.01'
	A "right: the clock stays in its corner" up 'b.clockX < 30'
	A "right: the right group ends before the pill" up 'b.rightEnd <= c.S - 7.9 or b.rightEnd <= c.L'
	A "right: back" back 'c.main == ""'
	for f in compact notifs wide narrow open back; do ok "right: nothing over the camera in $f" "black g-right-$f 938.32 $HT $HD"; done
}
# a hole far from the edge
geo far 89.3; pconf "camera_hole=89.3,200,52.38"
run gfar && {
	A "far hole: margins even and the top follows" up 'abs(c.T - (200 * 392 / 1080 - 4)) < 0.1 and abs(c.B - c.T - c.hd - 8) < 0.01'
	A "far hole: the bar stays as it was" up 'abs(b.clockX - 57.4545) < 0.01'
	A "far hole: expanded still around it" open 'c.open and c.B > 200 * 392 / 1080 + 19'
	for f in compact wide open; do ok "far hole: nothing over the camera in $f" "black g-far-$f $HL 200 $HD"; done
}
# unknown: a centred pill, no hole assumed
{ echo "w 3000"; p base; cam post --id a --title Hello --tail 12% --icon timer; p up; shot g-none-compact; tl 196 20 900; p open; shot g-none-open; } >"$W/script"
run gnone PHONE_COMPATIBLE=none && {
	A "unknown: centred pill" up 'not c.known and c.side == "center" and abs((c.L + c.R) / 2 - 196) < 0.1'
	A "unknown: the bar has its corners" base 'b.clockX < 30'
	A "unknown: expanded" open 'c.open'
}

# ---- turned: the hole moves with the screen; the capture is the panel as built, so the hole stays put there ----
rot() { # TRANSFORM
	# after start: the compositor writes its own turn, normal here, when it starts
	{ echo "w 3000"; echo "x echo $1 >$W/state/phonegluewc/orientation"; echo "w 500"; p base; cam post --id a --icon timer --head Sample --title Hello --tail 12%; p up; shot r-$1-compact
	  echo "x phonecamera end a"; p back 1000; } >"$W/script"
	printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75 transform=%s\nroot_color = 205080\n' "$1" >"$W/cfg/phonegluewc/config.conf"
	pconf "camera_hole=89.3,42.31,52.38"
	echo "$1" >"$W/state/phonegluewc/orientation"
}
rot 90
run r90 && {
	A "turned 90: the hole is on the top right" up 'c.known and c.side == "right" and c.hx > 830 and c.hy < 36'
	A "turned 90: the pill sits beside it" up 'c.main == "a" and c.L < c.hx - 20 and abs(c.R - c.hx - c.hd - 4) < 0.01'
	ok "turned 90: nothing over the camera" "black r-90-compact $HL $HT $HD"
}
rot 270
run r270 && {
	A "turned 270: the hole is low, the pill centred on top" up 'not c.known and c.side == "center" and abs((c.L + c.R) / 2 - 436) < 2 and c.T < 10'
	ok "turned 270: nothing over the camera" "black r-270-compact $HL $HT $HD"
}
rot 180
run r180 && {
	A "turned 180: the pill centred on top" up 'not c.known and c.side == "center" and abs((c.L + c.R) / 2 - 196) < 2'
	ok "turned 180: nothing over the camera" "black r-180-compact $HL $HT $HD"
}
rm -f "$W/state/phonegluewc/orientation"

# ---- settings: saved and live, off restores ----
{ echo "w 3000"; p start
  echo "x pset set phone camera_hole 513.81,42.31,52.38"; p center 900
  echo "x pset set phone camera_hole auto"; p auto 900
  cam post --id a --title Hi --tail 1; p up
  echo "x pset set phone dyn_apps off"; p appsoff 900; echo "x pset set phone dyn_apps on"; p appson 900
  echo "x pset set phone dynamic_camera off"; p off 1000; shot off-live
  echo "x pset set phone dynamic_camera on"; p on 1500; cam post --id b --title Hi --tail 1; p on2
  echo "x phonecamera end b"; p on3 900; } >"$W/script"
run settings && {
	A "position: starts from the table" start 'abs(c.hd - 19.05) < 0.1 and c.side == "left"'
	A "position: a saved one is live" center 'c.side == "center"'
	A "position: automatic returns to the table" auto 'c.side == "left"'
	A "a group turned off hides it" appsoff 'c.main == ""'
	A "and on again it is back" appson 'c.main == "a"'
	A "off: nothing, bar as before" off 'not c.on and c.main == "" and not c.wanted and abs(b.clockX - 57.4545) < 0.01'
	A "on again works" on2 'c.on and c.main == "b"'
}
# settings page: real app, real pset
cat >"$W/set.sh" <<EOF
exec "$SRC/settings/phonesettings" camera >>"$W/app.log" 2>&1
EOF
{ echo "w 3000"; echo "x sh $W/set.sh"; echo "w 3000"; shot set-page
  tl 196 0 1; tl 340 112 700; echo "x cp $W/cfg/phonegluewc/phone.conf $W/after-off"; echo "w 100"; tl 340 112 700
  tl 196 176 1200; shot set-place; drag 0.5 0.8 0.6 0.81; shot set-dragged; tl 74 543 1200; echo "x cp $W/cfg/phonegluewc/phone.conf $W/after-done"; echo "w 300"; p placed; shot set-after; } >"$W/script"
rm -f "$W/stubs/phonesettings"
run settingspage && {
	ok "page: the on/off toggle saves" 'grep -qx "dynamic_camera=off" "$W/after-off"'
	ok "page: Done saves numbers" 'grep -Eq "^camera_hole=[0-9.]+,[0-9.]+,[0-9.]+$" "$W/after-done"'
	A "page: the ring moved by the finger's path, and it is live" placed 'abs(c.hx - 197.3 * 392 / 1080) < 1 and abs(c.hy - 66.31 * 392 / 1080) < 1'
	grep -a 'note:\|qml.*[Ee]rror' "$W/app.log" 2>/dev/null | cut -c1-200 | head
}
stub phonesettings <<'X'
echo "phonesettings $*" >>"$L"
X

# ---- off from the start ----
pconf dynamic_camera=off
{ echo "w 3000"; p base; shot off; echo "x sh $W/player.sh"; p music 1800; do_ none 100; } >"$W/script"
run off && {
	A "off from the start: no socket, no shape" base 'not c.on and not c.wanted'
	ok "off: the socket does not exist" '! grep -aq "listening on.*cam.sock" "$W/off.log"'
	A "off: music does not come here" music 'c.main == ""'
}

# ---- the lock ----
{ echo "w 3500"; p locked; shot l-idle
  echo "x sh $W/player.sh"; echo "w 1800"; p music; shot l-music; tl 72 25 900; p musicopen; shot l-music-open; tl 196 180 800; p musicpaused; t 0.5 0.7 800; p musicshut; hold 0.15 0.028; p musichold
  echo "x kill \$(cat $W/player.pid)"; echo "w 1200"
  echo "x sh $W/poster.sh lv --icon note --head Bank --title Secret --text Hidden --tail 99 --button a:Pay"; p live 900; shot l-live; tl 72 25 700; p liveopen; killp poster-lv
  echo "x notify-send -a Chat Alex 'Secret text'"; p notif 900; shot l-notif; echo "w 4800"
  echo "x sh $W/poster.sh c --kind call --state incoming --title Alex"; p call 900; tl 72 25 900; p callopen; shot l-call; killp poster-c
  do_ unlock 150; p unlock 50; shot l-unlock-1; echo "w 300"; shot l-unlock-2; p unlocked 1500; } >"$W/script"
run lock PHONEGLUEWC_RELOCK=1 PHONE_AUTH_MOCK=test && {
	A "lock: nothing active, nothing drawn" locked 'c.lock and c.main == "" and not c.wanted'
	A "lock: music with its title" music 'c.main == "music" and c.title == "Night Drive"'
	A "lock: music expands" musicopen 'c.open'
	ok "lock: music controls work" 'grep -Eq "player (PlayPause|Pause)" "$W/player.log"'
	ok "lock: a hold opens nothing" '! grep -a "launch\|app " "$W/lock.log" | grep -q sample-music'
	A "lock: third party text is hidden" live 'c.main == "lv" and c.title == "" and c.tail == "" and c.buttons == 0 and c.noExpand'
	A "lock: and it does not expand" liveopen 'not c.open'
	A "lock: notification text is hidden" notif 'c.main == "notif" and c.title == "" and c.sub == "" and c.head == ""'
	A "lock: a call can be answered" callopen 'c.main == "c" and c.open and c.title == "Alex"'
	A "unlock: its short animation" unlock 'c.main == "unlock" and not c.lock'
	A "unlock: then nothing" unlocked 'c.main == "" and not c.wanted'
}

# ---- the laptop's drawn hole ----
for side in left center right; do
	{ echo "w 3000"; p idle; shot f-$side-idle; cam post --id a --icon timer --title Hello --tail 12%; p up; shot f-$side-compact; } >"$W/script"
	run fake$side PHONE_NO_HOLE=1 PHONE_CAMERA=$side PHONE_COMPATIBLE=none && {
		A "laptop $side: a drawn hole when on" idle "c.fake and c.side == '$side'"
		A "laptop $side: the window stays for it" idle 'c.wanted'
	}
done
pconf dynamic_camera=off
{ echo "w 3000"; p idle; shot f-off; } >"$W/script"
run fakeoff PHONE_NO_HOLE=1 PHONE_COMPATIBLE=none && {
	A "laptop off: no hole, clock in the corner" idle 'not c.fake and not c.known and b.clockX < 30'
}

# ---- animations off: direct changes ----
pconf animations=off
{ echo "w 3000"; cam post --id a --title Hi --tail 1; p up; tl 72 25 500; p open; t 0.5 0.8 500; echo "x phonecamera end a"; p gone 400; } >"$W/script"
run noanim && {
	ok "animations off: never moving" '! grep -a "CAM " "$W/noanim.log" | grep -q "\"moving\":true"'
	A "animations off: still opens" open 'c.open'
	A "animations off: still clears" gone 'c.main == ""'
}

# ---- gestures next to and on the pill ----
{ echo "w 3000"; cam post --id a --title Hi --tail 1 --icon timer; p up
  drag 0.13 0.028 0.13 0.5; p pillpull 400; drag 0.5 0.7 0.5 0.1; p shut 800
  drag 0.5 0.028 0.5 0.5; p besidepull 400; drag 0.5 0.7 0.5 0.1; p shut2 800
  tl 80 25 900; p open; drag 0.5 0.09 0.5 0.5; p cardpull 400; drag 0.5 0.7 0.5 0.1; p shut3 800
  echo "x notify-send -a Chat Alex One"; echo "w 900"; p notifcard; drag 0.2 0.06 0.2 0.5; p notifleft 400; drag 0.5 0.7 0.5 0.1; p shut4 800; echo "w 4500"
  echo "x notify-send -a Chat Alex Two"; echo "w 900"; drag 0.8 0.06 0.8 0.5; p notifright 400; drag 0.5 0.7 0.5 0.1; p shut5 800; echo "w 4500"
  tl 80 25 900; p open2; hold 0.5 0.06; p heldopen; } >"$W/script"
run gestures && {
	A "a pull on the pill opens the sheet" pillpull 'c.panel and c.main == "a"'
	A "a pull right next to it does too" besidepull 'c.panel'
	A "tap on the pill expands" open 'c.open'
	A "a pull on the open card opens the sheet, the card goes" cardpull 'c.panel and not c.open'
	A "a notification opens as a card" notifcard 'c.open and c.main != "a"'
	A "a pull on it, at the left: the left sheet" notifleft 'c.panel and not c.open and c.sheet == 0'
	A "a pull on it, at the right: the right sheet" notifright 'c.panel and not c.open and c.sheet == 1'
}

# ---- the local interface: from any program, so never trusted ----
cat >"$W/bad.py" <<'P'
import json, socket, sys, time
path, out = sys.argv[1:3]
def send(line, keep=False):
    s = socket.socket(socket.AF_UNIX); s.connect(path)
    s.sendall(line if isinstance(line, bytes) else line.encode()); s.settimeout(1.5)
    try: r = s.recv(4096).decode(errors='replace').strip()
    except Exception as e: r = 'timeout'
    if keep: return s, r
    s.close(); return r
with open(out, 'w') as f:
    def t(name, line): f.write(name + ' ' + send(line) + '\n'); f.flush()
    t('notjson', 'not json\n'); t('array', '[1]\n'); t('noid', '{"op":"post"}\n')
    t('badid', '{"op":"post","id":"../../etc"}\n'); t('longtitle', json.dumps({"op":"post","id":"a","title":"x"*65}) + '\n')
    t('longtext', json.dumps({"op":"post","id":"a","text":"x"*141}) + '\n'); t('pathicon', '{"op":"post","id":"a","icon":"/etc/passwd"}\n')
    t('urlicon', '{"op":"post","id":"a","icon":"file:///etc/passwd"}\n'); t('badprogress', '{"op":"post","id":"a","progress":3}\n')
    t('titletype', '{"op":"post","id":"a","title":{"a":1}}\n'); t('badkind', '{"op":"post","id":"a","kind":"root"}\n')
    t('protoproto', '{"op":"post","id":"a","kind":"__proto__"}\n'); t('manybuttons', json.dumps({"op":"post","id":"a","buttons":[{"id":"a","label":"b"}]*4}) + '\n')
    t('badbutton', '{"op":"post","id":"a","buttons":[{"id":"a b","label":"x"}]}\n'); t('hugeline', 'x' * 8000 + '\n'); t('noend', 'x' * 8000)
    t('badseconds', '{"op":"timer","seconds":-1}\n'); t('updnone', '{"op":"update","id":"nothing"}\n')
    s, r = send('{"op":"post","id":"rich","title":"<b>bold</b><img src=x>","text":"a\\u202eb\\nc","icon":"timer"}\n', True); f.write('rich ' + r + '\n'); f.flush()
    held = [s]
    time.sleep(1.2)
    s2 = socket.socket(socket.AF_UNIX); s2.connect(path); s2.settimeout(1)
    for i in range(5):
        s2.sendall(('{"op":"post","id":"m%d","title":"m"}\n' % i).encode()); time.sleep(0.05)
    time.sleep(0.3)
    try: f.write('toomany ' + s2.recv(4096).decode().replace('\n', ' ') + '\n')
    except Exception: f.write('toomany timeout\n')
    f.flush(); s2.close(); time.sleep(0.5)
    s3 = socket.socket(socket.AF_UNIX); s3.connect(path); s3.settimeout(1.5)
    s3.sendall(b''.join(b'{"op":"poll"}\n' for i in range(40))); time.sleep(0.6)
    try: f.write('flood ' + s3.recv(65536).decode().replace('\n', ' ')[-60:] + '\n')
    except Exception: f.write('flood timeout\n')
    f.flush(); s3.close()
    time.sleep(1.5)
    held[0].close(); time.sleep(0.6)
    f.write('done\n')
P
echo "python3 $W/bad.py $W/run/cam.sock $W/bad.out" >"$W/bad.sh"
{ echo "w 3000"; echo "x sh $W/bad.sh"; echo "w 2200"; p during; echo "w 8000"; p after; shot i-after; } >"$W/script"
run input && {
	rj() { grep -q "^$1 .*error" "$W/bad.out"; }
	for n in notjson array noid badid longtitle longtext pathicon urlicon badprogress titletype badkind protoproto manybuttons badbutton hugeline noend badseconds updnone; do ok "input refused: $n" "rj $n"; done
	ok "input: a good one is accepted" 'grep -q "^rich .*ok" "$W/bad.out"'
	ok "input: at most four per connection" 'grep -q "^toomany .*too many" "$W/bad.out"'
	ok "input: a flood is cut off" 'grep -q "^flood .*too much" "$W/bad.out"'
	ok "input: nothing stays after they go" 'at after "c.main == \"\"" '
	ok "input: rich text stays plain" 'grep -a "CAM " "$W/input.log" | grep -qF "<b>bold</b><img src=x>"'
	ok "input: direction marks are gone" '! grep -a "CAM " "$W/input.log" | grep -qP "\xe2\x80\xae"'
}
[ -z "${LOGS:-}" ] || [ ! -e "$W/bad.out" ] || cp "$W/bad.out" "$LOGS/"

# ---- captures only: every activity, compact and open. SCENES="gal-left" runs one ----
gal() { # SIDE HOLE_X TAP_X
	local n=$1 x=$3 a=a-$1
	both() { shot "$a-$1"; tl "$x" 25 900; shot "$a-$1-open"; t 0.5 0.8 700; }
	{ echo "w 3000"
	  echo "x sh $W/player.sh"; echo "w 1800"; both music; echo "x kill \$(cat $W/player.pid)"; echo "w 1200"
	  echo "x sh $W/poster.sh c --kind call --state incoming --title 'Alex Sample'"; echo "w 1000"; shot "$a-ring-open"; t 0.5 0.8 700; shot "$a-ring"
	  cam update --id c --state active --elapsed; both call; killp poster-c
	  cam timer 300; both timer; cam cancel timer; echo "w 800"
	  cam stopwatch; both stopwatch; cam cancel stopwatch; echo "w 800"
	  echo "x sh $W/rec.sh"; do_ rec 900; both record; tl "$x" 25 900; tl 76 118 1500
	  cam post --id nv --kind nav --icon navr --head "'In 200 m'" --title "'Turn right'" --text "'Strada Sample'" --tail "'200 m'"; both nav; cam end nv; echo "w 800"
	  cam post --id tr --kind transfer --icon transfer --head Transfer --title file.zip --progress 0.4; both transfer; cam end tr; echo "w 800"
	  echo "x sh $W/poster.sh lv --icon note --head App --title Pizza --text Soon --tail 12m --button a:Fine --button b:Later"; echo "w 900"; both live; killp poster-lv
	  echo "x notify-send -a Chat Alex 'Are you coming?'"; echo "w 1000"; shot "$a-notif-open"; t 0.5 0.8 700; shot "$a-notif"; echo "w 4800"
	  echo "x echo Charging >$BAT/status"; polled; both charging; echo "w 2500"
	  echo "x echo Discharging >$BAT/status"; echo "x echo 14 >$BAT/capacity"; polled; both low; echo "w 4000"; echo "x echo 62 >$BAT/capacity"
	  echo "x echo 0.70 >$ST/vol"; polled; both volume; echo "w 2000"
	  echo "x echo Device 00 Test Buds >$ST/bt"; polled; both device; echo "w 3000"
	  echo "x echo Tun:vpn >$ST/active"; polled; both vpn; echo "w 2000"; echo "x : >$ST/active"; polled; echo "w 3000"
	  echo "x echo Hotspot:802-11-wireless >$ST/active"; polled; both hotspot; echo "x : >$ST/active"; polled; echo "w 3000"
	  echo "x echo '  71. in < Mic' >$ST/streams"; polled; both mic; echo "x : >$ST/streams"; polled; echo "w 500"
	  echo "x echo 1 >$S/leds/white:torch/brightness"; polled; both torch; echo "x echo 0 >$S/leds/white:torch/brightness"; polled; echo "w 500"
	  echo "x pset set phone ringer silent"; echo "w 800"; both ringer; echo "w 6500"
	  do_ flash 800; both screenshot; echo "w 2500"; } >"$W/script"
	printf 'root_color = 205080\n' >>"$W/cfg/phonegluewc/config.conf"
	pconf "camera_hole=$2,42.31,52.38"
	run "gal-$n"
	reset
}
case " ${SCENES:-} " in *" gal-"*)
	gal left 89.3 72; gal center 513.81 196; gal right 938.32 320 ;;
esac
# ---- the demo video, from files outside the project: SCENES=video VIDEO_DIR=... ----
case " ${SCENES:-} " in *" video "*) . "$VIDEO_DIR/scene.sh" ;; esac
# ---- captures only: one expand and one collapse, frame by frame ----
case " ${SCENES:-} " in *" frames "*)
	frames() { for i in 0 1 2 3 4 5 6 7 8 9; do shot_ "$1-$i"; echo "w 25"; done; echo "w 600"; }
	shot_() { echo "x wshot $W/s/${1}.ppm"; }
	{ echo "w 3000"; echo "x sh $W/player.sh"; echo "w 1800"; echo "d 0 0.18 0.028"; echo f; echo "u 0"; echo f; frames fr-open
	  echo "d 0 0.5 0.8"; echo f; echo "u 0"; echo f; frames fr-close; echo "w 500"; } >"$W/script"
	printf 'root_color = 205080\n' >>"$W/cfg/phonegluewc/config.conf"
	run frames
	reset ;;
esac

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
