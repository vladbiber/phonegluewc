#!/bin/bash
# Turning the phone: apps, home, the menu and the editor follow the pretend accelerometer, the rotation lock offers a button that turns once. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-rotate.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "FAIL keyboard"; exit 1; }
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
printf 'animations = %s\n' "${ANIM:-on}" >"$W/cfg/phonegluewc/phone.conf"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
S=$W/sys; mkdir -p "$S/power_supply/BAT0"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
ST=$W/state/phonegluewc; CTL=$W/ctl
turn() { echo "x echo $1 >$W/fake/orientation"; echo "w ${2:-1500}"; }
at() { python3 -c "print(round($2,4), round(1-$1,4))"; }
note() { echo "x cp $ST/orientation $W/$1.or"; echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; echo "p $1"; }
{ echo "w 3000"; echo "x cp $ST/orientation $W/start.or"
  echo "x echo left-up >$W/fake/orientation"; for i in 1 2 3 4 5 6 7 8; do echo "w 120"; echo "g turn1-$i"; done; echo "w 540"; note home
  echo "x echo 202020 >$CTL"; echo "x FAKEAPP_CTL=$CTL exec $W/fakeapp -n 1 -a app"; echo "w 2500"; note app
  turn right-up; note app270
  echo "x echo 1 >$ST/rotation-lock"; echo "w 1500"; note locked
  turn left-up 1000; echo "x cp $ST/rotate-offer $W/offer"; note button
  echo "d 0 0.883 0.888"; echo f; echo "u 0"; echo f; echo "w 1500"; note tapped
  echo "x phonegluewc-msg workspace 2"; echo "w 1500"; note home2
  echo "x phonegluewc-msg workspace 1"; echo "w 1500"; note back
  echo "x echo 0 >$ST/rotation-lock"; echo "w 2500"; note unlocked
  # turned 90: a touchscreen reports panel spots, the screen's (u, v) is the panel's (v, 1 - u)
  y=0.995; echo "d 0 $(at 0.5 $y)"; echo f; for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y-0.07,4))"); echo "m 0 $(at 0.5 $y)"; echo f; done; echo "w 300"; echo "u 0"; echo f; echo "w 1200"; note overview
  echo "d 0 $(at 0.5 0.995)"; echo f; echo "u 0"; echo f; echo "w 1200"; note closed
  x=0.004; echo "d 0 $(at $x 0.5)"; echo f; for i in 1 2 3 4 5 6 7 8 9 10; do x=$(python3 -c "print(round($x+0.03,4))"); echo "m 0 $(at $x 0.5)"; echo f; echo "w 30"; done; echo "u 0"; echo f; echo "w 1500"; note kbd
  echo "p done"; } >"$W/script"
SANDBOX_PATH="$W/fakebin:$BUILD:$SRC/keyboard"
comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 900
comp_stop

cp "$W/gw.log" "$SHOTS/rotate.log" 2>/dev/null
for n in home app app270 locked button tapped home2 back unlocked overview closed kbd; do magick "$W/$n.ppm" "$SHOTS/rotate-$n.png" 2>/dev/null; done
or() { cat "$W/$1.or" 2>/dev/null; }
size() { magick "$W/$1.ppm" -format "%wx%h" info: 2>/dev/null; }
# the round button sits at the bottom right in portrait: its spot differs from the app behind it
spot() { magick "$W/$1.ppm" -alpha off -crop 120x120+900+2070 +repage -format "%[fx:int(1000*standard_deviation)]" info:; }
echo "  orientation: start=$(or start) home=$(or home) app=$(or app) app270=$(or app270) locked=$(or locked) button=$(or button) tapped=$(or tapped) home2=$(or home2) back=$(or back) unlocked=$(or unlocked)"
echo "  offer: $(cat "$W/offer" 2>/dev/null)  sizes: home=$(size home) app=$(size app)  button spot: locked=$(spot locked) button=$(spot button)"
ok "no QML error" '! grep -hE "Failed to load|RotateButton.*(rror|Unable)|TypeError|ReferenceError" "$W/gw.log" | grep -q .'
ok "the compositor says it can turn, so the tile shows" '[ "$(or start)" = normal ]'
ok "home turns with the phone" '[ "$(or home)" = 90 ]'
tray1=$(sed -n 's/^GEOM turn1-[0-9] layer ns=phone-tray .*box=\([-0-9,]*\).*/\1/p' "$W/gw.log" | tr '\n' ' ')
echo "  tray every 120 ms after the first turn: $tray1"
# once the shell commits its column it must stand at the right edge at once, not after some later commit
ok "the tray takes its turned spot on the first turn" '[ -n "$tray1" ] && echo $tray1 | tr " " "\n" | awk -F, '"'"'$3 < 200 { col++; if ($1 + $3 != 873 || $2 != 0) bad++ } END { exit !(col > 0 && !bad) }'"'"''
ok "an app in front turns with it" '[ "$(or app)" = 90 ] && [ "$(or app270)" = 270 ]'
ok "the rotation lock puts it back upright" '[ "$(or locked)" = normal ]'
ok "locked, turning offers it instead" '[ "$(or button)" = normal ] && [ "$(cut -d" " -f2 "$W/offer" 2>/dev/null)" = 90 ]'
ok "and the button shows" '[ "$(spot button)" -gt "$(( $(spot locked) + 20 ))" ]'
ok "tapping it turns once" '[ "$(or tapped)" = 90 ]'
ok "home keeps the turn the button gave" '[ "$(or home2)" = 90 ]'
ok "back in the app the lock still holds that turn" '[ "$(or back)" = 90 ]'
ok "unlocking follows the sensor again" '[ "$(or unlocked)" = 90 ]'
ok "the overview opens turned and keeps the turn" 'grep -q "^FT overview .*overview=1" "$W/gw.log" && [ "$(or overview)" = 90 ]'
ok "so does the keyboard" '[ "$(or kbd)" = 90 ]'
ok "no core files" '[ -z "$(comp_cores)" ]'
# landscape home, menu and editor in both themes; the lock and greeter stay upright via rotfront
cp "$W/gw.log" "$W/main.log"
for th in dark light; do
	printf 'animations = off\ntheme = %s\n' $th >"$W/cfg/phonegluewc/phone.conf"
	for what in menu edit; do
		{ echo "w 3000"; turn left-up 2000; [ $what = menu ] && note "l-home-$th"
		  echo "x echo $what-1 >$ST/$what"; echo "w 2000"; note "l-$what-$th"; echo "p done"; } >"$W/script"
		comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/script"
		comp_wait 300
		comp_stop
		cat "$W/gw.log" >>"$W/land.log"
	done
	for n in home menu edit; do magick "$W/l-$n-$th.ppm" "$SHOTS/rotate-land-$n-$th.png" 2>/dev/null; done
done
ok "landscape: home, the menu and the editor turn in both themes" '(for th in dark light; do for n in home menu edit; do [ "$(or l-$n-$th)" = 90 ] || exit 1; done; done)'
ok "landscape: no QML error" '! grep -hE "Failed to load|TypeError|ReferenceError" "$W/land.log" | grep -q .'
# the menu and the editor draw something different from bare home
differ() { [ "$(magick compare -metric AE -fuzz 5% "$W/l-home-$1.ppm" "$W/l-$2-$1.ppm" null: 2>&1 | awk '{printf "%d", $1}')" -gt 50000 ]; }
ok "landscape: the menu and the editor open" 'differ dark menu && differ dark edit && differ light menu && differ light edit'
ok "landscape: no core files" '[ -z "$(comp_cores)" ]'
# every window on every workspace takes the turned size at once: a split here, one app on workspace 2
printf 'animations = off\n' >"$W/cfg/phonegluewc/phone.conf"; rm -f "$W/cfg/phonegluewc/screens.json"
{ echo "w 3000"; turn normal 1500; echo "x echo 202020 >$CTL"
  echo "x FAKEAPP_CTL=$CTL exec $W/fakeapp -n 1 -a left"; echo "w 2000"; echo "x FAKEAPP_CTL=$CTL exec $W/fakeapp -n 1 -a right"; echo "w 2000"
  echo "x phonegluewc-msg move 1"; echo "w 1000"; echo "x phonegluewc-msg workspace 3"; echo "w 1000"; echo "x FAKEAPP_CTL=$CTL exec $W/fakeapp -n 1 -a other"; echo "w 2000"
  echo "x phonegluewc-msg workspace 1"; echo "w 1500"; echo "g upright"
  turn left-up 2500; echo "g turned"; turn normal 2500; echo "g back"; echo "p done"; } >"$W/script"
comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 300
comp_stop
cp "$W/gw.log" "$SHOTS/rotate-relayout.log" 2>/dev/null
python3 - "$W/gw.log" >"$W/relayout" <<'PY'
import re, sys
mon, cl, ly = {}, {}, {}
for l in open(sys.argv[1], errors="replace"):
    g = re.match(r"GEOM (\S+) mon .* m=([-\d,]+) w=([-\d,]+) .*tf=(\d+)", l)
    if g: mon[g[1]] = ([int(v) for v in g[2].split(",")], [int(v) for v in g[3].split(",")], int(g[4]))
    g = re.match(r"GEOM (\S+) client title=(\S+) ws=(\d+) geom=([-\d,]+) .*fs=(\d)", l)
    if g and g[2] in ("left", "right", "other"): cl.setdefault(g[1], {})[g[2]] = (int(g[3]), [int(v) for v in g[4].split(",")], int(g[5]))
    g = re.match(r"GEOM (\S+) layer ns=(\S+) .*box=([-\d,]+)", l)
    if g: ly.setdefault(g[1], {})[g[2]] = [int(v) for v in g[3].split(",")]
for lab, tf in (("upright", 0), ("turned", 1), ("back", 0)):
    if lab not in mon or len(cl.get(lab, {})) != 3: print(lab, "missing"); continue
    m, w, t = mon[lab]
    if t != tf: print(lab, "transform", t)
    area = {}
    for n, (ws, b, fs) in cl[lab].items():
        box = m if fs else w
        if b[0] < box[0] - 1 or b[1] < box[1] - 1 or b[0] + b[2] > box[0] + box[2] + 1 or b[1] + b[3] > box[1] + box[3] + 1:
            print(lab, n, "outside", b, box)
        area[ws] = area.get(ws, 0) + b[2] * b[3]
    for ws, a in area.items():
        if a < 0.9 * w[2] * w[3]: print(lab, "ws", ws, "covers", round(a / (w[2] * w[3]), 2))
    bar = ly.get(lab, {}).get("phone-statusbar")
    if not bar or bar[:3] != [m[0], m[1], m[2]]: print(lab, "bar", bar)
    for ns, b in ly.get(lab, {}).items():
        if b[2] > m[2] or b[3] > m[3]: print(lab, "layer", ns, "larger than the output", b)
    L, R = cl[lab]["left"][1], cl[lab]["right"][1]
    if (L[1] == R[1]) != (tf == 1): print(lab, "split", "side by side" if L[1] == R[1] else "stacked")
    print(lab, "seen", " ".join("%s=ws%d:%s" % (n, v[0], ",".join(map(str, v[1]))) for n, v in sorted(cl[lab].items())), "w=" + ",".join(map(str, w)))
PY
cat "$W/relayout" | sed 's/^/  /'
ok "relayout: the split, the other workspace and the bar fit the output, upright, turned and back" '[ "$(grep -c " seen " "$W/relayout")" = 3 ] && ! grep -v " seen " "$W/relayout" | grep -q .'
ok "relayout: the split stays two windows on one workspace, stacked upright and side by side turned" 'grep " seen " "$W/relayout" | grep -q "left=ws\([0-9]*\):.* right=ws\1:"'
ok "relayout: no core files" '[ -z "$(comp_cores)" ]'
echo; echo "$FAILS failed"; [ "$FAILS" = 0 ]
