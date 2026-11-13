#!/bin/bash
# The battery pill: ink centred in device pixels at phone and laptop scale. SHOTS=DIR keeps PNGs and the contact sheet.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-bat.XXXXXX")
SANDBOX_EXTRA="timeout mktemp readlink sync"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o "$BUILD"/core.*
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }
COMP=$BUILD/phonegluewc
FAILS=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }

LEVELS="1 5 15 16 50 62 99 100"
mkdir -p "$W/fakebin" "$W/fake"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
S=$W/sys; mkdir -p "$S/power_supply/BAT0" "$S/backlight/panel"
echo Battery >"$S/power_supply/BAT0/type"; echo 100 >"$S/backlight/panel/max_brightness"; echo 60 >"$S/backlight/panel/brightness"
cat >"$W/l.sh" <<EOF
echo \$1 >"$S/power_supply/BAT0/capacity"; echo \$2 >"$S/power_supply/BAT0/status"
EOF

# scene NAME MODE SCALE ENV...: every level, charging and not
scene() { local n=$1 mode=$2 scale=$3; shift 3
	mkdir -p "$W/cfg/phonegluewc" "$W/$n"
	printf 'remember_layout = false\noutput = * mode=%s scale=%s\n' "$mode" "$scale" >"$W/cfg/phonegluewc/config.conf"
	{ echo "w 3000"
	for l in $LEVELS; do for c in Discharging Charging; do
		echo "x sh $W/l.sh $l $c"; echo "d 0 0.5 0.01"; echo f; echo "u 0"; echo f; echo "w 1400"
		echo "x $SRC/tests/wshot $W/$n/$l-$c.ppm"; echo "w 400"
	done; done
	echo "p done"; } >"$W/script"
	echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
	SANDBOX_PATH="$W/fakebin:$BUILD"
	comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script" "$@"
	comp_wait 900
	comp_stop
	mv "$W/gw.log" "$W/$n.log"
}
# the compositor starts the shell with the software scene graph everywhere, so this is the path that ships
scene phone 1080x2400 2.75
scene lap 450x1000 1.15 PHONE_NO_HOLE=1

ok "no QML error" '! grep -hE "BatteryPill.*(rror|Unable)|TypeError|ReferenceError" "$W/phone.log" "$W/lap.log" | grep -q .'

measure() { local n=$1 bar=$2 z=$3
	for f in "$W/$n"/*.ppm; do b=${f##*/}; b=${b%.ppm}; echo "$b $(python3 "$SRC/tests/battery-measure.py" "$f" "$bar")"; done | sort -V | tee "$W/$n.txt" | sed "s/^/$n /"
	row=""
	for c in Discharging Charging; do
		line=""; for l in $LEVELS; do
			box=$(grep "^$l-$c " "$W/$n.txt" | sed 's/.*box=//; s/ .*//'); IFS=, read -r x y w h <<<"$box"
			magick "$W/$n/$l-$c.ppm" -crop "$((w+8))x$((h+8))+$((x-4))+$((y-4))" +repage -filter point -resize "$z"00% "$W/$n/$l-$c.png"
			line="$line $W/$n/$l-$c.png"
		done
		magick $line -background '#303030' -splice 6x6 +append "$W/$n-$c.png"; row="$row $W/$n-$c.png"
	done
	magick $row -append "$SHOTS/battery-$n.png"
	magick "$W/$n/62-Discharging.ppm" -crop "$((bar*5))x$bar+$(( $(identify -format %w "$W/$n/62-Discharging.ppm") - bar*5 ))+0" +repage -filter point -resize "$z"00% "$SHOTS/group-$n.png"
}
measure phone 99 6
measure lap 42 12
magick "$SHOTS/battery-phone.png" "$SHOTS/battery-lap.png" -background '#303030' -append "$SHOTS/battery-sheet.png"

# not charging: ink centred to one device pixel, whichever way the odd one falls
awk '/Discharging/ { for (i=2;i<=NF;i++) { split($i,a,"="); v[a[1]]=a[2] } d=v["left"]-v["right"]; if (d<0) d=-d; e=v["top"]-v["bottom"]; if (e<0) e=-e; if (d>1||e>1) { print "off centre:",$0; bad=1 } } END { exit bad }' "$W/phone.txt" "$W/lap.txt" >"$W/off"; ok "ink centred to one device pixel at both scales" '[ ! -s "$W/off" ]' || true
cat "$W/off"
ok "the same size at every level while not charging" '[ "$(grep Discharging "$W/phone.txt" | sed "s/.* w=\([0-9]*\) h=\([0-9]*\).*/\1 \2/" | sort -u | wc -l)" = 1 ] && [ "$(grep Discharging "$W/lap.txt" | sed "s/.* w=\([0-9]*\) h=\([0-9]*\).*/\1 \2/" | sort -u | wc -l)" = 1 ]'
px() { magick "$W/$1/$2.ppm" -format "%[fx:int(255*p{$3,$4}.r)] %[fx:int(255*p{$3,$4}.g)]" info:; }
# one row near the top of the pill, away from the digits: the charged part stops on one column
for n in phone lap; do
	IFS=, read -r x y w h <<<"$(sed -n "s/^62-Discharging .*box=\([0-9,]*\).*/\1/p" "$W/$n.txt")"
	ok "$n: 62 white then grey, one edge" 'a=$(px $n 62-Discharging $((x+w*40/100)) $((y+h/8))); b=$(px $n 62-Discharging $((x+w*80/100)) $((y+h/8))); [ "$a" = "245 245" ] && [ "$b" = "112 112" ]'
	# the fill reaches the pill's bottom row: a clip rounded short leaves a grey line under the white
	ok "$n: no grey line under the fill" 'c=$(px $n 62-Discharging $((x+w*30/100)) $((y+h-2))); [ "$c" = "245 245" ]'
	ok "$n: 15 is the accent, 16 is white" '[ "$(px $n 15-Discharging $((x+w*11/100)) $((y+h/2)))" = "215 25" ] && [ "$(px $n 16-Discharging $((x+w*11/100)) $((y+h/2)))" = "245 245" ]'
done
ok "no core files" '[ -z "$(comp_cores)" ]'
echo; echo "$FAILS failed"; rm -rf "$W"; [ "$FAILS" = 0 ]
