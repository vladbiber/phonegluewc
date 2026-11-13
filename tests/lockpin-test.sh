#!/bin/bash
# Lock PIN and fingerprint, headless: set in settings, password after boot, wrong tries and the wait across a shell restart, fake fprintd. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-lockpin.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync dirname awk sleep"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg phonepin keyboard/phonekbd >"$W/build.log" 2>&1 || { tail -5 "$W/build.log"; echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
COMP=$BUILD/phonegluewc

mkdir -p "$W/fakebin" "$W/fake" "$W/cfg/phonegluewc" "$W/state" "$W/run"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep wlsunset wf-recorder fbcli fuser \
	fprintd-list fprintd-verify fprintd-enroll fprintd-delete systemctl loginctl reboot poweroff shutdown halt suspend rtcwake sudo doas pkexec; do
	ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"
done
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'user=sampleuser\n' >"$W/cfg/phonegluewc/login.conf"
printf 'theme = dark\n' >"$W/cfg/phonegluewc/phone.conf"
echo no >"$W/fake/fpdev"
PIN=482913
PIN2=715064
printf '#!/bin/sh\nexec %s/settings/phonesettings security >>%s/settings.log 2>&1\n' "$BUILD" "$W" >"$W/set.sh"

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-900}"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
mark() { echo "p $1"; echo "w 100"; }
key() { echo "K $1 1"; echo "w 30"; echo "K $1 0"; echo "w 70"; }
# evdev codes: digits 1..9 are 2..10, 0 is 11
digits() { local s=$1 c; while [ -n "$s" ]; do c=${s%"${s#?}"}; s=${s#?}; [ "$c" = 0 ] && key 11 || key $((c + 1)); done; }
word() { local s=$1 c; while [ -n "$s" ]; do c=${s%"${s#?}"}; s=${s#?}; case $c in t) key 20 ;; e) key 18 ;; s) key 31 ;; esac; done; }
enter() { key 28; echo "w ${1:-1200}"; }
lock() { echo "x qs ipc -p $BUILD/shell call lock lock"; echo "w 2500"; }
password() { t 0.5 0.86 1200; word "${1:-test}"; enter 1500; }
# the fake touch reads short lines, so the status call lives in a script
printf '#!/bin/sh\nXDG_STATE_HOME=%s/state PHONE_RUNTIME_DIR=%s/run %s/phonepin status >%s/$1.status\n' "$W" "$W" "$BUILD" "$W" >"$W/st.sh"
state() { echo "x sh $W/st.sh $1"; echo "w 300"; }
run() {
	SANDBOX_PATH="$W/fakebin:$BUILD:$BUILD/keyboard"
	comp_start QT_QUICK_BACKEND=software FAKE_STATE="$W/fake" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEKBD_DATA="$SRC/keyboard/data" \
		XDG_STATE_HOME="$W/state" PHONE_RUNTIME_DIR="$W/run" USER=sampleuser \
		PHONE_AUTH_MOCK=test PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 3000
	cp "$W/gw.log" "$W/$1.log"
	comp_stop
}

# one: the PIN is set in settings, behind the password; a wrong password and two different PINs first
{ echo "w 3500"
  echo "x sh $W/set.sh & echo \$! >$W/setpid"; echo "w 3500"; shot set-page
  t "${CHIP_X:-0.36}" "${CHIP_Y:-0.17}" 1200; shot set-password
  word tset; enter; shot set-wrongpw; state after-wrongpw
  word test; enter; shot set-pin1
  digits $PIN; enter 800; digits $PIN2; enter 800; shot set-mismatch; state after-mismatch
  digits $PIN; enter 800; digits $PIN; enter 2000; shot set-done
  state after-set
  echo "x sh -c 'kill \$(cat $W/setpid)'"; echo "w 800"
  # a boot: no password used yet, the PIN opens anyway (the user's choice)
  lock; shot boot-lock; mark bootlock
  digits $PIN; enter 1500; mark bootpin
  lock; password tset; mark bootwrongpw
  echo "D"; echo "w 300"; t 0.5 0.3 600
  password; mark pwopen; state after-password
  # now the PIN pad
  lock; shot pin-lock; mark pinlock
  digits 1111; enter 1000; shot pin-wrong; mark pinwrong
  digits $PIN; enter 1500; mark pinopen
  # five wrong tries start the wait; the right PIN does nothing during it
  lock
  for i in 1 2 3 4 5; do digits 0000; enter 900; done
  shot pin-wait; mark waiting; state after-five
  digits $PIN; enter 1200; mark waitright
  # the shell dies and comes back: still waiting
  echo k; echo "w 4500"; shot pin-wait-restart; mark restarted; state after-restart
  digits $PIN; enter 1200; mark restartright
  echo "p end"; } >"$W/script"
run one

# two: the wait ran out; fingerprint enrolled; then a boot
echo "5 0" >"$W/state/phonegluewc/pin-tries"
echo yes >"$W/fake/fpdev"; echo right-index-finger >"$W/fake/fingers"; echo no-match >"$W/fake/fpnext"
{ echo "w 3500"
  lock; shot finger-lock; mark fplock
  digits $PIN; enter 1500; mark expiredopen
  lock
  echo "d 0 0.5 ${FP_Y:-0.82}"; echo f; echo "w 300"; shot finger-scan; echo "u 0"; echo f; echo "w 1800"; shot finger-fail; mark fpfail
  echo "x sh -c 'echo match >$W/fake/fpnext'"; echo "w 200"
  t 0.5 "${FP_Y:-0.82}" 2000; mark fpopen
  # the boot: the runtime flag is gone
  echo "x rm -f $W/run/phonegluewc-password-used"; echo "w 300"
  lock; shot reboot-lock; mark rebootlock
  t 0.5 "${FP_Y:-0.82}" 2000; mark rebootfp
  echo "D"; echo "w 300"; t 0.5 0.3 600
  password; mark rebootpw
  # the pad's own keys and its password link
  lock; digits 12; shot pad-lock
  echo "x $BUILD/settings/pset set phone theme light"; echo "w 1500"; shot pad-light
  echo "x $BUILD/settings/pset set phone theme dark"; echo "w 1200"
  digits 0000; enter 1000; digits $PIN; enter 1500; mark padopen
  echo "x sh $W/set.sh & echo \$! >$W/setpid"; echo "w 3500"; shot set-finger
  echo "p end"; } >"$W/script"
run two

# three: the boot login never offers the PIN or the finger
echo match >"$W/fake/fpnext"
{ echo "w 4000"; shot greeter; mark greeter; echo "p end"; } >"$W/script"
run three PHONEGLUEWC_GREETER=1 2>/dev/null || true

cp "$W/settings.log" "$W"/*.log "$W"/*.status "$W/fake/calls.log" "$SHOTS/" 2>/dev/null
printf '%s\n' "$W"/*.ppm | SHOTS=$SHOTS xargs -P8 -I{} sh -c 'f={}; b=${f##*/}; magick "$f" "$SHOTS/${b%.ppm}.png"' 2>/dev/null

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
ft() { grep -a "^FT $2 " "$W/$1.log" | grep -c "$3"; }
st() { cat "$W/$1.status" 2>/dev/null; }
ok "settings: a wrong password sets nothing"           'st after-wrongpw | grep -q "pin=0"'
ok "settings: two different PINs are refused"           'st after-mismatch | grep -q "pin=0"'
ok "settings: the PIN is saved"                         'st after-set | grep -q "pin=1 password=0"'
ok "the PIN file is a slow salted hash, mode 600"       'grep -qE "^\\\$6\\\$rounds=100000\\\$[./0-9A-Za-z]{16}\\\$" "$W/state/phonegluewc/pin" && [ "$(stat -c %a "$W/state/phonegluewc/pin")" = 600 ]'
ok "the PIN is in clear nowhere"                        '! grep -rqa -e "$PIN" -e "$PIN2" "$W/state" "$W/cfg" "$W/run" "$W/fake" "$W/settings.log" "$W/one.log" "$W/two.log"'
ok "after a boot the PIN opens too"                    '[ "$(ft one bootpin "locked=0")" = 1 ]'
ok "after a boot a wrong password stays locked"         '[ "$(ft one bootwrongpw "locked=1")" = 1 ]'
ok "the password opens and sets the boot flag"          '[ "$(ft one pwopen "locked=0")" = 1 ] && st after-password | grep -q "password=1"'
ok "then the lock shows the PIN pad"                    'grep -q "Enter PIN" "$W/one.log" || [ -s "$W/pin-lock.ppm" ]'
ok "a wrong PIN stays locked"                           '[ "$(ft one pinwrong "locked=1")" = 1 ]'
ok "the right PIN opens"                                '[ "$(ft one pinopen "locked=0")" = 1 ]'
ok "five wrong PINs start a 30 s wait"                  'st after-five | grep -qE "wait=(2[0-9]|30) fails=5"'
ok "the right PIN does nothing during the wait"         '[ "$(ft one waitright "locked=1")" = 1 ]'
ok "a shell restart keeps the lock and the wait"        '[ "$(ft one restarted "locked=1")" = 1 ] && [ "$(ft one restartright "locked=1")" = 1 ] && st after-restart | grep -q "fails=5"'
ok "after the wait the right PIN opens"                 '[ "$(ft two expiredopen "locked=0")" = 1 ]'
ok "a finger that does not match stays locked"          '[ "$(ft two fpfail "locked=1")" = 1 ]'
ok "a matching finger opens"                            '[ "$(ft two fpopen "locked=0")" = 1 ]'
ok "fprintd was asked only through its tools"           'grep -q "^fprintd-verify" "$W/fake/calls.log" && grep -q "^fprintd-list sampleuser$" "$W/fake/calls.log"'
ok "after a boot the finger does not open"              '[ "$(ft two rebootfp "locked=1")" = 1 ]'
ok "after a boot the password does"                     '[ "$(ft two rebootpw "locked=0")" = 1 ]'
ok "after a wrong one, the right PIN opens again"       '[ "$(ft two padopen "locked=0")" = 1 ]'
ok "the boot login has no PIN or finger"                '! grep -q "Enter PIN" "$W/three.log" 2>/dev/null'
for f in set-page set-password set-pin1 set-done boot-lock pin-lock pin-wrong pin-wait pin-wait-restart finger-lock finger-scan finger-fail reboot-lock pad-lock pad-light set-finger; do
	ok "captured $f" '[ -s "$W/$f.ppm" ]'
done
ok "no QML error" '! grep -aE "ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|file://.*qml:[0-9]+" "$W/one.log" "$W/two.log" "$W/settings.log" | grep -q .'
ok "no crash"     '! grep -a "Segmentation\|Aborted\|core dumped" "$W/one.log" "$W/two.log" | grep -q .'
ok "no core files" '! ls "$W"/core.* "$BUILD"/core.* >/dev/null 2>&1'
[ -n "${PIN_VERBOSE:-}" ] && { grep -a '^FT ' "$W/one.log" "$W/two.log" | cut -c1-60 | grep -v ' done'; cat "$W"/*.status; grep -a 'qml\|WARN' "$W/one.log" | head -20; }
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
exit 0
