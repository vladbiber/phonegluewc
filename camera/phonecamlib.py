"""phonecamlib: maths and file formats shared by phonecam and phonecam-develop (pure Python).

python3 phonecamlib.py --selfcheck
"""
import math
import struct
import time
from fractions import Fraction

# s5kjn1 white balance from this module's OTP (EEPROM 0x20 and 0x42: R, Gr, Gb, B under the light box):
# R and B gains that make grey neutral. shortcut: the OTP does not name its illuminants, D50 and A
# are the usual pair; recalibrate with a grey card if Kelvin readings look off.
WB_CAL = ((2856, 1.105, 2.398), (5000, 1.459, 1.650))
SRGB_XYZ = ((0.4124, 0.3576, 0.1805), (0.2126, 0.7152, 0.0722), (0.0193, 0.1192, 0.9505))
ASPECTS = (("4:3", 4 / 3), ("16:9", 16 / 9), ("1:1", 1.0), ("1.43", 1.43), ("1.90", 1.90), ("2.39", 2.39))


def kelvin_gains(kelvin, tint=0):
    """(R gain, B gain) for a light of that colour temperature: log gains run straight in mired
    between the two calibrated lights. tint -50..50 is green to magenta."""
    (k0, r0, b0), (k1, r1, b1) = WB_CAL
    t = (1e6 / kelvin - 1e6 / k0) / (1e6 / k1 - 1e6 / k0)
    m = 2 ** (tint / 100)
    return r0 * (r1 / r0) ** t * m, b0 * (b1 / b0) ** t * m


def gains_kelvin(rg, bg):
    """colour temperature whose gains have the same blue to red ratio"""
    (k0, r0, b0), (k1, r1, b1) = WB_CAL
    t = math.log((bg / rg) / (b0 / r0)) / math.log((b1 / r1) / (b0 / r0))
    return 1e6 / min(max(1e6 / k0 + t * (1e6 / k1 - 1e6 / k0), 50), 1000)


def shutter_us(angle, fps):
    """exposure time of a rotary shutter: angle / (360 x fps)"""
    return angle / 360 / fps * 1e6


def shutter_label(us):
    if us >= 400000:
        return f'{us / 1e6:.1f}"'
    return f"1/{round(1e6 / us)}"


def crop_aspect(w, h, aspect):
    """largest centred w, h with long edge / short edge = aspect"""
    long, short = max(w, h), min(w, h)
    if aspect > long / short:
        short = round(long / aspect)
    else:
        long = round(short * aspect)
    return (long, short) if w >= h else (short, long)


class AFSearch:
    """contrast autofocus. Move the lens to .pos, measure sharpness there, feed() it; feed returns
    the next position, or None when .best is final (.sure tells whether the scene gave a clear peak).
    A fresh search sweeps lo..hi coarsely, then finely around the best point. With `around` (the
    current position) it only looks nearby, and falls back to the full sweep when the peak is not inside."""

    def __init__(self, lo, hi, around=None, coarse=11, fine=5):
        self.lo, self.hi, self.coarse, self.fine = lo, hi, coarse, fine
        self.step = (hi - lo) / (coarse - 1)
        self.best, self.sure, self.near = None, False, around is not None
        if self.near:
            self._fine(around)
        else:
            self._sweep()

    def _sweep(self):
        self.pts = [round(self.lo + i * self.step) for i in range(self.coarse)]
        self.seen, self.stage, self.pos = [], 0, self.pts[0]

    def _fine(self, centre):
        a, b = max(self.lo, centre - self.step), min(self.hi, centre + self.step)
        self.pts = [round(a + j * (b - a) / (self.fine - 1)) for j in range(self.fine)]
        self.seen, self.stage, self.pos = [], 1, self.pts[0]

    def feed(self, sharp):
        self.seen.append(sharp)
        # a sweep stops early once sharpness has clearly fallen off for two points: the peak is behind
        passed = self.stage == 0 and len(self.seen) >= 4 and max(self.seen[-2:]) < .7 * max(self.seen)
        if len(self.seen) < len(self.pts) and not passed:
            self.pos = self.pts[len(self.seen)]
            return self.pos
        i = max(range(len(self.seen)), key=self.seen.__getitem__)
        if self.stage == 0:
            # a flat curve is noise, not a peak; a slope that only tops out at the end of the sweep
            # has to be steep to count, a drifting scene makes gentle ones
            edge = i in (0, len(self.seen) - 1)
            self.sure = self.seen[i] > (2.5 if edge else 1.5) * min(self.seen)
            self._fine(self.pts[i])
            return self.pos
        if self.near and i in (0, len(self.pts) - 1) and self.lo < self.pts[i] < self.hi \
                and self.seen[i] > 1.3 * min(self.seen):
            self.near = False  # the peak is somewhere beyond the window
            self._sweep()
            return self.pos
        best = self.pts[i]
        if 0 < i < len(self.pts) - 1:  # vertex of the parabola through the peak and its neighbours
            y0, y1, y2 = (math.log(max(y, 1e-9)) for y in self.seen[i - 1:i + 2])  # peaks are near Gaussian
            d = y0 - 2 * y1 + y2
            if d < 0:
                best += (y0 - y2) / (2 * d) * (self.pts[i + 1] - self.pts[i])
        self.sure = self.sure or (self.near and self.seen[i] > 1.3 * min(self.seen))
        self.best = self.pos = int(min(max(round(best), self.lo), self.hi))
        return None


TYPES = {1: "B", 3: "H", 4: "I", 7: "B"}


def _ifd(tags, at):
    """a TIFF directory placed at offset `at`, long values right behind it"""
    tags = sorted(tags)
    data_at, out, data = at + 2 + 12 * len(tags) + 4, b"", b""
    for tag, typ, val in tags:
        if typ == 2:
            raw = val.encode() + b"\0"
            n = len(raw)
        elif typ in (5, 10):
            fr = [Fraction(v).limit_denominator(100000) for v in val]
            raw = b"".join(struct.pack("<ii" if typ == 10 else "<II", f.numerator, f.denominator) for f in fr)
            n = len(val)
        else:
            raw, n = struct.pack(f"<{len(val)}{TYPES[typ]}", *val), len(val)
        if len(raw) <= 4:
            field = raw.ljust(4, b"\0")
        else:
            field = struct.pack("<I", data_at + len(data))
            data += raw + b"\0" * (len(raw) & 1)
        out += struct.pack("<HHI", tag, typ, n) + field
    return struct.pack("<H", len(tags)) + out + b"\0\0\0\0" + data


def _exif_tags(exp_us, iso, t):
    stamp = time.strftime("%Y:%m:%d %H:%M:%S", time.localtime(t))
    return [(33434, 5, [exp_us / 1e6]), (34855, 3, [int(min(max(iso, 1), 65535))]), (36867, 2, stamp), (36868, 2, stamp)]


def exif_segment(exp_us, iso, t, model="Nothing Phone (1)"):
    """JPEG APP1 segment with exposure time, ISO and capture time"""
    stamp = time.strftime("%Y:%m:%d %H:%M:%S", time.localtime(t))
    base = [(271, 2, "Nothing"), (272, 2, model), (306, 2, stamp), (305, 2, "phonecam")]
    ifd0 = _ifd(base + [(34665, 4, [0])], 8)
    ifd0 = _ifd(base + [(34665, 4, [8 + len(ifd0)])], 8)
    body = b"Exif\0\0II*\0" + struct.pack("<I", 8) + ifd0 + _ifd(_exif_tags(exp_us, iso, t), 8 + len(ifd0))
    return b"\xff\xe1" + struct.pack(">H", len(body) + 2) + body


def add_exif(path, exp_us, iso, t):
    with open(path, "rb") as f:
        jpg = f.read()
    if jpg[:2] == b"\xff\xd8":
        with open(path, "wb") as f:
            f.write(jpg[:2] + exif_segment(exp_us, iso, t) + jpg[2:])


def _inv3(m):
    (a, b, c), (d, e, f), (g, h, i) = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
            [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
            [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]


def _mul3(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def color_matrix(ccm):
    """DNG ColorMatrix (XYZ D65 -> raw camera RGB) from a matrix that takes white-balanced camera
    RGB to linear sRGB: the inverse of sRGB->XYZ x ccm x diag(D65 gains)."""
    rg, bg = kelvin_gains(6504)
    to_xyz = _mul3(_mul3(SRGB_XYZ, ccm), [[rg, 0, 0], [0, 1, 0], [0, 0, bg]])
    return [v for row in _inv3(to_xyz) for v in row]


def write_dng(path, w, h, pixels, black, white, wb, ccm, rot=0, cfa=(1, 0, 2, 1), exp_us=0, iso=0, t=None,
              model="Nothing Phone (1) S5KJN1"):
    """uncompressed 16-bit Bayer DNG. pixels: h*w uint16 little endian (bytes-like), cfa: colour
    of the 2x2 tile (0 R, 1 G, 2 B), wb: (R gain, B gain) as shot, rot: clockwise degrees to upright."""
    t = time.time() if t is None else t
    tags = [
        (254, 4, [0]), (256, 4, [w]), (257, 4, [h]), (258, 3, [16]), (259, 3, [1]), (262, 3, [32803]),
        (271, 2, "Nothing"), (272, 2, model), (274, 3, [{0: 1, 90: 6, 180: 3, 270: 8}[rot]]), (277, 3, [1]),
        (278, 4, [h]), (279, 4, [w * h * 2]), (284, 3, [1]), (305, 2, "phonecam"),
        (306, 2, time.strftime("%Y:%m:%d %H:%M:%S", time.localtime(t))),
        (33421, 3, [2, 2]), (33422, 1, list(cfa)), (50706, 1, [1, 4, 0, 0]), (50707, 1, [1, 1, 0, 0]),
        (50708, 2, model), (50711, 3, [1]), (50714, 4, [black]), (50717, 4, [white]),
        (50721, 10, color_matrix(ccm)), (50728, 5, [1 / wb[0], 1, 1 / wb[1]]), (50778, 3, [21]),
    ]
    if exp_us:
        tags += [(t_, ty, v) for t_, ty, v in _exif_tags(exp_us, iso, t) if t_ in (33434, 34855)]
    at = 8 + len(_ifd(tags + [(273, 4, [0])], 8))
    with open(path, "wb") as f:
        f.write(b"II*\0" + struct.pack("<I", 8) + _ifd(tags + [(273, 4, [at])], 8))
        f.write(pixels)


def selfcheck():
    import os
    import tempfile
    # the calibrated lights come back exactly; warmer light needs more blue, less red
    for k, r, b in WB_CAL:
        g = kelvin_gains(k)
        assert abs(g[0] - r) < 1e-6 and abs(g[1] - b) < 1e-6
        assert abs(gains_kelvin(r, b) - k) < 1
    assert kelvin_gains(3200)[1] > kelvin_gains(6500)[1] and kelvin_gains(3200)[0] < kelvin_gains(6500)[0]
    assert abs(gains_kelvin(*kelvin_gains(4300, 20)) - 4300) < 1  # tint leaves the temperature alone
    # 180 degrees at 24 fps is 1/48 s, 360 is the whole frame
    assert abs(shutter_us(180, 24) - 1e6 / 48) < 1e-6 and abs(shutter_us(360, 30) - 1e6 / 30) < 1e-6
    assert shutter_label(shutter_us(180, 25)) == "1/50" and shutter_label(500000) == '0.5"'
    assert crop_aspect(4000, 3000, 16 / 9) == (4000, 2250) and crop_aspect(3000, 4000, 16 / 9) == (2250, 4000)
    assert crop_aspect(4000, 3000, 1.0) == (3000, 3000) and crop_aspect(3000, 4000, 1.43) == (2797, 4000)
    # autofocus finds the peak of a lens whose sharpness falls off around it, within a few codes
    def focus(peak, around=None, flat=False):
        af, n = AFSearch(0, 1023, around), 0
        pos = af.pos
        while pos is not None:
            pos = af.feed(5.0 if flat else 1000 / (1 + ((af.pos - peak) / 60) ** 2))
            n += 1
        return af, n
    for peak, steps in ((0, 9), (437, 12), (1023, 16), (612, 14)):
        af, n = focus(peak)
        assert abs(af.best - peak) <= 12 and n == steps and af.sure, (peak, af.best, n)
    af, n = focus(437, around=400)  # a small change is found without the sweep
    assert abs(af.best - 437) <= 8 and n == 5 and af.sure, (af.best, n)
    af, n = focus(900, around=300)  # a big one falls back to it
    assert abs(af.best - 900) <= 8 and n == 21 and af.sure, (af.best, n)
    assert not focus(0, flat=True)[0].sure  # nothing to focus on
    af = AFSearch(260, 860)  # a gentle rise to the end of the range, as a drifting scene gives: not a focus
    pos = af.pos
    while pos is not None:
        pos = af.feed(0.78 + 0.5 * (af.pos - 260) / 600)
    assert not af.sure, af.best
    # DNG: header, strip where the directory says, values readable back
    tmp = os.path.join(tempfile.mkdtemp(), "t.dng")
    px = struct.pack("<8H", *range(100, 108))
    eye = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    write_dng(tmp, 4, 2, px, 64, 1023, (1.5, 1.6), eye, rot=270, exp_us=10000, iso=400, t=0)
    d = open(tmp, "rb").read()
    os.unlink(tmp)
    os.rmdir(os.path.dirname(tmp))
    assert d[:4] == b"II*\0" and d[-16:] == px
    n = struct.unpack_from("<H", d, 8)[0]
    ent = {struct.unpack_from("<H", d, 10 + 12 * i)[0]: struct.unpack_from("<HII", d, 12 + 12 * i) for i in range(n)}
    assert list(ent) == sorted(ent) and ent[273][2] == len(d) - 16 and ent[256][2] == 4 and ent[50717][2] == 1023
    assert ent[274][2] & 0xffff == 8 and struct.unpack_from("<II", d, ent[50728][2]) == (2, 3)  # 1/1.5
    # identity ccm: the colour matrix is the inverse of sRGB->XYZ scaled by the D65 gains
    m = color_matrix(eye)
    rg, bg = kelvin_gains(6504)
    assert abs(m[0] * rg - 3.2406) < 2e-3 and abs(m[8] * bg - 1.0570) < 2e-3, m
    seg = exif_segment(20000, 800, 0)
    assert seg[:2] == b"\xff\xe1" and struct.unpack(">H", seg[2:4])[0] == len(seg) - 2 and b"1970:01:01" in seg


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["--selfcheck"]:
        selfcheck()
        print("ok")
    else:
        sys.exit(__doc__.strip())
