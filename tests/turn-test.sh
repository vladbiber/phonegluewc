#!/bin/bash
# Home settings' "home stays upright" switch both ways, and the Rotate tile in quick settings with no sensor:
# a tap turns sideways, a hold picks one of four, either locks the sensor out until the lock tile lets go. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-turn.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/fakeapp" "$SRC/tests/fakeapp.c" "$BUILD/touchlog-xdg-protocol.c" $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0) -lwayland-client || { echo "FAIL fakeapp"; exit 1; }
COMP=$BUILD/phonegluewc
FAILS=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }

C=$W/cfg/phonegluewc; CONF=$C/phone.conf
mkdir -p "$C" "$W/fakebin" "$W/fake"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$C/config.conf"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
printf '#!/bin/sh\n' >"$W/fakebin/phonesettings"; chmod +x "$W/fakebin/phonesettings"
S=$W/sys; mkdir -p "$S/power_supply/BAT0"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
ST=$W/state/phonegluewc
# no sliders without a backlight or a sink: the tiles start right under the bar
TILE="0.267 0.0875"
t() { echo "d 0 $1 $2"; echo f; echo "w 40"; echo "u 0"; echo f; echo "w ${3:-700}"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w ${3:-1100}"; echo "u 0"; echo f; echo "w 700"; }
open() { echo "d 0 0.75 0.012"; echo f; for i in 1 2 3 4 5 6 7 8 9 10; do echo "m 0 0.75 $(python3 -c "print(round(0.012+0.0588*$i,4))")"; echo f; echo "w 30"; done; echo "w 200"; echo "u 0"; echo f; echo "w 900"; }
note() { echo "x cp $ST/orientation $W/$1.or"; echo "x sh -c 'cat $ST/rotation-lock >$W/$1.lk 2>/dev/null'"; echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
setconf() { echo "x sh -c 'grep -v ^home_rotate $CONF >$W/c; echo home_rotate = $1 >>$W/c; mv $W/c $CONF'"; echo "w ${2:-1500}"; }
run() { local n=$1; shift
	SANDBOX_PATH="$W/fakebin:$BUILD"
	comp_start "$@" QT_QUICK_BACKEND=software PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 600
	comp_stop
	cp "$W/gw.log" "$SHOTS/turn-$n.log"; cat "$W/gw.log" >>"$W/all.log"
}

# 1: the switch, set in the home settings page, then flipped in phone.conf while turned
printf 'animations = on\n' >"$CONF"
{ echo "w 3500"; hold 0.5 0.55; t 0.5 0.78 900; note set-page
  t 0.62 0.244 900; echo "x cp $CONF $W/conf-off"; t 0.05 0.07 700; t 0.5 0.95 1200
  echo "x echo left-up >$W/fake/orientation"; echo "w 2000"; note home-off
  echo "x $W/fakeapp -n 1 -a app"; echo "w 2500"; note app-off
  echo "x phonegluewc-msg workspace 2"; echo "w 1500"; note home2-off
  setconf on; note home-on
  echo "x echo menu-1 >$ST/menu"; echo "w 1500"; note menu-on
  setconf off; note menu-off
  echo "p done"; } >"$W/script"
run switch FAKE_STATE="$W/fake"

# 2: no sensor at all; a tap on the tile turns, the panel comes back for the hold sheet
printf 'animations = on\nquick_tiles = turn,rotation\n' >"$CONF"
rm -f "$ST/rotation-lock" "$W/fake/orientation"
{ echo "w 3500"; note start; open; note qs; t $TILE 1800; note tapped
  echo "x phonegluewc-msg rotate normal"; echo "w 1500"
  open; hold $TILE; note sheet; t 0.5 0.8145 1800; note picked
  echo "x sh -c 'echo 0 >$ST/rotation-lock'"; echo "w 2500"; note auto
  echo "p done"; } >"$W/script"
run nosensor PHONEGLUEWC_SENSOR=

# 3: with a sensor the manual turn holds against it until the lock goes off
rm -f "$ST/rotation-lock"; echo normal >"$W/fake/orientation"
# FAKE_STATE gives the fake tools a sink, so the volume slider pushes the tiles down
{ echo "w 3500"; open; t 0.267 0.334 1800; note held0
  echo "x echo right-up >$W/fake/orientation"; echo "w 2500"; note held
  echo "x sh -c 'echo 0 >$ST/rotation-lock'"; echo "w 2500"; note follows
  echo "p done"; } >"$W/script"
run sensor FAKE_STATE="$W/fake"

for f in "$W"/*.ppm; do magick "$f" "$SHOTS/turn-$(basename "${f%.ppm}").png" 2>/dev/null; done
or() { cat "$W/$1.or" 2>/dev/null; }
lk() { cat "$W/$1.lk" 2>/dev/null; }
for n in home-off app-off home2-off home-on menu-on menu-off start tapped picked auto held0 held follows; do echo "  $n: $(or $n) lock=$(lk $n)"; done
ok "no QML error"                                       '! grep -hE "Failed to load|TypeError|ReferenceError" "$W/all.log" | grep -q .'
ok "the settings page writes home_rotate = off"         'grep -q "^home_rotate = off" "$W/conf-off"'
ok "off: home stays upright with the phone turned"      '[ "$(or home-off)" = normal ]'
ok "off: an app still turns"                            '[ "$(or app-off)" = 90 ]'
ok "off: back home it is upright again"                 '[ "$(or home2-off)" = normal ]'
ok "on: home turns"                                     '[ "$(or home-on)" = 90 ] && [ "$(or menu-on)" = 90 ]'
ok "off again: the menu goes upright"                   '[ "$(or menu-off)" = normal ]'
ok "no sensor: the tile turns sideways and locks"       '[ "$(or start)" = normal ] && [ "$(or tapped)" = 90 ] && [ "$(lk tapped)" = 1 ]'
ok "no sensor: the hold sheet picks landscape flipped"  '[ "$(or picked)" = 270 ]'
ok "no sensor: lock off goes back to upright"           '[ "$(or auto)" = normal ]'
ok "sensor: the manual turn holds against it"           '[ "$(or held0)" = 90 ] && [ "$(or held)" = 90 ]'
ok "sensor: lock off follows it again"                  '[ "$(or follows)" = 270 ]'
ok "no core files"                                      '[ -z "$(comp_cores)" ]'
[ "$FAILS" = 0 ] && echo "turn: all passed" || echo "turn: failed: $FAILS"
exit "$((FAILS > 0))"
