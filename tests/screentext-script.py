#!/usr/bin/env python3
# touch script for screentext-test.sh; bar positions follow barlayout() in screentext/phonetext.c
import sys
W, case = sys.argv[1], sys.argv[2]
OW, OH = 1080 / 2.75, 2400 / 2.75
OCR_WAIT = int(sys.argv[3]) if len(sys.argv) > 3 else 15000
TR_WAIT = int(sys.argv[4]) if len(sys.argv) > 4 else 12000
BAR_Y = OH - 26 - 10 - 26
out = []

def op(*a): out.append(" ".join(str(x) for x in a))
def n(x, y): return f"{x / OW:.5f}", f"{y / OH:.5f}"
def tap(x, y, wait=400):
    op("d 0", *n(x, y)); op("f"); op("u 0"); op("f"); op("w", wait)
def shot(name):
    op("x", f"{W}/shot.sh {name}"); op("w", 400)
def hold(wait=800):
    op("d 0", *n(OW / 2, OH - 8)); op("f"); op("w", wait); op("u 0"); op("f")
def drag(x0, y0, x1, y1):
    op("d 0", *n(x0, y0)); op("f"); op("w", 30)
    for i in range(1, 9):
        t = i / 8
        op("m 0", *n(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)); op("f"); op("w", 16)
    op("u 0"); op("f"); op("w", 200)
def check(tag):
    op("x", f"{W}/alive.sh {tag}"); op("w", 300)

COPY, SEARCH, TRANSLATE = 92, 169, 270
# the page's first line and its second paragraph, at font size 22 in a window starting at the top
LINE1_Y, LINE2_Y = 37, 66

op("w", 1500)
op("x", f"{W}/page.sh")
op("w", 2500)
if case == "noocr":
    # no reader on this machine: it says so on screen, a tap leaves
    hold(); op("w", 1500); shot("noocr-" + sys.argv[5])
    tap(OW / 2, 200, 800); check("after" + sys.argv[5])
elif case == "trfail":
    # a failed translation leaves a message: with a selection, Copy must still be on screen
    hold(); op("w", OCR_WAIT)
    tap(320, BAR_Y, 1500); shot("st-trfail")
    drag(30, LINE1_Y, 230, LINE1_Y); shot("st-trfail-selected")
    tap(COPY, BAR_Y); op("x", f"{W}/paste.sh clip3"); op("w", 500)
    tap(OW / 2, 650, 600)
elif case == "en":
    # a slow drag that passes the hold time moving is still the overview drag
    x, y = n(OW / 2, OH - 8)
    op("d 0", x, y); op("f"); op("w", 150)
    op("m 0", x, f"{(OH - 60) / OH:.5f}"); op("f"); op("w", 500)
    op("m 0", x, f"{(OH - 300) / OH:.5f}"); op("f"); op("w", 100)
    op("p", "slowdrag"); op("u 0"); op("f"); op("w", 500)
    check("afterdrag")
    op("c 0"); op("f")
    tap(OW / 2, 200, 600)  # back to the app from the overview
    op("p", "backtoapp")
    hold(); op("w", 300); shot("st-reading")
    op("w", OCR_WAIT); shot("st-ready"); op("p", "ready")
    drag(30, LINE1_Y, 230, LINE1_Y); shot("st-selected")
    tap(COPY, BAR_Y); op("x", f"{W}/paste.sh clip1"); op("w", 500); shot("st-copied")
    tap(TRANSLATE, BAR_Y, TR_WAIT); shot("st-translated")
    tap(OW / 2, BAR_Y, 400); shot("st-original")
    tap(OW / 2, 650, 600); check("aftertap")
    hold(); op("w", OCR_WAIT)
    drag(30, LINE1_Y, 100, LINE1_Y)
    tap(SEARCH, BAR_Y, 700); check("aftersearch")
    hold(); op("w", OCR_WAIT)
    x, y = n(OW / 2, OH - 8)
    op("d 0", x, y); op("f"); op("w", 30); op("m 0", x, f"{(OH - 22) / OH:.5f}"); op("f"); op("w", 30); op("u 0"); op("f"); op("w", 600)
    check("afterswipe")
else:
    op("w", 800); op("p", "kbdup")
    hold(); op("w", 500); op("p", "frozen"); op("w", OCR_WAIT); shot("st-ro-ready"); op("x", f"{W}/rss.sh")
    op("w", 300)
    drag(30, LINE1_Y, OW - 40, LINE2_Y); tap(COPY, BAR_Y); op("x", f"{W}/paste.sh clip2"); op("w", 500)
    tap(TRANSLATE, BAR_Y, TR_WAIT); shot("st-ro-translated")
    tap(OW / 2, 650, 600); check("aftertap2")
op("w", 300)
op("x", f"{W}/idle.sh")
op("w", 400)
op("p", "done")
print("\n".join(out))
