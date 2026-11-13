/* software drawing shared by the on-screen clients; the includer defines px, bw, bh, sc and face */
static inline void
blend(int x, int y, uint32_t col, float a)
{
	uint32_t d, r, g, b;
	uint32_t ia;

	if (x < 0 || y < 0 || x >= bw || y >= bh || a <= 0)
		return;
	if (a >= 1) {
		px[y * bw + x] = col;
		return;
	}
	d = px[y * bw + x];
	ia = (uint32_t)(a * 256);
	r = ((col >> 16 & 255) * ia + (d >> 16 & 255) * (256 - ia)) >> 8;
	g = ((col >> 8 & 255) * ia + (d >> 8 & 255) * (256 - ia)) >> 8;
	b = ((col & 255) * ia + (d & 255) * (256 - ia)) >> 8;
	px[y * bw + x] = 0xff000000u | r << 16 | g << 8 | b;
}

static void
rrect(float lx, float ly, float lw, float lh, float lr, uint32_t col)
{
	float x = lx * sc, y = ly * sc, w = lw * sc, h = lh * sc, r = lr * sc;
	int x0 = (int)floorf(x), x1 = (int)ceilf(x + w), y0 = (int)floorf(y), y1 = (int)ceilf(y + h);
	float cx = x + w / 2, cy = y + h / 2;

	for (int j = MAX(y0, 0); j < MIN(y1, bh); j++) {
		float qy = fabsf((float)j + 0.5f - cy) - (h / 2 - r);

		for (int i = MAX(x0, 0); i < MIN(x1, bw); i++) {
			float qx = fabsf((float)i + 0.5f - cx) - (w / 2 - r);
			float d;

			/* straight run between the corners needs no maths */
			if (qx < -1 && qy < r - 1 && qy >= -r) {
				if (qy <= 0) {
					px[j * bw + i] = col;
					continue;
				}
			}
			d = (qx > 0 && qy > 0) ? hypotf(qx, qy) - r : MAX(qx, qy) - r;
			blend(i, j, col, 0.5f - d);
		}
	}
}

static uint32_t
utf8_next(const char **s)
{
	const unsigned char *p = (const unsigned char *)*s;
	uint32_t c = *p;
	int n = c < 0x80 ? 0 : c < 0xe0 ? 1 : c < 0xf0 ? 2 : 3;

	if (n)
		c &= 0x3fu >> n;
	p++;
	while (n-- && (*p & 0xc0) == 0x80)
		c = c << 6 | (*p++ & 0x3f);
	*s = (const char *)p;
	return c;
}

static float
textw(const char *s, float size)
{
	float w = 0;

	if (!face)
		return 0;
	FT_Set_Pixel_Sizes(face, 0, (FT_UInt)(size * sc + 0.5f));
	while (*s) {
		if (!FT_Load_Char(face, utf8_next(&s), FT_LOAD_DEFAULT))
			w += (float)face->glyph->advance.x / 64;
	}
	return w / sc;
}

/* centred on (cx, cy) in logical px; fits to maxw by going smaller */
static void
text(const char *s, float cx, float cy, float size, float maxw, uint32_t col)
{
	float w, x, base;

	if (!face || !s || !*s)
		return;
	w = textw(s, size);
	if (maxw > 0 && w > maxw) {
		size = MAX(size * maxw / w, 9);
		w = textw(s, size);
	}
	FT_Set_Pixel_Sizes(face, 0, (FT_UInt)(size * sc + 0.5f));
	x = (cx - w / 2) * sc;
	base = cy * sc + size * sc * 0.35f;
	while (*s) {
		FT_GlyphSlot g;

		if (FT_Load_Char(face, utf8_next(&s), FT_LOAD_RENDER))
			continue;
		g = face->glyph;
		for (unsigned j = 0; j < g->bitmap.rows; j++)
			for (unsigned i = 0; i < g->bitmap.width; i++)
				blend((int)x + g->bitmap_left + (int)i, (int)base - g->bitmap_top + (int)j, col,
					(float)g->bitmap.buffer[j * (unsigned)g->bitmap.pitch + i] / 255.f);
		x += (float)g->advance.x / 64;
	}
}

static const char *
findfont(char *buf, size_t size)
{
	static const char *paths[] = {
		"/usr/share/fonts/noto/NotoSans-Regular.ttf",
		"/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
		"/usr/share/fonts/TTF/NotoSans-Regular.ttf",
		"/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
	};
	const char *e = getenv("PHONEKBD_FONT");
	FILE *p;

	if (e && !access(e, R_OK))
		return e;
	for (size_t i = 0; i < LEN(paths); i++)
		if (!access(paths[i], R_OK))
			return paths[i];
	if ((p = popen("fc-match -f %{file} sans", "r"))) {
		size_t n = fread(buf, 1, size - 1, p);

		buf[n] = 0;
		pclose(p);
		if (n)
			return buf;
	}
	return NULL;
}
