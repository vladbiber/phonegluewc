#!/bin/bash
# The screen recorder, headless at phone size: sheet, countdown, floating control, stop, lock stops it. wf-recorder is a fake.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-record.XXXXXX")
SANDBOX_EXTRA="date"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
SH=$BUILD/shell
sed -i 's|^    property int count: 3|&\n    onStageChanged: console.log("REC stage=" + stage)\n    readonly property bool rec: Status.recording\n    onRecChanged: console.log("REC rec=" + rec)|' "$SH/Recorder.qml"
sed -i 's|^    readonly property string idsKey: .*|&\n    onIdsKeyChanged: console.log("IDS " + idsKey)|' "$SH/QuickModel.qml"
for k in '"REC stage=' '"IDS "'; do grep -q "$k" "$SH"/*.qml || { echo "FAIL log not injected: $k"; exit 1; }; done
COMP=$BUILD/phonegluewc

mkdir -p "$W/fakebin" "$W/nowf" "$W/fake" "$W/cfg/phonegluewc" "$W/state/phonegluewc"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep fbcli; do
	ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; ln -sf "$SRC/laptop/fake-tool" "$W/nowf/$t"; done
for p in systemctl loginctl reboot poweroff shutdown halt suspend rtcwake zzz; do
	printf '#!/bin/sh\necho "POWER $0 $*" >>%s/power.log\n' "$W" >"$W/fakebin/$p"; chmod +x "$W/fakebin/$p"; cp "$W/fakebin/$p" "$W/nowf/$p"; done
# stays alive until SIGINT, then writes the file it was given, as wf-recorder does
# python, since a background sh ignores SIGINT and the real tool sets its own handler; named as the real one
cat >"$W/fakebin/wf-recorder" <<EOF
#!$(command -v python3) -I
import ctypes, signal, sys, time
ctypes.CDLL(None).prctl(15, b"wf-recorder")
a =sys.argv[1:]; f = a[a.index("-f") + 1]
open("$W/rec.log", "a").write("start " + " ".join(a) + "\n")
def stop(*_):
    open("$W/rec.log", "a").write("stop\n"); open(f, "w").write("data\n"); sys.exit(0)
signal.signal(signal.SIGINT, stop)
while True: time.sleep(0.2)
EOF
printf '#!/bin/sh\necho "notify $*" >>%s/rec.log\n' "$W" >"$W/fakebin/notify-send"
chmod +x "$W/fakebin/wf-recorder" "$W/fakebin/notify-send"
S=$W/sys; mkdir -p "$S/power_supply/BAT0" "$S/backlight/f"; echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"; echo 100 >"$S/backlight/f/max_brightness"; echo 60 >"$S/backlight/f/brightness"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'user=sampleuser\n' >"$W/cfg/phonegluewc/login.conf"
printf 'quick_tiles = record,airplane\n' >"$W/cfg/phonegluewc/phone.conf"
DIR="$W/home/Videos/Screen recordings"

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-700}"; }
open() { echo "d 0 0.75 0.012"; echo f; for y in 0.07 0.13 0.2 0.28 0.36 0.44 0.52 0.6; do echo "m 0 0.75 $y"; echo f; echo "w 30"; done; echo "w 200"; echo "u 0"; echo f; echo "w 1200"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
mark() { echo "x cp $W/rec.log $W/$1.rec"; echo "w 150"; echo "p $1"; }
TILE="0.267 0.3345"; CANCEL="0.501 0.938"; START="0.791 0.938"; SOUND="0.5 0.848"; STOP="0.898 0.0848"
run() { local n=$1; shift
	comp_start QT_QUICK_BACKEND=software FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$SH" PHONEGLUEWC_KEYBOARD= PHONE_AUTH_MOCK=test PHONEGLUEWC_FAKETOUCH="$W/script" "$@"
	comp_wait 900
	cp "$W/gw.log" "$W/$n.log"
	comp_stop
}
: >"$W/rec.log"

{ echo "w 3000"; open; shot r-panel; t $TILE 900; shot r-sheet; mark sheet
  t $CANCEL 900; mark cancelled
  open; t $TILE 900; t $SOUND 600; t $START 1500; shot r-count; echo "w 2500"; mark started; shot r-chip
  # carry the control down by its time, then stop it where it landed
  echo "d 0 0.82 0.0848"; echo f; for y in 0.12 0.16 0.2 0.24 0.28 0.3; do echo "m 0 0.82 $y"; echo f; echo "w 30"; done; echo "u 0"; echo f; echo "w 500"; shot r-moved
  # the drag starts past a threshold, so the control lands a little above the finger
  t 0.898 0.2645 1500; mark stopped
  # a tap during the countdown cancels it
  open; t $TILE 900; t $START 1200; t 0.5 0.5 3500; mark countcancel
  # recording, then the power key locks the phone
  open; t $TILE 900; t $START 4000; mark again
  echo "K 116 1"; echo "w 60"; echo "K 116 0"; echo "w 2500"; mark locked
  echo "p end"; } >"$W/script"
SANDBOX_PATH="$W/fakebin:$BUILD" run one

{ echo "w 3000"; open; echo "p nowf"; echo "p end"; } >"$W/script"
SANDBOX_PATH="$W/nowf:$BUILD" run two

for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
# the last REC line of a kind before the FT line $2
last() { awk -v l="FT $2 " -v k="REC $3=" 'index($0, k) { v = substr($0, index($0, k) + length(k)) } index($0, l) == 1 { print v; exit }' "$W/$1.log"; }
starts() { grep -c '^start' "$W/$1.rec"; }
[ -n "${REC_VERBOSE:-}" ] && { grep -a '^FT \|REC \|IDS \|WARN\|rror' "$W/one.log" "$W/two.log" | cut -c1-160; cat "$W/rec.log"; ls -la "$DIR"; }
ok "the tile opens the sheet, nothing records yet" '[ "$(last one sheet stage)" = sheet ] && [ "$(starts sheet)" = 0 ]'
ok "Cancel closes the sheet without recording" '[ "$(last one cancelled stage)" = "" ] && [ "$(starts cancelled)" = 0 ]'
ok "Start counts down, then records"          '[ "$(starts started)" = 1 ] && [ "$(last one started rec)" = true ] && grep -q "REC stage=count" "$W/one.log"'
ok "the sound choice adds the microphone, and is kept" 'grep -q "^start -a -f " "$W/started.rec" && grep -q "^record_sound = on$" "$W/cfg/phonegluewc/phone.conf"'
ok "the file goes to Videos, Screen recordings" 'grep -q "^start -a -f $DIR/Screen recording [0-9-]* [0-9-]*\.mp4$" "$W/started.rec"'
ok "the moved control stops the recording"     'grep -q "^stop" "$W/stopped.rec" && [ "$(last one stopped rec)" = false ]'
ok "the saved file is there, with a note"      'f=$(sed -n "s/^notify .*Recording saved //p" "$W/stopped.rec"); [ -s "$f" ] && [ "${f%/*}" = "$DIR" ]'
ok "a tap during the countdown cancels it"     '[ "$(starts countcancel)" = 1 ] && [ "$(last one countcancel stage)" = "" ]'
ok "locking the phone stops the recording"     '[ "$(starts again)" = 2 ] && [ "$(grep -c "^stop" "$W/locked.rec")" = 2 ] && grep -q "^FT locked .*lock=1" "$W/one.log" && [ "$(last one locked rec)" = false ]'
ok "with wf-recorder present the tile is there" 'grep "IDS " "$W/one.log" | tail -1 | grep -qw record'
ok "without wf-recorder the tile is hidden"    'grep -q "IDS airplane" "$W/two.log" && ! grep "IDS " "$W/two.log" | tail -1 | grep -qw record'
ok "no crash, no warning from the recorder"    '! grep -a "Recorder.qml\|RecordOverlay.qml\|Segmentation\|core dumped" "$W/one.log" "$W/two.log" | grep -q .'
ok "no core files"                             '! ls "$W"/core.* "$BUILD"/core.* >/dev/null 2>&1'
ok "nothing powered off"                       '! grep -q "poweroff\|suspend\|reboot\|halt" "$W/power.log" 2>/dev/null'
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
exit 0
