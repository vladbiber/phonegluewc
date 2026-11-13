#!/bin/bash
# The top bar takes the colour of the app's top rows, picks its ink by brightness and hides only over fullscreen. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-appbar.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/fakeapp" "$SRC/tests/fakeapp.c" "$BUILD/touchlog-xdg-protocol.c" $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0) -lwayland-client || { echo "FAIL fakeapp"; exit 1; }
COMP=$BUILD/phonegluewc
FAILS=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }

mkdir -p "$W/cfg/phonegluewc" "$W/fakebin" "$W/fake"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
S=$W/sys; mkdir -p "$S/power_supply/BAT0"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
CTL=$W/ctl; TOP=$W/state/phonegluewc/topcolor
step() { echo "x echo '$2' >$CTL"; echo "w 1500"; echo "x cp $TOP $W/$1.top"; echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; echo "p $1"; }
{ echo "w 3000"
  echo "x cp $TOP $W/home.top"; echo "x $SRC/tests/wshot $W/home.ppm"; echo "w 400"
  echo "x echo ffffff >$CTL"; echo "x FAKEAPP_CTL=$CTL exec $W/fakeapp -n 1 -a app"; echo "w 1500"
  step light ffffff
  step red ff0000
  step dark 202020
  step fs "ff0000 fs"
  step back ff0000
  echo "p done"; } >"$W/script"
SANDBOX_PATH="$W/fakebin:$BUILD"
comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 900
comp_stop

cp "$W/gw.log" "$SHOTS/appbar.log" 2>/dev/null
for n in home light red dark fs back; do magick "$W/$n.ppm" "$SHOTS/appbar-$n.png" 2>/dev/null; done
top() { cat "$W/$1.top" 2>/dev/null; }
# a clear spot of the strip, and the icons and battery at the right end of it
strip() { magick "$W/$1.ppm" -format "%[hex:p{620,40}]" info: | cut -c1-6 | tr A-F a-f; }
inkmin() { magick "$W/$1.ppm" -alpha off -colorspace Gray -crop 200x80+880+10 +repage -format "%[fx:int(255*minima)]" info:; }
inkmax() { magick "$W/$1.ppm" -alpha off -colorspace Gray -crop 200x80+880+10 +repage -format "%[fx:int(255*maxima)]" info:; }
flat() { magick "$W/$1.ppm" -alpha off -crop 200x80+880+10 +repage -format "%[fx:int(1000*standard_deviation)]" info:; }
echo "  topcolor: home=$(top home) light=$(top light) red=$(top red) dark=$(top dark)"
echo "  strip: home=$(strip home) light=$(strip light) red=$(strip red) dark=$(strip dark) fs=$(strip fs)"
echo "  ink: light $(inkmin light)..$(inkmax light) red $(inkmin red)..$(inkmax red) fs flat=$(flat fs)"
ok "no QML error" '! grep -hE "Failed to load|StatusBar.*(rror|Unable)|BatteryPill.*(rror|Unable)|TypeError|ReferenceError" "$W/gw.log" | grep -q .'
ok "home: no app colour, the bar stays clear" '[ "$(top home)" = none ] && [ "$(strip home)" != ffffff ]'
ok "a white top paints the strip white" '[ "$(top light)" = "#ffffff" ] && [ "$(strip light)" = ffffff ]'
ok "and its icons are dark" '[ "$(inkmin light)" -lt 60 ]'
ok "a red top paints it red, icons light" '[ "$(top red)" = "#ff0000" ] && [ "$(strip red)" = ff0000 ] && [ "$(inkmax red)" -gt 200 ]'
ok "a dark top: dark strip, light icons" '[ "$(top dark)" = "#202020" ] && [ "$(strip dark)" = 202020 ] && [ "$(inkmax dark)" -gt 200 ]'
ok "fullscreen hides the bar" '[ "$(strip fs)" = ff0000 ] && [ "$(flat fs)" = 0 ]'
ok "and it comes back after" '[ "$(strip back)" = ff0000 ] && [ "$(inkmax back)" -gt 200 ]'
ok "no core files" '[ -z "$(comp_cores)" ]'
echo; echo "$FAILS failed"; [ "$FAILS" = 0 ]
