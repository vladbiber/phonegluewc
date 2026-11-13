#!/usr/bin/env python3
# frame-check.py LOG SHOTDIR CHECK...: geometry assertions from GEOM lines, and rows of real pixels
import sys, re
log, shots = sys.argv[1], sys.argv[2]
CARD_TOP = 6
SIDE_CARD = 0.86
BAR_ZONE = 16
GAP = 8
BAR = bytes.fromhex("2040c0"); GREY = bytes.fromhex("808080"); GREEN = bytes.fromhex("00c000")
S = {}
for line in open(log, errors="replace"):
    p = line.split()
    if len(p) < 3 or p[0] != "GEOM":
        continue
    d = {}
    for kv in p[3:]:
        if "=" in kv:
            k, v = kv.split("=", 1)
            if re.fullmatch(r"-?\d+(,-?\d+)+", v):
                v = tuple(int(x) for x in v.split(","))
            d[k] = v
    s = S.setdefault(p[1], {"clients": {}, "layers": {}})
    if p[2] == "mon": s["mon"] = d
    elif p[2] == "client": s["clients"][d["title"]] = d
    else: s["layers"][d["ns"]] = d

fails = 0
def ok(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  {why}"))
    fails += not cond

def rows(shot, xfrac=0.1):
    """a column of logical x = xfrac, top to bottom, whatever way the buffer is turned"""
    d = open(f"{shots}/{shot}.ppm", "rb").read()
    w, h = (int(x) for x in d.split(None, 4)[1:3])
    px = d[-w * h * 3:]
    tf = int(S[shot]["mon"]["tf"])
    at = lambda x, y: px[(y * w + x) * 3:(y * w + x) * 3 + 3]
    if tf == 0:
        x = int(w * xfrac)
        return h, [at(x, y) for y in range(h)]
    if tf == 1:  # 90: logical y runs along buffer x, logical x back along buffer y
        y = h - 1 - int(h * xfrac)
        return w, [at(x, y) for x in range(w)]
    if tf == 3:  # 270
        y = int(h * xfrac)
        return w, [at(w - 1 - x, y) for x in range(w)]
    raise SystemExit(f"no rows for transform {tf}")

def span(col, color):
    ys = [y for y, c in enumerate(col) if c == color]
    return (ys[0], ys[-1] + 1, len(ys)) if ys else None

def top_of_keyboard(s):
    k = s["layers"].get("phone-keyboard")
    return k["box"][1] if k else None

def usable(s):
    """what the exclusive layers leave, computed apart from the compositor's own m->w"""
    x, y, w, h = s["mon"]["m"]
    top, bot = y, y + h
    for l in s["layers"].values():
        e = int(l["excl"])
        if e > 0:
            if l["box"][1] == y: top = max(top, y + e)
            else: bot = min(bot, l["box"][1])
    return (x, top, w, bot - top)

def single(n, title="one", pixels=True):
    s = S[n]; c = s["clients"][title]; w = s["mon"]["w"]
    ok(f"{n}: usable area is what the bars leave", w == usable(s), f"w={w} expected={usable(s)}")
    ok(f"{n}: window fills the usable area exactly", c["geom"] == w, f"geom={c['geom']} w={w}")
    ok(f"{n}: the app drew at that size", tuple(c["surf"]) == w[2:], f"surf={c['surf']} w={w}")
    if pixels:
        h, col = rows(n)
        sc = float(s["mon"]["scale"])
        g = span(col, GREY)
        # the status bar's strip takes the window's top colour, so the grey runs from the top
        ok(f"{n}: pixels: window rows match", g and (g[0] <= 2 or abs(g[0] - w[1] * sc) <= 2) and abs(g[1] - (w[1] + w[3]) * sc) <= 2,
           f"grey={g} want {w[1]*sc}..{(w[1]+w[3])*sc}")
        ok(f"{n}: pixels: nothing inside the window is covered", g and g[2] == g[1] - g[0], f"grey={g}")
        ok(f"{n}: pixels: window stays on the screen", g and g[1] <= s["mon"]["m"][3] * sc + 2, f"grey={g}")
        b = span(col, BAR)
        if "frame-bar" in s["layers"]:
            ok(f"{n}: pixels: bar rows are whole", b and b[0] == 0 and abs(b[1] - w[1] * sc) <= 3 and b[2] == b[1], f"bar={b}")

def overview(n, title="one"):
    s = S[n]; m = s["mon"]; card = m["card"]; c = s["clients"][title]; bx = c["cardwin"]
    ok(f"{n}: overview is open", m["ov"] == "1")
    if m["ov"] != "1":
        return
    ok(f"{n}: card has the screen's proportions",
       abs(card[2] / card[3] - m["m"][2] / m["m"][3]) < 0.01, f"card={card} m={m['m']}")
    ok(f"{n}: window in the card keeps its proportions",
       abs(bx[2] / bx[3] - c["geom"][2] / c["geom"][3]) < 0.01, f"box={bx} geom={c['geom']}")
    ok(f"{n}: window sits inside its card",
       bx[0] >= card[0] - 1 and bx[1] >= card[1] - 1 and bx[0] + bx[2] <= card[0] + card[2] + 1 and bx[1] + bx[3] <= card[1] + card[3] + 1, f"box={bx} card={card}")
    # the phone bar stays in the overview: the card starts under it and ends above the bottom edge zone; turned it is centred between them
    top_ok = card[1] >= m["w"][1] + CARD_TOP if m["m"][2] > m["m"][3] else card[1] in (CARD_TOP, m["w"][1] + CARD_TOP)
    ok(f"{n}: card under the bar, clear of the bottom edge", top_ok and card[1] + card[3] <= m["m"][3] - BAR_ZONE, f"card={card} w={m['w']}")
    sc = float(m["scale"])
    ok(f"{n}: neighbours are smaller", sidecards(m["card0"], card, m["card2"]), f"{m['card0']} {card} {m['card2']}")
    h, col = rows(n, (card[0] - 3) / m["m"][2])
    # from below the bar: a test shell's bar does not fade like the phone's
    seen = {bytes(p) for p in col[int(-(-max(card[1], m["w"][1]) * sc // 1)):int((card[1] + card[3]) * sc)]}
    ok(f"{n}: pixels: nothing shows between the cards", seen == {b"\0\0\0"}, f"colours={list(seen)[:4]}")

def sidecards(a, card, b):
    """both side cards SIDE_CARD of the centre one, centred on it vertically"""
    return all(abs(x[i] - card[i] * SIDE_CARD) <= 1 for x in (a, b) for i in (2, 3)) \
        and all(abs((x[1] + x[3] / 2) - (card[1] + card[3] / 2)) <= 1 for x in (a, b))

def screen(n):
    """pixels of a shot in logical px, portrait"""
    d = open(f"{shots}/{n}.ppm", "rb").read()
    w, h = (int(x) for x in d.split(None, 4)[1:3])
    px = d[-w * h * 3:]
    return w, h, px

def countpx(n, box, test):
    w, h, px = screen(n)
    sc = float(S[n]["mon"]["scale"])
    x0, y0, x1, y1 = int(box[0] * sc), int(box[1] * sc), int((box[0] + box[2]) * sc), int((box[1] + box[3]) * sc)
    c = 0
    for y in range(max(y0, 0), min(y1, h)):
        for x in range(max(x0, 0), min(x1, w), 2):
            c += test(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
    return c

BRIGHT = lambda p: p[0] > 180 and p[1] > 180 and p[2] > 180

def cards(n, title=None):
    """the cards as the user asked for them, with the tray and bar of the real shell"""
    s = S[n]; m = s["mon"]; card = m["card"]; a, b = m["card0"], m["card2"]
    W, H = m["m"][2], m["m"][3]
    ok(f"{n}: true screen aspect", abs(card[2] / card[3] - W / H) < 0.005, f"card={card}")
    bar = m["w"][1]
    traytop = s["layers"]["phone-tray"]["box"][1]
    ok(f"{n}: starts under the bar", card[1] == bar + CARD_TOP and bar > CARD_TOP, f"card={card} bar={bar}")
    ok(f"{n}: ends where the tray starts", card[1] + card[3] == traytop, f"card={card} traytop={traytop}")
    ok(f"{n}: centred sideways", abs(card[0] - (W - card[0] - card[2])) <= 1, f"card={card}")
    ok(f"{n}: neighbours are smaller", sidecards(a, card, b), f"{a} {card} {b}")
    ok(f"{n}: neighbours peek in at the same spacing", card[0] - a[0] - a[2] == b[0] - card[0] - card[2] and a[0] + a[2] > 15 and b[0] < W - 15, f"{a} {card} {b}")

def noclock(n):
    """an empty workspace's card and its neighbours: no widget"""
    card = S[n]["mon"]["card"]
    c = countpx(n, (0, card[1], S[n]["mon"]["m"][2], card[3]), BRIGHT)
    ok(f"{n}: pixels: no clock in any card", c == 0, f"bright={c}")
    band = (card[0] + 8, card[1] + 1, card[2] - 16, 28)
    c = countpx(n, band, BRIGHT)
    ok(f"{n}: pixels: no label on an empty card", c == 0, f"lit={c}")

def homeclock(n):
    c = countpx(n, (20, 80, 300, 90), BRIGHT)
    ok(f"{n}: pixels: the home screen does show the clock (control)", c > 100, f"bright={c}")

def label(n):
    card = S[n]["mon"]["card"]
    c = countpx(n, (card[0] + 8, card[1] + 1, card[2] - 16, 28), BRIGHT)
    ok(f"{n}: pixels: a label on a card with an app", c > 20, f"bright={c}")

def letter(n):
    """the icon that cannot be seen on black gives way to its letter in a circle"""
    card = S[n]["mon"]["card"]
    # the label is centred in the top strip now
    c = countpx(n, (card[0], card[1] + 1, card[2], 28), BRIGHT)
    ok(f"{n}: pixels: a letter where the icon would not show", c > 3, f"bright={c}")
    H = S[n]["mon"]["m"][3]
    o = countpx(n, (0, H - 100, S[n]["mon"]["m"][2], 74), lambda p: p == bytes.fromhex("ff8800"))
    ok(f"{n}: pixels: an icon that shows keeps its picture", o > 100, f"orange={o}")

def ws(n, want):
    ok(f"{n}: on workspace {want}", S[n]["mon"]["ws"] == want, f"got={S[n]['mon']['ws']} clients={[(k, v['ws']) for k, v in S[n]['clients'].items()]}")

def cardeq(n, ref):
    a, b = S[n]["mon"], S[ref]["mon"]
    ok(f"{n}: cards exactly as in {ref}", (a["card"], a["card0"], a["card2"]) == (b["card"], b["card0"], b["card2"]), f"{a['card']} {b['card']}")

def rubber(n, ref):
    d = S[n]["mon"]["card"][0] - S[ref]["mon"]["card"][0]
    want = -0.2 * S[n]["mon"]["m"][2] / 4  # the first move only anchors the drag
    ok(f"{n}: the last card resists, a quarter of the drag", abs(d - want) <= 8, f"moved={d} want={want:.0f}")

def haskb(n):
    ok(f"{n}: keyboard is up", "phone-keyboard" in S[n]["layers"], f"layers={list(S[n]['layers'])}")

def nokb(n):
    ok(f"{n}: keyboard is gone", "phone-keyboard" not in S[n]["layers"], f"layers={list(S[n]['layers'])}")

def shown(n, title, ref):
    c = S[n]["clients"].get(title)
    r = S[ref]["clients"][title]
    ok(f"{n}: {title} stays on its card", c is not None and c["cardwin"] == r["cardwin"], f"got={c and c['cardwin']} wanted={r['cardwin']}")

def gone(n, title):
    ok(f"{n}: {title} closed", title not in S[n]["clients"], f"clients={list(S[n]['clients'])}")

def flung(n, title, ref):
    c = S[n]["clients"][title]; r = S[ref]["clients"][title]
    ok(f"{n}: {title} left its card", c["cardwin"][1] < r["cardwin"][1] - 100, f"got={c['cardwin']} ref={r['cardwin']}")

def conf(n):
    """settings written while the shell runs: the wallpaper everywhere, the accent on the clock"""
    m = S[n]["mon"]
    blue = lambda p: p[0] < 20 and 70 < p[1] < 110 and p[2] > 170
    box = m["card"] if m["ov"] == "1" else (0, 300, m["m"][2], 300)
    box = (box[0], box[1] + box[3] // 2, box[2], 40)
    c = countpx(n, box, blue)
    ok(f"{n}: pixels: the wallpaper shows", c > 1000, f"blue={c}")
    if n == "confhome":
        g = countpx(n, (20, 80, 300, 90), lambda p: p[1] > 200 and p[0] < 60 and p[2] < 60)
        ok(f"{n}: pixels: the clock's colon has the new accent", g > 20, f"green={g}")

def confoff(n):
    c = countpx(n, (0, 300, S[n]["mon"]["m"][2], 300), lambda p: p[2] > 170)
    ok(f"{n}: pixels: the wallpaper left with its key", c == 0, f"blue={c}")

def count(n, w, want):
    got = sum(1 for v in S[n]["clients"].values() if v["ws"] == w)
    ok(f"{n}: workspace {w} still has its {want} windows", got == int(want), f"got={got}")

def tiled(n, titles):
    s = S[n]; w = s["mon"]["w"]
    gs = [s["clients"][t]["geom"] for t in titles]
    for t in titles:
        c = s["clients"][t]
        ok(f"{n}: {t} drew at its tile size", tuple(c["surf"]) == c["geom"][2:], f"surf={c['surf']} geom={c['geom']}")
    L = min(g[0] for g in gs); T = min(g[1] for g in gs)
    R = max(g[0] + g[2] for g in gs); B = max(g[1] + g[3] for g in gs)
    ok(f"{n}: outer gaps are all {GAP}", (L - w[0], T - w[1], w[0] + w[2] - R, w[1] + w[3] - B) == (GAP,) * 4,
       f"{(L - w[0], T - w[1], w[0] + w[2] - R, w[1] + w[3] - B)} geoms={gs}")
    inner = True; touching = 0
    for i, a in enumerate(gs):
        for b in gs[i + 1:]:
            over = max(a[0], b[0]) < min(a[0] + a[2], b[0] + b[2]) and max(a[1], b[1]) < min(a[1] + a[3], b[1] + b[3])
            inner = inner and not over
            if max(a[0], b[0]) < min(a[0] + a[2], b[0] + b[2]):
                d = max(a[1], b[1]) - min(a[1] + a[3], b[1] + b[3])
            else:
                d = max(a[0], b[0]) - min(a[0] + a[2], b[0] + b[2])
            if 0 <= d <= GAP * 2:
                touching += 1
                inner = inner and d == GAP
    ok(f"{n}: no overlap, inner gaps are {GAP}", inner and touching >= len(gs) - 1, f"geoms={gs}")

def full(n, title):
    s = S[n]; c = s["clients"][title]
    ok(f"{n}: fullscreen covers the whole screen", c["geom"] == s["mon"]["m"] and c["fs"] == "1", f"geom={c['geom']} fs={c['fs']}")
    ok(f"{n}: the app drew fullscreen", tuple(c["surf"]) == s["mon"]["m"][2:], f"surf={c['surf']}")
    h, col = rows(n)
    g = len([p for p in col if p in (GREY, GREEN)])
    ok(f"{n}: pixels: every row is the app", g == h, f"app rows={g} of {h}")

def field(n, title):
    s = S[n]; c = s["clients"][title]
    ok(f"{n}: the keyboard leaves the window room", S[n]["mon"]["w"][3] >= 120, f"w={S[n]['mon']['w']}")
    kt = top_of_keyboard(s)
    ok(f"{n}: keyboard is up", kt is not None)
    if kt is None: return
    sc = float(s["mon"]["scale"])
    ok(f"{n}: window ends at the keyboard's top", c["geom"][1] + c["geom"][3] == kt, f"geom={c['geom']} kbtop={kt}")
    ok(f"{n}: the app redrew at that height", tuple(c["surf"]) == tuple(c["geom"][2:]), f"surf={c['surf']} geom={c['geom']}")
    h, col = rows(n)
    g = span(col, GREEN)
    ok(f"{n}: pixels: field is whole and right above the keyboard",
       g and abs(g[1] - kt * sc) <= 3 and g[2] >= min(60, c["geom"][3]) * sc - 3, f"green={g} kbtop={kt * sc}")

def fieldgone(n, title):
    s = S[n]; c = s["clients"][title]; w = s["mon"]["w"]
    ok(f"{n}: keyboard went away", top_of_keyboard(s) is None, str(s["layers"].keys()))
    ok(f"{n}: window grew back", c["geom"] == w == usable(s) and tuple(c["surf"]) == w[2:], f"geom={c['geom']} surf={c['surf']} w={w}")
    h, col = rows(n)
    g = span(col, GREEN)
    sc = float(s["mon"]["scale"])
    ok(f"{n}: pixels: field sits at the window's new bottom", g and abs(g[1] - (w[1] + w[3]) * sc) <= 2, f"green={g}")

def landscape(n):
    m = S[n]["mon"]
    ok(f"{n}: logical size is landscape", m["m"][2] > m["m"][3], f"m={m['m']}")

def portrait(n):
    m = S[n]["mon"]
    ok(f"{n}: logical size is portrait", m["m"][2] < m["m"][3], f"m={m['m']}")

def centred(n, t):
    g, w = S[n]["clients"][t]["geom"], S[n]["mon"]["w"]
    ok(f"{n}: {t} in the middle of the usable area", abs(g[0] + g[2] / 2 - (w[0] + w[2] / 2)) <= 1
       and abs(g[1] + g[3] / 2 - (w[1] + w[3] / 2)) <= 1, f"geom={g} w={w}")

def windows(name, *want):
    """pid<TAB>app id per window, the pid being that of the client that opened it"""
    got = sorted(open(f"{shots}/{name}.windows").read().splitlines())
    exp = []
    for w in want:
        who, _, id_ = w.partition("=")
        exp.append(f"{open(f'{shots}/pid-{who}').read().strip()}\t{id_ or who}")
    ok(f"{name}: windows file lists {want}", sorted(exp) == got, f"got={got}")

for chk in sys.argv[3:]:
    name, *a = chk.split(":")
    {"letter": letter, "cardeq": cardeq, "rubber": rubber, "haskb": haskb, "nokb": nokb, "ws": ws, "count": count, "centred": centred, "windows": windows, "conf": conf, "confoff": confoff, "cards": cards, "noclock": noclock, "homeclock": homeclock, "label": label, "shown": shown, "gone": gone, "flung": flung, "single": single, "overview": overview, "field": field, "fieldgone": fieldgone, "full": full, "landscape": landscape, "portrait": portrait,
     "tiled": lambda n, *t: tiled(n, t)}[name](*a)
sys.exit(1 if fails else 0)
