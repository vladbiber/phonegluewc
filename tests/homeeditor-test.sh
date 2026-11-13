#!/bin/bash
# The saved screens editor, headless, on a private copy of the shell. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-home.XXXXXX")
SANDBOX_EXTRA="timeout date mktemp readlink sync head magick"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
# the log's tray= field reports the editor in this copy
sed -i 's/ft_layer("phone-tray")/ft_layer("phone-screens")/' "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }

C=$W/cfg/phonegluewc
mkdir -p "$C" "$W/state/phonegluewc" "$W/home/Pictures" "$W/stubs" "$W/data/applications"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$C/config.conf"
printf 'user=sampleuser\n' >"$C/login.conf"
magick -size 1080x2400 gradient:'#203080-#000000' "$W/home/Pictures/blue.png"
magick -size 1080x2400 gradient:'#205030-#000000' "$W/home/Pictures/green.png"
printf '[Desktop Entry]\nType=Application\nName=Sample\nExec=true\n' >"$W/data/applications/sample.desktop"
L=$W/calls; : >"$L"
for p in phonesettings systemctl loginctl reboot poweroff shutdown halt suspend rtcwake nmcli wpctl bluetoothctl rfkill brightnessctl; do
	printf '#!/bin/sh\necho "%s $*" >>%s\n' "$p" "$L" >"$W/stubs/$p"; chmod +x "$W/stubs/$p"
done

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-600}"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w 1100"; echo "u 0"; echo f; echo "w 700"; }
swipe() { echo "d 0 $1 $2"; echo f; python3 -c "
for s in range(1,9): print('m 0 %.3f %.3f\nf\nw 30' % ($1+($3-$1)*s/8, $2+($4-$2)*s/8))"; echo "w 100"; echo "u 0"; echo f; echo "w 700"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
save() { echo "x cp $C/screens.json $W/$1.json"; echo "w 150"; }
cat >"$W/rss.sh" <<EOF
p=\$(cat "$W/pid"); q=\$(pgrep -P \$p -x qs)
echo "\$1 pid=\$q qs=\$(awk '/VmRSS/{print \$2}' /proc/\$q/status 2>/dev/null) kB" >>"$W/rss"
EOF
rss() { echo "w 1500"; echo "x sh $W/rss.sh $1"; echo "w 300"; }

COMP=$BUILD/phonegluewc
run() {
	SANDBOX_PATH="$BUILD:$W/stubs"
	comp_start ${RUN_ENV:-} QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 600
	comp_stop
	mv "$W/gw.log" "$W/$1.log"
}

CARD=0.40; BTN=0.78
{ echo "w 3000"; rss idle; shot home
  hold 0.5 0.5; echo "p opened"; shot editor; rss open
  t 0.113 $BTN 900; shot wallpaper; t 0.5 0.2 900; shot wall-set; save w1
  t 0.307 $BTN 900; shot widgets; t 0.5 0.9 600; shot add; t 0.5 0.75 700; shot added; save w2
  t 0.1 0.08 700
  t 0.9 $CARD 900; shot plus; t 0.5 $CARD 900; shot new; save w3
  t 0.5 $CARD 900; echo "p closed"; shot switched; rss closed; } >"$W/script"
run first
grep -E 'ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|qml:.*rror|Cannot' "$W/first.log" | cut -c1-200 | sort -u | head -20
grep '^FT' "$W/first.log" | cut -c1-140
cat "$W/rss"
for f in "$W"/*.ppm; do magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
cp "$W"/w*.json "$SHOTS"/ 2>/dev/null
