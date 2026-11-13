#!/bin/bash
# The settings app, headless, against stub tools that log their exact arguments. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-settings.XXXXXX")
SANDBOX_EXTRA="mktemp readlink timeout uname df sync date dirname chmod ln touch"
. "$SRC/tests/sandbox.sh"
# KEEP_LOG=DIR keeps the first scene's logs, even when the run stops early
trap '[ -n "${KEEP_LOG:-}" ] && cp "$W"/calls* "$W"/marks* "$W"/app.* "$KEEP_LOG"/ 2>/dev/null; comp_kill; rm -rf "$W"' EXIT
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
# a copy without the shipped wallpapers, so the test's own picture keeps its place in the grid
mkdir -p "$W/app/shell"; cp -a "$SRC/settings" "$W/app/"; cp "$SRC/shell/camera-holes" "$W/app/shell/"
APP=$W/app/settings
PS=$APP/pset
CFG=$W/cfg/phonegluewc

# ---- the config writer on its own: no compositor needed ----
reset_cfg() { rm -rf "$CFG" "$W/cfg/mimeapps.list" "$W/cfg/phonekbd" "$W/state/phonekbd"; mkdir -p "$CFG"; }
reset_cfg
printf '# my notes\nremember_layout = false\n\noutput = * mode=1080x2400 scale=2.75\nxkb_layout = us\nnot a real line\n' >"$CFG/config.conf"
cp "$CFG/config.conf" "$W/orig.conf"
chmod 640 "$CFG/config.conf"
sandbox "$PS" output HEAD-1 scale 3.20
ok "a scale edit changes only that key"     '[ "$(diff "$W/orig.conf" "$CFG/config.conf" | grep -c "^[<>]")" = 2 ] && grep -qx "output = \* mode=1080x2400 scale=3.20" "$CFG/config.conf"'
ok "an edit keeps the file mode"            '[ "$(stat -c %a "$CFG/config.conf")" = 640 ]'
sandbox "$PS" output HEAD-1 transform 90
ok "a new key joins the others"             'grep -qx "output = \* mode=1080x2400 scale=3.20 transform=90" "$CFG/config.conf"'
cp "$CFG/config.conf" "$W/before.conf"
sandbox "$PS" output HEAD-1 scale '3;reboot' 2>/dev/null; a=$?
sandbox "$PS" set config xkb_layout $'us\noutput = * enabled=false' 2>/dev/null; b=$?
sandbox "$PS" set config remember_layout true 2>/dev/null; c=$?
sandbox "$PS" output $'x\ny' scale 3 2>/dev/null; d=$?
ok "bad values are refused, nothing written" '[ "$a$b$c$d" != 0000 ] && [ $a != 0 ] && [ $b != 0 ] && [ $c != 0 ] && [ $d != 0 ] && cmp -s "$W/before.conf" "$CFG/config.conf"'
mv "$CFG/config.conf" "$W/config.away"
sandbox "$PS" output HEAD-1 scale 3 2>/dev/null; a=$?
ok "a missing config.conf is not invented"  '[ $a != 0 ] && [ ! -e "$CFG/config.conf" ]'
mv "$W/config.away" "$CFG/config.conf"
ln -s "$W/real.conf" "$CFG/phone.conf"; printf 'accent=#112233\nkeep=me\n' >"$W/real.conf"
sandbox "$PS" set phone accent '#2f7bff'
ok "a symlinked file stays a symlink"       '[ -L "$CFG/phone.conf" ] && grep -qx "accent=#2f7bff" "$W/real.conf" && grep -qx "keep=me" "$W/real.conf"'
chmod 500 "$CFG"; printf 'accent=#000000\n' >"$W/ro" 
cp "$CFG/config.conf" "$W/before.conf"
sandbox "$PS" output HEAD-1 scale 2 2>/dev/null; a=$?
chmod 700 "$CFG"
ok "a directory that refuses writes keeps the file" '[ $a != 0 ] && cmp -s "$W/before.conf" "$CFG/config.conf"'
ok "no temp files are left behind"          '[ -z "$(find "$CFG" -name "*.??????")" ]'
sandbox "$PS" wallpaper "$W/home/my pic;x.png"
ok "the wallpaper reaches home and lock"    'grep -qxF "wallpaper=$W/home/my pic;x.png" "$W/real.conf" && grep -qxF "wallpaper=$W/home/my pic;x.png" "$CFG/login.conf"'
sandbox "$PS" wallpaper relative.png 2>/dev/null; a=$?
ok "a relative wallpaper is refused"        '[ $a != 0 ]'
printf '[Added Associations]\ntext/html=old.desktop;\n\n[Default Applications]\nimage/png=viewer.desktop\ntext/html=old.desktop;\n' >"$W/cfg/mimeapps.list"
sandbox "$PS" browser testbrowser
ok "the default browser takes its three keys, others stay" 'grep -c "testbrowser.desktop;" "$W/cfg/mimeapps.list" | grep -qx 3 && grep -qx "image/png=viewer.desktop" "$W/cfg/mimeapps.list" && sed -n 2p "$W/cfg/mimeapps.list" | grep -qx "text/html=old.desktop;"'
printf '# mine\nold.desktop\n' >"$CFG/pinned-apps"
sandbox "$PS" pinned one two
ok "the pinned list keeps its comment"      '[ "$(cat "$CFG/pinned-apps")" = "$(printf "# mine\none.desktop\ntwo.desktop")" ]'
sandbox "$PS" pinned 'a b' 2>/dev/null; a=$?
sandbox "$PS" bt-pair 'AA:BB;reboot' 2>/dev/null; b=$?
ok "a bad app id or device address is refused" '[ $a != 0 ] && [ $b != 0 ]'
sandbox "$PS" output HEAD-1 scale 0.00 2>/dev/null; a=$?
ok "a scale the compositor would refuse never reaches the file" '[ $a != 0 ]'
sandbox "$PS" kbd-layout laptop
ok "the keyboard state folder is created when missing" 'grep -qx laptop "$W/state/phonekbd/layout"'
mkdir -p "$W/cfg/phonekbd"; printf 'learn = off\npredict = on\n' >"$W/cfg/phonekbd/config"
sandbox "$PS" set kbd predict off
sandbox "$PS" set kbd autocorrect maybe 2>/dev/null; a=$?; sandbox "$PS" set kbd one_handed left 2>/dev/null; b=$?
ok "a bad value or other keyboard key is refused" '[ $a != 0 ] && [ $b != 0 ] && ! grep -q "autocorrect\|one_handed" "$W/cfg/phonekbd/config"'
ok "the keyboard option changes alone"      '[ "$(cat "$W/cfg/phonekbd/config")" = "$(printf "learn = off\npredict = off")" ]'
printf 'accent=#000000\n' >"$W/real.conf"; chmod 000 "$W/real.conf"
sandbox "$PS" set phone accent '#2f7bff' 2>/dev/null; a=$?
chmod 600 "$W/real.conf"
ok "an unreadable file is not treated as empty" '[ $a != 0 ] && grep -qx "accent=#000000" "$W/real.conf"'
reset_cfg

# ---- the stub tools ----
STUBS=$W/stubs; mkdir -p "$STUBS"
cat >"$STUBS/_stub" <<'EOF'
#!/bin/sh
name=${0##*/}
line=$name; for a; do line="$line	$a"; done
printf '%s\n' "$line" >>"$STUB_W/calls"
case "$name $*" in
*--ask*) cat >>"$STUB_W/stdin.log"
	case "$*" in *'<b>'*) echo "Error: Connection activation failed: Secrets were required, but not provided." >&2; exit 4 ;; esac ;;
'nmcli -t -f WIFI g') echo enabled ;;
'nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list')
	printf '%s\n' '*:88:WPA2:Home\:5G' ' :77:WPA2:Cafe Guest' " :60:--:a;touch \$HOME/pwned;'\"\$(id)" ' :50:WPA2:<b>Bold</b>' ' :40:WPA2:Office' ;;
'nmcli -t -f NAME,TYPE con show') printf '%s\n' 'Home\:5G:802-11-wireless' 'Office:802-11-wireless' 'Wired:802-3-ethernet' ;;
'nmcli -t -f DEVICE,TYPE dev') printf '%s\n' 'wlan0:wifi' 'lo:loopback' ;;
'nmcli -t -f NAME,TYPE,ACTIVE con show') printf '%s\n' 'Fake Carrier:gsm:no' ;;
'nmcli -g gsm.home-only con show id Fake Carrier') echo yes ;;
'bluetoothctl show') printf 'Controller 00:11:22:33:44:55 (public)\n\tPowered: yes\n' ;;
'bluetoothctl devices') printf 'Device AA:BB:CC:00:00:01 Fake Headset\nDevice AA:BB:CC:00:00:02 Fake;Keyboard\n' ;;
'bluetoothctl info AA:BB:CC:00:00:01') printf '\tPaired: yes\n\tConnected: yes\n\tIcon: audio-headset\n\tBattery Percentage: 0x40 (64)\n' ;;
'bluetoothctl info AA:BB:CC:00:00:02') printf '\tPaired: no\n\tConnected: no\n\tIcon: input-keyboard\n' ;;
'bluetoothctl --timeout 12 scan on') echo $$ >"$STUB_W/scanpid"; exec sleep 13 ;;
'brightnessctl -m') echo 'fake0,backlight,500,50%,1000' ;;
'wpctl get-volume @DEFAULT_AUDIO_SINK@') echo 'Volume: 0.40' ;;
'wpctl status') printf 'PipeWire\n\nAudio\n ├─ Devices:\n │      40. Fake Card\n │\n ├─ Sinks:\n │      45. Fake Speaker        [vol: 0.40]\n │  *   46. Fake Headphones     [vol: 0.50]\n │\n ├─ Sources:\n │  *   50. Fake Mic\n\nVideo\n ├─ Sinks:\n │      60. Not Sound\n' ;;
'mmcli -L -K') printf 'modem-list.length : 1\nmodem-list.value[1] : /org/freedesktop/ModemManager1/Modem/3\n' ;;
'mmcli -m 3 -K') printf 'modem.generic.state : registered\nmodem.generic.sim : /org/freedesktop/ModemManager1/SIM/0\nmodem.generic.unlock-required : sim-pin\nmodem.generic.signal-quality.value : 70\nmodem.3gpp.operator-name : Fake Carrier\nmodem.3gpp.registration-state : home\n' ;;
'upower -e') printf '/org/freedesktop/UPower/devices/line_power_AC\n/org/freedesktop/UPower/devices/battery_BAT0\n' ;;
'upower -i /org/freedesktop/UPower/devices/battery_BAT0') printf '  battery\n    state:               discharging\n    percentage:          64%%\n    capacity:            91.2%%\n    charge-cycles:       123\n    time to empty:       4.5 hours\n' ;;
esac
exit 0
EOF
chmod +x "$STUBS/_stub"
for t in nmcli bluetoothctl rfkill brightnessctl wpctl pactl mmcli upower loginctl systemctl reboot shutdown poweroff fbcli; do ln -s _stub "$STUBS/$t"; done

# ---- a build with the fake touchscreen ----
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg keyboard/phonekbd keyboard/phonekbd-lang >"$W/build.log" 2>&1 || { grep -E "error|\*\*\*" "$W/build.log" | tail -5; echo "FAIL build failed"; exit 1; }
# the real clear command; a plain start, as the compositor does, must not bring a keyboard up here
cat >"$STUBS/phonekbd" <<EOF
#!/bin/sh
printf 'phonekbd\t%s\n' "\$*" >>"$W/calls"
case "\$1" in --clear-*) exec "$BUILD/keyboard/phonekbd" "\$@" ;; esac
exit 0
EOF
chmod +x "$STUBS/phonekbd"
# the list the page reads is what the real helper prints, from a server on loopback; the page itself only ever runs the fake
python3 "$SRC/tests/fake-lang-server.py" "$W/lang-srv" "$SRC/keyboard/packs" >/dev/null 2>&1 & LSRV=$!
for i in $(seq 50); do [ -s "$W/lang-srv/port" ] && break; sleep 0.1; done
LB=http://127.0.0.1:$(cat "$W/lang-srv/port")
rlang() { env HOME="$W/rl" XDG_DATA_HOME="$W/rl/data" XDG_CACHE_HOME="$W/rl/$1" PHONEKBD_DATA="$SRC/keyboard/data" PHONEKBD_REGISTRY="$LB/records" PHONEKBD_CDN="$LB/cdn/" PHONEKBD_PACKS="$LB/packs" "$BUILD/keyboard/phonekbd-lang" "${@:2}"; }
mkdir -p "$W/rl"; rlang cache list >"$W/lang-real"; rlang cache install ro >/dev/null; rlang cache list >"$W/lang-real-ro"; kill "$LSRV"
rlang nocache list >"$W/lang-offline"
{ head -1 "$W/lang-real"; grep -P '^L (de|ja|ro)\t' "$W/lang-real"; printf 'L xx\t<b>Bold</b> $(touch %s/pwned)\ttoen\t1572864000\tavailable\t0\n' "$W"
  printf 'L ../evil\tEvil\tboth\t100\tavailable\t0\nL --help\tDash\tboth\t100\tavailable\t0\nL en\tEnglish\tboth\t100\tavailable\t0\nL qq\tNotanumber\tboth\tNaN\tavailable\t0\nL pp\tShort\tboth\ngarbage\n'; } >"$W/lang-base"
{ head -1 "$W/lang-real-ro"; grep -P '^L (de|ja|ro)\t' "$W/lang-real-ro"; } >"$W/lang-ro"
cp "$W/lang-base" "$W/lang-list"
# installed packs for the keyboard page, plus folders it must skip
mkdir -p "$W/data/phonekbd/langs/ro" "$W/data/phonekbd/langs/Bad;x" "$W/data/phonekbd/langs/en" "$W/data/phonekbd/langs/de"
touch "$W/data/phonekbd/langs/ro/words.tsv" "$W/data/phonekbd/langs/Bad;x/words.tsv" "$W/data/phonekbd/langs/en/words.tsv"
sed '1s/.*/S cached/' "$W/lang-base" >"$W/lang-cached"; printf 'not a list\nL de\tDeutsch\tboth\t1\tavailable\t0\n' >"$W/lang-bad"
cat >"$STUBS/phonekbd-lang" <<EOF
#!/bin/sh
printf 'phonekbd-lang\t%s\n' "\$*" >>"$W/calls"
case "\$1 \${2:-}" in
"list ") cat "$W/lang-list" ;;
"install de") echo "P 0 104857600"; echo "P 52428800 104857600"
	echo \$\$ >"$W/lang-pid"
	trap 'echo term >>"$W/lang-term"; echo "E Cancelled"; exit 1' TERM
	sleep 30 & echo \$! >>"$W/lang-sleeps"; wait ;;
"install ro") echo "P 0 630526"; echo "P 630526 630526"; cp "$W/lang-ro" "$W/lang-list"; echo D ;;
"install xx") echo "P 0 1572864000"; echo "E No connection. Nothing was installed."; exit 1 ;;
"remove ro") cp "$W/lang-base" "$W/lang-list"; echo D ;;
*) exit 2 ;;
esac
EOF
chmod +x "$STUBS/phonekbd-lang"
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot build failed"; exit 1; }
wayland-scanner client-header "$SRC/tests/input-method-unstable-v2.xml" "$BUILD/input-method-protocol.h"
wayland-scanner private-code "$SRC/tests/input-method-unstable-v2.xml" "$BUILD/input-method-protocol.c"
cc -w -I"$BUILD" -o "$W/imlog" "$SRC/tests/imlog.c" "$BUILD/input-method-protocol.c" -lwayland-client || { echo "FAIL imlog build failed"; exit 1; }

scene() {
	reset_cfg; rm -rf "$W/data/applications" "$W/home/Pictures"
	mkdir -p "$W/data/applications" "$W/data/icons/hicolor/scalable/apps" "$W/home/Pictures"
	printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$CFG/config.conf"
	printf 'phone.desktop\nbrowser.desktop\n' >"$CFG/pinned-apps"
	for n in Browser Camera Phone Notes; do
		id=$(echo "$n" | tr A-Z a-z); c=; ic=
		[ "$n" = Browser ] && c=Categories=Network\;WebBrowser\;
		[ "$n" = Phone ] && ic=Icon=testphone
		printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\n%s\n%s\n' "$n" "$c" "$ic" >"$W/data/applications/$id.desktop"
	done
	printf '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" rx="12" fill="#2060e0"/></svg>\n' >"$W/data/icons/hicolor/scalable/apps/testphone.svg"
	magick -size 200x300 gradient:'#203040-#102030' "$W/home/Pictures/wall one.png"
}

# logical pixels at the phone's default size
SW=393; SH=873
drag() { awk -v x="$1" -v a="$2" -v b="$3" -v sw="$SW" -v sh="$SH" 'BEGIN { printf "d 0 %.4f %.4f\nf\n", x/sw, a/sh; for (i = 1; i <= 10; i++) printf "m 0 %.4f %.4f\nf\nw 16\n", x/sw, (a + (b-a)*i/10)/sh; printf "w 200\nu 0\nf\nw 900\n" }'; }
tp() { awk -v x="$1" -v y="$(($2+8))" -v w="${3:-900}" -v sw="$SW" -v sh="$SH" 'BEGIN { printf "d 0 %.4f %.4f\nf\nu 0\nf\nw %d\n", x/sw, y/sh, w }'; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
cat >"$W/run.sh" <<EOF
exec "$APP/phonesettings" "\$@" >>"$W/app.log" 2>&1
EOF
launch() { echo "x sh $W/run.sh $1 & echo \$! >$W/apppid"; echo "w 2500"; }
goto() { echo "x sh $W/run.sh $1"; echo "w 1500"; }
# a labelled mark: is the app alive, and which page does it say it shows
cat >"$W/mark.sh" <<EOF
p=\$(cat "$W/apppid"); a=0; kill -0 "\$p" 2>/dev/null && a=1
echo "\$1 alive=\$a page=\$(qs ipc -p "$APP" call settings page 2>&1)" >>"$W/marks"
EOF
# have TEST NAME: writes NAME to the marks when the shell test holds at this moment of the script
have() { printf '%s && echo %s >>%s\n' "$1" "$2" "$W/marks" >"$W/have-$2.sh"; echo "x sh $W/have-$2.sh"; echo "w 300"; }
mark() { echo "x sh $W/mark.sh $1"; echo "w 500"; }
cat >"$W/rss.sh" <<EOF
c=\$(cat "$W/pid"); q=\$(pgrep -P \$c -x qs | head -1)
s=\$(awk '/VmRSS/{print \$2}' /proc/\$q/status); a=\$(awk '/VmRSS/{print \$2}' /proc/\$(cat "$W/apppid" 2>/dev/null || echo 0)/status 2>/dev/null)
echo "\$1 shell=\$s app=\${a:-gone}" >>"$W/rss"
EOF
rss() { echo "w 1500"; echo "x sh $W/rss.sh $1"; echo "w 300"; }
# the close a window gets from the compositor, as the overview's own close sends it
mkdir -p "$W/closer"; cat >"$W/closer/shell.qml" <<'EOF'
import Quickshell
import Quickshell.Wayland
import QtQuick
ShellRoot {
    // reading the list starts it, the windows arrive from the compositor a moment later
    property int windows: ToplevelManager.toplevels.values.length
    Timer {
        running: true
        interval: 1000
        onTriggered: {
            for (const t of ToplevelManager.toplevels.values)
                if (t.title === "Settings") t.close();
            Qt.quit();
        }
    }
}
EOF
msg() { echo "x phonegluewc-msg outputs >$W/$1 2>&1"; echo "w 300"; }

COMP=$BUILD/phonegluewc
SANDBOX_PATH="$STUBS:$BUILD"
PASS='s3cret-pass;$(id)'
META="a;touch \$HOME/pwned;'\"\$(id)"
called() { local s="$1"; shift; for a; do s+=$'\t'"$a"; done; grep -Fxq -- "$s" "$W/calls"; }

scene; : >"$W/calls"; : >"$W/stdin.log"; : >"$W/app.log"; : >"$W/marks"; : >"$W/rss"
KCONF=$W/cfg/phonekbd/config; KSTATE=$W/state/phonekbd
mkdir -p "$W/cfg/phonekbd"; printf 'learn = false\n' >"$KCONF"
mkdir -p "$W/state/phonekbd"; for f in learned.tsv bigrams.tsv emoji-recent; do echo fake >"$W/state/phonekbd/$f"; done
# shortcut: written by hand until the compositor writes it itself
mkdir -p "$W/state/phonegluewc"; echo normal >"$W/state/phonegluewc/orientation"
HOMEQS=
{
	echo "w 2500"; rss idle; echo "w 60000"; rss before; shot home-before
	# memory first, while no setting has changed: a wallpaper the shell draws is its own cost
	launch ""; rss app-main; goto wifi; rss app-wifi; tp 32 68 1000; tp 32 68 1500; rss after
	launch ""; mark main; shot settings-main
	echo "x $W/imlog blue >$W/im1.log 2>&1 & echo \$! >$W/im1.pid"; echo "w 500"
	tp 196 126; echo "w 800"; shot search; tp 196 194 1200; mark searched
	echo 'x kill $(cat '"$W"'/im1.pid)'; echo "w 300"
	tp 32 68 1000; mark backed

	goto wifi; mark wifi; shot settings-wifi
	tp 196 128 800
	tp 196 237 700; tp 70 293 1000
	tp 196 365 700; shot wifi-open; tp 70 421 1500
	tp 196 493 700; tp 170 549 500; tp 170 549 1500
	# a script: the hook cuts an x line at 128 bytes, and a lost pid would leave this input method running
	printf "%s '%s' >%s 2>&1 &\necho \$! >%s\n" "$W/imlog" "$PASS" "$W/im2.log" "$W/im2.pid" >"$W/im2.sh"
	echo "x sh $W/im2.sh"; echo "w 500"
	tp 196 301 700; tp 70 357 1000; shot settings-password; tp 70 275 1500; mark wifi-pass
	tp 196 429 700; tp 70 485 1000; tp 70 275 2000; shot wifi-failed; mark wifi-fail
	echo 'x kill $(cat '"$W"'/im2.pid)'; echo "w 300"

	goto display; mark display; shot settings-display
	tp 196 543 800; have "grep -qx animations=off $W/cfg/phonegluewc/phone.conf" anim-off; shot display-anim; tp 196 543 800
	tp 196 455 800; have "grep -qx 1 $W/state/phonegluewc/rotation-lock" rot-locked; shot display-rot; tp 196 455 800; have "grep -qx 0 $W/state/phonegluewc/rotation-lock" rot-auto
	tp 196 167 500; tp 21 167 500
	tp 240 260 1500; msg out-large; shot display-large
	goto display; SW=337; SH=750; tp 149 260 1500; SW=393; SH=873; msg out-default
	tp 200 355 1500; msg out-land
	shot display-land
	echo "x $APP/pset output HEADLESS-1 transform normal"; echo "w 1500"; msg out-port

	goto sound; mark sound; shot sound; tp 300 160 600; tp 196 220 600; tp 196 334 800
	PCONF=$W/cfg/phonegluewc/phone.conf
	shot sound-ringer; tp 239 494 800; have "grep -qx ringer=silent $PCONF" ringer-silent; shot sound-silent
	tp 154 494 800; have "grep -qx ringer=vibrate $PCONF" ringer-vibrate
	tp 196 636 800; have "grep -qx dnd=on $PCONF" dnd-on; shot sound-dnd
	tp 196 636 800; have "grep -qx dnd=off $PCONF" dnd-off
	goto bluetooth; mark bluetooth; tp 70 365 700; shot bluetooth
	tp 196 301 700; tp 70 357 1500
	tp 196 237 700; tp 70 293 1500
	goto mobile; mark mobile; shot mobile; tp 196 $((96+45+64*4+45+32)) 900; tp 196 $((96+45+64*4+45+64+32)) 900
	goto battery; mark battery; shot battery; drag 196 700 100; shot battery-power
	tp 165 516 800; have "grep -qx power_double=flashlight $W/cfg/phonegluewc/phone.conf" pw-double
	tp 65 712 800; have "grep -qx power_triple=none $W/cfg/phonegluewc/phone.conf" pw-triple; shot battery-picked
	goto look; mark look; shot look; tp 220 251 800; tp 196 480 800
	goto apps; mark apps; shot apps; tp 196 173 800; tp 325 282 800
	goto language; mark language; shot language
	tp 196 170 800; tp 196 239 800
	tp 196 318 800; have "grep -qx 'learn = on' $KCONF" learn-on; shot language-learn-on; tp 196 318 800
	shot language-set
	tp 196 406 800; have "[ ! -e $KSTATE/emoji-recent ] && [ -e $KSTATE/learned.tsv ] && grep -qx 'emoji_history = off' $KCONF" emoji-off
	# the real keyboard, given what this app wrote, must drop a recent list that came back
	printf 'echo fake >%s/emoji-recent\n%s/keyboard/phonekbd >%s/kbd.log 2>&1 &\necho $! >%s/kbd.pid\n' "$KSTATE" "$BUILD" "$W" "$W" >"$W/kbd-start.sh"
	echo "x sh $W/kbd-start.sh"; echo "w 1500"
	have "[ ! -e $KSTATE/emoji-recent ] && kill -0 \$(cat $W/kbd.pid)" kbd-dropped-emoji
	echo 'x kill $(cat '"$W"'/kbd.pid)'; echo "w 300"
	tp 196 406 800; have "grep -qx 'emoji_history = on' $KCONF && [ \$(grep -c clear-emoji $W/calls) = 1 ]" emoji-on
	tp 340 561 800; have "[ ! -e $KSTATE/clipboard-cleared ]" clip-asked; tp 340 561 1000; shot language-clip
	tp 196 492 800; shot language-clip-off
	tp 196 644 800
	tp 340 718 800; have "[ -e $KSTATE/learned.tsv ]" clear-asked; tp 340 718 1000; shot language-cleared
	drag 196 700 100; shot keyboard-2
	have "! grep -q phonekbd-lang $W/calls" lang-quiet; tp 196 352 1500; mark languages; shot languages
	have "[ \$(grep -c 'phonekbd-lang.list' $W/calls) = 1 ]" lang-one
	tp 318 174 800; have "! grep -q 'phonekbd-lang.install' $W/calls" lang-asked; shot languages-ask
	tp 318 174 1200; shot languages-progress
	tp 318 260 600; tp 318 260 800; have "! grep -q 'install ro' $W/calls" lang-blocked
	goto about; goto languages; have "kill -0 \$(cat $W/lang-pid)" lang-survives; shot languages-resumed
	tp 318 170 1500; have "[ -s $W/lang-term ]" lang-cancelled; shot languages-cancelled
	tp 318 432 600; tp 318 432 1500; shot languages-failed
	tp 318 325 600; tp 318 325 2000; shot languages-installed
	tp 318 174 600; have "! grep -q 'remove' $W/calls" lang-rm-asked; tp 318 174 2000; shot languages-removed
	tp 32 68 1000; mark lang-back
	drag 196 700 100; drag 196 700 100; shot keyboard-3; drag 196 700 100; shot keyboard-4
	drag 196 700 100; shot language-bottom; tp 186 690 800; shot language-chip
	goto security; mark security; shot security
	goto about; mark about
	goto no-such-page; mark unknown
	tp 32 68 1000; tp 32 68 1500; mark gone; shot home-after
	echo "x rm -f $W/lang-term"; echo "w 200"; launch languages; tp 318 174 600; tp 318 174 1200; shot languages-closing
	tp 32 68 800; tp 32 68 800; tp 32 68 2000; have "[ -s $W/lang-term ]" lang-closed-term; have "! kill -0 \$(cat $W/lang-pid)" lang-closed-gone
	echo "x cp $W/lang-offline $W/lang-list"; echo "w 200"; launch languages; shot languages-offline
	echo "x cp $W/lang-cached $W/lang-list"; echo "w 200"; tp 196 197 1500; shot languages-cached
	echo "x cp $W/lang-bad $W/lang-list"; echo "w 200"; tp 196 197 1500; shot languages-bad
	tp 32 68 800; tp 32 68 800; tp 32 68 2000
	launch ""; mark reopened; echo "x qs -p $W/closer >$W/closer.log 2>&1"; echo "w 3000"; mark closed
	echo "x true"; echo "w 300"
} >"$W/script"
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/script" STUB_W="$W"
comp_wait 3600
comp_stop
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done

mk() { grep -q "^$1 alive=1 page=$2\$" "$W/marks"; }
ok "the launcher opens the main list"       'mk main ""'
ok "search and a tap push a page"           'grep -q committed "$W/im1.log" && mk searched bluetooth'
ok "the back arrow returns to the list"     'mk backed ""'
for p in wifi display sound bluetooth mobile battery look apps keyboard languages security about; do
	# the keyboard page is opened by its old name, which also checks the alias
	q=$p; [ $p = keyboard ] && q=language
	ok "$p opens in the running app, no second copy" "mk $q $p"
done
have_() { grep -q "^$1" "$W/marks"; }
ok "Languages: the real helper's list has the fields the page reads" 'grep -qP "^L ro\tRomână\tboth\t\d+\tavailable\t1$" "$W/lang-real" && grep -qP "^L ro\tRomână\tinstalled\t0\tinstalled\t0$" "$W/lang-offline" && [ "$(head -1 "$W/lang-offline")" = "S offline" ]'
ok "Languages: no network tool on the app's PATH" '! PATH="$STUBS:$BUILD" command -v curl'
ok "Languages: nothing runs the helper before the page opens" 'have_ lang-quiet'
ok "Languages: opening runs one list"       'have_ lang-one'
ok "Languages: first tap only asks"         'have_ lang-asked'
ok "Languages: the download gets the exact arguments" 'grep -qxP "phonekbd-lang\tinstall de" "$W/calls"'
ok "Languages: a second download waits"     'have_ lang-blocked'
ok "Languages: a download survives leaving the page" 'have_ lang-survives'
ok "Languages: cancel stops the helper"     'have_ lang-cancelled'
ok "Languages: a failed download says why"  'grep -q "note: No connection. Nothing was installed." "$W/app.log"'
ok "Languages: remove asks, then gets the exact arguments" 'have_ lang-rm-asked && grep -qxP "phonekbd-lang\tremove ro" "$W/calls"'
ok "Languages: back returns to the keyboard page" 'mk lang-back keyboard'
ok "Languages: closing the app stops a download" 'have_ lang-closed-term && have_ lang-closed-gone'
ok "Languages: bad codes never reach the helper" '! grep -Eq "phonekbd-lang.(install|remove) .*(evil|help|en$|qq|pp)" "$W/calls"'
ok "Languages: a name is never run"         '[ ! -e "$W/pwned" ]'
ok "Languages: offline, cached and unreadable lists say so" 'grep -q "note: You are offline" "$W/app.log" && grep -q "note: Could not reach" "$W/app.log" && grep -q "note: The language list could not be read" "$W/app.log"'
ok "an unknown page name changes nothing"   'mk unknown about'
ok "back on the main list ends the program" 'grep -q "^gone alive=0" "$W/marks"'
ok "the window can be opened again"         'grep -q "^reopened alive=1" "$W/marks"'
ok "closing the window ends the program"    'grep -q "^closed alive=0" "$W/marks"'
ok "the app logged no QML errors"           '! grep -E "WARN|ERROR|FATAL|TypeError|ReferenceError|Segmentation" "$W/app.log" | grep -v "Wayland connection broke" | grep -q .'

ok "Wi-Fi: the radio switches off"          'called nmcli radio wifi off'
ok "Wi-Fi: disconnect names the device"     'called nmcli dev disconnect wlan0'
ok "Wi-Fi: a hostile name stays one argument" 'called nmcli -w 30 dev wifi connect "$META"'
ok "Wi-Fi: and it ran nothing"              '[ ! -e "$W/home/pwned" ] && [ ! -e pwned ]'
ok "Wi-Fi: forget removes the profile"      'called nmcli con delete id Office'
ok "Wi-Fi: the password flow names the network" 'called nmcli -w 30 --ask dev wifi connect "Cafe Guest"'
ok "Wi-Fi: the password arrives on stdin"   'grep -Fxq -- "$PASS" "$W/stdin.log"'
ok "Wi-Fi: the password is on no command line" '! grep -Fq -- "$PASS" "$W/calls"'
ok "Wi-Fi: nothing but the test keeps the password" '[ -z "$(find "$W" -type f ! -path "$W/build/*" ! -name stdin.log ! -name script ! -name im2.log ! -name im2.sh -exec grep -laF -- "$PASS" {} + | tee "$W/leak")" ] || { cat "$W/leak"; false; }'
ok "Wi-Fi: a sensitive field reaches the keyboard" 'grep -q "^content_type " "$W/im2.log" && awk "/^content_type/ { if (and(\$2, 128)) f = 1 } END { exit !f }" "$W/im2.log"'
ok "Wi-Fi: the field lets go of the keyboard" 'grep -q deactivate "$W/im2.log"'
ok "Wi-Fi: a refused new network leaves no profile" 'called nmcli con delete id "<b>Bold</b>"'
ok "Wi-Fi: the refusal is explained"        'grep -q "note: Wrong password" "$W/app.log"'

ok "Display: brightness follows the slider" 'called brightnessctl -q set 50%'
ok "Display: the slider stops at 1%"        'called brightnessctl -q set 1% && ! grep -q "brightnessctl.*set.0%" "$W/calls"'
ok "Display: a size choice reaches the compositor" 'grep -q "scale=3.20" "$W/out-large"'
ok "Display: and comes back"                'grep -q "scale=2.75" "$W/out-default"'
ok "Display: orientation reaches the compositor" 'grep -q "transform=90" "$W/out-land"'
ok "Display: and back to portrait"          'grep -q "transform=normal" "$W/out-port"'
ok "Display: the config file kept its other keys" 'grep -qx "remember_layout = false" "$CFG/config.conf" && grep -q "mode=1080x2400" "$CFG/config.conf"'
ok "Sound: mute toggles the default output" 'called wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle'
ok "Sound: the ringer choice reaches phone.conf" 'grep -q "^ringer-silent" "$W/marks" && grep -q "^ringer-vibrate" "$W/marks"'
ok "Sound: the ringer leaves the output alone" '! grep -Eq "set-mute.*[01]$" "$W/calls"'
ok "Sound: do not disturb turns on and off"  'grep -q "^dnd-on" "$W/marks" && grep -q "^dnd-off" "$W/marks"'
ok "Keyboard: the new keys take their values" 'sandbox "$PS" set kbd theme light && sandbox "$PS" set kbd accent theme && sandbox "$PS" set kbd height large && sandbox "$PS" set kbd long_press short && sandbox "$PS" set kbd sound on && sandbox "$PS" set kbd predict_languages "en ro" && grep -qx "theme = light" "$KCONF" && grep -qx "predict_languages = en ro" "$KCONF"'
ok "Keyboard: no languages is a value of its own" 'sandbox "$PS" set kbd predict_languages "" && grep -qx "predict_languages = " "$KCONF"'
ok "Keyboard: bad keyboard values are refused" '! sandbox "$PS" set kbd theme pink 2>/dev/null && ! sandbox "$PS" set kbd sound yes 2>/dev/null && ! sandbox "$PS" set kbd predict_languages "en;rm" 2>/dev/null && ! sandbox "$PS" set kbd height 90% 2>/dev/null && ! sandbox "$PS" set kbd one_handed left 2>/dev/null'
ok "Keyboard: installed packs are only the valid folders with words" '[ "$(sandbox "$PS" kbd-langs)" = ro ]'
ok "Keyboard: the old page name still opens it" 'grep -q "^language alive=1 page=keyboard" "$W/marks"'
ok "Display: animations turn off" 'grep -q "^anim-off" "$W/marks"'
ok "Display: auto-rotate off locks rotation, on unlocks it" 'grep -q "^rot-locked" "$W/marks" && grep -q "^rot-auto" "$W/marks"'
ok "Battery: the power button presses reach phone.conf" 'grep -q "^pw-double" "$W/marks" && grep -q "^pw-triple" "$W/marks"'
ok "Battery: a bad press action is refused" '! sandbox "$PS" set phone power_double reboot 2>/dev/null && ! sandbox "$PS" set phone animations maybe 2>/dev/null'
ok "Sound: a bad ringer or dnd value is refused" '! sandbox "$PS" set phone ringer loud 2>/dev/null && ! sandbox "$PS" set phone dnd maybe 2>/dev/null'
ok "Sound: the vibration strength takes 1500 to 3600 mV in steps of 100" 'sandbox "$PS" set phone vibration_mv 3000 2>/dev/null && ! sandbox "$PS" set phone vibration_mv 3700 2>/dev/null && ! sandbox "$PS" set phone vibration_mv 2450 2>/dev/null'
ok "Sound: the volume stays limited"        'grep -Eq "^wpctl.set-volume.-l.1.0.@DEFAULT_AUDIO_SINK@.[0-9]+%$" "$W/calls"'
ok "Sound: picks an audio output, not a video one" 'called wpctl set-default 45 || called wpctl set-default 46; ! grep -q "set-default.60" "$W/calls"'
ok "Bluetooth: the scan ran"                'called bluetoothctl --timeout 12 scan on'
ok "Bluetooth: the scan ends with the page" '! kill -0 "$(cat "$W/scanpid")" 2>/dev/null'
ok "Bluetooth: pairing runs on the right device" 'called bluetoothctl pair AA:BB:CC:00:00:02 && called bluetoothctl trust AA:BB:CC:00:00:02'
ok "Bluetooth: disconnect runs"             'called bluetoothctl disconnect AA:BB:CC:00:00:01'
ok "Mobile: data switches the carrier profile" 'called nmcli con up id "Fake Carrier"'
ok "Mobile: roaming changes the profile"    'called nmcli con modify id "Fake Carrier" gsm.home-only no'
ok "Battery: reads the battery, not the charger" 'called upower -i /org/freedesktop/UPower/devices/battery_BAT0 && ! grep -q "upower.-i.*line_power" "$W/calls"'
ok "Look: the running home screen takes the accent" '[ "$(python3 -I "$SRC/tests/colors.py" "$W/home-before.ppm" 21a366)" = 0 ] && [ "$(python3 -I "$SRC/tests/colors.py" "$W/home-after.ppm" 21a366)" = 1 ]'
ok "Look: the running home screen draws the wallpaper" '[ "$(python3 -I "$SRC/tests/colors.py" "$W/home-before.ppm" 182838)" = 0 ] && [ "$(python3 -I "$SRC/tests/colors.py" "$W/home-after.ppm" 182838)" = 1 ]'
ok "Look: the accent is saved"              'grep -qx "accent=#21a366" "$CFG/phone.conf"'
ok "Look: the wallpaper reaches home and lock files" 'grep -qxF "wallpaper=$W/home/Pictures/wall one.png" "$CFG/phone.conf" && grep -qxF "wallpaper=$W/home/Pictures/wall one.png" "$CFG/login.conf"'
ok "Apps: the default browser is written"   'grep -qx "x-scheme-handler/https=browser.desktop;" "$W/cfg/mimeapps.list"'
ok "Apps: a removed app leaves the file"    '[ "$(cat "$CFG/pinned-apps")" = browser.desktop ]'
# the first tray slot, the left quarter of the screen: Phone leaves it for Browser
slot1() { magick "$W/$1.ppm" -crop 25%x100%+0+0 +repage "$W/$1-slot.ppm"; python3 -I "$SRC/tests/colors.py" "$W/$1-slot.ppm" 2060e0; }
ok "Apps: and leaves its place in the running tray" '[ "$(slot1 home-before)" = 1 ] && [ "$(slot1 home-after)" = 0 ]'
ok "Language: the layout reaches config.conf" 'grep -qx "xkb_layout = gb" "$CFG/config.conf"'
ok "Keyboard: the first tap on Clear only asks" 'grep -q "^clear-asked" "$W/marks"'
ok "Keyboard: Clear removes learned data through the keyboard itself" 'called phonekbd --clear-learned && [ ! -e "$W/state/phonekbd/learned.tsv" ] && [ ! -e "$W/state/phonekbd/bigrams.tsv" ] && [ ! -e "$W/state/phonekbd/emoji-recent" ]'
ok "Keyboard: autocorrect starts on and turns off" 'grep -qx "autocorrect = off" "$W/cfg/phonekbd/config"'
ok "Keyboard: learn = false reads as off and turns on" 'grep -q "^learn-on" "$W/marks"'
ok "Keyboard: learning turns off again" 'grep -qx "learn = off" "$W/cfg/phonekbd/config"'
ok "Keyboard: Emoji off deletes only the recent emoji, at once" 'grep -q "^emoji-off" "$W/marks" && called phonekbd --clear-emoji-history'
ok "Keyboard: the real keyboard obeys the setting this app wrote" 'grep -q "^kbd-dropped-emoji" "$W/marks"'
ok "Keyboard: Emoji back on deletes nothing" 'grep -q "^emoji-on" "$W/marks"'
ok "Keyboard: the first tap on clipboard Clear only asks" 'grep -q "^clip-asked" "$W/marks"'
ok "Keyboard: clipboard Clear reaches the real keyboard command" 'called phonekbd --clear-clipboard-history && [ -e "$W/state/phonekbd/clipboard-cleared" ]'
ok "Keyboard: Clipboard history turns off" 'grep -qx "clipboard_history = off" "$W/cfg/phonekbd/config"'
ok "Language: suggestions and laptop layout are saved" 'grep -qx "predict = off" "$W/cfg/phonekbd/config" && grep -qx laptop "$W/state/phonekbd/layout"'
ok "no power tool was ever called"          '! grep -Eq "^(loginctl|systemctl|reboot|shutdown|poweroff)" "$W/calls"'
ok "the app does not grow the shell"        'b=$(sed -n "s/^before shell=\([0-9]*\).*/\1/p" "$W/rss"); a=$(sed -n "s/^after shell=\([0-9]*\).*/\1/p" "$W/rss"); [ -n "$a" ] && [ -n "$b" ] && [ $((a-b)) -lt 5000 ]'
ok "the app is gone when measured last"     'grep -q "^after .*app=gone" "$W/rss"'
cat "$W/rss"; cp "$W/calls" "$W/calls.main"; cp "$W/app.log" "$W/app.main"; cp "$W/marks" "$W/marks.main"

# ---- every tool missing: only the real programs in the sandbox remain ----
pages="wifi bluetooth display sound mobile battery look apps keyboard languages about security"
script2() {
	echo "w 2500"; launch "$1"; mark first
	for p in $pages; do goto $p; mark $p; shot "$2-$p"; done
	echo "x true"; echo "w 300"
}
mkdir -p "$W/nostubs"; printf '#!/bin/sh\nexit 0\n' >"$W/nostubs/placeholder"; chmod +x "$W/nostubs/placeholder"
PFX=$W/pfx; mkdir -p "$PFX/bin" "$PFX/share/phonegluewc"
make -n -C "$SRC" install DESTDIR="$W/d" PREFIX=/p 2>/dev/null >"$W/make-n"
ok "make install places the program, menu entry and icon" '! for w in "cp -rf settings" "settings/phonesettings " "settings/phonesettings.desktop" "settings/phonesettings.svg"; do grep -qF "$w" "$W/make-n" || echo missing; done | grep -q missing'
cp -r "$APP" "$PFX/share/phonegluewc/settings"; cp "$APP/phonesettings" "$PFX/bin/"
sed -i "s|$APP/phonesettings|$PFX/bin/phonesettings|" "$W/run.sh"
sed -i "s|-p \"$APP\"|-p \"$PFX/share/phonegluewc/settings\"|" "$W/mark.sh"
scene; : >"$W/app.log"; : >"$W/marks"; rm -f "$W"/*.ppm
script2 wifi none >"$W/script"
SANDBOX_PATH="$W/nostubs:$BUILD"
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 600
comp_stop
for f in "$W"/*.ppm; do magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
cp "$W/app.log" "$W/app.none"
note() { grep -q "note: $2" "$W/app.$1"; }
ok "installed: the launcher finds its files" 'grep -q "^first alive=1" "$W/marks"'
ok "no tools: a page link opens that page"  'grep -q "^first alive=1 page=wifi$" "$W/marks"'
ok "no tools: every page opens, no crash"   '[ "$(grep -c "alive=1" "$W/marks")" = 13 ]'
ok "no tools: Vibrate is replaced by a note" 'note none "Vibration is not available"'
ok "with the vibration tool there is no such note" '! note main "Vibration is not available"'
ok "no tools: Wi-Fi says what is missing"   'note none "Wi-Fi settings need NetworkManager"'
ok "no tools: Bluetooth says so"            'note none "Bluetooth settings need the bluetoothctl"'
ok "no tools: brightness says so"           'note none "Brightness needs the brightnessctl"'
ok "no tools: sound says so"                'note none "Sound settings need wpctl or pactl"'
ok "no tools: clearing learned words says so" 'note none "Clearing keyboard data needs the phonekbd"'
ok "no tools: mobile network says so"       'note none "Mobile network is unavailable: the ModemManager"'
ok "no tools: battery says so"              'note none "Battery details need the upower"'
ok "no tools: no QML errors"                '! grep -E "WARN|ERROR|FATAL|TypeError|ReferenceError" "$W/app.none" | grep -v "Wayland connection broke" | grep -q .'

# ---- the tools are there but have nothing to offer, and only pactl for sound ----
EMPTY=$W/empty; mkdir -p "$EMPTY"
cat >"$EMPTY/_stub" <<'EOF'
#!/bin/sh
name=${0##*/}
line=$name; for a; do line="$line	$a"; done
printf '%s\n' "$line" >>"$STUB_W/calls"
case "$name $*" in
'bluetoothctl show') echo 'No default controller available' ; exit 1 ;;
'nmcli '*) echo 'Error: NetworkManager is not running.' >&2; exit 8 ;;
'mmcli -L -K') printf 'modem-list.length : 0\n' ;;
'brightnessctl -m') exit 1 ;;
'pactl get-sink-volume @DEFAULT_SINK@') echo 'Volume: front-left: 32768 /  50% / -18.06 dB' ;;
'pactl get-sink-mute @DEFAULT_SINK@') echo 'Mute: no' ;;
'pactl get-default-sink') echo fake_sink_b ;;
'pactl list short sinks') printf '1\tfake_sink_a\tPipeWire\ts16le 2ch 48000Hz\tIDLE\n2\tfake_sink_b\tPipeWire\ts16le 2ch 48000Hz\tIDLE\n' ;;
esac
exit 0
EOF
chmod +x "$EMPTY/_stub"
for t in nmcli bluetoothctl brightnessctl pactl mmcli upower; do ln -s _stub "$EMPTY/$t"; done
sed -i "s|$PFX/bin/phonesettings|$APP/phonesettings|" "$W/run.sh"
sed -i "s|-p \"$PFX/share/phonegluewc/settings\"|-p \"$APP\"|" "$W/mark.sh"
scene; : >"$W/calls"; : >"$W/app.log"; : >"$W/marks"; rm -f "$W"/*.ppm
{
	echo "w 2500"; launch ""; mark first
	for p in $pages; do goto $p; mark $p; shot "empty-$p"
		[ "$p" = sound ] && { tp 196 220 600; tp 196 334 800; tp 196 399 800; }
	done
	echo "x true"; echo "w 300"
} >"$W/script"
SANDBOX_PATH="$EMPTY:$BUILD"
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_FAKETOUCH="$W/script" STUB_W="$W"
comp_wait 600
comp_stop
for f in "$W"/*.ppm; do magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
cp "$W/app.log" "$W/app.empty"
ok "empty: every page opens, no crash"      '[ "$(grep -c "alive=1" "$W/marks")" = 13 ]'
ok "empty: NetworkManager down is explained" 'note empty "Error: NetworkManager is not running"'
ok "empty: no Bluetooth adapter is explained" 'note empty "No Bluetooth adapter was found"'
ok "empty: no modem is explained"           'note empty "Mobile network is unavailable: no modem was found"'
ok "empty: no battery is explained"         'note empty "No battery was found"'
ok "empty: no backlight is explained"       'note empty "This screen has no brightness control"'
ok "pactl fallback: reads the default output" 'called pactl get-sink-volume @DEFAULT_SINK@ && called pactl list short sinks'
ok "pactl fallback: mute and output change"  'called pactl set-sink-mute @DEFAULT_SINK@ toggle && called pactl set-default-sink fake_sink_a'
ok "empty: no QML errors"                   '! grep -E "WARN|ERROR|FATAL|TypeError|ReferenceError" "$W/app.empty" | grep -v "Wayland connection broke" | grep -q .'

ok "no core files"                          '[ -z "$(ls "$W"/core* 2>/dev/null)" ]'
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; [ -z "${SETTINGS_DEBUG:-}" ] || { cut -c1-150 "$W/calls.main" | grep -v 'nmcli.-t\|bluetoothctl.\(show\|devices\|info\)\|mmcli\|upower\|get-volume\|status\|brightnessctl.-m\|gsm.home'; grep -v 'INFO.*\(Launching\|Shell ID\|Saving\|safedispatch\|Configuration\)' "$W/app.main" | cut -c1-180; grep . "$W"/im2.log | cut -c1-100 | head -20; cat "$W/marks"; cat "$CFG/config.conf"; }; exit 1; }
