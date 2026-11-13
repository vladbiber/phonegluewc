#!/bin/bash
# The top bar's height and margins in device pixels, with the hole and without. SHOTS=DIR keeps the captures.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-top.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync notify-send"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
# the bar is clear over home now; painted black in this copy so the measure finds its bottom edge
sed -i 's/opacity: root.onApp ? 1 : 0/opacity: 1/' "$BUILD/shell/StatusBar.qml"
grep -q 'opacity: 1$' "$BUILD/shell/StatusBar.qml" || { echo "FAIL strip shim"; exit 1; }
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
COMP=$BUILD/phonegluewc
FAILS=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }

mkdir -p "$W/fakebin" "$W/fake" "$W/cfg/phonegluewc"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
S=$W/sys; mkdir -p "$S/power_supply/BAT0"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" rx="12" fill="#20c060"/></svg>' >"$W/icon.svg"
magick -size 64x64 xc:'#2040c0' "$W/wall.png"
echo "wallpaper=$W/wall.png" >"$W/cfg/phonegluewc/phone.conf"

# scene NAME MODE SCALE ENV...: idle, then with notifications, then the panels and the lock must fit
scene() { local n=$1 mode=$2 scale=$3; shift 3
	mkdir -p "$W/$n"
	printf 'remember_layout = false\noutput = * mode=%s scale=%s\n' "$mode" "$scale" >"$W/cfg/phonegluewc/config.conf"
	{ echo "w 3500"
	echo "x $SRC/tests/wshot $W/$n/idle.ppm"; echo "w 500"
	echo "x notify-send -t 800 -a Sample -i $W/icon.svg one two"; echo "w 7000"
	echo "x $SRC/tests/wshot $W/$n/notif.ppm"; echo "w 500"
	echo "d 0 0.75 0.01"; echo f; for f in 0.1 0.2 0.3 0.4 0.5 0.55; do echo "m 0 0.75 $f"; echo f; echo "w 30"; done; echo "u 0"; echo f; echo "w 900"
	echo "x $SRC/tests/wshot $W/$n/panel.ppm"; echo "w 500"
	echo "p done"; } >"$W/script"
	SANDBOX_PATH="$W/fakebin:$BUILD"
	comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script" "$@"
	comp_wait 400
	comp_stop
	mv "$W/gw.log" "$W/$n.log"
}
scene phone 1080x2400 2.75
scene lap 450x1000 1.15 PHONE_NO_HOLE=1 PHONE_CAMERA=center
python3 "$SRC/tests/topbar-measure.py" "$W/phone/idle.ppm" 2.75 >"$W/m-phone"
python3 "$SRC/tests/topbar-measure.py" "$W/lap/idle.ppm" 1.15 >"$W/m-lap"
python3 "$SRC/tests/topbar-measure.py" "$W/lap/notif.ppm" 1.15 >"$W/m-notif"
python3 "$SRC/tests/topbar-measure.py" "$W/phone/notif.ppm" 2.75 >"$W/m-pnotif"
sed 's/^/phone: /' "$W/m-phone"; sed 's/^/laptop: /' "$W/m-lap"; sed 's/^/laptop notif: /' "$W/m-notif"; sed 's/^/phone notif: /' "$W/m-pnotif"
for n in phone lap; do for f in idle notif panel; do
	wd=$(identify -format %w "$W/$n/$f.ppm"); magick "$W/$n/$f.ppm" -crop "${wd}x$((wd/6))+0+0" +repage "$W/$n/$f.png"
	cp "$W/$n/$f.png" "$SHOTS/$n-$f.png"
done; done
magick "$SHOTS/lap-idle.png" "$SHOTS/lap-notif.png" "$SHOTS/lap-panel.png" -background '#555' -splice 0x4 -append -filter point -resize 240% "$W/a.png"
magick "$SHOTS/phone-idle.png" "$SHOTS/phone-notif.png" "$SHOTS/phone-panel.png" -background '#555' -splice 0x4 -append "$W/b.png"
magick "$W/b.png" "$W/a.png" -background '#555' -append "$SHOTS/topbar-sheet.png"
get() { sed -n "s/.*\b$2=\([-0-9]*\).*/\1/p" "$1" | head -1; }
ok "phone: the bar covers the hole's bottom edge" '[ "$(get $W/m-phone bar)" -ge 95 ]'
ok "phone: clock after the hole" '[ "$(get $W/m-phone clockx)" -ge 150 ]'
ok "laptop: the bar shrank" '[ "$(get $W/m-lap bar)" -le 31 ]'
ok "laptop: the clock is in the corner" '[ "$(get $W/m-lap clockx)" -le 30 ]'
for m in phone lap notif pnotif; do
	ok "$m: every item is centred to 2 device pixels" '! grep -qE "off=([3-9]|[0-9]{2})" "$W/m-$m"'
done
ok "laptop: notification icon right of the clock" '[ "$(get $W/m-notif green)" -gt "$(get $W/m-notif clockend)" ]'
ok "phone: notification icon right of the clock" '[ "$(get $W/m-pnotif green)" -gt "$(get $W/m-pnotif clockend)" ]'
ok "no QML error" '! grep -hE "StatusBar.*(rror|Unable)|TypeError|ReferenceError" "$W"/phone.log "$W"/lap.log | grep -q .'
ok "no core files" '[ -z "$(comp_cores)" ]'
echo; echo "$FAILS failed"; rm -rf "$W"; [ "$FAILS" = 0 ]
