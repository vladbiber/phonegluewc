#!/bin/sh
# Run once by hand: builds the translator and fetches the two models. Nothing else uses the network.
# --binary-only builds just the translator; the keyboard's language list fetches the models.
# Needs git, cmake, ninja, a C++ compiler and pcre2 headers.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
d=${PHONETEXT_MODELS:-${XDG_DATA_HOME:-$HOME/.local/share}/phonegluewc/translate}
base=https://firefox-settings-attachments.cdn.mozilla.net/main-workspace/translations-models
commit=9f0b1a20d14871cc94dbe65b7a3df128e5e81f55
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
mkdir -p "$d"

fetch() { # name, url id, sha256
	if ! echo "$3  $d/$1" | sha256sum -c >/dev/null 2>&1; then
		echo "fetching $1"
		curl -fsSL -o "$w/$1" "$base/$2"
		echo "$3  $w/$1" | sha256sum -c >/dev/null || { echo "bad checksum: $1" >&2; exit 1; }
		mv "$w/$1" "$d/$1"
	fi
}
if [ "${1:-}" != --binary-only ]; then
fetch vocab.enro.spm 41f055b0-76a8-4dae-a18c-44d8c1293bf0.spm d89eedf6cbbcb30d7ed4b0b092189196ac2b010ec0c3ede33a6676b17ea1c95e
fetch model.enro.intgemm.alphas.bin f12620b2-d705-4d7a-82e0-e16f0aa29d74.bin aa98c415e5beb1c5ee2f7d2508a3bbba949be223d7d9e5e1788ad0ae8598dda5
fetch lex.50.50.enro.s2t.bin 0b9db082-327d-4ab0-bad6-17e7631ec163.bin 508bce64a8bc906a99043ad2f4855b4662e06f8827c1c6a75ab83181b4f17f81
fetch vocab.roen.spm 6cfea415-f0ff-47d7-ac93-5450bc92f0aa.spm 2a690fbcd1b79bc9b99c43d582252720e0900245c82ecc813c8eb05cf063fd0c
fetch model.roen.intgemm.alphas.bin 5e717d94-7c4e-4fd6-af34-63e3c29682af.bin e7542557fc6dbafacddae7b48e67fcdb07bd67b3fb55a76139edf366eca5dbdb
fetch lex.50.50.roen.s2t.bin 6661bfc3-fd0e-47ae-ab65-4c19adaa5ab0.bin d242745eadff6f345784fccf1d58046061501b28c8190ba5912a9da5f056cd2f
fi

if [ ! -x "$d/slimt-cli" ]; then
	git clone -q https://github.com/jerinphilip/slimt "$w/slimt"
	git -C "$w/slimt" checkout -q "$commit"
	git -C "$w/slimt" submodule -q update --init --recursive --depth 1
	# position in the decoder, bias under the ruy shortlist, and -Werror on new compilers
	git -C "$w/slimt" apply "$here/slimt-fixes.patch"
	cmake -S "$w/slimt" -B "$w/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DWITH_BLAS=OFF -DWITH_GEMMOLOGY=OFF -DWITH_RUY=ON -DBUILD_SHARED=OFF \
		-DCMAKE_CXX_FLAGS='-include cstdint -Wno-error' >/dev/null
	ninja -C "$w/build" slimt-cli >/dev/null
	cp "$w/build/app/slimt-cli" "$d/"
fi
[ "${1:-}" != --binary-only ] || { echo "translator ready in $d"; exit 0; }
out=$(echo "Good morning." | PHONETEXT_MODELS="$d" sh "$here/phonetext-translate" en ro)
[ -n "$out" ] || { echo "translator did not answer" >&2; exit 1; }
echo "ready in $d: Good morning -> $out"
