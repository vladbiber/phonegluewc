#!/bin/bash
# What is behind an app: a translucent window shows the wallpaper (sharp, or blurred with blur = true),
# and closing it uncovers the wallpaper, never grey. Headless, a private copy. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-transp.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync magick"
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

C=$W/cfg/phonegluewc
mkdir -p "$C" "$W/fakebin" "$W/home/Pictures"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
# red and blue stripes: sharp behind glass keeps the edges, blurred loses them, grey has neither colour
magick -size 80x2400 xc:'#d02020' -size 80x2400 xc:'#2020d0' +append -write mpr:s +delete -size 1080x2400 tile:mpr:s "$W/home/Pictures/stripes.png"
shot() { echo "x $SRC/tests/wshot $W/$1-$2.ppm"; echo "w ${3:-300}"; }
SANDBOX_PATH="$W/fakebin:$BUILD"
for b in off on; do
	printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n%s' "$([ $b = on ] && echo 'blur = true')" >"$C/config.conf"
	printf 'animations = on\nwallpaper = %s\n' "$W/home/Pictures/stripes.png" >"$C/phone.conf"
	printf '{"home":{"active":0,"screens":[{"x":0,"y":0,"wallpaper":"%s","widgets":[]}]}}\n' "$W/home/Pictures/stripes.png" >"$C/screens.json"
	{ echo "w 3500"; shot $b home
	  echo "x sh -c 'echo \$\$ >$W/app.pid; FAKEAPP_ARGB=1 exec $W/fakeapp -n 1 -a glass'"; echo "w 2500"; shot $b app
	  echo "x sh -c 'kill \$(cat $W/app.pid)'"; echo "w 60"; shot $b close1 40; shot $b close2 40; echo "w 1500"; shot $b after
	  # the other way out: the overview, and the card flung up
	  echo "x sh -c 'FAKEAPP_ARGB=1 exec $W/fakeapp -n 1 -a glass'"; echo "w 2500"
	  y=0.995; echo "d 0 0.5 $y"; echo f; for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y-0.05,4))"); echo "m 0 0.5 $y"; echo f; done; echo "w 250"; echo "u 0"; echo f; echo "w 1200"; shot $b cards
	  y=0.6; echo "d 0 0.5 $y"; echo f; for i in 1 2 3 4 5 6 7 8; do y=$(python3 -c "print(round($y-0.08,4))"); echo "m 0 0.5 $y"; echo f; done; echo "u 0"; echo f; echo "w 60"; shot $b fling1 40; shot $b fling2 40; echo "w 1500"; shot $b flung
	  echo "p done"; } >"$W/script"
	comp_start ${GLES:+WLR_RENDERER=gles2} QT_QUICK_BACKEND=${GLES:+rhi}${GLES:-software} PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 600
	comp_stop
	cp "$W/gw.log" "$SHOTS/transparent-$b.log"
done
for f in "$W"/*.ppm; do magick "$f" "$SHOTS/transparent-$(basename "${f%.ppm}").png"; done
# a band across the middle, clear of the bar, the tray and any clock
band() { f=$1; shift; magick "$W/$f.ppm" -alpha off -crop 1080x300+0+1300 +repage "$@" 2>/dev/null; }
mean() { band $1 -format "%[fx:int(255*mean.r)] %[fx:int(255*mean.g)] %[fx:int(255*mean.b)]" info:; }
edges() { band $1 -format "%[fx:int(1000*standard_deviation)]" info:; }
# wallpaper colour in it: red and blue well above green, which grey or black cannot do
colour() { mean $1 | awk '{ exit !($1 > $2 + 40 && $3 > $2 + 40) }'; }
for n in off-home off-app off-close1 off-close2 off-after on-app on-close1 on-close2 on-after off-cards on-cards off-fling1 off-fling2 off-flung on-fling1 on-fling2 on-flung; do echo "  $n: mean $(mean $n) edges $(edges $n)"; done
ok "the wallpaper is behind the translucent app"     'colour off-app'
ok "sharp with blur off"                             '[ "$(edges off-app)" -gt 100 ]'
ok "blurred with blur on"                            'colour on-app && [ "$(edges on-app)" -lt "$(( $(edges off-app) / 2 ))" ]'
ok "closing uncovers the wallpaper, not grey"        'for n in off-close1 off-close2 off-after on-close1 on-close2 on-after; do colour $n || exit 1; done'
ok "its card and a card flung up show it too, and home is back"                 'colour off-cards && colour on-cards && for n in off-fling1 off-fling2 off-flung on-fling1 on-fling2 on-flung; do colour $n || exit 1; done && [ "$(edges off-flung)" -gt 200 ]'
comp_cores
[ "$FAILS" = 0 ] && echo "transparent: all passed" || echo "transparent: failed: $FAILS"
exit "$((FAILS > 0))"
