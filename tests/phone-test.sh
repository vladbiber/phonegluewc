#!/bin/bash
# The whole shell at phone size, headless, driven by a fake touchscreen. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
REALHOME=$HOME
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-phone.XXXXXX")
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1

wayland-scanner client-header "$SRC/tests/input-method-unstable-v2.xml" "$BUILD/input-method-protocol.h"
wayland-scanner private-code "$SRC/tests/input-method-unstable-v2.xml" "$BUILD/input-method-protocol.c"
cc -w -I"$BUILD" -o "$W/imlog" "$SRC/tests/imlog.c" "$BUILD/input-method-protocol.c" -lwayland-client || exit 1

mkdir -p "$W/cfg/phonegluewc" "$W/state/phonegluewc" "$W/data/applications"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' > "$W/cfg/phonegluewc/config.conf"
printf 'phone.desktop\nmessages.desktop\ncamera.desktop\nbrowser.desktop\n' > "$W/cfg/phonegluewc/pinned-apps"
for n in Browser Calculator Calendar Camera Clock Contacts Files Gallery Maps Messages Music Notes Phone Podcasts Recorder Settings Terminal Weather; do
	id=$(echo "$n" | tr A-Z a-z)
	# each its own app id, or a tap on one goes to the window of another
	exe="env TOUCHLOG_TITLE=$id $W/touchlog"
	case "$n" in
	Phone) icon=Icon=testphone ;;
	Messages) icon=Icon=$W/icon-messages.svg ;;
	Browser) icon=Icon=testbrowser ;;
	*) icon= ;;
	esac
	printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n%s\n' "$n" "$exe" "$icon" > "$W/data/applications/$id.desktop"
done
# one icon from each place an app can name it; Camera has none and gets its letter
svg() { printf '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" rx="12" fill="%s"/></svg>\n' "$1"; }
mkdir -p "$W/data/icons/hicolor/scalable/apps" "$W/data/pixmaps"
svg '#2060e0' >"$W/data/icons/hicolor/scalable/apps/testphone.svg"
svg '#20c060' >"$W/icon-messages.svg"
svg '#e0a020' >"$W/data/pixmaps/testbrowser.svg"

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-700}"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
# bottom edge drag up to fraction $1
pillup() { echo "d 0 0.5 0.995"; echo f; for s in 1 2 3 4 5 6 7 8; do echo "m 0 0.5 $(python3 -c "print(0.995-$1*$s/8)")"; echo f; done; echo "w 200"; }
pillopen() { pillup 0.5; echo "u 0"; echo f; echo "w 700"; }
MORE="0.887 0.92"; FIRST="0.148 0.22"; THIRD="0.617 0.379"
# idle memory of the compositor and the shell, without and with the menu loaded
cat >"$W/rss.sh" <<EOF
p=\$(cat "$W/pid"); q=\$(pgrep -P \$p -x qs)
echo "\$1 phonegluewc=\$(awk '/VmRSS/{print \$2}' /proc/\$p/status) qs=\$(awk '/VmRSS/{print \$2}' /proc/\$q/status) kB" >>"$W/rss"
EOF
rss() { echo "w 1500"; echo "x sh $W/rss.sh $1"; echo "w 300"; }
{ echo "w 2500"; echo "x sh $SRC/tests/sandbox-probe.sh >$W/probe.txt 2>&1"; echo "p home"; shot 1-home; rss never-opened
  t $MORE; echo "p menu"; shot 2-menu; rss menu-open; t 0.9 0.094 1000; echo "p menu-closed"; rss menu-closed; t $MORE
  t $FIRST; echo "w 800"; echo "p first"; shot 3-app
  pillup 0.2; echo "p midway"; shot 4-midway; echo "u 0"; echo f; echo "w 700"; echo "p settled"; shot 5-overview
  t $MORE; shot 6-menu-used; t $THIRD; echo "w 800"; echo "p second"
  pillopen; echo "p ov2"; shot 7-two
  t 0.02 0.4; echo "p dot"; shot 8-neighbour; pillopen; t 0.5 0.5 1000; echo "p picked"
  pillopen; t $MORE; echo "p menu3"; t 0.5 0.995; echo "p pillclosed"
  shot 9-before-drop; echo "d 0 0.5 0.3"; echo f; echo "w 400"; echo "m 0 0.7 0.3"; echo f; echo "m 0 0.97 0.3"; echo f; echo "p carrying"; shot 10-carrying
  echo "u 0"; echo f; echo "w 700"; echo "p dropped"; shot 11-tiled
  t 0.561 0.842; t 0.5 0.5 1000; echo "p tiled"; shot 12-tiled-live
  pillopen; echo "x exec $W/imlog cam >$W/im.log 2>&1"; echo "w 600"; t $MORE; t 0.35 0.947 1000; echo "p searching"; shot 13-search
  t 0.148 0.178; echo "w 800"; echo "p searched"
  echo "x phonegluewc-msg workspace 3"; echo "w 800"; t 0.106 0.92; echo "w 800"; echo "p pinned"; echo "x true"; echo "w 300"; } > "$W/script"

COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD"
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$SRC/shell" PHONEGLUEWC_KEYBOARD="${PHONEGLUEWC_KEYBOARD-}" \
	PHONEGLUEWC_FAKETOUCH="$W/script" PHONE_WRAP="${PHONE_WRAP:-}"
comp_wait 500
USAGE=$(cat "$W/state/phonegluewc/app-usage.json" 2>/dev/null)
comp_stop
[ -n "${TOUCH_VERBOSE:-}" ] && cat "$W/im.log"
[ -n "${PHONE_LOG:-}" ] && cp "$W/gw.log" "$PHONE_LOG"
[ -n "${TOUCH_VERBOSE:-}" ] && grep '^FT' "$W/gw.log"
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }
state() { grep "^FT $1 " "$W/gw.log" | grep -q " $2\( \|$\)"; }
ok "the sandbox holds no real path"    '! grep -E "^(HOME|PATH|TMPDIR|XDG_[A-Z_]*|DBUS_[A-Z_]*)=" "$W/probe.txt" | grep -qF "$REALHOME"'
ok "the bus can activate nothing"     '[ "$(sed -n "/== activatable/,/== launchers/p" "$W/probe.txt" | grep -c "^\"")" = 1 ]'
ok "no launcher or power tool on PATH" '[ -z "$(sed -n "/== launchers/,/== runtime/p" "$W/probe.txt" | grep "^/")" ]'
ok "the compositor did not take wayland-0" 'grep -qx wayland-1 "$W/probe.txt" && ! grep -qx wayland-0 "$W/probe.txt"'
ok "a theme icon, a path and a pixmap show in the dock" '[ "$(python3 -I "$SRC/tests/colors.py" "$W/1-home.ppm" 2060e0 20c060 e0a020)" = "1 1 1" ]'
ok "empty workspace shows the tray"  'state home tray=1 && state home menu=0'
ok "more apps opens the menu"        'state menu menu=1'
ok "app from the menu closes it"     'state first menu=0 && state first counts=100000000'
ok "a full screen app hides the tray" 'state first tray=0'
ok "pill drag follows, tray with it" 'state midway tray=1 && state midway gesture=3'
ok "partway settles open"            'state settled overview=1 && state settled gesture=0'
ok "next app gets a new workspace"   'state second counts=110000000 && state second ws=1'
ok "a tap on the neighbour card goes there" 'state dot ws=0 && state dot overview=0'
ok "card tap enters the workspace"   'state picked overview=0 && state picked ws=0'
ok "the pill closes the menu"        'state menu3 menu=1 && state pillclosed menu=0'
ok "dropping a window tiles it"      'state dropped counts=020000000 || state dropped counts=200000000'
ok "the keyboard's text reaches the search field" 'grep -q committed "$W/im.log" && state searching menu=1'
ok "search finds the app and opens it" 'state searched menu=0 && echo "$USAGE" | grep -q camera'
ok "the close button closes the menu" 'state menu-closed menu=0'
ok "the seat always offers a keyboard" 'state home caps=7'
ok "the first pinned app is first in the tray" 'echo "$USAGE" | grep -q phone'
ok "usage counts rise"               'echo "$USAGE" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(sum(d.values())!=4 or d.get(\"browser\")!=1)"'
echo "usage: $USAGE"
cat "$W/rss" 2>/dev/null
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
