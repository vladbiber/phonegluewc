#!/bin/bash
# Runs the real run-on-laptop.sh, nested in a headless compositor, with a tripwire in place of every
# real system tool further down PATH. No tile or settings page may reach one. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-lapiso.XXXXXX")
SANDBOX_EXTRA="timeout dirname make ln readlink mktemp sync cut date uname df"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -s -C "$BUILD/keyboard" phonekbd phonekbd-lang >/dev/null 2>&1 || { echo "FAIL keyboard build"; exit 1; }
make -s -C "$BUILD/screentext" phonetext >/dev/null 2>&1 || { echo "FAIL screentext build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
COMP=$BUILD/phonegluewc

FAKED="nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep wlsunset fbcli wf-recorder fuser systemctl loginctl reboot poweroff shutdown halt suspend rtcwake sudo doas pkexec"
mkdir -p "$W/real" "$W/cfg/phonegluewc"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=1\n' >"$W/cfg/phonegluewc/config.conf"
for p in $FAKED flatpak waydroid; do
	printf '#!/bin/sh\necho "%s $*" >>%s\n' "$p" "$W/real-called" >"$W/real/$p"; chmod +x "$W/real/$p"
done

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-500}"; }
pull() { echo "d 0 0.75 0.02"; echo f; python3 -c "
for s in range(1,9): print('m 0 0.75 %.3f\nf\nw 30' % (0.02+0.53*s/8))"; echo "w 200"; echo "u 0"; echo f; echo "w 600"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
cat >"$W/who.sh" <<EOF
for t in $FAKED phonesettings pset; do echo "\$t \$(command -v \$t)"; done >"$W/who"
printf '%s\n' "\$PATH" >"$W/who-path"
EOF

# only processes under the one captured
stop_under() { local c; for c in $(pgrep -P "$1"); do [ "$(cat /proc/$c/comm 2>/dev/null)" = phonegluewc ] && kill "$c" || stop_under "$c"; done; }
# inner NAME: the real script, its log in NAME.log; ends with the status of the compositor in it
inner() {
	local run sh=${2:-run-on-laptop.sh}
	: >"$W/$1.log"
	SANDBOX_PATH="$W/real" sandbox WAYLAND_DISPLAY="$SOCK" PHONE_LAPTOP_DIR="$W/$1" PHONEGLUEWC_FAKETOUCH="$W/script" QT_QUICK_BACKEND=software \
		sh "$BUILD/$sh" 1000 >"$W/$1.log" 2>&1 &
	run=$!
	for _ in $(seq 3000); do
		kill -0 "$PID" 2>/dev/null || { echo "FAIL outer compositor died"; PID=; exit 1; }
		kill -0 "$run" 2>/dev/null || break
		grep -q '^FT done' "$W/$1.log" && break
		sleep 0.1
	done
	grep -q '^FT done' "$W/$1.log" || { echo "FAIL $1 did not finish"; tail -15 "$W/$1.log" | cut -c1-200; }
	grep -q "Running compositor on wayland display 'wayland-0'" "$W/$1.log" && { echo "FAIL inner took wayland-0"; exit 1; }
	stop_under "$run"
	for _ in $(seq 80); do kill -0 "$run" 2>/dev/null || break; sleep 0.1; done
	kill -0 "$run" 2>/dev/null && { echo "FAIL $1 hung on exit"; kill -9 "$run"; }
	wait "$run"
	echo $? >"$W/$1.rc"
	for c in "$BUILD"/core.*; do [ -e "$c" ] && { mkdir -p "$SRC/tests/crashes"; mv "$c" "$SRC/tests/crashes/"; echo "FAIL core file: $c"; exit 1; }; done
}

comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell"

# the control: the same script without the fakes must trip the wire, or this test proves nothing
sed 's|$BASE/fakebin:||' "$BUILD/run-on-laptop.sh" >"$BUILD/no-fakes.sh"
{ echo "w 6000"; echo "p done"; } >"$W/script"
inner control no-fakes.sh
mv "$W/real-called" "$W/control-called" 2>/dev/null

{ echo "w 3000"; echo "x sh $W/who.sh"; echo "w 300"; shot home; pull; pull; shot panel
  # the second page of tiles first: the sweep below also hits the pencil, and edit mode stays
  for y in 0.37 0.45 0.54; do
	for x in 0.27 0.73; do
	  echo "d 0 0.85 0.45"; echo f; for m in 0.7 0.5 0.3 0.15; do echo "m 0 $m 0.45"; echo f; done; echo "u 0"; echo f; echo "w 700"
	  t $x $y 400; pull; pull
	done
  done
  for y in 0.13 0.19 0.26 0.33 0.40 0.47 0.54 0.61 0.68 0.75; do
	for x in 0.12 0.30 0.50 0.70 0.88; do t $x $y 400; pull; pull; done
  done
  shot swept
  echo "x rfkill unblock all; nmcli radio wifi on"; echo "w 500"
  t 0.5 0.85 900
  for pg in wifi bluetooth mobile sound display battery; do echo "x phonesettings $pg"; echo "w 2500"; shot "page-$pg"; done
  echo "x pset bt-power off; pset bt-power on; pset bt-pair 00:00:00:00:00:03"; echo "w 1500"
  echo "p done"; } >"$W/script"
inner main
comp_stop

B=$W/main
cp "$W/main.log" "$SHOTS/main.log"; cp "$B/fake/calls.log" "$SHOTS/calls.txt" 2>/dev/null
for f in "$W"/*.ppm; do magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done 2>/dev/null

fails=0
ok() { if ( eval "$2" ); then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
called() { grep -qE "$1" "$B/fake/calls.log"; }
ok "the control without fakes does reach the wire" '[ -s "$W/control-called" ]'
ok "the window exited cleanly" '[ "$(cat "$W/main.rc")" = 0 ]'
ok "the startup text says the tools are fake" 'grep -q "Fake tools" "$W/main.log"'
ok "fakes come first on the window PATH" 'grep -q "^$B/fakebin:" "$W/who-path"'
# bash takes suspend as its own builtin, which only stops that shell
ok "every faked tool resolves to the fake" '[ -z "$(grep -vE " $B/fakebin/|^(phonesettings|pset) |^suspend suspend$" "$W/who")" ]'
ok "the settings app is on the window PATH" 'grep -q "^phonesettings $BUILD/settings/phonesettings$" "$W/who"'
ok "no real tool was reached" '[ ! -e "$W/real-called" ]'
for c in "^nmcli radio wifi" "^bluetoothctl power" "^rfkill (un)?block" "^wpctl set-(volume|mute)" "^brightnessctl .*set" "^powerprofilesctl set" "^gsettings set"; do
	ok "a tile reached the fake: $c" "called '$c'"
done
for c in "^nmcli -t -f WIFI g" "^nmcli -t -f IN-USE" "^bluetoothctl show" "^bluetoothctl info" "^mmcli -L" "^wpctl status" "^brightnessctl -m" "^upower -e"; do
	ok "settings reached the fake: $c" "called '$c'"
done
ok "a tile moved the pretend backlight, or the torch, not a real one" 'called "^brightnessctl -q .*-d (laptop-fake|white:torch) set"'
echo; [ -e "$W/real-called" ] && { echo "real calls:"; sort -u "$W/real-called" | head -20; }
grep -vE " $B/fakebin/|^(phonesettings|pset) " "$W/who"
grep -E 'ReferenceError|TypeError|is not a type|Failed to load' "$W/main.log" | cut -c1-200 | sort -u | head
echo "$fails failed"
[ "$fails" = 0 ]
