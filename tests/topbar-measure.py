#!/usr/bin/env python3
# topbar-measure.py FILE.ppm SCALE: bar height, then the top and bottom gap of each thing in it
import sys
d = open(sys.argv[1], 'rb').read(); scale = float(sys.argv[2])
parts = d.split(b'\n', 3); w, h = map(int, parts[1].split()); px = parts[3]
p = lambda x, y: px[(y * w + x) * 3: (y * w + x) * 3 + 3]
# the bar ends where the blue wallpaper starts
bar = 0
while bar < h and p(3, bar)[2] < 100: bar += 1
print(f"bar={bar}")
lit = lambda x: any(max(p(x, y)) > 45 for y in range(bar))
gap = int(3 * scale) + 1
x = 0; runs = []
while x < w:
    if lit(x):
        s = x; last = x
        while x < w and x - last <= gap:
            if lit(x): last = x
            x += 1
        runs.append((s, last))
    else: x += 1
green = [x for x in range(w) for y in range(bar) if p(x, y)[1] > 150 and p(x, y)[0] < 80]
clockend = runs[0][1] if runs else 0
print(f"clockx={runs[0][0] if runs else -1} clockend={clockend} green={min(green) if green else -1}")
for a, b in runs:
    rows = [y for y in range(bar) if any(max(p(x, y)) > 45 for x in range(a, b + 1))]
    t = rows[0]; u = bar - 1 - rows[-1]
    print(f"item x={a}-{b} h={rows[-1]-t+1} top={t} bottom={u} off={abs(t-u)}")
