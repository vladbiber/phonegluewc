"""phonecamretro: old-camera looks. One renderer for the developed still and for live frames, so the
viewfinder, the clip and the photo agree. BGR uint8 in, BGR uint8 out, at the size of the old camera."""
import time

import cv2
import numpy as np

# Numbers are for a 640 px wide picture and scale with the width.
#   soft      lens blur, sigma px                 hblur    extra horizontal blur (tape luma bandwidth)
#   smudge    median size: the painted patches of a tiny, heavily compressed picture
#   sharp     in-camera sharpening (amount, radius), horizontal only when hblur is set: the halo of old video
#   chroma    colour resolution divider (x, y)    cshift   colour drawn this many px to the right
#   black, white  input levels mapped to 0 and 1; above knee the curve bends over instead of clipping,
#             so a bright sky stays sky and does not burn out like a lamp
#   lift, peak  darkest and brightest output level (milky blacks; tape never reaches full white)
#   gamma     under 1 brightens the middle        sat      colour strength
#   tint      (red, blue) shift in the shadows, in the highlights
#   bloom     glow around bright parts            vig      corner darkening
#   noise     luma grain, streak makes it horizontal lines; cnoise colour blotches
#   jpeg      quality the old camera saved at     stamp    "vhs" | "date"
#   night     smeared noise reduction as a flash photo of the dark has it
#   dark      the same keys for a dark scene: the look moves there as the light goes (dusk turns blue
#             or violet, lamps glow, grain comes up), numbers and pairs are blended by how dark it is
STYLES = {
    "DIGICAM": dict(soft=.55, sharp=(.9, 1.2), chroma=(4, 4), black=8, white=228, lift=10, knee=.6, sat=1.75,
                    tint=((-2, 2), (-5, 9)), bloom=.06, vig=.14, noise=1.6, jpeg=62, stamp="date",
                    dark=dict(sat=1.5, tint=((-8, 20), (-4, 10)), bloom=.35, noise=3.0, lift=4)),
    "VHS": dict(soft=.5, hblur=1.5, sharp=(.9, 2.6), chroma=(20, 2), cshift=3, black=4, white=240, lift=16, peak=235, knee=.6,
                sat=1.55, tint=((1, 3), (-3, 4)), bloom=.1, vig=.1, noise=3.0, streak=True, cnoise=1.0, tape=True, stamp="vhs",
                dark=dict(sat=1.25, tint=((7, 14), (3, -3)), bloom=.5, noise=4.5, lift=26)),
    "DREAM": dict(soft=.9, smudge=5, chroma=(6, 6), black=0, white=245, lift=34, peak=240, gamma=.95, knee=.55, sat=1.6,
                  tint=((-2, 4), (-3, 7)), bloom=.3, vig=.05, noise=.8, jpeg=30, stamp="date",
                  dark=dict(sat=1.2, tint=((3, 12), (0, 3)), bloom=.55, lift=44)),
    "LIMINAL": dict(soft=.8, hblur=.8, sharp=(.5, 2.0), chroma=(10, 2), cshift=1, black=6, white=250, lift=24, peak=228,
                    gamma=1.12, knee=.6, sat=.55, tint=((2, -4), (4, -8)), bloom=.1, vig=.38, noise=3.5, cnoise=1.0, jpeg=55,
                    stamp="date", dark=dict(sat=.7, tint=((0, -8), (3, -12)), vig=.5, lift=14)),
    "NIGHT": dict(soft=.5, night=True, chroma=(6, 6), black=14, white=225, knee=.65, sat=1.0, tint=((-3, 12), (1, -4)),
                  bloom=.3, vig=.45, noise=2.2, jpeg=45, stamp="date", flash=True),
}
# what the photographer can turn on top of a style: stops, colour x, warmth (red up, blue down), grain x, blur x, glow x
ADJ = dict(ev=0.0, sat=1.0, warm=0.0, grain=1.0, soft=1.0, glow=1.0)
SIZES = {"VGA": 640, "1 MP": 1152, "2 MP": 1600}
GLYPHS = {c: [int(r, 2) for r in rows.split()] for c, rows in {
    "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11111 00010 00100 00010 00001 10001 01110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    ":": "00000 00100 00100 00000 00100 00100 00000", ".": "00000 00000 00000 00000 00000 00110 00110",
    "'": "00100 00100 01000 00000 00000 00000 00000", " ": "00000 00000 00000 00000 00000 00000 00000"}.items()}


def text_mask(text, k):
    """5x7 glyphs as a 0/255 mask, each dot k px"""
    m = np.zeros((7, 6 * len(text)), np.uint8)
    for i, ch in enumerate(text):
        for r, bits in enumerate(GLYPHS.get(ch, GLYPHS[" "])):
            for c in range(5):
                if bits >> (4 - c) & 1:
                    m[r, 6 * i + c] = 255
    return cv2.resize(m, None, fx=k, fy=k, interpolation=cv2.INTER_NEAREST)


class Look:
    """one style at one picture size; keeps what does not change between frames"""

    def __init__(self, style, w, h, seed=None, adj=None):
        self.p, self.w, self.h, self.s = STYLES[style], w, h, max(w, h) / 640
        self.adj = dict(ADJ, **(adj or {}))  # may be changed between frames
        self.rng = np.random.default_rng(seed)
        self.prev = self.prev_out = None
        self.dark = -1.0
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        self.r2 = (((xx - w / 2) ** 2 + (yy - h / 2) ** 2) / ((w / 2) ** 2 + (h / 2) ** 2)) ** 1.3
        self.vig = (None, None)
        # a few grain fields (sigma 8 around 128), shifted at random per frame: fresh noise each frame costs more than the look
        n = self.rng.normal(0, 1, (4, h + 16, w + 16)).astype(np.float32)
        if self.p.get("streak"):
            n = np.stack([cv2.blur(f, (int(9 * self.s) | 1, 1)) * 2.2 for f in n])
        self.grain = np.clip(128 + n * 8, 0, 255).astype(np.uint8)
        c = self.rng.normal(0, 1, (4, h // 8 + 4, w // 24 + 4)).astype(np.float32)
        self.cgrain = [np.clip(128 + cv2.resize(f, (w + 16, h + 16), interpolation=cv2.INTER_CUBIC) * 8, 0, 255).astype(np.uint8)
                       for f in c]

    def q(self, key, d, default=0.0):
        """a number or pair of the style, moved toward its "dark" value by d"""
        a = self.p.get(key, default)
        b = self.p.get("dark", {}).get(key, a)
        mix = lambda u, v: tuple(mix(i, j) for i, j in zip(u, v)) if isinstance(u, tuple) else u + (v - u) * d
        return mix(a, b)

    def tone(self, d):
        """the brightness curve; in the dark the black level goes up so the noise floor ends as black"""
        p, x = self.p, np.arange(256, dtype=np.float32)
        black = p["black"] + 14 * d
        v = (np.clip((x - black) / (p["white"] - black), 0, None) * 2.0 ** self.adj["ev"]) ** p.get("gamma", 1.0)
        t = p.get("knee", 1.0)
        if t < 1:
            v = np.where(v > t, t + (1 - t) * (1 - np.exp(-(v - t) / (1 - t))), v)
        lift = self.q("lift", d)
        return np.clip(lift + np.minimum(v, 1) * (p.get("peak", 255) - lift), 0, 255).astype(np.uint8)

    def field(self, pool):
        f = pool[self.rng.integers(len(pool))]
        dy, dx = self.rng.integers(0, 16, 2)
        return f[dy:dy + self.h, dx:dx + self.w]

    def render(self, img, stamp=None, live=False):
        """img: BGR, any size with the look's aspect. stamp: unix time to print, None for none."""
        p, s, w, h, adj = self.p, self.s, self.w, self.h, self.adj
        if img.shape[1] != w or img.shape[0] != h:
            img = cv2.resize(img, (w, h), interpolation=cv2.INTER_AREA)
        y, cr, cb = cv2.split(cv2.cvtColor(img, cv2.COLOR_BGR2YCrCb))
        # how dark the scene is, 0..1, eased over frames so the picture does not pump
        d = float(np.clip((75 - cv2.mean(y)[0]) / 50, 0, 1))
        self.dark = d if self.dark < 0 or not live else self.dark + (d - self.dark) * .1
        d = self.dark
        if live and d > .05 and self.prev is not None:
            # dark frames are averaged with the ones before, as a camcorder's low-light mode does:
            # sensor noise turns into soft trails instead of a crawling checkerboard
            a = .65 * d
            y, cr, cb = (cv2.addWeighted(n, 1 - a, o, a, 0) for n, o in zip((y, cr, cb), self.prev))
        if live:
            self.prev = (y, cr, cb)
        y = cv2.GaussianBlur(y, (0, 0), max((p["soft"] * adj["soft"] + .8 * d) * s, .1))
        if d > (.15 if p.get("night") else .5):  # flat smeared patches where the noise was
            y = cv2.medianBlur(y, max(int(2 * s) * 2 + 1, 3))
        if p.get("smudge"):
            y = cv2.medianBlur(y, int(p["smudge"] * s) | 1)
        if p.get("hblur"):
            y = cv2.GaussianBlur(y, (0, 1), p["hblur"] * s, sigmaY=.01)
        if "sharp" in p:
            amt, rad = p["sharp"]
            amt *= 1 - .7 * d  # sharpening the dark only digs the noise back out
            wide = cv2.GaussianBlur(y, (0, 1) if p.get("hblur") else (0, 0), rad * s, sigmaY=.01 if p.get("hblur") else rad * s)
            y = cv2.addWeighted(y, 1 + amt, wide, -amt, 0)
        y = cv2.LUT(y, self.tone(d))
        # colour at a fraction of the resolution, drawn a little to the right of where it belongs
        cx, cy = p["chroma"]
        cx, cy = max(int(cx * s * (1 + d)), 1), max(int(cy * s * (1 + d)), 1)
        small = (max(w // cx, 2), max(h // cy, 2))
        sh = int(p.get("cshift", 0) * s)
        sat = self.q("sat", d) * adj["sat"]
        (sr, sb), (hr, hb) = self.q("tint", d)
        x = np.arange(256, dtype=np.float32) / 255
        cn = self.q("cnoise", d) / 4
        out = []
        for c, lo, hi, warm in ((cr, sr, hr, adj["warm"]), (cb, sb, hb, -adj["warm"])):
            c = cv2.resize(cv2.resize(c, small, interpolation=cv2.INTER_AREA), (w, h), interpolation=cv2.INTER_LINEAR)
            if sh:
                c = np.roll(c, sh, axis=1)
            # the tint follows the brightness: one table per colour channel
            lut = np.clip(128 + warm + lo + (hi - lo) * x, 0, 255).astype(np.uint8)
            c = cv2.addWeighted(c, sat, cv2.LUT(y, lut), 1, 128 * (1 - sat) - 128)
            if cn:
                c = cv2.addWeighted(c, 1, self.field(self.cgrain), cn, -128 * cn)
            out.append(c)
        cr, cb = out
        bloom = self.q("bloom", d) * adj["glow"]
        if bloom:
            glow = cv2.resize(y, (max(w // 8, 2), max(h // 8, 2)), interpolation=cv2.INTER_AREA)
            glow = cv2.GaussianBlur(cv2.subtract(glow, 150), (0, 0), 3.5)
            y = cv2.addWeighted(y, 1, cv2.resize(glow, (w, h), interpolation=cv2.INTER_LINEAR), bloom * 2.4, 0)
        vig = round(self.q("vig", d), 2)
        if vig:
            if self.vig[0] != vig:
                self.vig = (vig, (255 * (1 - vig * self.r2)).astype(np.uint8))
            y = cv2.multiply(y, self.vig[1], scale=1 / 255)
        gn = self.q("noise", d) * adj["grain"] / 4
        if gn:
            y = cv2.addWeighted(y, 1, self.field(self.grain), gn, -128 * gn)
        if "peak" in p:
            y = cv2.min(y, p["peak"] + 4)
        if p.get("tape"):
            y, cr, cb = self.tape(y, cr, cb, live)
        img = cv2.cvtColor(cv2.merge((y, cr, cb)), cv2.COLOR_YCrCb2BGR)
        if stamp is not None:
            self.stamp(img, stamp)
        if "jpeg" in p:  # the blocks of a cheap camera's compression are part of the picture
            ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, p["jpeg"]])
            img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        return img

    def tape(self, y, cr, cb, live):
        """what the tape transport adds: the torn band where the heads switch, dark side edges, fields of two moments"""
        s, w, h = self.s, self.w, self.h
        band = max(int(7 * s), 2)
        for row in range(h - band, h, 2):
            dx = int(self.rng.integers(int(8 * s), int(40 * s)))
            for c in (y, cr, cb):
                c[row:row + 2] = np.roll(c[row:row + 2], dx, axis=1)
        y[h - band:] = cv2.addWeighted(y[h - band:], .8, self.field(self.grain)[:band], 3, -352)
        edge = max(int(5 * s), 1)
        y[:, :edge] = y[:, :edge] // 4
        y[:, w - edge // 2:] = y[:, w - edge // 2:] // 4
        if live:  # interlace: every other line still shows the frame before
            now = (y.copy(), cr.copy(), cb.copy())
            if self.prev_out is not None:
                for c, o in zip((y, cr, cb), self.prev_out):
                    c[1::2] = cv2.addWeighted(c[1::2], .5, o[1::2], .5, 0)
            self.prev_out = now
        return y, cr, cb

    def stamp(self, img, t):
        s, w, h, tm = self.s, self.w, self.h, time.localtime(t)
        if self.p["stamp"] == "vhs":  # camcorder titler: white blocks with a dark edge, two lines bottom left
            k, lines, rgb = max(int(round(2.6 * s * min(w, h) / 480)), 1), [time.strftime("%H:%M", tm), "%2d.%2d.%d" % (tm.tm_mday, tm.tm_mon, tm.tm_year)], (255, 255, 255)
            x0 = int(w * .12)
        else:  # the orange date of a compact camera, bottom right
            k, lines, rgb = max(int(round(1.9 * s * min(w, h) / 480)), 1), [time.strftime("'%y %m %d", tm)], (30, 150, 255)
            x0 = None
        y0 = int(h * .9) - len(lines) * 9 * k
        for i, text in enumerate(lines):
            m = text_mask(text, k)
            mh, mw = m.shape
            x = x0 if x0 is not None else w - mw - int(w * .06)
            yy = y0 + i * 9 * k
            if x < 0 or x + mw + k > w or yy + mh + k > h:
                continue
            m = cv2.GaussianBlur(m, (0, 0), .35 * k)
            sub = img[yy + k:yy + mh + k, x + k:x + mw + k]  # shadow
            sub[:] = (sub * (1 - m[..., None] / 340)).astype(np.uint8)
            sub = img[yy:yy + mh, x:x + mw]
            a = m[..., None] / 255
            sub[:] = (sub * (1 - a) + np.array(rgb, np.float32) * a).astype(np.uint8)


def still(img, style, width=640, stamp=None, adj=None):
    """a developed photo (BGR, upright) as the old camera would have saved it"""
    h, w = img.shape[:2]
    scale = width / max(w, h)
    return Look(style, round(w * scale), round(h * scale), adj=adj).render(img, stamp)


def selfcheck():
    rng = np.random.default_rng(1)
    for name in STYLES:
        for shape in ((480, 640, 3), (640, 480, 3)):
            src = rng.integers(0, 255, shape, dtype=np.uint8)
            look = Look(name, shape[1], shape[0], seed=1)
            a, b = look.render(src, 1e9, live=True), look.render(src, None, live=True)
            assert a.shape == b.shape == shape and a.dtype == np.uint8, (name, a.shape)
        # the dark must come out calm: noise of a black room is flattened, not kept as a pixel pattern
        noisy = rng.integers(0, 40, (480, 640, 3), dtype=np.uint8)
        out = cv2.cvtColor(Look(name, 640, 480, seed=1).render(noisy), cv2.COLOR_BGR2GRAY)
        grain = max(STYLES[name].get("noise", 0), STYLES[name].get("dark", {}).get("noise", 0)) * 2 + 3
        assert np.abs(np.diff(out[100:300, 100:400].astype(np.int16), axis=1)).mean() < grain, (name, "dark noise")
    assert still(np.zeros((1500, 2000, 3), np.uint8), "VHS", 640, 0).shape == (480, 640, 3)
    # a burnt-out sky bends over under white, and the photographer's exposure moves the picture
    white = np.full((480, 640, 3), 255, np.uint8)
    for name in ("DIGICAM", "VHS", "DREAM"):
        assert 200 < np.median(still(white, name)) < 250, name
    grey = np.full((480, 640, 3), 110, np.uint8)
    assert np.median(still(grey, "DIGICAM", adj=dict(ev=1.0))) > np.median(still(grey, "DIGICAM")) + 25


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["--selfcheck"]:
        selfcheck()
        sys.exit(print("ok"))
    # phonecamretro.py IN OUT STYLE [WIDTH]: try a look on any picture
    src = cv2.imread(sys.argv[1])
    cv2.imwrite(sys.argv[2], still(src, sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 640, time.time()),
                [cv2.IMWRITE_JPEG_QUALITY, 92])
