#!/bin/bash
# Every widget in every look on the home and the lock, headless, weather from a local fake Open-Meteo. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-widgets.XXXXXX")
SANDBOX_EXTRA="timeout date mktemp readlink sync head magick df"
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1 || { echo "FAIL wshot"; exit 1; }

C=$W/cfg/phonegluewc; ST=$W/state/phonegluewc
mkdir -p "$C" "$ST" "$W/home/Pictures" "$W/stubs" "$W/data/applications"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$C/config.conf"
printf 'user=sampleuser\nwallpaper=%s\n' "$W/home/Pictures/lock.png" >"$C/login.conf"
magick -size 1080x2400 gradient:'#2a5a8a-#7a3a5a' "$W/home/Pictures/lock.png"
magick -size 1080x2400 gradient:'#203080-#000000' "$W/home/Pictures/blue.png"
magick -size 600x600 plasma:fractal -seed 7 "$W/home/Pictures/photo.png"
printf '[Desktop Entry]\nType=Application\nName=Sample\nExec=true\n' >"$W/data/applications/sample.desktop"
S=$W/sys; mkdir -p "$S/power_supply/BAT0"
echo Battery >"$S/power_supply/BAT0/type"; echo 62 >"$S/power_supply/BAT0/capacity"; echo Discharging >"$S/power_supply/BAT0/status"
L=$W/calls; : >"$L"
for p in phonesettings systemctl loginctl reboot poweroff shutdown halt suspend rtcwake nmcli wpctl bluetoothctl rfkill brightnessctl; do
	printf '#!/bin/sh\necho "%s $*" >>%s\n' "$p" "$L" >"$W/stubs/$p"; chmod +x "$W/stubs/$p"
done

# the fake Open-Meteo: one known city, anything else is not found
cat >"$W/meteo.py" <<'PY'
import json, sys, http.server, urllib.parse
log = open(sys.argv[2], "a", buffering=1)
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        log.write(self.path + "\n")
        if u.path == "/v1/search":
            r = {"results": [{"name": "Iasi", "latitude": 47.16, "longitude": 27.59}]} if q.get("name") == ["Iasi"] else {}
        elif u.path == "/v1/forecast":
            r = {"current": {"temperature_2m": 17.4, "weather_code": 2},
                 "daily": {"time": ["2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15", "2026-11-16"],
                           "weather_code": [2, 61, 3, 0, 71], "temperature_2m_max": [18.2, 14.9, 12, 15.5, 3],
                           "temperature_2m_min": [8.1, 7, 5.4, 4, -2.6]}}
        else:
            self.send_response(404); self.end_headers(); return
        b = json.dumps(r).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$W/meteo.py" "$W/port" "$W/meteo.log" & MPID=$!
trap 'kill $MPID 2>/dev/null; comp_kill; rm -rf "$W"' EXIT
for i in $(seq 50); do [ -s "$W/port" ] && break; sleep 0.1; done
URL=http://127.0.0.1:$(cat "$W/port")

# one screens file per page: every type and size packed into the grid, per look; the lock keeps 4 rows under its clock
python3 - "$W" "$W/home/Pictures/photo.png" <<'PY'
import json, sys
W, photo = sys.argv[1], sys.argv[2]
home = {"clock": [[2,2],[2,4]], "analog": [[2,4],[1,2]], "date": [[2,4],[1,2]], "world": [[2,4],[2,2]],
    "battery": [[2,1],[1,1],[1,2],[2,2]], "storage": [[2,2],[1,2]], "wifi": [[2,2],[1,2]], "bluetooth": [[2,2],[1,2]],
    "torch": [[2,2],[1,2]], "airplane": [[2,2],[1,2]], "rotate": [[2,2],[1,2]], "dark": [[2,2],[1,2]],
    "timer": [[2,2],[1,2]], "stopwatch": [[2,2],[1,2]], "music": [[4,2],[2,4],[2,2]],
    "weather": [[2,4],[4,2],[2,2],[1,2]], "note": [[2,2],[4,2]], "photo": [[2,4],[1,2]]}
lock = {k: home[k] for k in ["analog", "world", "battery", "weather", "timer", "stopwatch", "torch"]}
extra = {"weather": {"city": "Iasi"}, "world": {"offset": 540}, "timer": {"minutes": 25}, "note": {"text": "Buy bread"}, "photo": {"file": photo}}
def pack(items, rows):
    pages, cur, grid = [], [], set()
    for t, (w, h) in items:
        spot = next(((c, r) for r in range(rows - h + 1) for c in range(4 - w + 1)
            if not any((c + x, r + y) in grid for x in range(w) for y in range(h))), None)
        if spot is None:
            pages.append(cur); cur, grid = [], set()
            spot = (0, 0)
        c, r = spot
        grid |= {(c + x, r + y) for x in range(w) for y in range(h)}
        cur.append(dict(type=t, col=c, row=r, w=w, h=h, **extra.get(t, {})))
    return pages + [cur]
names = []
for style in ["nothing-dark", "nothing-light", "apple"]:
    for kind, cat, rows in [("home", home, 15), ("lock", lock, 4)]:
        items = sorted(((t, s) for t in cat for s in cat[t]), key=lambda i: -i[1][0] * i[1][1])
        for n, ws in enumerate(pack(items, rows)):
            for w in ws:
                w["style"] = style
            doc = {"version": 1, "home": {"active": 0, "screens": [{"wallpaper": "", "widgets": ws if kind == "home" else []}]},
                   "lock": {"active": 0, "screens": [{"wallpaper": "", "widgets": ws if kind == "lock" else []}]}}
            name = "%s-%s-%d" % (kind, style, n + 1)
            json.dump(doc, open("%s/%s.json" % (W, name), "w"))
            names.append(name)
# the format before widget looks: a dot clock, a date line, a battery, music, a note and an app; the lock had clock and date
old = {"version": 1, "home": {"active": 0, "screens": [{"wallpaper": "", "widgets": [
    {"type": "clock", "col": 0, "row": 0, "w": 4, "h": 2}, {"type": "date", "col": 0, "row": 2, "w": 4, "h": 1},
    {"type": "battery", "col": 0, "row": 3, "w": 2, "h": 1}, {"type": "music", "col": 0, "row": 4, "w": 4, "h": 2},
    {"type": "note", "col": 0, "row": 6, "w": 2, "h": 2, "text": "Old note"}, {"type": "app", "col": 3, "row": 6, "w": 1, "h": 2, "app": "sample"}]}]},
    "lock": {"active": 0, "screens": [{"wallpaper": "", "widgets": [
    {"type": "clock", "col": 0, "row": 0, "w": 4, "h": 2}, {"type": "date", "col": 0, "row": 2, "w": 4, "h": 1},
    {"type": "battery", "col": 0, "row": 0, "w": 2, "h": 1}]}]}}
json.dump(old, open(W + "/old.json", "w"))
json.dump({"version": 1, "home": {"active": 0, "screens": [{"wallpaper": "", "widgets": []}]},
    "lock": {"active": 0, "screens": [{"wallpaper": "", "widgets": []}]}}, open(W + "/empty.json", "w"))
open(W + "/pages", "w").write("\n".join(names) + "\n")
PY

t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-600}"; }
hold() { echo "d 0 $1 $2"; echo f; echo "w 1100"; echo "u 0"; echo f; echo "w 700"; }
shot() { echo "x $SRC/tests/wshot $W/$1.ppm"; echo "w 400"; }
use() { echo "x cp $W/$1.json $C/screens.json"; echo "w ${2:-1200}"; }
save() { echo "x cp $C/screens.json $W/$1.json.out"; echo "w 150"; }

COMP=$BUILD/phonegluewc
run() {
	SANDBOX_PATH="$BUILD:$W/stubs"
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$BUILD/shell" PHONEGLUEWC_FAKETOUCH="$W/script" PHONE_SYS_DIR="$S" \
		PHONE_WEATHER_GEO="$URL" PHONE_WEATHER_API="$URL"
	comp_wait 1800
	comp_stop
	mv "$W/gw.log" "$W/$1.log"
}

# home pages, the old file, then the picker: open, a tap adds, a hold drags one out
{ echo "w 3000"; use empty; shot home-empty
  for p in $(grep ^home "$W/pages"); do use "$p" 2500; shot "$p"; done
  use old; shot old-home
  echo "x rm -f $C/screens.json"; echo "w 1200"
  hold 0.5 0.5; t 0.402 0.78 900; t 0.5 0.9 900; shot picker
  t 0.206 0.53 900; save tap; shot picker-added
  t 0.5 0.9 900; echo "d 0 0.62 0.53"; echo f; echo "w 1200"
  python3 -c "
for s in range(1,11): print('m 0 %.3f %.3f\nf\nw 40' % (0.62-0.12*s/10, 0.53-0.30*s/10))"
  echo "w 200"; echo "u 0"; echo f; echo "w 900"; save drag; shot picker-dragged
} >"$W/script"
run home

# the lock: every lock page, then the old file there
{ echo "w 3000"; echo "x qs ipc -p $BUILD/shell call lock lock"; echo "w 2000"; use empty; shot lock-empty
  for p in $(grep ^lock "$W/pages"); do use "$p" 2500; shot "$p"; done
  use old; shot old-lock
} >"$W/script"
run lock

fail=0
ok() { if (eval "$2"); then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
for f in "$W"/*.ppm; do magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done
cp "$W"/*.json.out "$SHOTS"/ 2>/dev/null
errs=$(cat "$W/home.log" "$W/lock.log" | grep -vE '^[0-9:.]+ \[' | grep -E 'ReferenceError|TypeError|is not a type|Unable to assign|Binding loop|Failed to load|rror|Invalid|Cannot|not defined|non-existent|Non-existent' | cut -c1-220 | sort -u)
ok "no QML errors" '[ -z "$errs" ]'
[ -z "$errs" ] || echo "$errs" | head -40
ok "weather asked only the fake server, by city" 'grep -q "^/v1/search?count=1&name=Iasi" "$W/meteo.log" && grep -q "^/v1/forecast?latitude=47.16" "$W/meteo.log"'
ok "weather kept its answer on disk" 'grep -q "\"temp\":17" "$ST/weather-iasi.json"'
pxdiff() { magick compare -metric AE -fuzz 4% "$W/$1.ppm" "$W/$2.ppm" null: 2>&1 | awk '{ printf "%d", $1 }'; }
ok "all $(wc -l <"$W/pages") pages captured" 'for p in $(cat "$W/pages"); do [ -s "$W/$p.ppm" ] || exit 1; done'
# a page draws its widgets: well apart from the same screen with none
ok "every page drew its widgets" 'for p in $(cat "$W/pages"); do [ "$(pxdiff $p ${p%%-*}-empty)" -gt 20000 ] || { echo "  $p"; exit 1; }; done'
ok "a tap in the picker added a clock in the picked look" 'python3 -c "
import json,sys; w=json.load(open(\"$W/tap.json.out\"))[\"home\"][\"screens\"][0][\"widgets\"]
sys.exit(0 if any(x[\"type\"]==\"clock\" and x[\"w\"]==2 and x[\"h\"]==2 and x.get(\"style\") for x in w) else 1)"'
ok "a drag from the picker added one more" 'python3 -c "
import json,sys; a=json.load(open(\"$W/tap.json.out\"))[\"home\"][\"screens\"][0][\"widgets\"]; b=json.load(open(\"$W/drag.json.out\"))[\"home\"][\"screens\"][0][\"widgets\"]
sys.exit(0 if len(b)==len(a)+1 else 1)"'
ok "old home file still draws" '[ "$(pxdiff old-home home-empty)" -gt 20000 ]'
ok "old lock file draws its battery" '[ "$(pxdiff old-lock lock-empty)" -gt 1000 ]'
ok "nothing toggled a radio or slept" '! grep -qE "rfkill (block|unblock)|nmcli radio|bluetoothctl power|suspend|poweroff" "$L"'
echo "shots: $SHOTS"
[ "$fail" = 0 ] && echo "all widget checks passed"
exit $fail
