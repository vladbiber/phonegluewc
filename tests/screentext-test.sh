#!/bin/bash
# Screen text end to end, headless, with a fake touchscreen. SHOTS=DIR keeps PNGs.
# Without tesseract (ron and eng) only the "no reader" checks run and the result is SKIPPED, exit 77;
# ALLOW_SKIP=1 turns that into 0. OCR_DIR=DIR adds a tesseract to PATH. TRANSLATE=stub fakes the translator.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
command -v tesseract >/dev/null || { [ -n "${OCR_DIR:-}" ] && PATH="$OCR_DIR:$PATH"; }
fails=0
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-st.XXXXXX")
. "$SRC/tests/sandbox.sh"
MODELS=${PHONETEXT_MODELS:-${XDG_DATA_HOME:-$HOME/.local/share}/phonegluewc/translate}
SHOTS=${SHOTS:-$W/shots}; mkdir -p "$SHOTS" "$W/bin"
BUILD=$W/build; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/ 2>/dev/null; rm -f "$BUILD"/phonegluewc.o
python3 "$SRC/tests/touch-hook.py" "$BUILD/phonegluewc.c"
make -C "$BUILD" phonegluewc ${SAN:+CC="cc -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"} >/dev/null 2>&1 || { echo "build failed"; exit 1; }
make -C "$SRC/keyboard" phonekbd >/dev/null 2>&1 || { echo "keyboard build failed"; exit 1; }
make -C "$SRC/screentext" >/dev/null 2>&1 || { echo "screentext build failed"; exit 1; }
make -C "$SRC/tests" wshot >/dev/null 2>&1
mkdir -p "$W/cfg/phonegluewc" "$W/state" "$W/data"
printf 'remember_layout = false\noutput = * mode=1080x2400 scale=2.75\n' > "$W/cfg/phonegluewc/config.conf"

printf 'The quick brown fox jumps over the lazy dog.\n\nThe train leaves at seven and it is a nice day.\n' >"$W/en.txt"
printf 'Ana are mere și pere în grădină.\n\nAstăzi este o zi frumoasă și trenul pleacă la ora șapte.\n' >"$W/ro.txt"

# the browser is a stub: Search must hand it the query and nothing else
cat >"$W/bin/xdg-open" <<STUB
#!/bin/sh
printf '%s\n' "\$1" >>"$W/opened.txt"
STUB
chmod +x "$W/bin/xdg-open"
if [ "${TRANSLATE:-}" = stub ]; then
	cat >"$W/bin/phonetext-translate" <<STUB
#!/bin/sh
sed 's/^/[\$1-\$2] /' | sed "s/\\\$1/\$1/; s/\\\$2/\$2/"
STUB
	chmod +x "$W/bin/phonetext-translate"
fi
cat >"$W/shot.sh" <<SHOT
#!/bin/sh
exec "$SRC/tests/wshot" "$W/\$1.ppm"
SHOT
cat >"$W/paste.sh" <<PASTE
#!/bin/sh
wl-paste --no-newline >"$W/\$1.txt"
PASTE
cat >"$W/alive.sh" <<ALIVE
#!/bin/sh
p=\$(cat "$W/pid")
echo "\$1 \$(pgrep -P \$p -x phonetext | wc -l) \$(pgrep -x tesseract -P \$p | wc -l)" >>"$W/alive.txt"
ALIVE
cat >"$W/rss.sh" <<RSS
#!/bin/sh
p=\$(pgrep -P \$(cat "$W/pid") -x phonetext)
awk '/VmRSS|VmHWM/{print \$1,\$2}' /proc/\$p/status | tr '\n' ' ' >>"$W/rss.txt"; echo >>"$W/rss.txt"
RSS
cat >"$W/idle.sh" <<IDLE
#!/bin/sh
p=\$(cat "$W/pid")
echo "compositor \$(awk '/VmRSS/{print \$2}' /proc/\$p/status)" >>"$W/idle.txt"
IDLE
chmod +x "$W"/*.sh

# $1 en|ro, $2 background, $3 text colour, $4 keyboard command
run() {
cat >"$W/page.sh" <<PAGE
#!/bin/sh
PAGE_FILE=$W/${PAGE_NAME:-$1}.txt PAGE_BG=$2 PAGE_FG=$3 QT_QUICK_BACKEND=software exec qs -p $SRC/tests/screentext-page
PAGE
chmod +x "$W/page.sh"
python3 "$SRC/tests/screentext-script.py" "$W" "${CASE:-$1}" ${OCR_WAIT:-15000} ${TR_WAIT:-12000} "$1" >"$W/script"
COMP=$BUILD/phonegluewc
SANDBOX_PATH="$W/bin:$BUILD:$SRC/keyboard:$SRC/screentext"
comp_start QT_QUICK_BACKEND=software PHONEGLUEWC_SHELL= PHONEGLUEWC_KEYBOARD="$4" PHONEKBD_DATA="$SRC/keyboard/data" \
	PHONETEXT_DUMP="$W/dump-$1.txt" PHONETEXT_MODELS="$MODELS" ${TESSDATA_PREFIX:+TESSDATA_PREFIX="$TESSDATA_PREFIX"} \
	PHONEGLUEWC_FAKETOUCH="$W/script"
comp_wait 1800
comp_stop
cat "$W/gw.log" >>"$W/all.log"
[ -n "${ST_LOG:-}" ] && cat "$W/gw.log" >>"$ST_LOG"
}
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', wanted '$3'"; fails=$((fails+1)); fi; }
# no reader at all, then one without the languages: both must say so and leave cleanly
real=$(readlink "$W/sysbin/tesseract" 2>/dev/null)
rm -f "$W/sysbin/tesseract"
PAGE_NAME=en CASE=noocr run missing "#0b0b0b" "#f0f0f0" ""
printf '#!/bin/sh\nexit 1\n' >"$W/bin/tesseract"; chmod +x "$W/bin/tesseract"
PAGE_NAME=en CASE=noocr run nolang "#0b0b0b" "#f0f0f0" ""
rm -f "$W/bin/tesseract"
ok "says on screen that tesseract is missing"  "$(grep '^message' "$W/dump-missing.txt" 2>/dev/null)" "message Install tesseract to read text"
ok "says on screen that the languages are missing" "$(grep '^message' "$W/dump-nolang.txt" 2>/dev/null)" "message Install tesseract's ron and eng data"
ok "a tap leaves when there is no reader"      "$(grep '^aftermissing' "$W/alive.txt")" "aftermissing 0 0"
ok "a tap leaves when the data is missing"     "$(grep '^afternolang' "$W/alive.txt")" "afternolang 0 0"
copyshots() { for f in "$W"/*.ppm; do [ -e "$f" ] && magick "$f" "$SHOTS/$(basename "${f%.ppm}").png"; done; }
why=
if [ -z "$real" ]; then
	why="tesseract is not on PATH"
else
	ln -sf "$real" "$W/sysbin/tesseract"
	langs=$(sandbox ${TESSDATA_PREFIX:+TESSDATA_PREFIX="$TESSDATA_PREFIX"} tesseract --list-langs 2>&1)
	printf '%s\n' "$langs" | grep -qx ron && printf '%s\n' "$langs" | grep -qx eng ||
		why="tesseract has no ron and eng data (TESSDATA_PREFIX=${TESSDATA_PREFIX:-unset}): $(printf '%s' "$langs" | head -2 | tr '\n' ' ')"
fi
if [ -n "$why" ]; then
	copyshots
	echo "SKIPPED, the reading checks did not run: $why"
	[ "$fails" = 0 ] || exit 1
	[ -n "${ALLOW_SKIP:-}" ] && exit 0
	exit 77
fi
run en "#0b0b0b" "#f0f0f0" ""
run ro "#ffffff" "#111111" phonekbd
printf '#!/bin/sh\nexit 1\n' >"$W/bin/phonetext-translate"; chmod +x "$W/bin/phonetext-translate"
PAGE_NAME=en CASE=trfail run trfail "#0b0b0b" "#f0f0f0" ""
# what a missing language package looks like: phonekbd-lang leaves no tool or no model
printf '#!/bin/sh\nexit 127\n' >"$W/bin/phonetext-translate"
PAGE_NAME=en CASE=trfail run trnolang "#0b0b0b" "#f0f0f0" ""
copyshots

words() { awk '$1=="word"{print $7}' "$W/dump-$1.txt" | awk 'NR==FNR{} !s[$0]++' | head -"$2" | tr '\n' ' ' | sed 's/ $//'; }
ok "a slow drag still opens the overview"  "$(grep -c '^FT slowdrag .*overview=1' "$W/all.log")" 1
ok "the drag did not start screen text"    "$(grep '^afterdrag' "$W/alive.txt")" "afterdrag 0 0"
ok "a missing language says where to add it" "$(grep '^message' "$W/dump-trnolang.txt" 2>/dev/null | head -1)" "message Add a language in the keyboard's Translate panel"
ok "reads light text on dark"              "$(words en 9)" "The quick brown fox jumps over the lazy dog."
ok "reads dark Romanian text on white"     "$(words ro 7)" "Ana are mere și pere în grădină."
ok "copies the selection"                  "$(cat "$W/clip1.txt" 2>/dev/null)" "The quick brown fox jumps"
ok "tap outside exits"                     "$(grep '^aftertap ' "$W/alive.txt")" "aftertap 0 0"
ok "search opens the browser with the query" "$(cat "$W/opened.txt" 2>/dev/null)" "https://www.google.com/search?q=The%20quick"
ok "search exits"                          "$(grep '^aftersearch' "$W/alive.txt")" "aftersearch 0 0"
ok "swiping the bar exits"                 "$(grep '^afterswipe' "$W/alive.txt")" "afterswipe 0 0"
ok "the keyboard goes away for the freeze" "$(grep -c '^FT frozen .*kbd=0' "$W/all.log")" 1
ok "the keyboard was up before it"         "$(grep -c '^FT kbdup .*kbd=1' "$W/all.log")" 1
ok "Copy stays on screen after a failed translation" "$(cat "$W/clip3.txt" 2>/dev/null)" "The quick brown fox jumps"
ok "copies Romanian with diacritics"       "$(head -1 "$W/clip2.txt" 2>/dev/null)" "Ana are mere și pere în grădină."
echo "     en: $(grep -E '^state' "$W/dump-en.txt" | head -3 | tr '\n' ';')"
echo "     ro: $(grep -E '^(state|dst)' "$W/dump-ro.txt" | head -4 | tr '\n' ';')"
echo "     en translation: $(grep '^dst' "$W/dump-en.txt" | head -2 | tr '\n' ';')"
[ -s "$W/rss.txt" ] && echo "     phonetext: $(head -1 "$W/rss.txt")"
[ "$fails" = 0 ] && echo "all screen text checks passed"
exit "$fails"
