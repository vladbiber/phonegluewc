#!/bin/bash
# Language downloads against a local fake registry; the real network is never used. No compositor needed.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/pg-lang.XXXXXX")
trap '[ -n "${srv:-}" ] && kill "$srv" 2>/dev/null; rm -rf "$W"' EXIT
ulimit -c 0
# the helper edits the keyboard config: never the real one
export XDG_CONFIG_HOME="$W/cfg"
mkdir -p "$W/cfg/phonekbd"
make -C "$SRC/keyboard" phonekbd-lang >/dev/null 2>&1 || { echo "build failed"; exit 1; }
python3 "$SRC/tests/fake-lang-server.py" "$W/srv" "$SRC/keyboard/packs" >"$W/reqs" 2>/dev/null & srv=$!
for i in $(seq 50); do [ -s "$W/srv/port" ] && break; sleep 0.1; done
[ -s "$W/srv/port" ] || { echo "FAIL the fake server did not start"; exit 1; }
base=http://127.0.0.1:$(cat "$W/srv/port")
L=$SRC/keyboard/phonekbd-lang
lang() { env HOME="$W/home" XDG_DATA_HOME="$W/data" XDG_CACHE_HOME="${CACHE:-$W/cache}" PHONEKBD_DATA="$SRC/keyboard/data" PHONEKBD_REGISTRY="${REG:-$base/records}" PHONEKBD_CDN="$base/cdn/" PHONEKBD_PACKS="${PACKS_URL:-$base/packs}" "$L" "$@"; }
# in the background, so that its pid is the helper's own
langbg() { exec env HOME="$W/home" XDG_DATA_HOME="$W/data" XDG_CACHE_HOME="$W/cache" PHONEKBD_DATA="$SRC/keyboard/data" PHONEKBD_REGISTRY="$base/records" PHONEKBD_CDN="$base/cdn/" PHONEKBD_PACKS="$base/packs" "$L" "$@"; }
M=$W/data/phonegluewc/translate
fails=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', wanted '$3'"; fails=$((fails+1)); fi; }
nothing() { ls -A "$M" | grep -c "$1\|stage"; }
reqs() { wc -l <"$W/reqs"; }

# --- the base state ---
ok "English only: nothing installed" "$(ls -A "$W/data" 2>/dev/null | wc -l)" 0
lang list >"$W/list"
ok "the list says it is online"      "$(head -1 "$W/list")" "S online"
ok "a language with models is offered" "$(grep -c "^L ro	.*	both	[0-9]*	available	1$" "$W/list")" 1
ok "a separate vocabulary is unavailable, before any download" "$(grep -c '^L ja	.*	none	0	unavailable' "$W/list")" 1
ok "a name with a path in it is dropped" "$(grep -c 'evil' "$W/list")" 0
ok "a location outside the host is dropped" "$(grep -c '^L tr	' "$W/list")" 0
ok "an alpha model is dropped"       "$(grep -c '^L al	' "$W/list")" 0
ok "reading the list downloads nothing else" "$(grep -c '/cdn/\|/packs/ro' "$W/reqs")" 0
lang install ../evil >"$W/o"
ok "a bad code is refused"           "$(grep -c '^E Bad language' "$W/o") $(ls -A "$W/data/phonegluewc" 2>/dev/null | wc -l)" "1 0"

# --- add and remove ---
n=$(reqs)
lang install ro >"$W/o"; rc=$?
ok "install finishes"                "$rc $(tail -1 "$W/o")" "0 D"
ok "progress is reported to the total" "$(awk '/^P /{d=$2; t=$3} END{print (d==t && t>0)}' "$W/o")" 1
ok "both directions are in place"    "$(ls "$M/en-ro" "$M/ro-en" | grep -c 'model\|lex\|vocab\|layers')" 8
ok "the decoder depth was read"      "$(cat "$M/en-ro/layers")" 2
ok "no scratch folder stays"         "$(ls -A "$M" | grep -c stage)" 0
ok "its words join the English ones" "$(awk -F'\t' '$1=="the"||$2=="mănânc"' "$W/data/phonekbd/words.tsv" | wc -l)" 2
ok "its letters arrive"              "$(grep -c 'ș' "$W/data/phonekbd/letters")" 1
ok "the list shows it installed"     "$(lang list | grep -c '^L ro	.*installed')" 1
n=$(reqs)
lang remove ro >"$W/o"
ok "remove finishes"                 "$(tail -1 "$W/o")" "D"
ok "the models go"                   "$(ls -A "$M" | grep -c ro)" 0
ok "the words go"                    "$(cat "$W/data/phonekbd/words.tsv" 2>/dev/null | cut -f2 | grep -cx 'mănânc')" 0
ok "the password letters stay"       "$(grep -c 'ș' "$W/data/phonekbd/password-letters")" 1
ok "remove uses no network"          "$(reqs)" "$n"

# --- a pack index that answers 404: the list still works, translation only ---
CACHE=$W/cache404 PACKS_URL=$base/no-such-tag lang list >"$W/list404"; r=$?
ok "a 404 on the index leaves the list online" "$r $(head -1 "$W/list404")" "0 S online"
ok "a 404: the language is there with no pack" "$(grep -c "^L ro	.*	available	0$" "$W/list404")" 1
ok "a 404 asked for the index"       "$(grep -c '/no-such-tag/index.tsv' "$W/reqs")" 1

# --- which languages predict ---
K=$W/cfg/phonekbd/config
lang install ro >/dev/null
ok "no key: none is created"         "$(ls -A "$W/cfg/phonekbd" | wc -l)" 0
ok "a shared word names both"        "$(awk -F'\t' '$1=="a"&&$2==""{print $4}' "$W/data/phonekbd/words.tsv")" "en,ro"
ok "a pack word names its language"  "$(awk -F'\t' '$2=="mănânc"{print $4}' "$W/data/phonekbd/words.tsv")" "ro"
ok "an English word names English"   "$(awk -F'\t' '$1=="because"{print $4}' "$W/data/phonekbd/words.tsv")" "en"
ok "next words are labelled by language" "$(grep -c ' |ro ' "$W/data/phonekbd/bigrams.tsv" | awk '{print ($1>0)}')" 1
lang remove ro >/dev/null
printf 'learn = off\npredict_languages = en\nsound = on\n' >"$K"
lang install ro >/dev/null
ok "install adds to the key, others stay" "$(tr '\n' '/' <"$K")" "learn = off/predict_languages = en ro/sound = on/"
lang remove ro >/dev/null
ok "remove drops it from the key"    "$(tr '\n' '/' <"$K")" "learn = off/predict_languages = en/sound = on/"
printf 'predict_languages =\n' >"$K"
lang remove ro >/dev/null
ok "removing what is not there changes nothing" "$(cat "$K")" "predict_languages ="
rm -f "$K"
mkdir -p "$W/data/phonekbd/langs/ro" "$W/data/phonekbd/langs/fr"
cp "$SRC/keyboard/packs/ro/"* "$W/data/phonekbd/langs/ro/"
printf 'a\t\t100\tr\nzzfrword\t\t100\tr\n' >"$W/data/phonekbd/langs/fr/words.tsv"
printf 'the\tzzfrword\n' >"$W/data/phonekbd/langs/fr/bigrams.tsv"
lang merge
ok "three sources on one word"       "$(awk -F'\t' '$1=="a"&&$2==""{print $4}' "$W/data/phonekbd/words.tsv" | tr , '\n' | sort | tr '\n' ,)" "en,fr,ro,"
ok "a third language has its own label" "$(grep -P '^the\t' "$W/data/phonekbd/bigrams.tsv" | grep -c '|fr zzfrword')" 1
rm -rf "$W/data/phonekbd"
lang list >/dev/null

# --- failures leave nothing ---
lang list >/dev/null
lang install bh >"$W/o"
ok "bad hash: rejected"              "$(grep -c '^E A file failed' "$W/o") $(nothing bh)" "1 0"
lang install ct >"$W/o"
ok "a dropped connection: nothing half there" "$(grep -c '^E ' "$W/o") $(nothing ct)" "1 0"
lang install ug >"$W/o"
ok "an unsupported model: rejected after its check" "$(grep -c '^E This language' "$W/o") $(nothing ug)" "1 0"
lang install pk >"$W/o"
ok "a malformed word list: rejected" "$(grep -c '^E ' "$W/o") $(nothing pk) $(ls "$W/data/phonekbd/langs" 2>/dev/null | grep -c pk)" "1 0 0"
ok "the failure left the old words alone" "$(cat "$W"/data/phonekbd/words.tsv "$W"/data/phonekbd/langs/*/words.tsv 2>/dev/null | grep -c 'not a word')" 0

# --- cancel, and a kill in the middle ---
( langbg install sl ) >"$W/o" & p=$!
for i in $(seq 40); do [ -d "$M/.stage-sl" ] && break; sleep 0.1; done
sleep 0.5
ok "a download is in progress"       "$(ls -A "$M" | grep -c stage-sl)" 1
kill -TERM "$p"; wait "$p"
ok "cancel: says so, nothing stays"  "$(grep -c '^E Cancelled' "$W/o") $(nothing sl)" "1 0"
ok "cancel leaves no curl behind"    "$(pgrep -fc "$base/cdn/m/en-sl" || true)" 0
( langbg install sl ) >"$W/o" & p=$!
for i in $(seq 40); do [ -d "$M/.stage-sl" ] && break; sleep 0.1; done
sleep 0.5
kill -KILL "$p"; wait "$p" 2>/dev/null
pkid=$(pgrep -f "$base/cdn/m/en-sl" || true); [ -n "$pkid" ] && kill $pkid
ok "killed: not counted as installed" "$(lang list | grep -c '^L sl	.*installed')" 0
ok "killed: the next run clears the scratch" "$(ls -A "$M" | grep -c stage-sl)" 0

# --- offline ---
lang install ro >/dev/null
REG=http://127.0.0.1:9/records lang list >"$W/o"
ok "offline with a saved list says so" "$(head -1 "$W/o")" "S cached"
CACHE=$W/cache2 REG=http://127.0.0.1:9/records lang list >"$W/o"
ok "offline without one says so"     "$(head -1 "$W/o")" "S offline"
ok "offline it lists what is installed" "$(grep -c '^L ro	' "$W/o")" 1
lang remove ro >/dev/null

# --- the translator wrapper, with a stand-in for the engine ---
T=$W/models; mkdir -p "$T/en-de" "$T/ro-en"; touch "$T/en-de/model" "$T/ro-en/model"; echo 4 >"$T/en-de/layers"; echo 'x;y' >"$T/ro-en/layers"
cat >"$T/slimt-cli" <<STUB
#!/bin/sh
echo "\$*" >>$W/cli.log
printf 'a\nb\nc\nd\n'
while read -r l; do echo "\$l>\$2"; done
echo
STUB
chmod +x "$T/slimt-cli"
tr_() { echo hi | PHONETEXT_MODELS=$T sh "$SRC/screentext/phonetext-translate" "$@"; }
ok "a direct pair"                   "$(tr_ en de | sed "s,$T/,,g")" "hi>en-de"
ok "the model's decoder depth is passed" "$(grep -c 'decoder-layers 4' "$W/cli.log")" 1
ok "a bad depth file falls back"     "$(tr_ ro en >/dev/null; grep -c 'decoder-layers 2' "$W/cli.log")" 1
ok "a pair through English"          "$(tr_ ro de | sed "s,$T/,,g")" "hi>ro-en>en-de"
tr_ de ro >/dev/null; ok "no model is exit 127" "$?" 127
tr_ '../x' de >/dev/null 2>&1; ok "a bad code is exit 2" "$?" 2

ok "the server saw only what was asked" "$(grep -vc '^/records$\|^/packs/\|^/cdn/\|^/no-such-tag/' "$W/reqs")" 0
[ "$fails" = 0 ] && echo "all language checks passed"
exit "$fails"
