#!/bin/bash
# Hardware buttons through a fake key device. Power tools are fakes that only record. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-button.XXXXXX")
SANDBOX_EXTRA="grim date"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1

fails=0
ok() { # NAME CONDITION
	if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
POWER=116; VOLD=114; F5=63; F6=64
FAKE=$W/fake; O=$W/out; RECD=$W/recd; REC=$RECD/rec; CFG=$W/cfg/phonegluewc; LEDS=$W/leds
mkdir -p "$FAKE" "$O" "$RECD" "$CFG" "$W/state/phonegluewc" "$W/nofake"
: >"$REC"
# the shell reads the volume with wpctl status: only set-volume counts
for t in wpctl pactl loginctl systemctl rtcwake poweroff reboot shutdown halt zzz pm-suspend brightnessctl; do
	printf '#!/bin/sh\necho "$(date +%%s%%3N) %s $*" >>"%s"\n' "$t" "$REC" >"$FAKE/$t"
	chmod +x "$FAKE/$t"
done
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$CFG/config.conf"
printf 'user=sampleuser\n' >"$CFG/login.conf"
led() { rm -rf "$LEDS"; mkdir -p "$LEDS/white:torch"; echo 0 >"$LEDS/white:torch/brightness"; echo 255 >"$LEDS/white:torch/max_brightness"; }

press() { echo "K $1 1"; echo "w ${2:-60}"; echo "K $1 0"; echo "w ${3:-120}"; }
wait_ms() { echo "w $1"; }
shot() { echo "x $SRC/tests/wshot $O/$1.ppm"; echo "w 500"; }
mark() { echo "x cat $W/state/phonegluewc/button >$O/$1"; echo "w 150"; }
pics() { find "$W/home/Pictures/Screenshots" -name '*.png' 2>/dev/null | wc -l; }
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$FAKE:$BUILD"
: >"$W/all.log"
session() { # NAME [ENV...]
	local n=$1; shift
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEGLUEWC_KEYBOARD= PHONE_AUTH_MOCK=test \
		PHONE_LED_DIR="$LEDS" PHONEGLUEWC_FAKETOUCH="$W/$n.script" "$@"
	comp_wait 700
	cp "$W/gw.log" "$W/$n.log"
	cat "$W/gw.log" >>"$W/all.log"
	comp_stop
	python3 -c "
from PIL import Image; import glob, os
for f in glob.glob('$O/*.ppm'): Image.open(f).save(f[:-4] + '.png'); os.remove(f)"
}
has() { grep -c "button $2\$" "$W/$1.log"; }
res() { grep -c "button result.*$2" "$W/$1.log"; }

# ---- open phone: volume key delay, chord both ways, no lock from either ----
led
{ echo "w 3000"
  shot start
  echo "x date +%s%3N >$O/vol-at"; echo "w 20"; press $VOLD 60 500
  mark before-chord
  echo "K $POWER 1"; echo "w 80"; echo "K $VOLD 1"; echo "w 80"; echo "K $VOLD 0"; echo "w 40"; echo "K $POWER 0"; echo "w 40"; shot chord-flash; wait_ms 1200
  shot chord-after
  echo "x grep -c set-volume $REC >$O/rec-after-powerfirst"; echo "w 100"
  echo "K $VOLD 1"; echo "w 80"; echo "K $POWER 1"; echo "w 1200"; echo "K $POWER 0"; echo "w 40"; echo "K $VOLD 0"; echo "w 1500"
  shot chord2-after
  echo "x grep -c set-volume $REC >$O/rec-after-volfirst"; echo "w 100"
  echo "K 30 1"; echo "w 30"; echo "K 30 0"; wait_ms 100
  echo "x true"; echo "w 300"; } >"$W/open.script"
session open
ok "the key device reached the compositor: volume down called the tool once" '[ "$(head -1 "$O/rec-after-powerfirst")" = 1 ] && grep -q "wpctl set-volume" "$REC"'
VOLAT=$(cat "$O/vol-at"); VOLGOT=$(grep -m1 set-volume "$REC" | cut -d" " -f1)
echo "note volume key to tool call: $((VOLGOT - VOLAT - 20)) ms, press was sent up to one tick after the mark"
ok "volume key has no wait for the chord"       '[ $((VOLGOT - VOLAT)) -lt 200 ]'
ok "two chords saved two pictures"              '[ "$(pics)" = 2 ]'
ok "pictures have a timestamp and are PNG"      'find "$W/home/Pictures/Screenshots" -name "Screenshot-20[0-9]*-[0-9]*.png" -exec file -b {} + | grep -c "^PNG image data, 1080 x 240[0-9]" | grep -qx 2'
ok "no partly written picture left"             '[ -z "$(find "$W/home/Pictures/Screenshots" -name "*.tmp")" ]'
ok "power first: the volume did not move"       '[ "$(cat "$O/rec-after-powerfirst")" = 1 ]'
ok "volume first: the chord does not move the volume" '[ "$(cat "$O/rec-after-volfirst")" = 1 ]'
ok "a chord never locks"                        '[ "$(has open single)" = 0 ] && ! grep -q "qs.*Lock\|session_lock.*new" "$W/open.log"'
ok "a chord counts as no press afterwards"      '[ "$(has open double)" = 0 ] && [ "$(has open triple)" = 0 ]'

# ---- single press locks after the window; double and triple on the lock; then a typed password blocks the shot ----
led
: >"$REC"
BEFORE=$(pics)
{ echo "w 3000"
  press $POWER 60 100
  mark single-100ms
  wait_ms 300
  mark single-400ms
  wait_ms 1500; shot locked
  press $POWER 40 60; press $POWER 40 700; shot locked-double
  wait_ms 1000
  press $POWER 40 60; press $POWER 40 60; press $POWER 40 900; shot locked-triple
  wait_ms 1000; mark triple
  echo "K $VOLD 1"; echo "w 30"; echo "K $POWER 1"; echo "w 60"; echo "K $POWER 0"; echo "K $VOLD 0"; echo "w 1800"; shot locked-chord
  echo "d 0 0.5 0.86"; echo f; echo "u 0"; echo f; echo "w 1500"
  for k in 20 18; do echo "K $k 1"; echo "w 30"; echo "K $k 0"; echo "w 80"; done
  echo "w 500"; shot typed
  echo "K $VOLD 1"; echo "w 30"; echo "K $POWER 1"; echo "w 60"; echo "K $POWER 0"; echo "K $VOLD 0"; echo "w 900"; shot typed-chord
  echo "w 2200"
  for k in 31 20; do echo "K $k 1"; echo "w 30"; echo "K $k 0"; echo "w 80"; done
  echo "w 300"; shot typed4
  echo "K 28 1"; echo "w 30"; echo "K 28 0"
  echo "w 1800"; echo "p unlocked"; shot unlocked
  press $POWER 60 100; wait_ms 1500; echo "p relocked"; shot relocked
  echo "x true"; echo "w 300"; } >"$W/lock.script"
session lock
ok "single press: nothing inside the 300 ms window, single after it" '! grep -q single "$O/single-100ms" 2>/dev/null && [ "$(cut -d" " -f2 "$O/single-400ms")" = single ]'
ok "a double or triple sends no single first"  '[ "$(has lock single)" = 2 ]'
ok "double runs the camera message"             '[ "$(has lock double)" = 1 ] && grep -q "button action camera" "$W/lock.log"'
ok "triple turns the flashlight on"             '[ "$(cat "$LEDS/white:torch/brightness")" = 255 ] && [ "$(res lock "Flashlight on")" = 1 ]'
ok "lock screen with nothing typed: saved"      '[ "$(pics)" = $((BEFORE + 1)) ]'
ok "typed characters: refused, no file"         '[ "$(grep -c "button action screenshot" "$W/lock.log")" = 2 ] && [ "$(res lock "Screenshot saved")" = 1 ]'
ok "the password still opens after the buttons" 'grep -q "^FT unlocked .* locked=0" "$W/lock.log" && grep -q "^FT relocked .* locked=1" "$W/lock.log"'
ok "no power tool was ever called"              '! grep -Ev " wpctl " "$REC" | grep -q .'
cp "$O"/*.png "$SHOTS"/ 2>/dev/null

# ---- phone.conf; no LED; unwritable LED ----
rm -rf "$LEDS"; mkdir -p "$LEDS"
printf 'power_double = flashlight\npower_triple = none\n' >"$CFG/phone.conf"
{ echo "w 3000"
  press $POWER 40 60; press $POWER 40 900; shot noled
  wait_ms 2500
  press $POWER 40 60; press $POWER 40 60; press $POWER 40 900
  wait_ms 500; echo "x true"; echo "w 300"; } >"$W/conf.script"
session conf
ok "power_double chose the flashlight"          'grep -q "button action flashlight" "$W/conf.log"'
ok "no LED: a short message, nothing else"      '[ "$(res conf "No flashlight here")" = 1 ]'
ok "power_triple none does nothing"             '[ "$(grep -c "button action none" "$W/conf.log")" = 1 ] && [ "$(grep -c "button result" "$W/conf.log")" = 1 ]'
printf 'power_double = reboot\n' >"$CFG/phone.conf"
{ echo "w 3000"
  press $POWER 40 60; press $POWER 40 900
  echo "x true"; echo "w 300"; } >"$W/bad.script"
session bad
ok "an unknown value falls back to the camera"  'grep -q "button action camera" "$W/bad.log"'
rm -f "$CFG/phone.conf"

# ---- login screen ----
{ echo "w 3000"
  press $POWER 60 900; press $POWER 60 900
  echo "K $VOLD 1"; echo "w 30"; echo "K $POWER 1"; echo "w 60"; echo "K $POWER 0"; echo "K $VOLD 0"; echo "w 1500"; shot login-chord
  echo "x true"; echo "w 300"; } >"$W/login.script"
BEFORE=$(pics)
session login PHONEGLUEWC_GREETER=1
ok "login: one press darkens, the next lights it itself" '[ "$(has login single)" = 1 ]'
ok "login: nothing typed, the shot works"       '[ "$(pics)" = $((BEFORE + 1)) ]'

# ---- the laptop stand-ins; these keys never reach the volume ----
: >"$REC"
BEFORE=$(pics)
{ echo "w 3000"
  echo "K $F5 1"; echo "w 40"; echo "K $F6 1"; echo "w 60"; echo "K $F6 0"; echo "K $F5 0"; echo "w 1500"; shot laptop-chord
  press $F5 60 400
  press $F6 60 1000; shot laptop-lock
  echo "x true"; echo "w 300"; } >"$W/laptop.script"
session laptop PHONEGLUEWC_MOUSE_FINGER=1
ok "laptop: F5 with F6 takes the shot"          '[ "$(pics)" = $((BEFORE + 1)) ]'
ok "laptop: F5 alone never changes the volume"  '! grep -q set-volume "$REC"'
ok "laptop: F6 locks"                           '[ "$(has laptop single)" = 1 ]'
ok "laptop script sets the stand-ins apart"     'grep -q "PHONE_LED_DIR=" "$SRC/run-on-laptop.sh" && grep -q "F6 is the power button" "$SRC/run-on-laptop.sh"'

# ---- the helper by itself ----
bh() { env -i HOME="$W/home" PATH="$W/nofake:$FAKE:/usr/bin:/bin" PHONE_LED_DIR="$LEDS" sh "$SRC/shell/button.sh" "$@" | tr '\n' ' '; }
led
ok "a flash LED counts"       '[ "$(bh flashlight)" = "message=Flashlight on " ]'
ok "and turns off again"      '[ "$(bh flashlight)" = "message=Flashlight off " ] && [ "$(cat "$LEDS/white:torch/brightness")" = 0 ]'
rm -rf "$LEDS"; mkdir -p "$LEDS/kbd_backlight"; echo 0 >"$LEDS/kbd_backlight/brightness"
ok "another LED is left alone" '[ "$(bh flashlight)" = "message=No flashlight here " ] && [ "$(cat "$LEDS/kbd_backlight/brightness")" = 0 ]'
rm -rf "$LEDS"; mkdir -p "$LEDS/white:flash"; echo 0 >"$LEDS/white:flash/brightness"; echo 1 >"$LEDS/white:flash/max_brightness"
chmod 444 "$LEDS/white:flash/brightness"
ok "no permission: a message" '[ "$(id -u)" = 0 ] || [ "$(bh flashlight)" = "message=The flashlight cannot be switched here " ]'
printf '#!/bin/sh\nexit 1\n' >"$W/nofake/grim"; chmod +x "$W/nofake/grim"
ok "a failed shot says so"    '[ "$(bh screenshot)" = "message=Screenshot could not be saved " ]'

ok "the source has no power call"  '! grep -nE "\"(loginctl|systemctl|poweroff|reboot|rtcwake)\"|org.freedesktop.login1" "$SRC/phonegluewc.c" "$SRC/shell/button.sh" | grep -q .'
cp "$O"/*.png "$SHOTS"/ 2>/dev/null
echo "failed: $fails"
[ "$fails" = 0 ]
