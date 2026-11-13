#!/bin/bash
# The mobile data icon from the fake tools, at phone and laptop scale. SHOTS=DIR keeps the contact sheet.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-cell.XXXXXX")
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

mkdir -p "$W/fakebin" "$W/fake"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf; do ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/$t"; done
S=$W/sys; mkdir -p "$S/power_supply/BAT0"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
cat >"$W/l.sh" <<EOF
echo \$1 >"$W/fake/celltech"; echo \$2 >"$W/fake/data"; echo \$3 >"$W/fake/cellsig"
EOF
STATES="5gnr:connected:90 lte:connected:68 umts:connected:40 edge:connected:15 lte:disconnected:68 none:connected:68"
scene() { local n=$1 mode=$2 scale=$3; shift 3
	mkdir -p "$W/cfg/phonegluewc" "$W/$n"; rm -f "$W/fakebin/gone"
	ln -sf "$SRC/laptop/fake-tool" "$W/fakebin/mmcli"
	printf 'remember_layout = false\noutput = * mode=%s scale=%s\n' "$mode" "$scale" >"$W/cfg/phonegluewc/config.conf"
	{ echo "w 3000"
	for st in $STATES; do IFS=: read -r a b c <<<"$st"
		echo "x sh $W/l.sh $a $b $c"; echo "d 0 0.5 0.01"; echo f; echo "u 0"; echo f; echo "w 1400"
		echo "x $SRC/tests/wshot $W/$n/$a-$b.ppm"; echo "w 400"
	done
	echo "x rm $W/fakebin/mmcli"; echo "d 0 0.5 0.01"; echo f; echo "u 0"; echo f; echo "w 1400"
	echo "x $SRC/tests/wshot $W/$n/nomodem.ppm"; echo "w 400"
	echo "p done"; } >"$W/script"
	SANDBOX_PATH="$W/fakebin:$BUILD"
	comp_start FAKE_STATE="$W/fake" PHONE_SYS_DIR="$S" PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script" "$@"
	comp_wait 600
	comp_stop
	mv "$W/gw.log" "$W/$n.log"
}
scene phone 1080x2400 2.75
scene lap 450x1000 1.15 PHONE_NO_HOLE=1

# left edge of the right group: the rightmost run of things in the bar, gaps up to $3 pixels allowed
left() { python3 - "$1" "$2" "$3" <<'P'
import sys
d = open(sys.argv[1], 'rb').read(); bar = int(sys.argv[2]); gap = int(sys.argv[3])
parts = d.split(b'\n', 3)
w = int(parts[1].split()[0]) if len(parts[1].split()) > 1 else int(parts[1])
px = parts[-1] if len(parts[1].split()) > 1 else d.split(b'\n', 4)[-1]
br = lambda x: any(max(px[(y * w + x) * 3: (y * w + x) * 3 + 3]) > 45 for y in range(bar))
x = w - 1
while not br(x): x -= 1
l = x; miss = 0
while x > 0 and miss <= gap:
    x -= 1
    if br(x): l = x; miss = 0
    else: miss += 1
print(l)
P
}
for n in phone:99:50:6 lap:42:21:12; do IFS=: read -r n bar gap z <<<"$n"
	files=""
	for f in 5gnr-connected lte-connected umts-connected edge-connected lte-disconnected none-connected nomodem; do
		l=$(left "$W/$n/$f.ppm" "$bar" "$gap"); echo "$n $f left=$l"; eval "L_${n}_${f//-/_}=$l"
		wd=$(identify -format %w "$W/$n/$f.ppm")
		magick "$W/$n/$f.ppm" -crop "$((wd-wd/2))x$bar+$((wd/2))+0" +repage -filter point -resize "$((z*100/2))%" "$W/$n/$f.png"; files="$files $W/$n/$f.png"
	done
	magick $files -background '#303030' -splice 0x4 -append "$SHOTS/cell-$n.png"
	eval "lte=\$L_${n}_lte_connected none=\$L_${n}_none_connected off=\$L_${n}_lte_disconnected no=\$L_${n}_nomodem"
	ok "$n: the type takes room, unknown type does not" '[ "$lte" -lt "$none" ]'
	ok "$n: off keeps the same room" '[ "$off" = "$lte" ]'
	ok "$n: no modem hides the icon" '[ "$no" -gt "$none" ]'
	ok "$n: off looks different from on" '! cmp -s "$W/$n/lte-connected.ppm" "$W/$n/lte-disconnected.ppm"'
done
magick "$SHOTS/cell-phone.png" "$SHOTS/cell-lap.png" -background '#303030' +append "$SHOTS/cell-sheet.png"
ok "no QML error" '! grep -hE "StatusBar.*(rror|Unable)|TypeError|ReferenceError" "$W/phone.log" "$W/lap.log" | grep -q .'
ok "no core files" '[ -z "$(comp_cores)" ]'
echo; echo "$FAILS failed"; rm -rf "$W"; [ "$FAILS" = 0 ]
