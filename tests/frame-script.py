#!/usr/bin/env python3
# touch script for frame-test.sh: frame-script.py WORKDIR MODE
import sys
W, mode = sys.argv[1], sys.argv[2]
HERE = sys.argv[0].rsplit("/", 1)[0]

def op(*a): print(*a)
def f(): op("f")
TF = 90 if mode == "landscape" else 0
def panel(x, y):
    """the touch panel stays in the phone's portrait coordinates"""
    x, y = float(x), float(y)
    return {0: (x, y), 90: (y, 1 - x), 270: (1 - y, x)}[TF]
def down(x, y): op("d 0", *panel(x, y)); f()
def move(x, y): op("m 0", *panel(x, y)); f()
def t(x, y, wait=800): down(x, y); op("u 0"); f(); op("w", wait)
def shot(n): op("w 300"); op(f"x {HERE}/wshot {W}/{n}.ppm"); op("w 400")
def state(n): op("g", n); shot(n)
def pillopen():
    down(0.5, 0.995)
    for s in range(1, 9): move(0.5, 0.995 - 0.5 * s / 8)
    op("w 200"); op("p pill"); op("u 0"); f(); op("w 800")
def closeov(): t(0.5, 0.5, 1000)
def app(name, wait=1000, *env): op("x", *env, f"sh {W}/tl.sh {name}"); op("w", wait)
def drop():
    down(0.5, 0.3); op("w 400")
    move(0.3, 0.3); move(0.05, 0.3); op("w 600"); op("u 0"); f(); op("w 900")  # past CARRY_EDGE_MS
    t(0.05, 0.5)  # the workspace it landed on
def kill(name): op("x", f"kill $(cat {W}/pid-{name})"); op("w 800")
def rotate(tf, wait=1000):
    global TF
    TF = tf
    op("x", f"sh {W}/rot.sh {tf}"); op("w 300"); op("R"); op("w", wait)

def mdrag(x0, y0, x1, y1, n=6, wait=0):
    op(f"M {x0} {y0}"); f(); op("B 1"); f()
    if wait: op("w", wait)
    for s in range(1, n + 1):
        op(f"M {x0 + (x1 - x0) * s / n} {y0 + (y1 - y0) * s / n}"); f()
        if wait: op("w", wait)
    op("B 0"); f(); op("w 900")
# a pause before letting go: a quick flick goes to the free workspace instead
def mopen():
    op("M 0.5 0.995"); f(); op("B 1"); f()
    for s in range(1, 7): op(f"M 0.5 {0.995 - 0.495 * s / 6}"); f()
    op("w 300"); op("B 0"); f(); op("w 1200")
def mtap(x, y): op(f"M {x} {y}"); f(); op("B 1"); f(); op("B 0"); f(); op("w 900")
def four(x0, x1): op("F 1"); mdrag(x0, 0.5, x1, 0.5, 8, 40); op("F 0")
def msg(*a): op("x", "phonegluewc-msg", *a); op("w 700")

op("w 2500")
if mode == "field":
    # app with a field at its bottom, the keyboard comes and goes on its own
    op("x", f"sh {W}/field.sh {sys.argv[3] if len(sys.argv) > 3 else ''}"); op("w 3500"); state("typing"); op("D"); op("w 1500"); state("typed")
elif mode == "landscape":
    app("one"); state("one"); pillopen(); state("overview"); closeov()
    op("x", f"sh {W}/field.sh"); op("w 3500"); state("typing")
elif mode == "cards":
    state("home")
    down(0.5, 0.995)
    for s in range(1, 3): move(0.5, 0.995 - 0.06 * s)
    state("homemid"); op("w 200"); op("u 0"); f(); op("w 800")
    app("orange"); kill("orange")  # used once, so the tray shows its icon
    pillopen(); state("emptycard")
    # nothing to close on an empty card
    down(0.5, 0.5)
    for s in range(1, 7): move(0.5, 0.5 - 0.06 * s)
    op("u 0"); f(); op("w 900"); state("emptyup"); closeov(); state("homeback")
    app("goes", 1000, "TOUCHLOG_CLOSES=1"); state("appopen")
    down(0.5, 0.995)
    for s in range(1, 5): move(0.5, 0.995 - 0.06 * s)
    state("midway"); op("w 200"); op("u 0"); f(); op("w 800")
    state("cards")
    # short and slow stays, the finger rests before it lifts
    down(0.5, 0.5); move(0.5, 0.48); move(0.5, 0.47); op("w 300"); state("swipeheld"); op("u 0"); f(); op("w 800"); state("slowswipe")
    # a real fling closes it
    down(0.5, 0.5)
    for s in range(1, 7): move(0.5, 0.5 - 0.06 * s)
    op("u 0"); f(); op("w 1500"); state("closed"); closeov()
    # an app that does not close comes back to its card
    app("stays"); pillopen(); state("cards2")
    # the way a drag starts decides: up stays up, whatever it does after
    down(0.5, 0.5); move(0.5, 0.47); move(0.2, 0.47); op("w 300"); state("uplocked"); op("u 0"); f(); op("w 900"); state("upback")
    down(0.5, 0.5)
    for s in range(1, 7): move(0.5, 0.5 - 0.06 * s)
    op("u 0"); f(); op("w 500"); state("flung"); op("w 1500"); state("back"); closeov()
    # the pill up from the cards goes home, to the empty workspace
    pillopen(); pillopen(); state("pillhome")
elif mode == "stuck":
    # two windows on one workspace, then every way out, all with the mouse as the finger
    app("one"); app("two"); app("three")
    mopen()                          # on the third, drop it on the second by holding
    op("M 0.5 0.3"); f(); op("B 1"); f(); op("w 400")
    for x in (0.4, 0.2, 0.05): op(f"M {x} 0.3"); f()
    op("w 300"); op("B 0"); f(); op("w 900")
    state("droppedov")
    # the emptied third workspace closes up: the view is already on the shared one
    mtap(0.5, 0.5); state("two-on-1")
    # out of it: quick mouse swipe in the overview
    mopen(); state("ovbefore"); mdrag(0.8, 0.5, 0.2, 0.5); state("quickswipe")
    # back, and now as slowly as a hand with a mouse
    mdrag(0.2, 0.5, 0.8, 0.5); state("quickback")
    mdrag(0.8, 0.3, 0.2, 0.3, 8, 80); state("slowswipe")
    mdrag(0.2, 0.3, 0.8, 0.3); state("slowback")
    # a crawl: the first few pixels take the time a hold would
    mdrag(0.8, 0.3, 0.2, 0.3, 40, 60); state("crawl")
    mdrag(0.2, 0.3, 0.8, 0.3); state("crawlback")
    # slower still: a mouse starting gently, 20 px a second, moving the whole time
    def gentle(x0, x1, y=0.3):
        n = 12; d = 2 / 392 * (1 if x1 > x0 else -1)
        op(f"M {x0} {y}"); f(); op("B 1"); f()
        for s in range(1, n + 1):
            op("w 48"); op(f"M {x0 + d * s} {y}"); f()  # 96 ms a step with the harness clock
        for s in range(1, 7):
            op(f"M {x0 + d * n + (x1 - x0 - d * n) * s / 6} {y}"); f()
        op("B 0"); f(); op("w 900")
    gentle(0.8, 0.2); state("gentle")
    mdrag(0.2, 0.3, 0.8, 0.3); state("gentleback")
    # a reversal right at the end of a long drag must not cancel it
    op("M 0.8 0.3"); f(); op("B 1"); f()
    for x in (0.7, 0.5, 0.3, 0.2, 0.21): op(f"M {x} 0.3"); f()
    op("B 0"); f(); op("w 900"); state("wiggle")
    mdrag(0.2, 0.3, 0.8, 0.3); state("wiggleback")
    mtap(0.5, 0.5); state("tapped")
    # four fingers, with the windows under them, both ways
    four(0.8, 0.2); state("fourleft")
    four(0.2, 0.8); state("fourright")
    four(0.2, 0.8); state("fourhome")
elif mode == "dialog":
    app("dlg", 1000, "TOUCHLOG_DIALOG=1"); state("dlg")
elif mode == "wins":
    # the list of windows for the panel: on map, when the app id changes, on close
    def wins(n): op("x", f"cp {W}/state/phonegluewc/windows {W}/{n}.windows"); op("w 200")
    app("one"); wins("w1")
    app("late", 1000, "TOUCHLOG_LATE_ID=renamed"); wins("w2")
    t(0.5, 0.5); wins("w3")
    kill("one"); wins("w4")
    kill("late"); wins("w5")
elif mode == "reach":
    # the row of workspaces: one empty card past the last app, whichever way you move
    app("one"); mopen(); state("r0")
    mdrag(0.8, 0.3, 0.2, 0.3); state("r1")
    mdrag(0.8, 0.3, 0.2, 0.3); state("r1drag")
    # at the end the drag resists and settles back
    op("M 0.8 0.3"); f(); op("B 1"); f(); op("M 0.6 0.3"); f(); op("M 0.4 0.3"); f(); state("rubber")
    op("B 0"); f(); op("w 900"); state("rubberback")
    mdrag(0.8, 0.3, 0.6, 0.3, 2); state("r1flick")
    msg("workspace", "3"); state("r1msg")
    msg("workspace", "1"); state("r0msg")
    mdrag(0.2, 0.3, 0.8, 0.3); state("nowrapdrag")
    mtap(0.02, 0.5); state("nowraptap")
    mtap(0.5, 0.5); state("rclosed")
    four(0.8, 0.2); state("r1four")
    four(0.8, 0.2); state("r1fourlimit")
    four(0.2, 0.8); state("r0four")
    four(0.2, 0.8); state("r0fournowrap")
    msg("workspace", "2"); app("two"); state("two")
    msg("workspace", "3"); state("r2")
    msg("workspace", "4"); state("r2limit")
    # the moved app leaves a hole: the row closes up and the view goes to the card on its left
    msg("workspace", "2"); msg("move", "3"); msg("workspace", "4"); state("r3")
    msg("workspace", "5"); state("r3limit")
    msg("workspace", "2"); state("hole")
    # an app sent far away closes up the same way; 9 is past the free card
    msg("move", "9"); msg("workspace", "9"); state("far")
    # left empty past the limit: leaving it is the last you see of it
    kill("two"); state("farempty")
    mopen(); mdrag(0.2, 0.3, 0.8, 0.3); state("farback")
    msg("workspace", "9"); state("gonefar")
elif mode == "kbcards":
    app("one"); pillopen(); state("nokb"); closeov()
    op("x", f"sh {W}/field.sh"); op("w 3500"); state("kbup")
    pillopen(); state("kbov"); op("w 1000"); state("kbovlater")
    t(0.5, 0.5, 1500); state("kbback")
elif mode == "conf":
    op("x", f"sh {W}/conf.sh"); op("w 1500"); state("confhome")
    pillopen(); state("confcard"); closeov()
    op("x", f"sh {W}/confoff.sh"); op("w 1500"); state("confoff")
    op("x", "qs ipc -p $PHONEGLUEWC_SHELL call lock lock"); op("w 1500"); state("conflock")
elif mode == "rotate":
    app("one"); state("portrait")
    rotate(90); state("rotated"); pillopen(); state("rotated-overview"); closeov()
    rotate(270); state("rotated-back")
    rotate(0); state("upright")
else:
    app("one"); state("one")
    pillopen(); state("overview"); closeov()
    app("two"); state("two")
    pillopen(); drop(); state("tile2-overview"); closeov(); state("tile2")
    app("three"); pillopen(); drop(); closeov(); state("tile3")
    kill("three"); kill("two"); state("alone")
    op("x", f"TOUCHLOG_FS=1 sh {W}/tl.sh full"); op("w 1000"); state("full")
    op("s"); op("w 500"); state("unfull")
op("w 300")
