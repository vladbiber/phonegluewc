#!/usr/bin/env python3
# battery-measure.py FILE.ppm: pill box and ink box of the rightmost thing in the bar, in device pixels
import sys
def ppm(path):
    d = open(path, 'rb').read(); t = []; i = 0
    while len(t) < 4:
        while d[i] in b' \n\t': i += 1
        j = i
        while d[j] not in b' \n\t': j += 1
        t.append(d[i:j]); i = j
    return int(t[1]), int(t[2]), d[i + 1:]
def main(path, bar):
    w, h, px = ppm(path)
    lum = lambda x, y: max(px[(y * w + x) * 3: (y * w + x) * 3 + 3])
    bright = lambda x: any(lum(x, y) > 45 for y in range(bar))
    x = w - 1
    while not bright(x): x -= 1
    r = x
    while bright(x): x -= 1
    l = x + 1
    rows = [y for y in range(bar) if any(lum(x, y) > 45 for x in range(l, r + 1))]
    t, b = rows[0], rows[-1]
    # the neighbour on the left, for the height
    while not bright(x): x -= 1
    nr = x
    while bright(x) and r - x < 400: x -= 1
    nrows = [y for y in range(bar) if any(lum(q, y) > 45 for q in range(x + 1, nr + 1))]
    rad = (b - t + 1) / 2
    def inside(x, y):
        cy = t + rad - .5
        cx = l + rad - .5 if x < l + rad else r - rad + .5 if x > r - rad else x
        return (x - cx) ** 2 + (y - cy) ** 2 < (rad - 1.5) ** 2
    ink = [(x, y) for y in range(t, b + 1) for x in range(l, r + 1) if inside(x, y) and lum(x, y) < 62]
    if not ink:
        print(f"pill {l} {r} {t} {b} noink"); return
    xs = [p[0] for p in ink]; ys = [p[1] for p in ink]
    print(f"w={r-l+1} h={b-t+1} left={min(xs)-l} right={r-max(xs)} top={min(ys)-t} bottom={b-max(ys)} ink={max(xs)-min(xs)+1}x{max(ys)-min(ys)+1} box={l},{t},{r-l+1},{b-t+1} near_h={nrows[-1]-nrows[0]+1} near_top={nrows[0]} pill_top={t}")
main(sys.argv[1], int(sys.argv[2]))
