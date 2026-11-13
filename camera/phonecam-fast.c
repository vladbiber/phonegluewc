/* Per-pixel kernels for phonecam-develop, one row band per call (called from threads). */
#include <stdint.h>
#include <stdlib.h>

/* MIPI RAW10: 4 pixels in 5 bytes, high 8 bits first, the 5th byte holds the low 2 bits */
static void unpack(const uint8_t *s, int n4, uint16_t *d)
{
	for (int i = 0; i < n4; i++, s += 5, d += 4) {
		unsigned lo = s[4];
		d[0] = s[0] << 2 | (lo & 3);
		d[1] = s[1] << 2 | (lo >> 2 & 3);
		d[2] = s[2] << 2 | (lo >> 4 & 3);
		d[3] = s[3] << 2 | lo >> 6;
	}
}

/* rows y0..y1 of the sum of n frames into out (row 0 = y0), frame i read at (x + sx[i], y + sy[i]); frame 0 fills
 * where a shifted frame has no data. w, h: cropped size; (dx, dy): crop offset in the frame */
void stack_rows(uint8_t *const *f, int n, const int *sx, const int *sy, int w, int h, int stride,
		int dx, int dy, int y0, int y1, uint16_t *out)
{
	int n4 = (dx + w + 5) / 4;  /* covers x + dx for a crop anywhere in the row */
	if (n4 > stride / 5)
		n4 = stride / 5;
	uint16_t *ref = malloc(sizeof *ref * n4 * 4), *t = malloc(sizeof *t * n4 * 4);
	for (int y = y0; y < y1; y++) {
		uint16_t *o = out + (size_t)(y - y0) * w;
		unpack(f[0] + (size_t)(y + dy) * stride, n4, ref);
		for (int x = 0; x < w; x++)
			o[x] = ref[x + dx];
		for (int i = 1; i < n; i++) {
			int r = y + sy[i], s = sx[i];
			if (r < 0 || r >= h) {
				for (int x = 0; x < w; x++)
					o[x] += ref[x + dx];
				continue;
			}
			unpack(f[i] + (size_t)(r + dy) * stride, n4, t);
			int a = s < 0 ? -s : 0, b = s > 0 ? w - s : w;
			for (int x = 0; x < a; x++)
				o[x] += ref[x + dx];
			for (int x = a; x < b; x++)
				o[x] += t[x + s + dx];
			for (int x = b; x < w; x++)
				o[x] += ref[x + dx];
		}
	}
	free(ref);
	free(t);
}

#define S(a, b) { unsigned _t = a < b ? a : b; b = a < b ? b : a; a = _t; }
static unsigned med9(unsigned p0, unsigned p1, unsigned p2, unsigned p3, unsigned p4,
		     unsigned p5, unsigned p6, unsigned p7, unsigned p8)
{
	S(p1, p2) S(p4, p5) S(p7, p8) S(p0, p1) S(p3, p4) S(p6, p7) S(p1, p2) S(p4, p5) S(p7, p8)
	S(p0, p3) S(p5, p8) S(p4, p7) S(p3, p6) S(p1, p4) S(p2, p5) S(p4, p7) S(p4, p2) S(p6, p4)
	S(p4, p2)
	return p4;
}

/* rows y0..y1 of in with pixels far from the median of their 3x3 same-colour neighbourhood
 * (hot, dead, stuck) replaced by it; edges replicate like OpenCV's medianBlur */
void fix_rows(const uint16_t *in, int w, int h, unsigned th, int y0, int y1, uint16_t *out)
{
	for (int y = y0; y < y1; y++) {
		const uint16_t *u = in + (size_t)(y >= 2 ? y - 2 : y) * w, *c = in + (size_t)y * w,
			       *d = in + (size_t)(y + 2 < h ? y + 2 : y) * w;
		uint16_t *o = out + (size_t)y * w;
		for (int x = 0; x < w; x++) {
			int l = x >= 2 ? x - 2 : x, r = x + 2 < w ? x + 2 : x;
			unsigned p = c[x], m = med9(u[l], u[x], u[r], c[l], p, c[r], d[l], d[x], d[r]);
			unsigned diff = p > m ? p - m : m - p, lim = m / 2 > th ? m / 2 : th;
			o[x] = diff > lim ? m : p;
		}
	}
}

/* 1/4 scale RGB (float, mean of one frame minus black) of rows y0..y1 (multiples of 4) of a GRBG sum */
void quads(const uint16_t *in, int w, int n, float black, int y0, int y1, float *q)
{
	int qw = w / 4;
	float k = 1.0f / n;
	for (int y = y0; y < y1; y += 4) {
		float *o = q + (size_t)(y / 4) * qw * 3;
		for (int x = 0; x < qw * 4; x += 4, o += 3) {
			unsigned r = 0, g = 0, b = 0;
			for (int j = 0; j < 4; j += 2) {
				const uint16_t *a = in + (size_t)(y + j) * w + x, *c = a + w;
				g += a[0] + a[2] + c[1] + c[3];
				r += a[1] + a[3];
				b += c[0] + c[2];
			}
			o[0] = r * k / 4 - black;
			o[1] = g * k / 8 - black;
			o[2] = b * k / 4 - black;
		}
	}
}

/* GRBG sum -> white balanced 16-bit through per-colour tables (G, R, B) */
void wb_rows(const uint16_t *in, int w, int y0, int y1, const uint16_t *lg, const uint16_t *lr,
	     const uint16_t *lb, uint16_t *out)
{
	for (int y = y0; y < y1; y++) {
		const uint16_t *a = in + (size_t)y * w, *ev = (y & 1) ? lb : lg, *od = (y & 1) ? lg : lr;
		uint16_t *o = out + (size_t)(y - y0) * w;
		for (int x = 0; x + 1 < w; x += 2) {
			o[x] = ev[a[x]];
			o[x + 1] = od[a[x + 1]];
		}
	}
}

/* 16-bit BGR -> colour matrix (3x4, BGR) -> tone table -> 8-bit luma (OpenCV's BGR2GRAY weights) */
void ccm_luma(const uint16_t *bgr, size_t npix, const float *m, const uint8_t *tone, uint8_t *out)
{
	for (size_t i = 0; i < npix; i++, bgr += 3) {
		float b = bgr[0], g = bgr[1], r = bgr[2];
		unsigned c[3];
		for (int k = 0; k < 3; k++) {
			float v = m[4 * k] * b + m[4 * k + 1] * g + m[4 * k + 2] * r + m[4 * k + 3];
			c[k] = tone[v < 0 ? 0 : v > 65535 ? 65535 : (unsigned)(v + 0.5f)];
		}
		out[i] = (c[0] * 1868 + c[1] * 9617 + c[2] * 4899 + 8192) >> 14;
	}
}
