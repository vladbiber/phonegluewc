#!/bin/bash
# The lock and boot login, headless, with the fake authenticator only. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-lock.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonepin ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1

mkdir -p "$W/cfg/phonegluewc" "$W/state" "$W/state2" "$W/data/applications" "$W/data/wayland-sessions"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf 'user=sampleuser\n' >"$W/cfg/phonegluewc/login.conf"
printf '[Desktop Entry]\nName=Session one\nExec=one-session\n' >"$W/data/wayland-sessions/one.desktop"
printf '[Desktop Entry]\nName=Session two\nExec=two-session\n' >"$W/data/wayland-sessions/two.desktop"
: >"$W/tl.log"; : >"$W/launch.log"
cat >"$W/tl.sh" <<TL
exec "$W/touchlog" >>"$W/tl.log"
TL
cat >"$W/impostor.sh" <<IMP
echo \$\$ >"$W/impostor.pid"
QT_QUICK_BACKEND=software exec qs -p "$SRC/tests/lock-impostor"
IMP
cat >"$W/impostor-stop.sh" <<IMP
kill "\$(cat "$W/impostor.pid")"
IMP

python3 "$SRC/tests/kbd-script.py" "$W" lock >"$W/script-lock" || exit 1
python3 "$SRC/tests/kbd-script.py" "$W" greeter >"$W/script-greeter" || exit 1
python3 "$SRC/tests/kbd-script.py" "$W" lockpw >"$W/script-lockpw" || exit 1
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
run() { # script, state suffix, extra env
	s=$1; st=$2; shift 2
	comp_start XDG_STATE_HOME="$W/state$st" QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" \
		PHONEKBD_DATA="$SRC/keyboard/data" PHONEKBD_DUMP="$W/keys.txt" PHONE_AUTH_MOCK=test PHONE_AUTH_LOG="$W/launch.log" \
		PHONEGLUEWC_FAKETOUCH="$s" "$@"
	comp_wait 1800
	comp_stop
	cat "$W/gw.log" >>"$W/all.log"
}
run "$W/script-lock" ""
run "$W/script-greeter" 2 PHONEGLUEWC_GREETER=1
# a language was installed and removed: its letters must still open the lock
mkdir -p "$W/data/phonekbd/langs"; cp -r "$SRC/keyboard/packs/ro" "$W/data/phonekbd/langs/"
lang() { env XDG_DATA_HOME="$W/data" XDG_CACHE_HOME="$W/cache" PHONEKBD_DATA="$SRC/keyboard/data" "$SRC/keyboard/phonekbd-lang" "$@"; }
lang merge >/dev/null; lang remove ro >/dev/null
: >"$W/gw.log"
run "$W/script-lockpw" 3 PHONE_AUTH_MOCK=teș
# the clock editor, then every style on a dark and a light wallpaper, drawn here so nothing personal shows
python3 "$SRC/tests/kbd-script.py" "$W" lockedit >"$W/script-lockedit" || exit 1
: >"$W/gw.log"; run "$W/script-lockedit" 4
magick -size 1080x2400 gradient:'#1b2a4a-#3a1440' "$W/dark.png"
magick -size 1080x2400 gradient:'#f6e7d2-#bcd7ee' "$W/light.png"
cat >"$W/setstyle.sh" <<SET
printf 'user=sampleuser\nwallpaper=$W/%s.png\n' "\$1" >"$W/cfg/phonegluewc/login.conf"
printf 'sleep_after=0\nlock_clock=%s\nlock_clock_color=auto\n' "\$2" >"$W/cfg/phonegluewc/phone.conf"
SET
{ echo "w 4000"; echo "x qs ipc -p $SRC/shell call lock lock"; echo "w 2000"
  for wp in dark light; do for s in dot thin bold small stacked; do
	echo "x sh $W/setstyle.sh $wp $s"; echo "w 1200"; echo "x $SRC/tests/wshot $W/style-$wp-$s.ppm"; echo "w 300"
  done; done; } >"$W/script-styles"
run "$W/script-styles" 5
printf 'user=sampleuser\n' >"$W/cfg/phonegluewc/login.conf"
# a PIN set and the password used since boot: a hold, the PIN on the pad, and the editor opens
mkdir -p "$W/state6" "$W/run6"
# stacked, the tallest style, must shrink above the pad
printf 'sleep_after=0\nlock_clock=stacked\n' >"$W/cfg/phonegluewc/phone.conf"
printf 482913 | XDG_STATE_HOME="$W/state6" PHONE_RUNTIME_DIR="$W/run6" "$BUILD/phonepin" set
XDG_STATE_HOME="$W/state6" PHONE_RUNTIME_DIR="$W/run6" "$BUILD/phonepin" unlocked
# evdev codes: digits 1..9 are 2..10, 0 is 11, enter 28
{ echo "w 4000"; echo "x qs ipc -p $SRC/shell call lock lock"; echo "w 2500"
  echo "d 0 0.5 0.3"; echo f; echo "w 1100"; echo "u 0"; echo f; echo "w 900"; echo "p phold"; echo "x $SRC/tests/wshot $W/pin-1-hold.ppm"; echo "w 400"
  for k in 5 9 3 10 2 4 28; do echo "K $k 1"; echo "w 30"; echo "K $k 0"; echo "w 70"; done
  echo "w 1500"; echo "p pauth"; echo "x $SRC/tests/wshot $W/pin-2-editor.ppm"; echo "w 400"; } >"$W/script-pin"
run "$W/script-pin" 6 PHONE_RUNTIME_DIR="$W/run6"
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done

# the real backends load, nothing starts them
mkdir "$W/authcheck"; cp "$SRC"/shell/*.qml "$SRC"/shell/*.js "$W/authcheck/"
cat >"$W/authcheck/shell.qml" <<'QML'
import Quickshell
import QtQuick
ShellRoot {
    Loader { id: a; source: "AuthPam.qml" }
    Loader { id: b; source: "AuthGreetd.qml" }
    Timer { running: true; interval: 800; onTriggered: { console.log("AUTHCHECK", a.status === Loader.Ready, b.status === Loader.Ready); Qt.quit(); } }
}
QML
sandbox QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 20 qs -p "$W/authcheck" >"$W/authcheck.log" 2>&1
AUTHCHECK=$(grep -a AUTHCHECK "$W/authcheck.log" | head -1)
[ -n "$AUTHCHECK" ] || cut -c1-200 "$W/authcheck.log" | tail -12

fails=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', wanted '$3'"; fails=$((fails+1)); fi; }
ft() { grep -c "^FT $1 .*$2" "$W/all.log"; }
col() { python3 -I "$SRC/tests/colors.py" "$W/$1.ppm" 808080 ff0000 2>/dev/null; }
touches() { grep -c 'touch down\|pointer button' "$W/$1.txt"; }
pixels() { magick "$W/$1.ppm" "$W/$2.ppm" -crop 1080x1000+0+1400 +repage -compose difference -composite -threshold 0 -format '%[fx:int(mean*w*h+0.5)]' info: 2>&1; }
ok "lock: the wrong letter does not open it" "$(ft lockpwwrong 'locked=1')" 1
ok "lock: ș held on s, from a removed language, opens it" "$(ft lockpwdone 'locked=0')" 1
ok "lock: pressing a key shows no bubble" "$(pixels lockpw-idle lockpw-down)" 0
d=$(pixels lockpw-idle lockpw-hold)
[ "${d:-0}" -gt 0 ] 2>/dev/null && d=shows
ok "lock: holding it shows the choices" "$d" shows
ok "the open window shows before the lock (control)" "$(col lock-0-open)" "1 0"
ok "it takes the touch before the lock (control)" "$(touches tl0)" "1"
ok "locking by command locks" "$(ft locked 'locked=1 lock=1')" "1"
ok "nothing shows through the lock" "$(col lock-1-locked)" "0 0"
ok "no touch reaches the app while locked" "$(touches tl1)" "1"
ok "bar and four fingers do nothing while locked" "$(ft lockgest 'overview=0 visible=0')" "1"
ok "a stranger named phone-keyboard stays under the lock" "$(col lock-2-impostor)" "0 0"
ok "the stranger does show when unlocked (control)" "$(col lock-7b-impostor-open | cut -d' ' -f2)" "1"
ok "the keyboard opens on the lock screen" "$(ft lockkbd 'kbd=1')" "1"
ok "nothing shows through with the keyboard" "$(col lock-3-keyboard)" "0 0"
ok "the lock keyboard is secret, with no suggestions" "$(grep -c '^state .*secret=1 nsug=0' "$W/lockkeys.txt")" "1"
ok "the lock keyboard has no emoji or clipboard" "$(grep -cE '^(clip|emoji) ' "$W/lockkeys.txt")" "0"
ok "a wrong password stays locked" "$(ft lockwrong 'locked=1 lock=1')" "1"
ok "the shell's death does not unlock" "$(ft crashed 'locked=1 lock=0')" "1"
ok "nothing shows right after the crash" "$(col lock-5-crashed)" "0 0"
ok "no touch reaches the app after the crash" "$(touches tl2)" "1"
ok "a new shell brings the lock back" "$(ft relocked 'locked=1 lock=1')" "1"
ok "nothing shows after the relock" "$(col lock-6-relocked)" "0 0"
ok "the keyboard types the right password and unlocks" "$(ft unlocked 'locked=0 lock=0')" "1"
ok "the window is back after the unlock" "$(col lock-7-unlocked | cut -d' ' -f1)" "1"
ok "the app takes touches again" "$(touches tl3)" "2"
ok "a shell that keeps dying leaves it locked" "$(ft gaveup 'locked=1 lock=0')" "1"
ok "nothing shows after it gives up" "$(col lock-8-gave-up)" "0 0"
ok "passwords are never learned" "$(cat "$W"/state*/phonekbd/learned.tsv 2>/dev/null | grep -cE '^(abc|test|teest)')" "0"
ok "boot login has no tray or gestures" "$(ft greetgest 'overview=0 visible=0 fingers=0 gesture=0')" "1"
ok "the keyboard opens on the boot login" "$(ft greetkbd 'kbd=1')" "1"
ok "the login keyboard is secret, with no suggestions" "$(grep -c '^state .*secret=1 nsug=0' "$W/greetkeys.txt")" "1"
ok "the login keyboard has no emoji or clipboard" "$(grep -cE '^(clip|emoji) ' "$W/greetkeys.txt")" "0"
ok "a wrong password starts no session" "$(wc -c <"$W/l0.txt")" "0"
ok "the picked session starts on the right password" "$(cat "$W/launch.log")" "two-session"
ok "the user name is used only to log in" "$(grep -l 'config.user' "$SRC"/shell/*.qml | wc -l) $(grep -c 'config.user' "$SRC/shell/Auth.qml")" "1 1"
ok "the configured name is on no text" "$(grep -c 'sampleuser' "$W/all.log")" "0"
ok "the real PAM and greetd code loads" "${AUTHCHECK##*AUTHCHECK }" "true true"
# the editor's white Done pill, top right; the clock area of two captures, pixels that differ
pill() { magick "$W/$1.ppm" -crop 25x40+845+120 -format '%[fx:mean>0.9]' info: 2>&1 | awk '{ print ($0 == "1") ? "yes" : "no" }'; }
apart() { magick "$W/$1.ppm" "$W/$2.ppm" -crop 1080x800+0+150 +repage -compose difference -composite -threshold 10% -format '%[fx:int(mean*w*h+0.5)]' info: 2>&1; }
lit() { magick "$W/$1.ppm" -crop 300x200+60+1100 -format '%[fx:mean>0.05]' info: 2>&1 | awk '{ print ($0 == "1") ? "yes" : "no" }'; }
saved() { grep -c '^lock_clock=thin$\|^lock_clock_color=accent$' "$W/$1.conf" 2>/dev/null; }
ok "editor: a hold on the lock asks for the password first" "$(ft ehold 'kbd=1 .*locked=1') $(pill edit-1-hold)" "1 no"
ok "editor: the right password opens the editor, still locked" "$(ft eauth 'locked=1') $(pill edit-2-editor)" "1 yes"
ok "editor: Done saves the style and the colour" "$(saved saved)" 2
ok "editor: after it a swipe up opens without the password" "$(ft eswipe 'locked=0')" 1
ok "editor: Cancel keeps what was saved" "$(saved cancelled) $(ft ecancel 'locked=1') $(pill edit-7-cancelled)" "2 1 no"
ok "editor: a wallpaper picked then cancelled is not kept" "$(grep -c wallpaper "$W/login-cancelled.txt") $(lit edit-6-bold) $(lit edit-7-cancelled)" "0 yes no"
a=$(apart edit-8-restart edit-5-saved); b=$(apart edit-8-restart edit-0-lock)
ok "editor: the saved style is back after a restart" "$([ "${a:-x}" -ge 0 ] 2>/dev/null && [ $((a * 4)) -lt "${b:-0}" ] && echo yes || echo "no ($a vs $b)")" yes
ok "editor: with a PIN a hold shows the pad, the PIN opens the editor" "$(ft phold 'kbd=0 .*locked=1') $(pill pin-1-hold) $(ft pauth 'locked=1') $(pill pin-2-editor)" "1 no 1 yes"
ink() { magick "$W/style-$1.ppm" -crop 1080x800+0+150 -colorspace gray -format "%[fx:$2]" info: 2>&1; }
ok "auto ink: dark on the light wallpaper, white on the dark one" "$(ink light-bold 'minima<0.3') $(ink dark-bold 'maxima>0.9')" "1 1"
ok "every style on both wallpapers draws its own clock" "$(for f in "$W"/style-*.ppm; do magick "$f" -crop 1080x800+0+150 +repage rgb:- | md5sum; done | sort -u | wc -l)" 10
# the laptop script up to the point it would start: a stub stands where the window would open
mkdir "$W/stub" "$W/lap"
printf '#!/bin/sh\nenv >>"$PHONE_LAPTOP_DIR/env"; echo --- >>"$PHONE_LAPTOP_DIR/env"\n' >"$W/stub/dbus-run-session"; chmod +x "$W/stub/dbus-run-session"
lap() { env -i HOME="$W/home" PATH="$W/stub:$PATH" WAYLAND_DISPLAY=stub-no-window PHONE_LAPTOP_DIR="$W/lap" sh "$SRC/run-on-laptop.sh" "$@" >/dev/null 2>&1; }
lap; lap --lock 800; lap --login
ok "the laptop window keeps its languages to itself and starts in English" "$(grep -c "^XDG_DATA_HOME=$W/lap/data$" "$W/lap/env")" "3"
ok "the laptop script always uses the fake authenticator" "$(grep -c '^PHONE_AUTH_MOCK=test$' "$W/lap/env")" "3"
ok "the laptop script can start locked" "$(grep -c '^PHONEGLUEWC_RELOCK=1$' "$W/lap/env")" "1"
ok "the laptop script can start at the login" "$(grep -c '^PHONEGLUEWC_GREETER=1$' "$W/lap/env")" "1"
ok "the laptop script keeps its window size with a mode" "$(grep -c 'mode=360x800' "$W/lap/config/phonegluewc/config.conf")$(lap 800 --lock; grep -c 'mode=360x800' "$W/lap/config/phonegluewc/config.conf")" "01"
if [ -n "${TOUCH_VERBOSE:-}" ]; then grep -a '^FT ' "$W/all.log" | cut -c1-40; sed -n 1,5p "$W/launch.log"; cat "$W/gw.log" | grep -a 'qml\|WARN' | head -20; fi
[ "$fails" = 0 ] && echo "all lock checks passed"
exit "$fails"
