#!/bin/bash
# run-on-laptop.sh: what apps inside the window get as home, with nothing started (dbus-run-session is a stub).
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-env.XXXXXX")
mkdir -p "$W/bin" "$W/copy"
cp -a "$SRC"/. "$W/copy"/ 2>/dev/null
printf '#!/bin/sh\nenv >"%s/env"\n' "$W" >"$W/bin/dbus-run-session"
for t in make tesseract; do printf '#!/bin/sh\nexit 0\n' >"$W/bin/$t"; done
chmod +x "$W/bin"/*
REAL=/home/someone-real
env -i HOME="$REAL" PATH="$W/bin:/usr/bin:/bin" WAYLAND_DISPLAY=stub-not-a-socket PHONE_LAPTOP_DIR="$W/base" sh "$W/copy/run-on-laptop.sh" >"$W/out" 2>&1
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
ok "apps inside get a private home" 'grep -qx "HOME=$W/base/home" "$W/env" && [ -d "$W/base/home" ]'
ok "a browser cannot reach the real profile through XDG either" '! grep -E "^XDG_(CONFIG|DATA|CACHE|STATE)_HOME=" "$W/env" | grep -q "$REAL"'
ok "the app menu still finds the real local apps" 'grep -q "^XDG_DATA_DIRS=$REAL/.local/share:" "$W/env"'
rm -rf "$W"
[ "$fails" = 0 ] && echo "all passed"
[ "$fails" = 0 ]
