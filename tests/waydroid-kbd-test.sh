#!/bin/bash
# Waydroid has no text-input: with a waydroid window in front the keys go to the IME bridge socket, its show/hide requests drive the keyboard.
# It overlays Android without an exclusive zone and reports its height, so Android insets the app like a phone.
# Headless; a fake IME listens where the Android one would.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-wdkbd.XXXXXX")
. "$SRC/tests/sandbox.sh"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
XS=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $XS "$BUILD/touchlog-xdg-protocol.h"
wayland-scanner private-code $XS "$BUILD/touchlog-xdg-protocol.c"
cc -w -I"$BUILD" -o "$W/touchlog" "$SRC/tests/touchlog.c" "$BUILD/touchlog-xdg-protocol.c" -lwayland-client || exit 1
mkdir -p "$W/cfg/phonegluewc" "$W/cfg/phonekbd" "$W/br"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$W/cfg/phonegluewc/config.conf"
printf '%s\n' "autocap = off" "autocorrect = off" "predict = off" >"$W/cfg/phonekbd/config"
printf 'TOUCHLOG_TITLE=$1 exec "%s/touchlog" >/dev/null 2>&1\n' "$W" >"$W/tl.sh"
mkfifo "$W/br.in"
# the fake IME: logs what arrives and, after >, what it sent, passes lines written to br.in back to the keyboard
python3 - "$W" <<'PY' &
import os, socket, sys, threading
W = sys.argv[1]
s = socket.socket(socket.AF_UNIX); s.bind(W + "/br/s"); s.listen(1)
c, _ = s.accept()
log = open(W + "/br.log", "wb", buffering=0)
def back():
    while True:
        with open(W + "/br.in") as f:
            for l in f:
                log.write(b">" + l.encode())
                c.sendall(l.encode())
threading.Thread(target=back, daemon=True).start()
while (d := c.recv(4096)):
    log.write(d)
PY
FAKE=$!
trap 'kill $FAKE 2>/dev/null; comp_kill; rm -rf "$W"' EXIT
python3 - "$W" "$SRC/tests/kbd-script.py" >"$W/script" <<'PY'
import sys
W, ks = sys.argv[1], sys.argv[2]
src = open(ks).read()
sys.argv = [ks, W]
exec(src[:src.index('FIELD = ("0.5", "0.84")')])
def ime(m): op(f"x sh -c 'echo {m} >{W}/br.in'"); op("w 900")
op("w 2500"); op(f"x sh {W}/tl.sh waydroid.org.test"); op("w 1500")
ime("s1"); op("g up")
typ("qa"); tap("shift"); tap("w"); tap("space"); tap("bksp", wait=200); tap("enter", wait=300)
ime("x"); op("g gone")
op(f"x sh {W}/tl.sh other"); op("w 1500")
ime("s1"); op("g native")
op("x true"); op("w 300")
print("\n".join(out))
PY
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$BUILD:$SRC/keyboard"
fails=0
ok() { if eval "$2"; then echo "ok $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL= PHONEKBD_DATA="$SRC/keyboard/data" PHONEKBD_BRIDGE="$W/br" PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 600
comp_stop
L=$W/gw.log
kbd() { grep -q "^GEOM $1 layer ns=phone-keyboard " "$L"; }
# what the Android field would hold after these messages
field=$(python3 - "$W/br.log" <<'PY'
import sys
t = ""
for l in open(sys.argv[1], encoding="utf-8").read().split("\n"):
    a = l[1:].replace("\\n", "\n").replace("\\\\", "\\")
    if l[:1] == "t": t += a
    elif l[:1] == "r":
        n, s = a.split(" ", 1); b = t.encode()[:len(t.encode()) - int(n)]; t = b.decode() + s
    elif l[:1] == "k":
        code = a.split()[0]
        if code == "14": t = t[:-1]
        elif code == "28": t += "\n"
print(t.replace("\n", "<NL>"))
PY
)
echo "  bridge got: $(tr '\n' '|' <"$W/br.log")"
ok "a show request from Android raises the keyboard"     'kbd up'
ok "over Android it takes no space, so Waydroid is not resized" 'grep -q "^GEOM up layer ns=phone-keyboard .* excl=0$" "$L"'
ok "Android is told how tall it is, and when it goes"      'grep -qE "^h[1-9][0-9]* [1-9][0-9]*$" "$W/br.log" && grep -qE "^h0 " "$W/br.log"'
ok "no zero height between the show request and the keyboard" '! sed -n "/^>s1/,/^h[1-9]/p" "$W/br.log" | grep -q "^h0 "'
ok "letters, shift, space, backspace, enter reach the field" '[ "$field" = "qaW<NL>" ]'
ok "backspace and enter go as keys"                       'grep -qx "k14 0" "$W/br.log" && grep -qx "k28 0" "$W/br.log"'
ok "a hide request takes it down"                         '! kbd gone'
ok "with a native window in front Android cannot raise it" '! kbd native'
[ "$fails" = 0 ] && echo "all passed" || { echo "failed: $fails"; exit 1; }
