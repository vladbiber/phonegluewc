#!/bin/sh
# Renders the generated wallpapers (CC0, by the project) into this directory. Needs ImageMagick 7.
set -eu
cd "$(dirname "$0")"
S=1080x2400
J="-seed 7 -strip -colorspace sRGB -sampling-factor 4:2:0 -interlace JPEG -quality 90"
# the grain also breaks up JPEG banding in the gradients
grain() { echo "-attenuate $1 +noise Gaussian"; }

magick -size $S xc:'#0c0c0c' $(grain 0.12) -colorspace gray $J 01-black-grain.jpg

magick -size $S gradient:'#05060a-#1c2433' $(grain 0.05) $J 02-dark-gradient.jpg

# a dot grid that fades out downward, one red dot
awk 'BEGIN {
	print "fill white"
	for (y = 60; y < 2400; y += 54) for (x = 54; x < 1080; x += 54) {
		a = 0.55 - y / 2400 * 0.5
		printf "fill rgba(255,255,255,%.3f) circle %d,%d %d,%d\n", a, x, y, x + 4, y
	}
	print "fill #d71921 circle 864,330 873,330"
}' >dots.mvg
magick -size $S xc:black -draw @dots.mvg $J 03-dot-matrix.jpg
rm -f dots.mvg

# drawn small and blurred, then scaled up: same look, a fraction of the blur cost
magick -size 270x600 xc:'#07080b' \
	-fill '#1d2c4d' -draw 'circle 60,140 60,290' \
	-fill '#3a2140' -draw 'circle 230,330 230,460' \
	-fill '#123a3a' -draw 'circle 90,520 90,610' \
	-blur 0x60 -resize $S! $(grain 0.06) $J 04-soft-shapes.jpg

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# fields OUT BACKGROUND DRAW...: big soft colour fields, blurred small with mirrored edges so no dark rim
fields() {
	out=$1 bg=$2; shift 2
	magick -size 270x600 "$bg" "$@" -virtual-pixel mirror -blur 0x45 -resize $S! $(grain 0.06) $J "$out"
}
fields 07-dusk.jpg gradient:'#0a0f3a-#24104a' \
	-fill '#2f46e0' -draw 'circle 40,90 40,250' -fill '#8a2fd0' -draw 'circle 250,280 250,420' \
	-fill '#ea4c93' -draw 'circle 50,500 50,600' -fill '#ff8aa6' -draw 'circle 230,600 230,660'
fields 14-sunrise.jpg gradient:'#4a0b24-#ff9a45' \
	-fill '#c41f45' -draw 'circle 230,80 230,230' -fill '#ff5533' -draw 'circle 40,300 40,430' \
	-fill '#ffad42' -draw 'circle 220,470 220,580' -fill '#ffe0a0' -draw 'circle 60,620 60,700'
fields 15-teal.jpg gradient:'#05303a-#0b5a48' \
	-fill '#0aa6b0' -draw 'circle 220,110 220,250' -fill '#1b6fd8' -draw 'circle 30,300 30,420' \
	-fill '#2fc48a' -draw 'circle 240,480 240,590' -fill '#b4f2c8' -draw 'circle 70,640 70,720'
# aurora: tall slanted curtains
curtains() { printf 'push graphic-context rotate -18 fill %s ellipse %s 0,360 pop graphic-context\n' "$@"; }
curtains '#14b88c' '-60,250 30,200' '#1fe0a8' '-10,300 22,230' '#1a8ed8' '40,270 30,210' '#2fd6c0' '100,300 26,240' '#6a44dc' '160,330 30,200' '#c24ebf' '210,360 20,150' >"$T/a.mvg"
magick -size 270x600 xc:'#03050d' -draw @"$T/a.mvg" -virtual-pixel mirror -blur 0x22 -resize $S! $(grain 0.06) $J 05-aurora-dark.jpg
curtains '#b2f0dc' '-60,250 30,200' '#c9f5e6' '-10,300 22,230' '#bcd6ff' '40,270 30,210' '#cfe9f7' '100,300 26,240' '#dcc8fa' '160,330 30,200' '#ffd6c4' '210,360 20,150' >"$T/a.mvg"
magick -size 270x600 xc:'#f5f6fb' -draw @"$T/a.mvg" -virtual-pixel mirror -blur 0x22 -resize $S! $(grain 0.04) $J 20-aurora-light.jpg

# ribbons OUT BACKGROUND SHADOW then per ribbon: Y0 THICKNESS AMPLITUDE WAVELENGTH PHASE SLOPE COLOUR1 COLOUR2
# drawn at 2x (2160x4800) for smooth edges, each over a soft shadow, then scaled down
ribbons() {
	out=$1 shadow=$3
	magick -size 2160x4800 "$2" "$T/acc.png"
	shift 3
	while [ $# -ge 8 ]; do
		awk -v y0="$1" -v th="$2" -v a="$3" -v l="$4" -v p="$5" -v s="$6" 'BEGIN {
			printf "polygon"
			for (x = -240; x <= 2400; x += 12) printf " %d,%.1f", x, y0 + s * x + a * sin(6.2832 * x / l + p)
			for (x = 2400; x >= -240; x -= 12) printf " %d,%.1f", x, y0 + th + s * x + a * 0.7 * sin(6.2832 * x / (l * 1.35) + p + 1.1)
		}' >"$T/r.mvg"
		magick -size 2160x4800 xc:black -fill white -draw @"$T/r.mvg" "$T/m.png"
		magick "$T/m.png" -resize 25% -blur 0x10 -resize 2160x4800! -roll +0+40 -evaluate multiply "$shadow" "$T/s.png"
		magick "$T/acc.png" \( -size 2160x4800 xc:black \( "$T/s.png" \) -alpha off -compose copy_opacity -composite \) -compose over -composite \
			\( -size 2160x4800 -define gradient:direction=east gradient:"$7-$8" \( "$T/m.png" -evaluate multiply 0.88 \) -alpha off -compose copy_opacity -composite \) -compose over -composite "$T/acc.png"
		shift 8
	done
	magick "$T/acc.png" -filter Lanczos -resize $S! $(grain 0.05) $J "$out"
}
ribbons 06-ribbons-dark.jpg gradient:'#050a1c-#0a1633' 0.55 \
	1100 760 260 3600 0.4 -0.35 '#173a9c' '#2b5fd8' \
	1750 660 220 3000 1.6 -0.30 '#2a5fe0' '#6a9cff' \
	2400 600 200 2600 2.6 -0.26 '#0f2d78' '#3c74ea' \
	3000 1100 180 3200 3.4 -0.22 '#1d48b8' '#9cc0ff'
ribbons 21-ribbons-light.jpg gradient:'#f4f1fc-#e3ddf5' 0.18 \
	1100 760 260 3600 0.4 -0.35 '#d9cdf8' '#c3b2f0' \
	1750 660 220 3000 1.6 -0.30 '#c5b6f2' '#e8e1ff' \
	2400 600 200 2600 2.6 -0.26 '#b2a3ea' '#d6ccfa' \
	3000 1100 180 3200 3.4 -0.22 '#cfc3f6' '#f5f1ff'

magick -size $S gradient:'#f6f5f2-#d4d6da' $(grain 0.05) $J 22-light-gradient.jpg
