#!/bin/bash
# Blur turned 90, 180 and 270: the menu, the pull down panel, the overview and a translucent window keep a blur that covers them. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-blurrot.XXXXXX")
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
printf 'remember_layout = false\nblur = 1\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
S=$W/sys; mkdir -p "$S/power_supply/BAT0"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
ST=$W/state/phonegluewc
# a sharp checkerboard: anywhere the blur is missing or offset it shows as full contrast
magick -size 2400x2400 pattern:checkerboard -threshold 50% +level 15%,85% -scale 200% -crop 2400x2400+0+0 +repage "$W/wall.png"
turn() { echo "x echo $1 >$W/fake/orientation"; echo "w ${2:-2000}"; }
shot() { echo "x cp $ST/orientation $W/$1.or"; echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 500"; }
# turned 90 the panel's (x, y) is the screen's (y, 1 - x)
at() { python3 -c "print(round($2,4), round(1-$1,4))"; }
walk() { echo "d 0 $(at $1 $2)"; echo f; python3 -c "
for s in range(1,11): print('m 0 %s\nf\nw 16' % ' '.join(str(round(v,4)) for v in ($2+($4-$2)*s/10, 1-($1+($3-$1)*s/10))))"; echo "w 200"; echo "u 0"; echo f; echo "w ${5:-1200}"; }
menu() { echo "x echo $1-a >$ST/menu"; echo "w 300"; echo "x echo $1-b >$ST/menu"; echo "w 1500"; }
# the menu has no close message: tap its X, given in the captured buffer's fractions
esc() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w 1000"; }
for th in dark light; do
	printf 'animations = off\ntheme = %s\nwallpaper = %s\n' $th "$W/wall.png" >"$W/cfg/phonegluewc/phone.conf"
	{ echo "w 3500"; turn normal; shot "p-home-$th"
	  turn left-up; shot "l-home-$th"
	  menu m1; shot "l-menu-$th"; esc 0.178 0.042
	  walk 0.75 0.02 0.75 0.6; shot "l-panel-$th"; walk 0.5 0.9 0.5 0.1
	  echo "x FAKEAPP_ARGB=1 $W/fakeapp -n 1 -a glass & echo \$! >$W/apppid"; echo "w 2500"; shot "l-win-$th"
	  walk 0.5 0.995 0.5 0.5 1500; shot "l-over-$th"; walk 0.5 0.995 0.5 0.99 1200
	  echo "x sh -c 'kill \$(cat $W/apppid)'"; echo "w 1500"
	  turn bottom-up; menu m2; shot "u-menu-$th"; esc 0.093 0.905
	  turn right-up; menu m3; shot "r-menu-$th"; esc 0.821 0.957
	  turn normal 2500; shot "p-back-$th"; echo "p done"; } >"$W/script"
	SANDBOX_PATH="$W/fakebin:$BUILD:$SRC/keyboard"
	comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 900
	comp_stop
	cat "$W/gw.log" >>"$W/all.log"
done
cp "$W/all.log" "$SHOTS/blurrotate.log" 2>/dev/null
for f in "$W"/*.ppm; do b=${f##*/}; magick "$f" "$SHOTS/${b%.ppm}.png" 2>/dev/null; done

or() { cat "$W/$1.or" 2>/dev/null; }
# the checkerboard's 30px squares, sharp: about 85 in a 32px box; blurred well under 15
sharp() { magick "$W/$1.ppm" -crop "$2" +repage -colorspace Gray -format '%[fx:int(255*standard_deviation)]\n' info: 2>/dev/null || echo 999; }
# per edge of the turned screen, the softest of 9 boxes along it: UI on a box is skipped, a sharp band (offset or short blur) is not
edges() { local f=$W/$1.ppm w h e k v m; w=$(magick "$f" -format %w info:); h=$(magick "$f" -format %h info:)
	for e in l r t b; do m=999; for k in 0 1 2 3 4 5 6 7 8; do
		case $e in l) v=$(sharp "$1" "32x32+4+$((h*(2*k+1)/18-16))");; r) v=$(sharp "$1" "32x32+$((w-36))+$((h*(2*k+1)/18-16))");;
		t) v=$(sharp "$1" "32x32+$((w*(2*k+1)/18-16))+4");; b) v=$(sharp "$1" "32x32+$((w*(2*k+1)/18-16))+$((h-36))");; esac
		[ "$v" -lt "$m" ] && m=$v; done; echo "$m"; done; }
soft() { for v in $(edges "$1"); do [ "$v" -lt 25 ] || return 1; done; }
for th in dark light; do for n in l-home l-menu l-panel l-win l-over u-menu r-menu p-home p-back; do echo "  $n-$th or=$(or $n-$th) edges: $(edges $n-$th | tr '\n' ' ')"; done; done
ok "turned: home, the menu, the panel, the window and the overview are at 90" '(for th in dark light; do for n in l-home l-menu l-panel l-win l-over; do [ "$(or $n-$th)" = 90 ] || exit 1; done; done)'
ok "turned 180 and 270 too" '(for th in dark light; do [ "$(or u-menu-$th)" = 180 ] && [ "$(or r-menu-$th)" = 270 ] || exit 1; done)'
ok "bare home shows the sharp wallpaper, so the edges can tell" '(for th in dark light; do ! soft l-home-$th || exit 1; done)'
for n in l-menu l-panel l-win l-over u-menu r-menu; do ok "$n: blurred to every edge, dark and light" "soft $n-dark && soft $n-light"; done
# the home button may sit elsewhere, so not a picture compare: every edge sharp again
ok "back upright: no blur left behind" '(for th in dark light; do for v in $(edges p-back-$th); do [ "$v" -ge 60 ] || exit 1; done; done)'
ok "no QML error" '! grep -hE "Failed to load|TypeError|ReferenceError" "$W/all.log" | grep -q .'
ok "no core files" '[ -z "$(comp_cores)" ]'
echo; echo "$FAILS failed"; [ "$FAILS" = 0 ]
