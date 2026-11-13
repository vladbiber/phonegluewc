#!/bin/bash
# Real apps found on this machine against the tap rule: temp home, private bus, headless. Prints what each did.
# Usage: tests/realapps-test.sh [DESKTOP_ID...]
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-real.XXXXXX")
IDS=${*:-Alacritty foot org.pulseaudio.pavucontrol assistant qdbusviewer}
export SANDBOX_EXTRA="alacritty foot pavucontrol assistant6 qdbusviewer6"
for d in /usr/lib64/qt6/bin /usr/lib/qt6/bin /usr/lib64/qt5/bin; do [ -d "$d" ] && QTBIN=$d; done
. "$SRC/tests/sandbox.sh"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "build failed"; exit 1; }
mkdir -p "$W/cfg/phonegluewc" "$W/data/applications"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD${QTBIN:+:$QTBIN}"
gows() { echo "x phonegluewc-msg workspace $1"; echo "w 800"; }
tap() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w $3"; }
X=0.402; Y=0.929 # one pinned app and the menu button: the first of two slots
OX=0.342 # the same in the overview, with close all beside them
for id in $IDS; do
	f=/usr/share/applications/$id.desktop
	[ -f "$f" ] || { echo "$id: no such entry here"; continue; }
	cp "$f" "$W/data/applications/"
	echo "$id.desktop" >"$W/cfg/phonegluewc/pinned-apps"
	{ echo "w 2500"; tap $X $Y 6000; echo "g one"; gows 2; tap $X $Y 2500; echo "g two"
	  gows 2; echo "d 0 $X $Y"; echo f; echo "w 700"; echo "u 0"; echo f; echo "w 300"; tap $X 0.721 6000; echo "g three"
	  # dropping the icon on the first card: a new instance beside the window
	  gows 1; echo "d 0 0.5 0.995"; echo f; for i in 1 2 3 4 5 6 7 8; do echo "m 0 0.5 $(python3 -c "print(0.995-$i*0.05)")"; echo f; done; echo "w 250"; echo "u 0"; echo f; echo "w 700"
	  echo "d 0 $OX $Y"; echo f; echo "w 700"; echo "m 0 $OX 0.90"; echo f; echo "w 300"; echo "m 0 0.5 0.75"; echo f; echo "w 150"; echo "u 0"; echo f; echo "w 6000"; echo "g four"; echo "x true"; echo "w 300"; } >"$W/s"
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_KEYBOARD= PHONEGLUEWC_SHELL="$SRC/shell" PHONEGLUEWC_FAKETOUCH="$W/s"
	comp_wait 800
	cp "$W/gw.log" "$W/log"; comp_stop
	python3 - "$W/log" "$id" <<'PY'
import re,sys
log,id=sys.argv[1:]
r={}
for l in open(log,errors='replace'):
    m=re.match(r'GEOM (\S+) mon .* ws=(\d+)',l)
    if m: r.setdefault(m[1],{'ws':int(m[2]),'c':[]})
    m=re.match(r'GEOM (\S+) client title=(.*?) ws=(\d+) ',l)
    if m and m[1] in r: r[m[1]]['c'].append(int(m[3]))
print(id, ' '.join(f"{k}: on {v['ws']} windows on {v['c']}" for k,v in r.items()))
PY
	grep -m1 -E 'appid|app_id' "$W/log" | cut -c1-100
	rm -f "$W/data/applications/$id.desktop"
done
