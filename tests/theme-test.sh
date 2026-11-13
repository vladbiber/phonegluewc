#!/bin/bash
# Dark and light, headless at phone size: the switch both ways while running, every sheet captured in each. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-theme.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync dirname"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg keyboard/phonekbd >"$W/build.log" 2>&1 || { tail -5 "$W/build.log"; echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
COMP=$BUILD/phonegluewc
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || { echo "FAIL touchlog"; exit 1; }

mkdir -p "$W/fakebin" "$W/fake" "$W/cfg/phonegluewc" "$W/state/phonegluewc" "$W/data/applications"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep wlsunset wf-recorder fbcli fuser \
	systemctl loginctl reboot poweroff shutdown halt suspend rtcwake sudo doas pkexec; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
CONF=$W/cfg/phonegluewc/phone.conf
for n in Browser Notes Terminal; do printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\n' "$n" >"$W/data/applications/$(echo $n | tr A-Z a-z).desktop"; done
printf '#!/bin/sh\nexec env TOUCHLOG_TITLE=app %s\n' "$W/touchlog" >"$W/app.sh"
printf '#!/bin/sh\nexec %s/settings/phonesettings "$@" >>%s/settings.log 2>&1\n' "$BUILD" "$W" >"$W/set.sh"

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-900}"; }
walk() { echo "d 0 $1 $2"; echo f; python3 -c "
for s in range(1,11): print('m 0 %.4f %.4f\nf\nw 16' % ($1+($3-$1)*s/10, $2+($4-$2)*s/10))"; echo "w 200"; echo "u 0"; echo f; echo "w ${5:-900}"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
theme() { echo "x $BUILD/settings/pset set phone theme $1"; echo "w 1200"; echo "p theme-$1"; }
# every sheet once, named after the mode it is in
sheets() {
	walk 0.75 0.012 0.75 0.6; shot "$1-quick"; walk 0.5 0.9 0.5 0.1
	walk 0.25 0.012 0.25 0.6; shot "$1-notifications"; walk 0.5 0.9 0.5 0.1
	t 0.795 0.947 1200; shot "$1-menu"; t 0.35 0.947 1500; shot "$1-keyboard"; t 0.9 0.094 1200
	echo "x sh $W/app.sh & echo \$! >$W/apppid"; echo "w 1500"; walk 0.5 0.995 0.5 0.6 250; shot "$1-overview"
	echo "x sh -c 'kill \$(cat $W/apppid)'"; echo "w 800"; t 0.5 0.995 900
	echo "x sh $W/set.sh & echo \$! >$W/setpid"; echo "w 3000"; shot "$1-settings"
	echo "x sh -c 'kill \$(cat $W/setpid)'"; echo "w 800"
}
run() {
	SANDBOX_PATH="$W/fakebin:$BUILD:$BUILD/keyboard"
	comp_start QT_QUICK_BACKEND=software FAKE_STATE="$W/fake" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEKBD_DATA="$SRC/keyboard/data" \
		PHONE_AUTH_MOCK=test PHONE_AUTH_LOG="$W/launch.log" PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 3000
	cp "$W/gw.log" "$W/$1.log"
	comp_stop
}

# starts dark; light and back while running; then a fresh start already light, ending at the lock
printf 'theme = dark\n' >"$CONF"
{ echo "w 3500"; sheets dark
  theme light; sheets light
  theme dark; walk 0.75 0.012 0.75 0.6; shot back-quick; walk 0.5 0.9 0.5 0.1
  echo "x qs ipc -p $BUILD/shell call lock lock"; echo "w 2000"; shot dark-lock; t 0.5 0.86 1500; shot dark-lockkbd
  echo "p end"; } >"$W/script"
run one
cp "$CONF" "$W/one.conf"
printf 'theme = light\n' >"$CONF"
{ echo "w 3500"; echo "x qs ipc -p $BUILD/shell call lock lock"; echo "w 2000"; shot light-lock; t 0.5 0.86 1500; shot light-lockkbd
  echo "p end"; } >"$W/script"
run two
# a light wallpaper under the menu blur: the bar must keep its clock readable in both themes
magick -size 1080x2400 xc:'#f0f0f0' "$W/white.png"
printf 'theme = dark\nwallpaper = %s\n' "$W/white.png" >"$CONF"
{ echo "w 3500"; shot wall-home; t 0.795 0.947 1500; shot wall-dark-menu; theme light; echo "w 600"; shot wall-light-menu
  echo "p end"; } >"$W/script"
run three

cp "$W/settings.log" "$SHOTS/" 2>/dev/null
printf '%s\n' "$W"/*.ppm | SHOTS=$SHOTS xargs -P8 -I{} sh -c 'f={}; b=${f##*/}; magick "$f" "$SHOTS/${b%.ppm}.png"' 2>/dev/null

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
# mean brightness 0..255 of a box given as fractions of the screen
lum() { magick "$W/$1.ppm" -crop "$(python3 -c "print('%dx%d+%d+%d' % (1080*$4, 2400*$5, 1080*$2, 2400*$3))")" -colorspace Gray -format '%[fx:int(255*mean)]' info: 2>/dev/null; }
dark() { [ "$(lum "$@")" -lt 70 ]; }
light() { [ "$(lum "$@")" -gt 185 ]; }
for f in dark-quick dark-notifications dark-menu dark-keyboard dark-overview dark-settings light-quick light-notifications light-menu light-keyboard \
	light-overview light-settings back-quick dark-lock light-lock wall-home wall-dark-menu wall-light-menu; do ok "captured $f" '[ -s "$W/$f.ppm" ]'; done
contrast() { magick "$W/$1.ppm" -crop 324x72+54+12 -colorspace Gray -format '%[fx:int(255*(maxima-minima))]' info: 2>/dev/null; }
ok "light wallpaper, menu open: the clock stands out, dark and light" '[ "$(contrast wall-dark-menu)" -gt 120 ] && [ "$(contrast wall-light-menu)" -gt 120 ]'
# dark ink: the pixel under the clock is dark on the light wallpaper
ok "light wallpaper, bare home: the bar ink turns dark" '[ "$(contrast wall-home)" -gt 120 ] && [ "$(magick "$W/wall-home.ppm" -crop 324x72+54+12 -colorspace Gray -format "%[fx:int(255*minima)]" info:)" -lt 80 ]'
ok "pset kept one theme line, back on dark"   '[ "$(grep -c "^theme" "$W/one.conf")" = 1 ] && grep -q "^theme *= *dark$" "$W/one.conf"'
ok "quick settings: dark, then light, then dark" 'dark dark-quick 0.05 0.85 0.9 0.05 && light light-quick 0.05 0.85 0.9 0.05 && dark back-quick 0.05 0.85 0.9 0.05'
ok "notifications: dark, then light"          'dark dark-notifications 0.05 0.5 0.9 0.2 && light light-notifications 0.05 0.5 0.9 0.2'
ok "app menu: dark, then light"               'dark dark-menu 0.05 0.6 0.9 0.2 && light light-menu 0.05 0.6 0.9 0.2'
ok "keyboard: dark, then light"               'dark dark-keyboard 0.02 0.8 0.96 0.15 && light light-keyboard 0.02 0.8 0.96 0.15'
ok "settings: dark, then light"               'dark dark-settings 0.05 0.85 0.9 0.1 && light light-settings 0.05 0.85 0.9 0.1'
ok "lock keyboard follows: dark, then light"  'dark dark-lockkbd 0.02 0.8 0.96 0.15 && light light-lockkbd 0.02 0.8 0.96 0.15'
ok "apps are told: light, then dark"          'grep -q "gsettings set org.gnome.desktop.interface color-scheme prefer-light" "$W/fake/calls.log" && tail -n +$(grep -n prefer-light "$W/fake/calls.log" | head -1 | cut -d: -f1) "$W/fake/calls.log" | grep -q prefer-dark'
ok "no QML error"                             '! grep -aE "ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|file://.*qml:[0-9]+" "$W/one.log" "$W/two.log" "$W/settings.log" | grep -q .'
ok "no crash"                                 '! grep -a "Segmentation\|Aborted\|core dumped" "$W/one.log" "$W/two.log" | grep -q .'
ok "no core files"                            '! ls "$W"/core.* "$BUILD"/core.* >/dev/null 2>&1'
[ -n "${THEME_VERBOSE:-}" ] && for f in "$W"/*.ppm; do b=${f##*/}; echo "${b%.ppm} $(lum "${b%.ppm}" 0.05 0.5 0.9 0.2)"; done
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
exit 0
