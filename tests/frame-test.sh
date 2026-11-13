#!/bin/bash
# Where windows land: geometry the compositor reports, checked against rows of real pixels.
# Headless, neutral clients only. SHOTS=DIR keeps the captures as PNG.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-frame.XXXXXX")
SANDBOX_EXTRA="timeout kill"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
mkdir -p "$W/cfg/phonegluewc"
cat >"$W/tl.sh" <<TL
echo \$\$ >"$W/pid-\$1"
TOUCHLOG_TITLE=\$1 exec "$W/touchlog" >/dev/null
TL
cat >"$W/field.sh" <<FIELD
[ "\${1:-}" = fs ] && export FIELD_FS=1
QT_QUICK_BACKEND=software exec qs -p "$SRC/tests/frame-field" >"$W/field.log" 2>&1
FIELD
# one app with a black icon: it must stay visible on the black screen
mkdir -p "$W/data/applications"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="30" fill="#000"/></svg>\n' >"$W/icon-black.svg"
printf '[Desktop Entry]\nType=Application\nName=Goes away\nExec=true\nIcon=%s\n' "$W/icon-black.svg" >"$W/data/applications/goes.desktop"
# one that draws nothing: its fill points at a pattern that does not exist
printf '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="url(#nope)" opacity="0"/></svg>\n' >"$W/icon-broken.svg"
printf '[Desktop Entry]\nType=Application\nName=Stays\nExec=true\nIcon=%s\n' "$W/icon-broken.svg" >"$W/data/applications/stays.desktop"
# and a normal one, which keeps its picture
printf '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="30" fill="#ff8800"/></svg>\n' >"$W/icon-orange.svg"
printf '[Desktop Entry]\nType=Application\nName=Orange\nExec=true\nIcon=%s\n' "$W/icon-orange.svg" >"$W/data/applications/orange.desktop"
# what the settings app does: both files replaced in one rename, with the shell running
python3 -c 'import sys;from PIL import Image;Image.new("RGB",(108,240),(0,90,200)).save(sys.argv[1])' "$W/wall.png"
cat >"$W/conf.sh" <<CONF
printf 'accent=#00ff00\nwallpaper=$W/wall.png\n' >"$W/cfg/phonegluewc/phone.tmp"
mv "$W/cfg/phonegluewc/phone.tmp" "$W/cfg/phonegluewc/phone.conf"
printf 'wallpaper=$W/wall.png\n' >"$W/cfg/phonegluewc/login.tmp"
mv "$W/cfg/phonegluewc/login.tmp" "$W/cfg/phonegluewc/login.conf"
CONF
printf 'printf "accent=#00ff00\\n" >"%s.tmp"; mv "%s.tmp" "%s"\n' "$W/cfg/phonegluewc/phone.conf" "$W/cfg/phonegluewc/phone.conf" "$W/cfg/phonegluewc/phone.conf" >"$W/confoff.sh"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
fails=0

# run NAME MODE|FIELDARG SIZE SCALE TRANSFORM SHELL CHECK...
run() {
	name=$1; mode=$2; size=$3; scale=$4; tf=$5; shell=$6; shift 6
	[ -z "${ONLY:-}" ] || [ "$ONLY" = "$name" ] || return 0
	cat >"$W/rot.sh" <<ROT
printf 'remember_layout = false\noutput = * mode=$size scale=$scale transform=%s\n' "\$(case \$1 in 0) echo normal;; *) echo \$1;; esac)" >"$W/cfg/phonegluewc/config.conf"
ROT
	sh "$W/rot.sh" "$tf"
	python3 "$SRC/tests/frame-script.py" "$W" $mode >"$W/script" || exit 1
	rm -f "$W"/*.ppm
	comp_start ${RUN_ENV:-} QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$shell" PHONEKBD_DATA="$SRC/keyboard/data" PHONEGLUEWC_FAKETOUCH="$W/script"
	comp_wait 1500
	comp_stop
	sed -n 's/^GEOM /GEOM /p' "$W/gw.log" >"$W/$name.geom"
	cp "$W/$name.geom" "$SHOTS/"
	[ -z "${ONLY:-}" ] || cp "$W/gw.log" "$SHOTS/$name.log"
	echo "-- $name"
	if grep -E 'config:[0-9]+:' "$W/gw.log" | head -3 | grep .; then echo "FAIL $name: config errors"; fails=$((fails + 1)); fi
	[ ! -s "$W/field.log" ] || grep -iE "error|\.qml:" "$W/field.log" | head -3
	python3 "$SRC/tests/frame-check.py" "$W/$name.geom" "$W" "$@" || fails=$((fails + 1))
	for p in "$W"/*.ppm; do
		[ -e "$p" ] || continue
		b=${p##*/}
		python3 -c 'import sys;from PIL import Image;Image.open(sys.argv[1]).save(sys.argv[2])' "$p" "$SHOTS/$name-${b%.ppm}.png" 2>/dev/null
	done
}
BAR=$SRC/tests/frame-shell

MAIN="single:one overview:overview tiled:tile2:one:two tiled:tile3:one:two:three single:alone:one full:full:full single:unfull:full"
run phone main 1080x2400 2.75 0 "$BAR" $MAIN
run laptop main 450x1000 1.15 0 "$BAR" $MAIN

run field field 1080x2400 2.75 0 "$BAR" field:typing:field fieldgone:typed:field
run fullfield "field fs" 1080x2400 2.75 0 "$BAR" field:typing:field full:typed:field
run landscape landscape 1080x2400 2.75 90 "$BAR" landscape:one single:one overview:overview field:typing:field
run rotate rotate 1080x2400 2.75 0 "$BAR" portrait:portrait single:portrait landscape:rotated single:rotated overview:rotated-overview landscape:rotated-back single:rotated-back portrait:upright single:upright
run realshell main 1080x2400 2.75 0 "$SRC/shell" single:one overview:overview single:alone:one
CARDS="homeclock:home homeclock:homeback cards:cards noclock:emptycard ws:emptyup:0 label:cards letter:cards letter:cards2 ws:uplocked:0 shown:upback:stays:cards2 shown:slowswipe:goes:cards gone:closed:goes flung:flung:stays:cards2 shown:back:stays:cards2 homeclock:pillhome ws:pillhome:1"
run cards cards 1080x2400 2.75 0 "$SRC/shell" $CARDS
run laptopcards cards 450x1000 1.15 0 "$SRC/shell" $CARDS

run conf conf 1080x2400 2.75 0 "$SRC/shell" conf:confhome conf:confcard confoff:confoff conf:conflock

run kbcards kbcards 1080x2400 2.75 0 "$SRC/shell" haskb:kbup cardeq:kbov:nokb cardeq:kbovlater:nokb nokb:kbovlater haskb:kbback
run laptopkb kbcards 450x1000 1.15 0 "$SRC/shell" haskb:kbup cardeq:kbov:nokb cardeq:kbovlater:nokb nokb:kbovlater haskb:kbback
RUN_ENV=PHONEGLUEWC_MOUSE_FINGER=1 run reach reach 450x1000 1.15 0 "$SRC/shell" ws:r0:0 ws:r1:1 ws:r1drag:1 cardeq:rubberback:r1 rubber:rubber:r1 ws:r1flick:1 ws:r1msg:1 ws:r0msg:0 ws:nowrapdrag:0 ws:nowraptap:0 ws:r1four:1 ws:r1fourlimit:1 ws:r0four:0 ws:r0fournowrap:0 ws:two:1 ws:r2:2 ws:r2limit:2 ws:r3:0 ws:r3limit:0 ws:hole:1 ws:far:0 ws:farback:0 ws:gonefar:0
RUN_ENV=PHONEGLUEWC_MOUSE_FINGER=1 run stuck stuck 450x1000 1.15 0 "$SRC/shell" ws:two-on-1:1 count:two-on-1:1:2 ws:quickswipe:2 ws:quickback:1 ws:slowswipe:2 ws:slowback:1 count:slowback:1:2 ws:crawl:2 count:crawl:1:2 ws:crawlback:1 ws:gentle:2 count:gentle:1:2 ws:gentleback:1 count:gentleback:1:2 ws:wiggle:2 ws:wiggleback:1 ws:tapped:1 ws:fourleft:2 ws:fourright:1 ws:fourhome:0 count:fourhome:1:2
RUN_ENV=
run dialog dialog 450x1000 1.15 0 "$BAR" centred:dlg:dlg
run wins wins 1080x2400 2.75 0 "$BAR" windows:w1:one windows:w2:one:late windows:w3:one:late=renamed windows:w4:late=renamed windows:w5

[ "$fails" = 0 ] && echo "all frame checks passed"
exit "$fails"
