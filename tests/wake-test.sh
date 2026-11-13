#!/bin/bash
# Screen off and on, headless: a session opens locked, dark means locked, a dark screen takes no touch,
# nothing held or typed outlives the screen (no lock editor after the PIN), volume keys work locked. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-wake.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync dirname awk sleep"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg phonepin keyboard/phonekbd >"$W/build.log" 2>&1 || { tail -5 "$W/build.log"; echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/fakeapp" "$SRC/tests/fakeapp.c" "$BUILD/touchlog-xdg-protocol.c" $(pkg-config --cflags --libs gio-2.0 gio-unix-2.0) -lwayland-client || { echo "FAIL fakeapp"; exit 1; }
COMP=$BUILD/phonegluewc

mkdir -p "$W/fakebin" "$W/fake" "$W/cfg/phonegluewc" "$W/state" "$W/run"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep wlsunset wf-recorder fbcli fuser \
	fprintd-list fprintd-verify fprintd-enroll fprintd-delete systemctl loginctl reboot poweroff shutdown halt suspend rtcwake sudo doas pkexec; do
	ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"
done
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'user=sampleuser\n' >"$W/cfg/phonegluewc/login.conf"
printf 'theme = dark\nsleep_after = 0\n' >"$W/cfg/phonegluewc/phone.conf"
echo no >"$W/fake/fpdev"
PIN=482913
echo $PIN | XDG_STATE_HOME="$W/state" PHONE_RUNTIME_DIR="$W/run" "$BUILD/phonepin" set || { echo "FAIL phonepin set"; exit 1; }

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-600}"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w 1300"; echo "u 0"; echo f; echo "w 400"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
mark() { echo "x cp $W/state/phonegluewc/screen $W/$1.screen"; echo "w 100"; echo "p $1"; echo "w 100"; }
key() { echo "K $1 1"; echo "w 30"; echo "K $1 0"; echo "w 70"; }
digits() { local s=$1 c; while [ -n "$s" ]; do c=${s%"${s#?}"}; s=${s#?}; [ "$c" = 0 ] && key 11 || key $((c + 1)); done; }
enter() { key 28; echo "w ${1:-1500}"; }
power() { key 116; echo "w ${1:-2500}"; }

{ echo "w 5000"; mark boot; shot boot
  digits $PIN; enter; mark bootopen
  echo "x exec $W/fakeapp -n 1 -a app"; echo "w 1500"; mark app
  # the power key: faded out, dark, locked
  power; mark off
  # in the dark: a hold on the clock, a pad key, the password link
  hold 0.5 0.2; t 0.5 0.62; t 0.5 0.9; mark dark
  power 1500; mark wake; shot wake
  digits $PIN; enter; mark wakeopen
  # a hold on the lit lock asks for its editor; the screen going off forgets that
  power; power 1500; hold 0.5 0.2; mark armed
  power; power 1500; shot wake2
  digits $PIN; enter; mark forgot
  # any other way off locks too, and volume keys work behind the lock
  echo "x phonegluewc-msg power off"; echo "w 2000"; mark msgoff
  echo "x phonegluewc-msg power on"; echo "w 1200"; mark msgon
  key 115; echo "w 1200"; key 114; echo "w 1200"
  digits $PIN; enter; mark end
  echo "p done"; } >"$W/script"
SANDBOX_PATH="$W/fakebin:$BUILD:$BUILD/keyboard"
comp_start QT_QUICK_BACKEND=software FAKE_STATE="$W/fake" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEKBD_DATA="$SRC/keyboard/data" \
	XDG_STATE_HOME="$W/state" PHONE_RUNTIME_DIR="$W/run" USER=sampleuser PHONEGLUEWC_LOCK_START=1 \
	PHONE_AUTH_MOCK=test PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 900
cp "$W/gw.log" "$W/one.log"
comp_stop

cp "$W"/*.log "$W/fake/calls.log" "$SHOTS/" 2>/dev/null
for f in "$W"/*.ppm; do b=${f##*/}; magick "$f" "$SHOTS/${b%.ppm}.png" 2>/dev/null; done

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
ft() { grep -a "^FT $1 " "$W/one.log" | grep -c "$2"; }
scr() { cat "$W/$1.screen" 2>/dev/null; }
ok "the session opens locked, with a lock drawn"       '[ "$(ft boot "locked=1 lock=1")" = 1 ]'
ok "the PIN opens it"                                  '[ "$(ft bootopen "locked=0")" = 1 ]'
ok "the power key: dark and locked"                    '[ "$(scr off)" = 0 ] && [ "$(ft off "locked=1 lock=1")" = 1 ]'
ok "the app is suspended dark and behind the lock, not after" '[ "$(ft app "sus=0")" = 1 ] && [ "$(ft off "sus=1")" = 1 ] && [ "$(ft wake "sus=1")" = 1 ] && [ "$(ft wakeopen "sus=0")" = 1 ]'
ok "touches in the dark reach nothing"                 '[ "$(ft dark "fingers=0 gesture=0 emu=-1")" = 1 ] && [ "$(scr dark)" = 0 ]'
ok "the power key lights it, still locked, no keyboard" '[ "$(scr wake)" = 1 ] && [ "$(ft wake "kbd=0 .*locked=1 lock=1")" = 1 ]'
ok "the PIN opens: no digit and no hold from the dark" '[ "$(ft wakeopen "locked=0")" = 1 ]'
ok "a lit hold leaves the lock closed"                 '[ "$(ft armed "locked=1")" = 1 ]'
ok "after a screen-off the PIN opens, not the editor"  '[ "$(ft forgot "locked=0")" = 1 ]'
ok "power off by request locks too"                    '[ "$(scr msgoff)" = 0 ] && [ "$(ft msgoff "locked=1 lock=1")" = 1 ]'
ok "power on by request lights it"                     '[ "$(scr msgon)" = 1 ] && [ "$(ft msgon "locked=1")" = 1 ]'
ok "volume keys step behind the lock"                  '[ "$(grep -c "^wpctl set-volume" "$W/fake/calls.log")" -ge 2 ]'
ok "and the PIN still opens"                           '[ "$(ft end "locked=0")" = 1 ]'
for f in boot wake wake2; do ok "captured $f" '[ -s "$W/$f.ppm" ]'; done
ok "no QML error" '! grep -aE "ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|file://.*qml:[0-9]+" "$W/one.log" | grep -q .'
ok "no crash"     '! grep -a "Segmentation\|Aborted\|core dumped" "$W/one.log" | grep -q .'
ok "no core files" '! ls "$W"/core.* "$BUILD"/core.* >/dev/null 2>&1'
[ -n "${WAKE_VERBOSE:-}" ] && { grep -a '^FT ' "$W/one.log" | sed 's/ws=.*kbd=/kbd=/' | cut -c1-90; grep -a 'qml\|WARN' "$W/one.log" | head -20; cat "$W/fake/calls.log" | grep wpctl; }
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
exit 0
