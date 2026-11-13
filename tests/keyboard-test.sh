#!/bin/bash
# The keyboard end to end, headless, with a fake touchscreen: a real Qt field, then foot. SHOTS=DIR keeps PNGs.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-kbd.XXXXXX")
SANDBOX_EXTRA="foot stty curl" # the terminal checks need a real one; it runs only the scripts below
. "$SRC/tests/sandbox.sh"
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
if [ -n "${SAN:-}" ]; then
	rm -f "$BUILD"/keyboard/*.o "$BUILD"/keyboard/phonekbd
	make -C "$BUILD/keyboard" phonekbd CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer" >/dev/null 2>&1 || { echo "sanitized keyboard build failed"; exit 1; }
fi
make -C "$SRC/tests" wshot >/dev/null 2>&1
mkdir -p "$W/cfg/phonegluewc" "$W/state" "$W/state2" "$W/data/applications"
printf '[Desktop Entry]\nType=Application\nName=Camera\nExec=foot sleep 60\n' >"$W/data/applications/camera.desktop"
for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28; do
	printf '[Desktop Entry]\nType=Application\nName=Camera %s\nExec=true\n' "$n" >"$W/data/applications/camera$n.desktop"
done
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\nbind_insert = mod+g = spawn:sh %s/bound.sh\n' "$W" > "$W/cfg/phonegluewc/config.conf"
printf 'echo pressed >>%s/bound.txt\n' "$W" >"$W/bound.sh"
mkdir -p "$W/cfg/phonekbd"
kcfg() { printf '%s\n' "$@" >"$W/cfg/phonekbd/config"; }

# foot: Ctrl+C must arrive as a real signal
cat >"$W/term.sh" <<TERM
trap 'echo GOT_INT >>$W/int.txt' INT
while :; do cat >>$W/typed.txt; done
TERM
cat >"$W/field.sh" <<FIELD
KBD_OUT=$W/field.txt QT_QUICK_BACKEND=software exec env \${KBD_SECRET_FIELD:+KBD_OUT_SECRET=$W/secret.txt} qs -p $SRC/tests/kbd-field
FIELD
cat >"$W/term2.sh" <<TERM
stty raw -echo
exec cat >>$W/raw.bin
TERM
cat >"$W/copy.sh" <<COPY
wl-copy "\$1"
COPY
mkdir -p "$W/fake"
cat >"$W/fake/phonesettings" <<FAKE
#!/bin/sh
echo "\$*" >>$W/settings.txt
FAKE
cat >"$W/fake/gsettings" <<FAKE
#!/bin/sh
[ "\$(cat $W/scheme)" = none ] && exit 1
cat $W/scheme
FAKE
chmod +x "$W/fake/phonesettings" "$W/fake/gsettings"
cat >"$W/ringer.sh" <<RINGER
mkdir -p $W/cfg/phonegluewc; echo "ringer = \$1" >$W/cfg/phonegluewc/phone.conf
RINGER
cat >"$W/scheme.sh" <<SCHEME
echo "\$1" >$W/scheme
SCHEME
cat >"$W/fake/paplay" <<FAKE
#!/bin/sh
echo click >>$W/sound.txt
FAKE
chmod +x "$W/fake/paplay"
cat >"$W/kalive.sh" <<KA
pgrep -P \$(cat "$W/pid") -x phonekbd >>"$W/kalive.txt" || echo DEAD >>"$W/kalive.txt"
KA
cat >"$W/sig.sh" <<SIG
kill -\$1 \$(pgrep -P \$(cat "$W/pid") -x phonekbd)
SIG
cat >"$W/rss.sh" <<RSS
p=\$(cat "$W/pid"); q=\$(pgrep -P \$p -x phonekbd)
echo "\$1 phonekbd=\$(awk '/VmRSS/{print \$2}' /proc/\$q/status) kB" >>"$W/rss"
RSS

python3 "$SRC/tests/kbd-script.py" "$W" > "$W/script" || exit 1
python3 "$SRC/tests/kbd-script.py" "$W" shell > "$W/script-shell" || exit 1
for m in mods emoji emoji-missing emoji-mono privacy history histoff features features2 features3 english plang-ro plang-en plang-empty plang-live strip predoff chevron chevron-secret options coroff bothoff pw pw-removed pw-en translate force; do
	python3 "$SRC/tests/kbd-script.py" "$W" "$m" > "$W/script-$m" || exit 1
done
# $1 shell dir or empty, $2 script, $3 state suffix, then extra environment
run() {
COMP=$BUILD/phonegluewc
SANDBOX_PATH="${FAKE_PATH:-}${SAN:+$BUILD/keyboard:}$BUILD:$SRC/keyboard"
sh_dir=$1; script=$2; st=${3:-}; shift; shift; [ $# -gt 0 ] && shift
comp_start XDG_STATE_HOME="$W/state$st" QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL="$sh_dir" PHONEKBD_DATA="$SRC/keyboard/data" PHONEKBD_DUMP="$W/keys.txt" \
	PHONEGLUEWC_FAKETOUCH="$script" "$@"
# the compositor does not restart it, so one keyboard per run; a new or missing one is a crash
( p=$(cat "$W/pid"); while sleep 0.3 && [ -d "$W" ]; do pgrep -P "$p" -x phonekbd >>"$W/kpids$st"; done ) & kw=$!
comp_wait "${KBD_WAIT:-900}"
kill "$kw" 2>/dev/null; wait "$kw" 2>/dev/null
comp_stop
tail -1 "$W/kalive.txt" 2>/dev/null | grep -q DEAD && { echo "     keyboard gone at the end of $(basename "$script")"; grep -v 'wlr_\|types/\|bsp:' "$W/gw.log" | tail -8; }
[ -n "${KBD_LOG:-}" ] && cat "$W/gw.log" >>"$KBD_LOG"
cat "$W/gw.log" >>"$W/all.log"
}
cat >"$W/maps.sh" <<MAPS
q=\$(pgrep -P \$(cat "$W/pid") -x phonekbd)
grep -c 'words.tsv\|bigrams.tsv' /proc/\$q/maps >"$W/maps-\$1.txt"
MAPS
# the same steps the helper takes on a phone, without the network
lang() { env XDG_CONFIG_HOME="$W/cfg" XDG_DATA_HOME="$W/data" XDG_CACHE_HOME="$W/cache" PHONEKBD_DATA="$SRC/keyboard/data" "$SRC/keyboard/phonekbd-lang" "$@"; }
ro_on() { rm -rf "$W/data/phonekbd"; mkdir -p "$W/data/phonekbd/langs"; cp -r "$SRC/keyboard/packs/ro" "$W/data/phonekbd/langs/"; lang merge >/dev/null; }
ro_none() { rm -rf "$W/data/phonekbd"; }
ro_on
kcfg "autocap = off"
run "" "$W/script"
run "$SRC/shell" "$W/script-shell" 2
mv "$W/typed.txt" "$W/typed-legacy.txt"; mv "$W/int.txt" "$W/int-legacy.txt" 2>/dev/null
run "" "$W/script-mods" 3
run "" "$W/script-emoji" 4
keep=$W/state4/phonekbd/emoji-recent; recents=$(wc -l <"$keep" 2>/dev/null); : >"$W/field.txt"
run "" "$W/script-emoji-missing" 6 PHONEKBD_EMOJI_FONT=none
run "" "$W/script-emoji-mono" 7 PHONEKBD_EMOJI_FONT=/usr/share/fonts/noto-emoji/NotoEmoji-Regular.ttf
kcfg "autocap = off"
: >"$W/field.txt"
run "" "$W/script-privacy" 5 KBD_SECRET_FIELD=1
cp "$W/secret.txt" "$W/secret-privacy.txt"
# the history switches, set from inside the running test
cat >"$W/hs.sh" <<EOF
d=\$XDG_STATE_HOME/phonekbd
echo "\$(find "\$d" -maxdepth 0 -printf %m) \$(find "\$d/emoji-recent" -maxdepth 0 -printf %m 2>/dev/null || echo gone) \$(cat "\$d/emoji-recent" 2>/dev/null | wc -l)" >"$W/hs-\$1.txt"
EOF
cat >"$W/setcfg.sh" <<EOF
{ echo "autocap = off"; for a; do echo "\${a%%=*} = \${a#*=}"; done; } >"$W/cfg/phonekbd/config.new"
mv "$W/cfg/phonekbd/config.new" "$W/cfg/phonekbd/config"
EOF
cat >"$W/setlayout.sh" <<'EOF'
echo "$1" >"$XDG_STATE_HOME/phonekbd/layout"
EOF
kcfg "autocap = off"
: >"$W/field.txt"
mkdir -p "$W/state13/phonekbd"; chmod 755 "$W/state13/phonekbd"
run "" "$W/script-history" 13 KBD_SECRET_FIELD=1
kcfg "autocap = off" "emoji_history = off" "clipboard_history = off"
: >"$W/field.txt"
mkdir -p "$W/state14/phonekbd"; echo neutral-old-entry >"$W/state14/phonekbd/emoji-recent"; chmod 644 "$W/state14/phonekbd/emoji-recent"
run "" "$W/script-histoff" 14
kcfg "# neutral comment" "autocap = on"
: >"$W/field.txt"
run "" "$W/script-features" 8
kcfg "autocap = off" "number_row = on" "key_height = 120" "theme = contrast"
: >"$W/field.txt"
run "" "$W/script-features2" 9
: >"$W/sound.txt"
ro_none
kcfg "# neutral comment" "autocap = off" "one_handed = right" "theme = red" "sound = on" "vibrate = on"
: >"$W/field.txt"
FAKE_PATH="$W/fake:" run "" "$W/script-features3" 10 PHONEKBD_VIBRATOR=/nonexistent/vibrator
cp "$W/cfg/phonekbd/config" "$W/config-toggled"
kcfg "autocap = off"
: >"$W/field.txt"
run "" "$W/script-english" 20
kcfg "autocap = off" "predict = off"
: >"$W/field.txt"
run "" "$W/script-predoff" 21
kcfg "autocap = off" "autocorrect = off"
: >"$W/field.txt"
run "" "$W/script-coroff" 22
kcfg "autocap = off"
: >"$W/field.txt"
run "" "$W/script-bothoff" 23
ro_on
kcfg "autocap = off" "predict_languages = ro"
: >"$W/field.txt"
run "" "$W/script-plang-ro" 29
kcfg "autocap = off" "predict_languages = en"
: >"$W/field.txt"
run "" "$W/script-plang-en" 30
kcfg "autocap = off" "predict_languages ="
: >"$W/field.txt"
run "" "$W/script-plang-empty" 31
kcfg "autocap = off" "predict_languages = en ro"
: >"$W/field.txt"
run "" "$W/script-plang-live" 32
kcfg "autocap = off"
: >"$W/field.txt"
run "" "$W/script-strip" 33
kcfg "autocap = off"
: >"$W/field.txt"; : >"$W/settings.txt"
printf '%s\n' "autocap = off" "theme = light" >"$W/cfg-light"
FAKE_PATH="$W/fake:" run "" "$W/script-chevron" 37
: >"$W/field.txt"; : >"$W/secret.txt"; cp "$W/settings.txt" "$W/settings-before"
FAKE_PATH="$W/fake:" run "" "$W/script-chevron-secret" 38 KBD_SECRET_FIELD=1
kcfg "autocap = off"
: >"$W/field.txt"; echo none >"$W/scheme"
KBD_WAIT=4000 FAKE_PATH="$W/fake:" run "" "$W/script-options" 39
rm -f "$W/cfg/phonegluewc/phone.conf"
# memory with more languages on: MEM_PACKS is a folder of unpacked packs, as the published repo has
if [ -n "${MEM_PACKS:-}" ] && [ -z "${SAN:-}" ]; then
	python3 "$SRC/tests/kbd-script.py" "$W" memlang > "$W/memlang" || exit 1
	cp "$W/rss" "$W/rss.keep"; cp "$W/kalive.txt" "$W/kalive.keep"
	for set in ro "ro fr" ""; do
		ro_none; mkdir -p "$W/data/phonekbd/langs"
		for c in $set; do cp -r "$MEM_PACKS/$c" "$W/data/phonekbd/langs/"; done
		[ -z "$set" ] || lang merge >/dev/null
		: >"$W/rss"; rm -f "$W/kpidsm"; run "" "$W/memlang" m
		echo "     memory with en $set: $(tr '\n' ' ' <"$W/rss") words $(du -k "$W/data/phonekbd/words.tsv" 2>/dev/null | cut -f1) kB, next words $(du -k "$W/data/phonekbd/bigrams.tsv" 2>/dev/null | cut -f1) kB"
	done
	rm -f "$W/kpidsm"; mv "$W/rss.keep" "$W/rss"; mv "$W/kalive.keep" "$W/kalive.txt"
	ro_on
fi
kcfg "autocap = off"
: >"$W/secret.txt"
run "" "$W/script-pw" 24 KBD_SECRET_FIELD=1
lang remove ro >/dev/null
: >"$W/secret.txt"
run "" "$W/script-pw-removed" 25 KBD_SECRET_FIELD=1
ro_none
run "" "$W/script-pw-en" 26 KBD_SECRET_FIELD=1
run "" "$W/script-force" 28 KBD_SECRET_FIELD=1
# Translate and the language list against a local fake registry; translator stubbed, never the real network
cat >"$W/fake/phonetext-translate" <<FAKE
#!/bin/sh
echo \$\$ >$W/stubpid
read -r line
case "\$line" in zz*) sleep 30 ;; esac
echo "[\$1-\$2] \$line"
FAKE
chmod +x "$W/fake/phonetext-translate"
cat >"$W/kids.sh" <<KIDS
q=\$(pgrep -P \$(cat "$W/pid") -x phonekbd)
pgrep -P \$q | wc -l >"$W/kids-\$1.txt"
KIDS
cat >"$W/grp.sh" <<GRP
pgrep -g \$(cat "$W/stubpid-slow") | wc -l >"$W/grp-\$1.txt"
GRP
python3 "$SRC/tests/fake-lang-server.py" "$W/srv" "$SRC/keyboard/packs" ui >"$W/reqs" 2>/dev/null & srv=$!
for i in $(seq 50); do [ -s "$W/srv/port" ] && break; sleep 0.1; done
base=http://127.0.0.1:$(cat "$W/srv/port")
kcfg "autocap = off"
: >"$W/field.txt"
FAKE_PATH="$W/fake:" run "" "$W/script-translate" 27 PHONEKBD_REGISTRY="$base/records" PHONEKBD_CDN="$base/cdn/" PHONEKBD_PACKS="$base/packs" PHONETEXT_MODELS="$W/data/phonegluewc/translate"
kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null
ro_none
sed -i 's/mode=1080x2400/mode=2400x1080/' "$W/cfg/phonegluewc/config.conf"
python3 "$SRC/tests/kbd-script.py" "$W" land1 >"$W/script-land1"
run "" "$W/script-land1" 11
python3 "$SRC/tests/kbd-script.py" "$W" land2 >"$W/script-land2"
run "" "$W/script-land2" 12
for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done

fails=0
step() { sed -n '1,$p' "$W/s$1.txt" 2>/dev/null | head -1; }
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', wanted '$3'"; fails=$((fails+1)); fi; }
ok "typing reaches the field"          "$(step 1)" "hi"
ok "suggestion tap replaces the word"  "$(step 2)" "hi hello "
ok "autocorrect on space"              "$(step 3)" "hi hello the "
ok "backspace undoes the correction"   "$(step 4)" "hi hello teh"
ok "a kept word is not corrected again" "$(step 5)" "hi hello teh teh "
ok "diacritics by long press"          "$(step 6)" "hi hello teh teh ășț"
ok "diacritics restored on space"      "$(step 7)" "hi hello teh teh ășț mănânc "
ok "shift gives a capital"             "$(step 8)" "hi hello teh teh ășț mănânc A"
ok "swipe writes the word"             "$(step 9)" "hi hello teh teh ășț mănânc A salut "
ok "the bottom edge of comma is a key"     "$(wc -m <"$W/s20.txt")" "$(($(wc -m <"$W/s9.txt") + 1))"
ok "the bottom edge of space is a key"     "$(cmp -s "$W/s20.txt" "$W/s21.txt"; echo $?)" 1
ok "the bottom edge of period is a key"    "$(cmp -s "$W/s21.txt" "$W/s22.txt"; echo $?)" 1
ok "the bar under the keyboard takes the swipe" "$(grep -c '^FT kbdbar .*gesture=3' "$W/all.log")" 1
ok "results stop above the keyboard"       "$(grep '^FT results ' "$W/all.log" | grep -o 'menuh=[0-9]*' | cut -d= -f2 | awk '{print ($1 > 0 && $1 <= 872 - 256) ? 1 : "menuh=" $1}')" 1
ok "laptop layout is remembered"       "$(cat "$W/state/phonekbd/layout")" "laptop"
ok "foot gets laptop keys"             "$(head -1 "$W/typed-legacy.txt")" "abC"
ok "Ctrl+C is a real signal"           "$(grep -c GOT_INT "$W/s11.txt")" "1"
ok "locked Ctrl stays for two keys"    "$(grep -c GOT_INT "$W/s12.txt")" "3"
ok "foot gets a normal key after"      "$(sed -n 2p "$W/typed-legacy.txt")" "z"
ok "no learned words from the terminal" "$(cat "$W/state/phonekbd/learned.tsv" 2>/dev/null | grep -c '^ab')" "0"
ok "the keyboard learned the kept word" "$(grep -c '^teh ' "$W/state/phonekbd/learned.tsv")" "1"
ok "the menu search gets the keyboard" "$(grep -c '^FT search .*menu=1 .*kbd=1' "$W/all.log")" "1"
ok "searching through the keyboard opens the app" "$(grep -c '^FT searched .*menu=0' "$W/all.log")" "1"
grep -q 'hidden' "$W/rss" && echo "     $(tr '\n' ' ' <"$W/rss")"
if [ -n "${SAN:-}" ]; then echo "     hidden memory not judged: sanitizers inflate it";
elif [ "$(awk '/^hidden/{print $2}' "$W/rss" | cut -d= -f2)" -lt 8000 ] 2>/dev/null; then echo "ok   hidden keyboard stays small"; else echo "FAIL hidden keyboard memory"; fails=$((fails+1)); fi
ok "keyboard shows on focus"  "$(grep -c '^FT shown .*kbd=1' "$W/all.log")" "1"
ok "keyboard hides without a field" "$(grep -c '^FT hidden .*kbd=0' "$W/all.log")" "1"

# --- the modifier row, from the normal layout, in a real terminal ---
st() { grep -c "^state .*$2" "$W/keys-$1.txt" 2>/dev/null; }
ok "the row opens from the normal layout"  "$(st row 'modrow=1')" 1
ok "a tap on Ctrl is one Ctrl+C"           "$(grep -c GOT_INT "$W/s31.txt")" 1
ok "a double tap locks it for two keys"    "$(grep -c GOT_INT "$W/s32.txt")" 3
ok "unlocked, c is only a letter"          "$(grep -c GOT_INT "$W/s33.txt")" 3
ok "hiding the row frees a locked Ctrl"    "$(grep -c GOT_INT "$W/s34.txt")" 3
ok "dismissing frees a locked Ctrl"        "$(grep -c GOT_INT "$W/s35.txt")" 3
ok "the row is closed after dismissing"    "$(st back 'modrow=0')" 1
ok "the letters arrive plain in the terminal" "$(tr '\n' ' ' <"$W/typed.txt")" "ab c d e f "
ok "Super+g runs the compositor binding"   "$(wc -l <"$W/bound.txt" 2>/dev/null)" 1
ok "raw bytes: modifiers, Esc, Tab, F keys, swipes" "$(python3 - "$W/s36.bin" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read() if __import__('os').path.exists(sys.argv[1]) else b''
want = [b'\x1b[1;5C', b'\x1b\x09', b'\x1b[15~', b'\x1b[24~', b'\x1bOP', b'\x1b[H', b'\x1ba', b'\x1b[1;5Q', b'\x1b[D', b'\x1b[D', b'\x17']
i = 0
for w in want:
    j = d.find(w, i)
    if j < 0:
        print('missing', w, 'in', d)
        break
    i = j + len(w)
else:
    print('all in order')
PY
)" "all in order"

# --- emoji ---
ok "the panel opens in colour"             "$(st open 'panel=1 kind=1')" 1
cp1() { python3 -c 'import sys;print(any(c in open(sys.argv[1],encoding="utf-8").read() for c in sys.argv[2:]))' "$@" 2>/dev/null; }
ok "a tile writes its emoji"               "$(cp1 "$W/s41.txt" 😀)" True
ok "a long press gives the skin tone"      "$(cp1 "$W/s42.txt" 👋🏼)" True
ok "recently used shows what was used"     "$(st recent 'tiles=2')" 1
ok "tapping a recent one writes it again"  "$(python3 -c 'import sys;print(open(sys.argv[1],encoding="utf-8").read().count("👋🏼"))' "$W/s43.txt")" 2
ok "scrolling the grid writes nothing"     "$(cmp -s "$W/s43.txt" "$W/s44.txt"; echo $?)" 0
ok "search finds rocket"                   "$(cp1 "$W/s45.txt" 🚀)" True
ok "the panel closes"                      "$(st closed 'panel=0 kind=0')" 1
ok "typing works after the panel"          "$(tr -d '\n' <"$W/s46.txt" | tail -c 1)" "x"
ok "recents survive on disk"               "$recents" 3
ok "missing font: a message, no crash"     "$(st nofont 'panel=2' ; st nofont 'panel=1 kind=0')" "0
1"
ok "missing font: the keyboard still types" "$(tr -d '\n' <"$W/s47.txt")" "x"
ok "a plain font still gives emoji"        "$(st mono 'kind=2')" 1
ok "and writes them"                       "$(cp1 "$W/s48.txt" 😀)" True
rs() { awk -v l="$1" '$1==l{split($2,a,"=");print a[2]}' "$W/rss"; }
echo "     emoji panel: before $(rs before) kB, open $(rs open) kB, closed $(rs closed) kB"
if [ -n "${SAN:-}" ]; then echo "     panel memory not judged: sanitizers inflate it";
elif [ "$(rs closed)" -lt "$(( $(rs before) + 1500 ))" ] 2>/dev/null; then echo "ok   closing the panel gives its memory back"; else echo "FAIL panel memory not released"; fails=$((fails+1)); fi

# --- privacy ---
ok "clipboard entries are caught"          "$(st clip1 'clips=1')" 1
ok "a clipboard entry can be pasted"       "$(cp1 "$W/s61.txt" neutral-clip-one)" True
ok "a secret field is recognised"          "$(st secret 'secret=1 nsug=0')" 1
ok "a secret field has no emoji or clipboard buttons" "$(grep -cE '^(clip|emoji) ' "$W/keys-secret.txt")" 0
ok "the secret field got the text"         "$(tr -d '\n' <"$W/secret-privacy.txt" | grep -c hunter)" 1
if [ -e "$W/before-clear/learned.tsv" ] && ! grep -q 'hunter\|^teh' "$W/before-clear/learned.tsv"; then echo "ok   nothing learned in the secret field"; else echo "FAIL learned from the secret field, or nothing at all"; fails=$((fails+1)); fi
ok "the normal field did learn"            "$(grep -c '^xqzvk' "$W/before-clear/learned.tsv")" 1
ok "no learned pairs from the secret field" "$(cat "$W/before-clear/bigrams.tsv" 2>/dev/null | grep -c hunter)" 0
d=$(magick "$W/secret-idle.ppm" "$W/secret-down.ppm" -crop 1080x800+0+1600 +repage -compose difference -composite -threshold 0 -format '%[fx:int(mean*w*h+0.5)]' info: 2>&1)
ok "a secret key press changes no pixel"   "${d:-none}" 0
d=$(magick "$W/secret-idle2.ppm" "$W/secret-hold.ppm" -crop 1080x800+0+1600 +repage -compose difference -composite -threshold 0 -format '%[fx:int(mean*w*h+0.5)]' info: 2>&1)
ok "a secret long press shows its popup"    "$([ "${d:-0}" -gt 0 ] && echo yes)" yes
ok "nothing copied while secret is kept"   "$(st clip2 'clips=1')" 1
ok "history can be cleared"                "$(st cleared 'clips=0')" 1
ok "no clipboard text on disk"             "$(grep -rl neutral-clip "$W/home" "$W/state5" "$W/cache" "$W/cfg" "$W/data" "$W/run" "$W/tmp" 2>/dev/null | wc -l)" 0
ok "no typed text in any log"              "$(grep -c 'hunter\|xqzvk\|neutral-clip' "$W/all.log")" 0
ok "clearing removes the learned files"    "$(ls "$W/state5/phonekbd" | grep -cE '^(learned.tsv|bigrams.tsv|emoji-recent)$')" 0

# --- the emoji key moved to the bottom row ---
U=39.27
kk() { awk -v n="$2" '$1==n{print ($5 > 48 ? "bottom" : "top")}' "$W/keys-$1.txt"; }
atcomma() { awk -v u=$U '$1==","{printf "%.1f", $4/u}' "$W/keys-$1.txt"; }
ok "letters: one emoji key, in the bottom row" "$(kk start emoji)" bottom
ok "letters: clipboard stays in the top bar"   "$(kk start clip)" top
ok "letters: emoji beside ?123"                "$(awk '$1=="emoji"{e=$5}$1=="?123"{p=$5}END{print e==p}' "$W/keys-start.txt")" 1
ok "letters: suggestions get the room"         "$(grep -c '^state .*nsug=3' "$W/keys-start.txt")" 1
ok "symbols: the emoji key is there too"       "$(kk sym emoji)" bottom
ok "laptop layout: no emoji key"               "$(grep -c '^emoji ' "$W/keys-laptop.txt")" 0
ok "laptop layout: its way back has its place" "$(atcomma laptop)" "3.0"
ok "secret: no emoji key and no gap"           "$(grep -c '^emoji ' "$W/keys-secret.txt") $(atcomma secret)" "0 2.0"
ok "turned: one emoji key, beside the Ctrl button" "$(grep -c '^emoji ' "$W/keys-land.txt") $(grep -c '^mods ' "$W/keys-land.txt")" "1 1"
ok "the keyboard reads a layout written while hidden" "$(grep -c '^Esc ' "$W/keys-h-laptop.txt")" 1

# --- the history switches ---
hs() { cat "$W/hs-$1.txt" 2>/dev/null; }
ok "on: an emoji is recorded, 0700 and 0600"   "$(hs on)" "700 600 1"
ok "on: the clipboard is recorded"             "$(st h-on 'clips=1')" 1
ok "password field: the panel closes"          "$(st h-secret 'panel=0 .*secret=1')" 1
ok "password field: no emoji recorded"         "$(hs secret)" "700 600 1"
ok "password field: no clipboard recorded"     "$(st h-secret-clip 'clips=1')" 1
ok "emoji off: the stored file is gone"        "$(hs eoff)" "700 gone 0"
ok "emoji off: the clipboard list stays"       "$(st h-eoff-clip 'clips=1')" 1
ok "emoji off: no recent tab"                  "$(grep -c '^recent ' "$W/keys-h-eoff.txt")" 0
ok "emoji off: picking still works"            "$(cp1 "$W/s101.txt" 😀)" True
ok "emoji off: nothing gets written"           "$(hs eoff2)" "700 gone 0"
ok "clipboard off: the list is empty"          "$(st h-coff 'clips=0')" 1
ok "clipboard off: no clear button"            "$(grep -c '^Clear ' "$W/keys-h-coff.txt")" 0
ok "clipboard off: normal paste works"         "$(cp1 "$W/s102.txt" neutral-clip-three)" True
ok "clipboard off: emoji records independently" "$(hs coff)" "700 600 1"
ok "on again: the clipboard records"           "$(st h-on2 'clips=1')" 1
ok "clear action: emoji file gone, still on"   "$(hs cleared)" "700 gone 0"
ok "clear command empties a keyboard that is up"  "$(st h-cleared-up 'clips=0')" 1
ok "still recording after that"                "$(st h-on3 'clips=1')" 1
ok "clear command empties a hidden keyboard"   "$(st h-cleared 'clips=0')" 1
ok "both off at start: the old file is gone"   "$(hs start)" "700 gone 0"
ok "both off: no recent tab"                   "$(grep -c '^recent ' "$W/keys-hoff.txt")" 0
ok "both off: picking still works"             "$(cp1 "$W/s103.txt" 😀)" True
ok "both off: nothing written after a pick"    "$(hs after)" "700 gone 0"
ok "both off: a copy is not recorded"          "$(st hoff-clip 'clips=0')" 1
ok "history runs leave no clipboard text"      "$(grep -rl neutral-clip "$W/state13" "$W/state14" 2>/dev/null | wc -l)" 0

# --- the rest ---
if grep -q '^H' "$W/s71.txt"; then echo "ok   a field that asks for capitals starts with one"; else echo "FAIL autocap: '$(cat "$W/s71.txt")'"; fails=$((fails+1)); fi
ok "two spaces end the sentence"           "$(tr -d '\n' <"$W/s72.txt")" "Hi. T"
if [ "$(tr -d '\n' <"$W/s73.txt" | wc -w)" = 3 ]; then echo "ok   a predicted next word can be tapped: $(tr -d '\n' <"$W/s73.txt")"; else echo "FAIL prediction: '$(cat "$W/s73.txt")'"; fails=$((fails+1)); fi
ok "a swipe on space moves the cursor"     "$(tail -1 "$W/s74.txt")" "Axbc"
ok "a swipe on backspace deletes the word" "$(tail -1 "$W/s75.txt")" "One "
ok "long press has symbols"                "$(tail -1 "$W/s76.txt")" "1?"
ok "number row and taller keys"            "$(awk '/^size/{print $5}' "$W/keys-numrow.txt")" "360"
ok "the number row types"                  "$(tr -d '\n' <"$W/s81.txt")" "17 "
ok "one hand: smaller block on the right"  "$(awk '$1=="q"{print ($4 > 392*.16)}' "$W/keys-onehand.txt")" 1
ok "one hand types"                        "$(tr -d '\n' <"$W/s91.txt")" "hi"
ok "one hand swaps sides"                  "$(tr -d '\n' <"$W/s92.txt")" "hih"
ok "one hand closes"                       "$(awk '$1=="q"{print ($4 < 30)}' "$W/keys-full.txt")" 1
ok "the keyboard's toggle keeps the file"  "$(grep -c '^# neutral comment$\|^one_handed = off$\|^theme = red$' "$W/config-toggled")" 3
ok "English only leaves the word alone"    "$(tr -d '\n' <"$W/s93.txt" | sed 's/^[a-z]* //')" "mananc "
if [ "$(wc -l <"$W/sound.txt")" -gt 3 ]; then echo "ok   sound on: the player was started"; else echo "FAIL sound"; fails=$((fails+1)); fi
ok "a missing vibrator is no crash"        "$(grep -c 'phonekbd.*crash\|segfault' "$W/all.log")" 0
# --- English only is the start; a language adds to it ---
ok "base data has no Romanian words"       "$(cut -f2 "$SRC/keyboard/data/words.tsv" | grep -c 'mănânc\|^și$')" 0
ok "English only: long press offers no ă"  "$(tr -d '\n' <"$W/s131.txt")" "@#"
ok "English only: no letters in a corner"  "$(grep -c 'ă\|ș' "$W/keys-english.txt")" 0

# --- which languages predict ---
ok "Romanian only: an English word stays, its own typo is fixed" "$(tr -d '\n' <"$W/s201.txt")" "because mănânc "
ok "English only with the pack in: the same the other way" "$(tr -d '\n' <"$W/s202.txt")" "mananc the "
ok "an empty list: an empty strip"         "$(st plang-empty 'nsug=0')" 1
ok "an empty list: no correction"          "$(tr -d '\n' <"$W/s203.txt")" "teh "
ok "an empty list: long press letters stay" "$(tr -d '\n' <"$W/s206.txt")" "teh ă"
ok "the key applies while running"         "$(tr -d '\n' <"$W/s205.txt")" "mănânc mananc "
ok "the strip has three slots with a long word" "$(st strip-long 'nsug=3')" 1

# --- autocomplete is optional ---
ok "predict off: an empty strip"           "$(st predoff 'nsug=0')" 1
ok "predict off: corrections still apply"  "$(tr -d '\n' <"$W/s111.txt")" "the "
ok "predict off: one backspace still undoes" "$(tr -d '\n' <"$W/s112.txt")" "teh"
ok "predict off: no pairs learned"         "$(cat "$W/state21/phonekbd/bigrams.tsv" 2>/dev/null | wc -l)" 0
ok "predict off: only the words are mapped" "$(cat "$W/maps-predoff.txt")" 1
ok "autocorrect off: three suggestions"    "$(st coroff 'nsug=3')" 1
ok "autocorrect off: the word stays"       "$(tr -d '\n' <"$W/s113.txt")" "teh "
ok "both on: dictionary in memory"         "$(cat "$W/maps-bothon.txt")" 2
ok "both off, once it next appears: no dictionary in memory" "$(cat "$W/maps-bothoff.txt")" 0
ok "both off: no suggestions"              "$(st bothoff 'nsug=0')" 1
ok "both off: the word stays"              "$(tr -d '\n' <"$W/s114.txt")" "teh "
ok "both off: nothing learned"             "$(cat "$W/state23/phonekbd/learned.tsv" "$W/state23/phonekbd/bigrams.tsv" 2>/dev/null | wc -l)" 0
echo "     memory: $(grep '^both' "$W/rss" | tr '\n' ' ')"

# --- a password's special letters: held on the base key, like everywhere ---
pixels() { magick "$W/$1.ppm" "$W/$2.ppm" -crop 1080x1000+0+1400 +repage -compose difference -composite -threshold 0 -format '%[fx:int(mean*w*h+0.5)]' info: 2>&1; }
hints() { grep -cE '^hint (a @|i 8|s #|t 5)$' "$W/keys-$1.txt"; }
ok "the corner hints show digits, no letters" "$(hints row) $(grep -cE '^hint . (ă|â|î|ș|ț)' "$W/keys-row.txt")" "4 0"
ok "a password field keeps those hints"    "$(hints pw)" 4
ok "holding s, Shift s and t's second choice reach the field" "$(tr -d '\n' <"$W/s121.txt")" "șȘ5"
ok "pressing a secret key shows no bubble" "$(pixels pw-idle pw-down)" 0
d=$(pixels pw-idle kbd-pw-popup)
[ "${d:-0}" -gt 0 ] 2>/dev/null && d=shows
ok "holding it shows the choices"          "$d" shows
ok "a removed language keeps its letters on a password field" "$(tr -d '\n' <"$W/s122.txt")" "ș"
ok "English only: no letters in the popup" "$(tr -d '\n' <"$W/s123.txt")" "#"

# --- shown and hidden by signal, twice each ---
fgeom() { grep -c "^GEOM $1 layer ns=phone-keyboard" "$W/all.log"; }
ok "SIGUSR1 shows it with no field"        "$(fgeom fup) $(st force 'secret=0')" "1 1"
ok "SIGUSR2 hides it"                      "$(fgeom fdown)" 0
ok "a password field still opens it"       "$(fgeom fsecret) $(st force-secret 'secret=1')" "1 1"
ok "SIGUSR2 hides it over that field"      "$(fgeom fhidden) $(fgeom fstill)" "0 0"

# --- Translate and languages ---
ok "the bar has a Translate button"        "$(grep -c '^translate ' "$W/keys-tr-closed.txt")" 1
ok "a password field has no Translate"     "$(grep -c '^translate ' "$W/keys-pw.txt")" 0
ok "nothing starts until it is used"       "$(cat "$W/kids-closed.txt")" 0
ok "no network until the list is opened"   "$(wc -l <"$W/reqs-opened")" 0
ok "the list shows every language offered" "$(st lang-list 'panel=4 .*rows=2')" 1
ok "reading the list downloads no language" "$(grep -c '/cdn/\|/packs/ro' "$W/reqs-listed")" 0
ok "the size shows before the download"    "$(grep -c '^Download Română, [0-9]* MB ' "$W/keys-lang-sel.txt")" 1
ok "after the tap it can be deleted"       "$(grep -c '^Delete Română ' "$W/keys-lang-done.txt")" 1
ok "it brings its words"                   "$(grep -c $'^mananc\tmănânc\t' "$W/merged-ui.tsv")" 1
ok "the new language is ready to use"      "$(st tr-ready 'panel=3 .*from=en to=ro')" 1
ok "one tap inserts the translation"       "$(tr -d '\n' <"$W/s141.txt")" "[en-ro] hi"
ok "no translator waits for typing to end" "$(cat "$W/kids-waiting.txt")" 0
ok "the translator is gone after the answer" "$(cat "$W/kids-after.txt")" 0
ok "swap turns the pair around and is kept" "$(st tr-swapped 'from=ro to=en') $(grep -c '^translate_from = ro$' "$W/config-swapped")" "1 1"
ok "a slow translator runs while it works" "$(cat "$W/kids-slow.txt")" 1
ok "a change of text ends it, with its children" "$(cat "$W/grp-edit.txt")" 0
ok "closing the panel ends it"             "$(cat "$W/grp-closed.txt") $(cat "$W/kids-closed2.txt")" "0 0"
ok "deleting removes the language"         "$(grep -c '^Download Română' "$W/keys-lang-removed.txt") $(ls "$W/data/phonegluewc/translate" 2>/dev/null | grep -c ro)" "1 0"
ok "deleting uses no network"              "$(cmp -s "$W/reqs-removed" "$W/reqs"; echo $?)" 0
ok "with none left it asks for one"        "$(st tr-gone 'panel=3 .*from= to=')" 1
echo "     memory: $(grep '^tr-' "$W/rss" | tr '\n' ' ')"

ok "turned: the button opens the Ctrl row" "$(grep -c '^state .*modrow=1' "$W/keys-land-mods.txt") $(grep -c '^Ctrl ' "$W/keys-land-mods.txt")" "1 1"
ok "turned: the emoji panel opens"         "$(grep -c '^state .*panel=1 .*tiles=[1-9]' "$W/keys-land-emoji.txt")" 1
# --- the strip under the keys, the hide area, the gear ---
tt() { tr -d '\n' <"$W/s$1.txt"; }
ok "the last line of the bottom row types" "$(tt 210)" " a"
ok "the strip types nothing"               "$(tt 211)" " a"
ok "a tap beside the hide area keeps it up" "$(fgeom cbeside)" 1
ok "a drag from the hide area keeps it up" "$(fgeom cdrag)" 1
ok "a tap on it hides the keyboard"        "$(fgeom cstart) $(fgeom chidden)" "1 0"
ok "it stays down on the same field"       "$(fgeom cstay)" 0
ok "a new tap in the same Qt field leaves it down (known limit)" "$(fgeom cretap)" 0
ok "the next focus brings it back"         "$(fgeom cback)" 1
ok "and it types"                          "$(tt 212)" " ab"
ok "the gear opens the keyboard page"      "$(cat "$W/settings-1.txt")" "keyboard"
ok "the gear hides and types nothing"      "$(fgeom cgear) $(tt 213)" "0  ab"
ok "it comes back after the gear"          "$(fgeom cgearback)" 1
ok "secret field: no gear, translate or clip" "$(grep -c '^gear \|^translate \|^clip ' "$W/keys-chev-secret.txt") $(st chev-secret 'secret=1')" "0 1"
ok "secret field: no hide area"            "$(fgeom csecret)" 1
ok "secret field: the gear's place hides it, opens nothing" "$(fgeom csecretgear) $(cmp "$W/settings.txt" "$W/settings-before" && echo same) $(tt 216)" "0 same ab"
ok "secret field: the next focus brings it back" "$(fgeom csecretback)" 1
ok "the hide key sits between clip and gear" "$(awk '$1=="clip"||$1=="hide"||$1=="gear"{printf "%s ", $1}' "$W/keys-chev.txt")" "clip hide gear "
ok "secret field: only the hide key on the right" "$(grep -c '^hide ' "$W/keys-chev-secret.txt")" 1
ok "the hide key hides and keeps the text" "$(fgeom khide) $(tt 214)" "0  ab"
ok "it comes back on the next field and types" "$(fgeom khideback) $(tt 215)" "1  abc"
ok "light theme: hide, back" "$(fgeom klight) $(fgeom klighthide) $(fgeom klightback)" "1 0 1"
ok "the hide key is drawn, dark and light" "$( { K=$SRC/tests/kbd-ppm.py; python3 -I $K ink "$W/kbd-hide-dark.ppm" 341 611 350 619; python3 -I $K ink "$W/kbd-hide-light.ppm" 341 611 350 619; python3 -I $K at "$W/kbd-hide-light.ppm" 2 868; } | paste -sd" ")" "1 1 e6e6e6"

# --- options; pixels compare captures at 2.75 per logical px ---
ppm() { python3 -I "$SRC/tests/kbd-ppm.py" "$@"; }
kh() { awk '$1=="size"{print $5}' "$W/keys-$1.txt"; }
ok "height small with a number row"        "$(kh opt-small) $(tt 220)" "269 qam1"
ok "height large follows"                  "$(kh opt-large) $(tt 221)" "287 qam1qm"
ok "height as a percentage"                "$(kh opt-pct) $(tt 222)" "224 qam1qmz"
ok "bad values: the same keys as no file"  "$(diff "$W/keys-opt-default.txt" "$W/keys-opt-bad.txt" | grep -v '^[<>] state\|^[-0-9]' | wc -l) $(tt 223)" "0 qam1qmzp"
ok "bad values: the same picture of the keys" "$(ppm diff "$W/kbd-opt-default.ppm" "$W/kbd-opt-bad.ppm" 0 650 392 872)" 0
bgof() { ppm at "$W/$1.ppm" 2 868; }
ok "light theme is light"                  "$(bgof kbd-opt-theme-light)" "e6e6e6"
ok "dark theme is black, strip too"        "$(bgof kbd-opt-theme-dark)" "000000"
ok "system: prefer-dark, default, unreadable" "$(bgof kbd-opt-system-dark) $(bgof kbd-opt-system-light) $(bgof kbd-opt-system-none)" "000000 e6e6e6 000000"
ok "accent colours the shift key"          "$(ppm has "$W/kbd-opt-accent-blue.ppm" 2f7fe0 0 750 60 810)" 1
ok "no key borders: the plate is gone"     "$(ppm at "$W/kbd-opt-flat.ppm" 6 670) $(ppm at "$W/kbd-opt-default.ppm" 6 670)" "000000 1c1c1c"
ok "corner hints off differs only in hints" "$(ppm diffq "$W/kbd-opt-default.ppm" "$W/kbd-opt-nohints.ppm" 0 660 392 860)" 1
ok "no bubble: no white above the key"     "$(ppm has "$W/kbd-opt-bubble.ppm" ffffff 200 645 212 652) $(ppm has "$W/kbd-opt-nobubble.ppm" ffffff 200 645 212 652)" "1 0"
lc() { tr -d '\n' <"$W/s$1.txt" | python3 -Ic 'import sys; print(sys.stdin.read()[-1])'; }
ok "long press short, normal, normal later, long" "$(lc 224) $(lc 225) $(lc 226) $(lc 227)" "ș s ș s"
ok "key sound: plays on ring"              "$(cmp -s "$W/sound-normal0.txt" "$W/sound-normal.txt" || echo yes)" yes
ok "key sound: quiet on silent and vibrate" "$(cmp "$W/sound-silent0.txt" "$W/sound-silent.txt" && cmp "$W/sound-vibrate0.txt" "$W/sound-vibrate.txt" && echo same)" same
echo "     memory by theme: $(grep '^theme-' "$W/rss" | tr '\n' ' ')"

ok "the keyboard is alive at each script's end" "$(grep -c DEAD "$W/kalive.txt") $(grep -vc DEAD "$W/kalive.txt")" "0 $(ls "$W"/script* | wc -l)"
for f in "$W"/kpids*; do ok "one keyboard for the whole of $(basename "$f")" "$(sort -u "$f" | wc -l)" 1; done
ok "no sanitizer report"                   "$(grep -c 'AddressSanitizer\|runtime error' "$W/all.log")" 0
ls "$W"/core.* >/dev/null 2>&1 && { echo "FAIL core files"; fails=$((fails+1)); }
if [ -n "${TOUCH_VERBOSE:-}" ]; then for i in 1 2 3 4 5 6 7 8 9; do echo "s$i: $(step $i)"; done; cat "$W/keys.txt" | head -3; fi
[ "$fails" = 0 ] && echo "all keyboard checks passed"
exit "$fails"
