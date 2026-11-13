#!/bin/bash
# Uninstall: the helper with fake flatpak, apk, waydroid and sudo that only record, and the
# dialog in a headless session. Nothing real can run: see the checks right below.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-rm.XXXXXX")
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc phonegluewc-msg ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }

REC=$W/rec; : >"$REC"
FAKE=$W/fake; mkdir -p "$FAKE"
for t in flatpak waydroid sudo apk; do
	cat >"$FAKE/$t" <<X
#!/bin/sh
# records only; a fake sudo records and does not run what it was given
[ -n "\${FAIL_TOOL:-}" ] && [ "\$FAIL_TOOL" = "$t" ] && { echo "first line" >&2; echo "$t said no" >&2; exit 1; }
printf '%s' "$t" >>"$REC"
# the dialog's cases: a failure, and a removal takes the sandbox's own desktop file away
case "\$*" in *org.t.Fail*) echo "org.t.Fail is busy" >&2; exit 1 ;; *org.t.Flat*) rm -f "$W/data/applications/tflat.desktop" ;; esac
for a in "\$@"; do printf ' [%s]' "\$a" >>"$REC"; done
echo >>"$REC"
if [ "$t" = sudo ]; then IFS= read -r line; printf 'stdin=%s\n' "\$line" >>"$REC"; fi
if [ "$t" = apk ]; then
	case "\$1 \${2:-}" in
	"info --who-owns") echo "\$3 is owned by \${FAKE_PKG:-hello-1.2.3-r0}" ;;
	"info -r") [ "\$3" = hello ] || [ "\$3" = needsme ] || exit 0; [ "\$3" = needsme ] && { echo "needsme-1.0-r0 is required by:"; echo "phonekbd-0.1-r0"; } ;;
	"info -e") [ -z "\${FAKE_STILL:-}" ] && exit 1 ;;
	esac
fi
exit 0
X
	chmod +x "$FAKE/$t"
done

# the phone case runs from a copy with the marker moved; the shipped file has one fixed path
SHELLCOPY=$W/shell; cp -a "$SRC/shell" "$SHELLCOPY"
: >"$W/marker"
sed -i "s#^MARKER=.*#MARKER=$W/marker#" "$SHELLCOPY/uninstall.sh"
PHONEH=$SHELLCOPY/uninstall.sh
LAPTOPH=$SRC/shell/uninstall.sh
ok "the shipped helper only trusts its one fixed marker" 'grep -qx "MARKER=/etc/phonegluewc/phone-session" "$LAPTOPH" && ! grep -q "MARKER=.*[$]" "$LAPTOPH"'
ok "this machine has no phone marker"                    '[ ! -e /etc/phonegluewc/phone-session ]'
ok "the laptop script sets the mock"                     'grep -q "PHONE_UNINSTALL_MOCK=1" "$SRC/run-on-laptop.sh"'
ok "every test tool here resolves to the fake"           '[ "$(PATH=$FAKE:/usr/bin command -v flatpak)" = "$FAKE/flatpak" ] && [ "$(PATH=$FAKE:/usr/bin command -v sudo)" = "$FAKE/sudo" ]'

D=$W/hd; H=$W/hh; S=$W/sys
mkdir -p "$D/applications" "$H" "$S/applications" "$D/flatpak/app/org.user.App" "$H/.var/app/org.user.App"
de() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n%s\n[Desktop Action x]\nExec=other\n' "$2" "$3" "${4:-}" >"$1/applications/$2.desktop"; }
de "$D" user.flat "flatpak run org.user.App" X-Flatpak=org.user.App
de "$S" sys.flat "flatpak run org.sys.App" X-Flatpak=org.sys.App
de "$D" waydroid.com.foo "waydroid app launch com.foo"
de "$S" hello hello
de "$S" needsme needsme
de "$S" phonesettings phonesettings
de "$D" local.script "/home/x/run.sh"
de "$S" bad.flat "x" 'X-Flatpak=--help'
de "$D" bad.way 'waydroid app launch $(touch${IFS}/tmp/pwned);x'
h() { env -i HOME="$H" XDG_DATA_HOME="$D" XDG_DATA_DIRS="$S" PATH="$FAKE:/usr/bin:/bin" "$@"; }
insp() { h sh "$PHONEH" inspect "$1" | tr '\n' ' '; }
rm1() { : >"$REC"; echo "${PW:-}" | h ${E:-} sh "$PHONEH" remove "$@" 2>&1 | tr '\n' ' '; }

ok "owner: user Flatpak needs no password, data known"   '[ "$(insp user.flat)" = "owner=flatpak name=org.user.App essential=0 needpw=0 data=$H/.var/app/org.user.App " ]'
ok "owner: system Flatpak asks for a password, no data"  '[ "$(insp sys.flat)" = "owner=flatpak name=org.sys.App essential=0 needpw=1 data= " ]'
ok "owner: Waydroid by its launch line"                  '[ "$(insp waydroid.com.foo)" = "owner=waydroid name=com.foo essential=0 needpw=0 data= " ]'
ok "owner: system package through apk"                   '[ "$(insp hello)" = "owner=system name=hello essential=0 needpw=1 data= " ]'
ok "essential: by name"                                  '[[ "$(FAKE_PKG=phonesettings-1-r0 insp phonesettings)" == *essential=1* ]]'
ok "essential: something the keyboard needs"             '[[ "$(h FAKE_PKG=needsme-1.0-r0 sh "$PHONEH" inspect needsme | tr "\n" " ")" == *essential=1* ]]'
ok "no owner for a loose file in the home"               '[[ "$(insp local.script)" == owner=none* ]]'

ok "a bad desktop id is refused"     '[ "$(rm1 "../../x")" = "error=Not a valid app id " ] && [ ! -s "$REC" ]'
ok "an id like an option is refused" '[ "$(rm1 "--help")" = "error=Not a valid app id " ] && [ ! -s "$REC" ]'
ok "a Flatpak id like an option is refused" '[ "$(rm1 bad.flat)" = "error=Not a valid Flatpak id " ] && [ ! -s "$REC" ]'
ok "a shell trick in a package is refused"  '[ "$(rm1 bad.way)" = "error=Not a valid Android package " ] && [ ! -s "$REC" ] && [ ! -e /tmp/pwned ]'

ok "user Flatpak removed, data stays" '[ "$(rm1 user.flat)" = "result=ok " ] && [ "$(cat "$REC")" = "flatpak [uninstall] [-y] [--noninteractive] [--user] [org.user.App]" ] && [ -d "$H/.var/app/org.user.App" ]'
ok "system Flatpak through the password tool, password never an argument" '[ "$(PW=s3cret rm1 sys.flat)" = "result=ok " ] && [ "$(head -n 1 "$REC")" = "sudo [-S] [-k] [-p] [] [--] [flatpak] [uninstall] [-y] [--noninteractive] [--system] [org.sys.App]" ] && grep -qx "stdin=s3cret" "$REC" && [ "$(grep -c s3cret "$REC")" = 1 ]'
ok "Waydroid through its own removal" '[ "$(rm1 waydroid.com.foo)" = "result=ok " ] && [ "$(cat "$REC")" = "waydroid [app] [remove] [com.foo]" ]'
ok "apk through the password tool"    '[ "$(PW=x rm1 hello)" = "result=ok " ] && grep -qx "sudo \[-S\] \[-k\] \[-p\] \[\] \[--\] \[apk\] \[del\] \[hello\]" "$REC"'
ok "a package still needed is an error"  '[ "$(PW=x E=FAKE_STILL=1 rm1 hello)" = "error=hello is still needed by another package " ]'
ok "a failure shows the last line of the tool" '[ "$(E=FAIL_TOOL=flatpak rm1 user.flat)" = "error=flatpak said no " ]'
ok "a wrong password is an error"     '[ "$(PW=x E=FAIL_TOOL=sudo rm1 hello)" = "error=sudo said no " ]'
ok "the ticked choice deletes Flatpak data" '[ "$(rm1 user.flat data)" = "result=ok " ] && [ ! -d "$H/.var/app/org.user.App" ]'

# the two ways out of real removal: with fake tools first on PATH, nothing may be called at all
: >"$REC"
RES=$(h PHONE_UNINSTALL_MOCK=1 sh "$LAPTOPH" remove user.flat data | tr '\n' ' ')
ok "laptop mode says simulated"         '[ "$RES" = "result=simulated " ]'
RES2=$(h PHONE_UNINSTALL_MOCK=1 sh "$LAPTOPH" inspect hello | tr '\n' ' ')
ok "laptop mode asks for no password"   '[[ "$RES2" == *needpw=0* ]]'
RES3=$(h PHONE_UNINSTALL_MOCK=1 sh "$PHONEH" remove hello | tr '\n' ' ')
ok "the mock wins even with a marker"   '[ "$RES3" = "result=simulated " ]'
ok "laptop mode reaches no tool"        '[ ! -s "$REC" ]'
RES4=
for a in user.flat sys.flat waydroid.com.foo hello; do RES4="$RES4$(h sh "$LAPTOPH" remove $a </dev/null | tr '\n' ' ')" 2>/dev/null; done
ok "any other session refuses"          '[ "$(grep -o "not a phone session" <<<"$RES4" | wc -l)" = 4 ]'
ok "the refusal reached no remove tool" '! grep -Eq "uninstall|remove|del|^sudo" "$REC"'

# ---- the dialog ----
CFG=$W/cfg/phonegluewc; O=$W/out; A=$W/data/applications
mkdir -p "$CFG" "$O" "$W/state/phonegluewc" "$A" "$W/sysapps/applications" "$W/data/icons/hicolor/scalable/apps" \
	"$W/home/.var/app/org.t.Flat" "$W/data/flatpak/app/org.t.Flat" "$W/home/.var/app/org.t.Keep" "$W/data/flatpak/app/org.t.Keep" "$W/data/flatpak/app/org.t.Fail" "$W/data/flatpak/app/org.t.Show"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' >"$CFG/config.conf"
COLORS="tflat=2060e0 tfail=20c060 tkeep=e0a020 phonesettings=c02080 tloose=20c0c0 hsys=8040e0 tshow=a0a020"
ap() { # DIR ID EXTRA EXEC
	local c; c=$(tr ' ' '\n' <<<"$COLORS" | sed -n "s/^$2=//p")
	printf '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#%s"/></svg>\n' "$c" >"$W/data/icons/hicolor/scalable/apps/$2.svg"
	printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\n%s\n' "$2" "${4:-true}" "$2" "$3" >"$W/$1/applications/$2.desktop"
}
ap data tflat X-Flatpak=org.t.Flat
ap data tfail X-Flatpak=org.t.Fail
ap data tkeep X-Flatpak=org.t.Keep
ap sysapps phonesettings ""
ap sysapps hsys ""
ap data tloose "" /x/y
ap data tshow X-Flatpak=org.t.Show
reset_lists() { printf '%s\n' "$@" | sed 's/$/.desktop/' >"$CFG/pinned-apps"; printf '{"tflat":9,"tfail":8}' >"$W/state/phonegluewc/app-usage.json"; : >"$REC"; }
cat >"$W/slots.py" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
colors = dict((k, tuple(bytes.fromhex(v))) for k, v in (kv.split("=") for kv in sys.argv[2].split()))
out = []
for i in range(4):
    p = im.getpixel((int((44.35 + 76 * i) * 2.75), int((872.73 - 62) * 2.75)))
    best = min(colors, key=lambda k: sum(abs(a - b) for a, b in zip(colors[k], p)))
    out.append(best if sum(abs(a - b) for a, b in zip(colors[best], p)) < 40 else "-")
print(" ".join(out))
PY
t() { echo "d 0 $1 $2"; echo f; echo "u 0"; echo f; echo "w ${3:-700}"; }
shot() { echo "x $SRC/tests/wshot $O/$1.ppm"; echo "w 500"; }
slot() { python3 -c "print(round((44.35 + 76 * $1) / 392.73, 3))"; }
Y=0.929
# what the dialog leaves on the screen, in screen fractions
RMY=0.783; rmx() { python3 -c "print(round(max(127, min(392.73 - 127, 44.35 + 76 * $1)) / 392.73, 3))"; }
open_dialog() { echo "d 0 $(slot "$1") $Y"; echo f; echo "w 1200"; echo "u 0"; echo f; echo "w 500"; t "$(rmx "$1")" $RMY 2500; }
OUTSIDE="0.5 0.7"
MAINX=0.778; CANCELX=0.514; TICK="0.2 0.2775"
BIGY=0.3525     # with the data row
PLAINY=0.28     # one or two lines of text and no data row
PWY=0.333       # with the password field
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$FAKE:$BUILD"
: >"$W/all.log"
session() { # NAME SHELL [ENV...]
	local n=$1 sh=$2; shift 2
	comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$sh" PHONEGLUEWC_KEYBOARD= XDG_DATA_DIRS="$W/data:$W/sysapps" PHONEGLUEWC_FAKETOUCH="$W/$n.script" "$@"
	comp_wait 900
	cat "$W/gw.log" >>"$W/all.log"
	comp_stop
	python3 -c "
from PIL import Image; import glob, os, sys
for f in glob.glob('$O/*.ppm'): Image.open(f).save(f[:-4] + '.png'); os.remove(f)"
}
slots() { python3 -I "$W/slots.py" "$O/$1.png" "$COLORS"; }
hasu() { grep -q "\"$1\"" "$W/state/phonegluewc/app-usage.json"; }

# a Flatpak: cancel, outside, then removed with its data staying; a failure keeps the app listed
reset_lists tflat tfail tkeep phonesettings
{ echo "w 3000"; shot one-start
  open_dialog 0; shot ask-flatpak; t $CANCELX $BIGY; shot one-cancel
  open_dialog 0; t $OUTSIDE; shot one-outside
  open_dialog 0; t $MAINX $BIGY 2500; shot one-gone
  open_dialog 0; shot ask-fail; t $MAINX $PLAINY 2500; shot fail-error; t $MAINX 0.255; shot fail-closed
  open_dialog 1; t $TICK; shot ticked; t $MAINX $BIGY 2500; shot keep-closed
  echo "x true"; echo "w 300"; } >"$W/one.script"
session one "$SHELLCOPY"
cp "$REC" "$O/one.rec"; cp "$CFG/pinned-apps" "$O/one.pinned"
ok "the start order"                     '[ "$(slots one-start)" = "tflat tfail tkeep phonesettings" ]'
ok "cancel and a tap outside remove nothing" '[ "$(slots one-cancel)" = "tflat tfail tkeep phonesettings" ] && [ "$(slots one-outside)" = "tflat tfail tkeep phonesettings" ]'
ok "the app left the tray"               '[ "$(slots one-gone | cut -d" " -f1-3)" = "tfail tkeep phonesettings" ]'
ok "the owner tool got one exact call"   'grep -qx "flatpak \[uninstall\] \[-y\] \[--noninteractive\] \[--user\] \[org.t.Flat\]" "$O/one.rec"'
ok "it left pins and usage"              '! grep -q tflat "$O/one.pinned" && ! hasu tflat'
ok "its data stayed when not ticked"     '[ -d "$W/home/.var/app/org.t.Flat" ]'
ok "a failure keeps it listed and used"  '[ "$(slots fail-closed | cut -d" " -f1)" = tfail ] && grep -q tfail "$O/one.pinned" && hasu tfail'
ok "ticking deletes that app data"       'grep -q "\[--system\] \[org.t.Keep\]\|\[--user\] \[org.t.Keep\]" "$O/one.rec" && [ ! -d "$W/home/.var/app/org.t.Keep" ]'

# an essential package: two warnings, then the password, which reaches stdin of the tool only
reset_lists phonesettings hsys
{ echo "w 3000"
  open_dialog 0; shot warn; t $CANCELX $PLAINY; shot warn-cancel
  open_dialog 0; t $MAINX $PLAINY; shot warn2; t 0.37 $PLAINY; shot warn2-keep
  open_dialog 0; t $MAINX $PLAINY; t $MAINX $PLAINY; shot password
  echo "x $SRC/tests/vkbd s f h"; echo "w 800"; shot password-typed; t $MAINX $PWY 2500; shot essential-done
  echo "x true"; echo "w 300"; } >"$W/two.script"
make -C "$SRC/tests" vkbd >/dev/null 2>&1
session two "$SHELLCOPY" FAKE_PKG=phonesettings-1-r0
ok "no call before the second step"      '[ "$(grep -c "\[del\]" "$REC")" = 1 ]'
ok "the password went to stdin only"     'grep -qx "sudo \[-S\] \[-k\] \[-p\] \[\] \[--\] \[apk\] \[del\] \[phonesettings\]" "$REC" && grep -qx "stdin=sfh" "$REC"'
ok "it left pins and usage after the call" '! grep -q phonesettings "$CFG/pinned-apps"'

# no owner known: says so, offers no removal
reset_lists tloose
{ echo "w 3000"; open_dialog 0; shot noowner; echo "x true"; echo "w 300"; } >"$W/three.script"
session three "$SHELLCOPY"
ok "no owner calls nothing"              '! grep -Eq "uninstall|remove|del" "$REC"'

# as the laptop window runs it, and as any non phone session runs it: the shipped helper
reset_lists tshow hsys
{ echo "w 3000"; open_dialog 0; t $MAINX $PLAINY 1500; shot simulated; echo "x true"; echo "w 300"; } >"$W/four.script"
session four "$SRC/shell" PHONE_UNINSTALL_MOCK=1
ok "the laptop dialog reached no tool"   '[ ! -s "$REC" ]'
ok "and the app stays"                   'grep -q tshow "$CFG/pinned-apps"'
reset_lists tshow hsys
{ echo "w 3000"; open_dialog 0; t $MAINX $PLAINY 1500; shot refused; echo "x true"; echo "w 300"; } >"$W/five.script"
session five "$SRC/shell"
ok "a session without the marker reached no remove tool" '! grep -Eq "uninstall|remove|del" "$REC"'
cp "$O"/*.png "$SHOTS"/ 2>/dev/null
echo "failed: $fails"
exit $((fails > 0))
