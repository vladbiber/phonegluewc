#!/usr/bin/env python3
# touch script for keyboard-test.sh; key positions follow build() in keyboard/phonekbd.c
import sys
W = sys.argv[1]
OW, OH = 1080 / 2.75, 2400 / 2.75
MARGIN = 26  # BAR_ROOM, black under the keys
ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
OFF = [0, 0.5, 1.5]
U = OW / 10
out = []

def op(*a): out.append(" ".join(str(x) for x in a))

def norm(x, y, surface_h):
    return f"{x / OW:.5f}", f"{(OH - MARGIN - surface_h + y) / OH:.5f}"

ROW_H, TOP, SH = 52, 48, 48 + 52 * 4  # normal layout, row closed; tests with other sizes change these

def layout(modrow=False, row_h=52, numrow=False):
    global ROW_H, TOP, SH
    ROW_H = row_h
    TOP = 48 + (44 if modrow else 0) + (row_h if numrow else 0)
    SH = TOP + 4 * row_h

def pos(name, laptop=False):
    h = 48 if laptop else ROW_H
    top = 48 * 3 if laptop else TOP
    sh = 48 * 7 if laptop else SH
    for r, row in enumerate(ROWS):
        if name in row:
            return norm((OFF[r] + row.index(name) + 0.5) * U, top + (r + 0.5) * h, sh)
    bottom = top + 3.5 * h
    table = {"shift": (0.75 * U, top + 2.5 * h), "bksp": (9.25 * U, top + 2.5 * h), "page": (0.75 * U, bottom),
             "laptop": (2 * U, bottom), "emoji": (2 * U, bottom), "space": (5 * U, bottom), "enter": (9.25 * U, bottom)}
    if name in table:
        return norm(*table[name], sh)
    if name == "ctrl":
        return norm(OW / 7 * 2.5, 24, sh)
    if name.startswith("sug"):
        return norm(2.2 * U + 4.5 * U / 3 * (int(name[3]) + 0.5), 24, sh)
    bar = {"mods": 0.55 * U, "translate": 1.65 * U, "clip": 7.7 * U, "hide": 8.8 * U, "gear": 9.45 * U}
    if name in bar:
        return norm(bar[name], 24, sh)
    row = ["r-ctrl", "r-super", "r-alt", "r-fn", "r-esc", "r-tab", "r-left", "r-down", "r-up", "r-right"]
    if name in row:
        return norm((row.index(name) + 0.5) * U, 48 + 22, sh)
    if name.startswith("F"):
        n = int(name[1:]) - 1
        return norm((n % 6 + 0.5) * OW / 6, top + (n // 6 + 0.5) * h, sh)
    if name.isdigit() and len(name) == 1:
        return norm(("1234567890".index(name) + 0.5) * U, top - h / 2, sh)
    raise SystemExit("no key " + name)

# the emoji panel: 8 columns on this screen
TILE = OW / 8
def ppos(x, y): return norm(x, y, SH)
def ptap(x, y, wait=250):
    a, b = ppos(x, y); op("d 0", a, b); op("f"); op("u 0"); op("f"); op("w", wait)
def tile(i, wait=250): ptap((i % 8 + 0.5) * TILE, 44 + (i // 8 + 0.5) * TILE, wait)
def tab(i): ptap((i + 1.5) * OW / 10, 22, 300)  # -1 is recent
def drag(name, dx, steps=8):
    x, y = pos(name); op("d 0", x, y); op("f"); op("w 40")
    for s in range(1, steps + 1):
        op("m 0", f"{float(x) + dx / OW * s / steps:.5f}", y); op("f"); op("w 16")
    op("u 0"); op("f"); op("w 250")
def keys(n): op("w 150"); op(f"x cp {W}/keys.txt {W}/keys-{n}.txt"); op("w 80")
def text(n): op("w 300"); op(f"x cp {W}/field.txt {W}/s{n}.txt"); op("w 80")

def tap(name, laptop=False, wait=70):
    x, y = pos(name, laptop)
    op("d 0", x, y); op("f"); op("u 0"); op("f"); op("w", wait)

def typ(s, laptop=False):
    for c in s:
        tap("space" if c == " " else c, laptop)

def hold(name, sel=0):
    x, y = pos(name)
    op("d 0", x, y); op("f"); op("w 500")
    if sel:
        op("m 0", f"{float(x) + sel * 48 / OW:.5f}", y); op("f")
    op("u 0"); op("f"); op("w 120")

def swipe(word):
    pts = [pos(c) for c in word]
    op("d 0", *pts[0]); op("f")
    for a, b in zip(pts, pts[1:]):
        for s in range(1, 7):
            t = s / 6
            op("m 0", f"{float(a[0]) + t * (float(b[0]) - float(a[0])):.5f}", f"{float(a[1]) + t * (float(b[1]) - float(a[1])):.5f}"); op("f")
            op("w 8")
    op("u 0"); op("f"); op("w 300")

def snap(n): op("w 350"); op(f"x cp {W}/field.txt {W}/s{n}.txt"); op("w 80")
def shot(n): op("w 300"); op(f"x {sys.argv[0].rsplit('/', 1)[0]}/wshot {W}/{n}.ppm"); op("w 400")

def t(x, y, wait=500):
    op("d 0", x, y); op("f"); op("u 0"); op("f"); op("w", wait)

def pillup():
    op("d 0 0.5 0.995"); op("f")
    for i in range(12):
        op("m 0 0.5", f"{0.995 - 0.05 * (i + 1):.3f}"); op("f"); op("w 16")
    op("u 0"); op("f"); op("w 800")

def fourfingers():
    for i in range(4):
        op(f"d {i}", f"{0.2 + 0.2 * i:.2f}", "0.5"); op("f")
    for s in range(8):
        for i in range(4):
            op(f"m {i}", f"{0.2 + 0.2 * i:.2f}", f"{0.5 - 0.03 * (s + 1):.2f}")
        op("f"); op("w 16")
    for i in range(4):
        op(f"u {i}")
    op("f"); op("w 800")

FIELD = ("0.5", "0.84")
if sys.argv[2:] == ["lock"]:
    op("w 4000"); op(f"x sh {W}/tl.sh"); op("w 1500"); shot("lock-0-open"); t("0.5", "0.5", 400); op(f"x cp {W}/tl.log {W}/tl0.txt"); op("w 200")
    op(f"x qs ipc -p {sys.argv[0].rsplit('/', 2)[0]}/shell call lock lock"); op("w 2000"); op("p locked"); shot("lock-1-locked")
    t("0.5", "0.5", 300); pillup(); fourfingers(); op("p lockgest"); op(f"x cp {W}/tl.log {W}/tl1.txt"); op("w 200")
    op(f"x sh {W}/impostor.sh"); op("w 3000"); shot("lock-2-impostor"); op(f"x sh {W}/impostor-stop.sh"); op("w 500")
    t(*FIELD, 900); op("p lockkbd"); shot("lock-3-keyboard"); op(f"x cp {W}/keys.txt {W}/lockkeys.txt"); op("w 100")
    typ("abc"); shot("lock-3b-typed")
    # on a secret field the hide key takes the gear's place
    tap("gear", wait=800); op("p lockhid"); shot("lock-3c-hidden"); t(*FIELD, 900); op("p lockback")
    tap("enter", wait=700); op("p lockwrong"); shot("lock-4-wrong")
    op("k"); op("w 150"); op("p crashed"); op(f"x {sys.argv[0].rsplit('/', 1)[0]}/wshot {W}/lock-5-crashed.ppm"); op("w 150")
    t("0.5", "0.5", 100); op(f"x cp {W}/tl.log {W}/tl2.txt"); op("w 4000"); op("p relocked"); shot("lock-6-relocked")
    t(*FIELD, 900); typ("test"); tap("enter", wait=1200); op("p unlocked"); shot("lock-7-unlocked"); op(f"x sh {W}/impostor.sh"); op("w 3000"); shot("lock-7b-impostor-open"); op(f"x sh {W}/impostor-stop.sh"); op("w 500")
    t("0.5", "0.5", 400); op(f"x cp {W}/tl.log {W}/tl3.txt"); op("w 200")
    op(f"x qs ipc -p {sys.argv[0].rsplit('/', 2)[0]}/shell call lock lock"); op("w 2000")
    for i in range(6):
        op("k"); op("w 2500")
    op("w 1500"); op("p gaveup"); shot("lock-8-gave-up")
    print("\n".join(out))
    sys.exit()
if sys.argv[2:] == ["lockpw"]:
    # a password with a special letter, held on its base key; a wrong one first, so a pass means it was compared
    op("w 4000"); op(f"x qs ipc -p {sys.argv[0].rsplit('/', 2)[0]}/shell call lock lock"); op("w 2000")
    t(*FIELD, 900); typ("tes")
    a, b = pos("enter"); op("d 0", a, b); op("f"); op("u 0"); op("f"); op("w 900"); op("p lockpwwrong")
    typ("te")
    op(f"x {sys.argv[0].rsplit('/', 1)[0]}/wshot {W}/lockpw-idle.ppm"); op("w 150")
    a, b = pos("s"); op("d 0", a, b); op("f"); op("w 40"); op(f"x {sys.argv[0].rsplit('/', 1)[0]}/wshot {W}/lockpw-down.ppm"); op("w 700"); op(f"x {sys.argv[0].rsplit('/', 1)[0]}/wshot {W}/lockpw-hold.ppm"); op("w 400"); op("u 0"); op("f"); op("w 300")
    a, b = pos("enter"); op("d 0", a, b); op("f"); op("u 0"); op("f"); op("w 1500"); op("p lockpwdone"); shot("lockpw-done")
    print("\n".join(out))
    sys.exit()
if sys.argv[2:] == ["lockedit"]:
    # the lock's clock editor: a hold asks for the password first, Done saves, Cancel forgets, a restart keeps it
    lk = f"x qs ipc -p {sys.argv[0].rsplit('/', 2)[0]}/shell call lock lock"
    def holdbg(): op("d 0 0.5 0.55"); op("f"); op("w 1100"); op("u 0"); op("f"); op("w 900")
    def auth(): typ("test"); tap("enter", wait=1500)
    def page(): op("d 0 0.85 0.62"); op("f"); [(op(f"m 0 {0.85 - 0.08 * s:.2f} 0.62"), op("f"), op("w 16")) for s in range(1, 9)]; op("u 0"); op("f"); op("w 900")
    conf = lambda n: (op(f"x cp {W}/cfg/phonegluewc/phone.conf {W}/{n}.conf"), op("w 100"))
    op("w 4000"); op(lk); op("w 2000"); shot("edit-0-lock")
    holdbg(); op("p ehold"); shot("edit-1-hold")
    auth(); op("p eauth"); shot("edit-2-editor")
    page(); shot("edit-3-thin"); t("0.5", "0.25", 700); shot("edit-4-colours"); t("0.6477", "0.5752", 500)
    t("0.8675", "0.0584", 1200); op("p esaved"); shot("edit-5-saved"); conf("saved")
    op("d 0 0.5 0.75"); op("f"); [(op(f"m 0 0.5 {0.75 - 0.04 * s:.2f}"), op("f"), op("w 16")) for s in range(1, 9)]; op("u 0"); op("f"); op("w 1500"); op("p eswipe")
    op(lk); op("w 2000"); holdbg(); auth(); page(); t("0.5", "0.9232", 1500); t("0.81", "0.578", 1200); shot("edit-6-bold"); t("0.145", "0.0584", 1200)
    op(f"x cp {W}/cfg/phonegluewc/login.conf {W}/login-cancelled.txt"); op("w 100"); op("p ecancel"); shot("edit-7-cancelled"); conf("cancelled")
    op("k"); op("w 5000"); op("p erestart"); shot("edit-8-restart")
    print("\n".join(out))
    sys.exit()
if sys.argv[2:] == ["greeter"]:
    op("w 4000"); op("p greet"); shot("greeter-1"); pillup(); fourfingers(); op("p greetgest")
    t("0.5", "0.927", 700); shot("greeter-2-picker"); t("0.5", "0.858", 700); shot("greeter-3-picked")
    t(*FIELD, 900); op("p greetkbd"); shot("greeter-4-keyboard"); op(f"x cp {W}/keys.txt {W}/greetkeys.txt"); op("w 100")
    typ("abc"); tap("enter", wait=700); shot("greeter-5-wrong"); op(f"x cp {W}/launch.log {W}/l0.txt"); op("w 200")
    typ("test"); tap("enter", wait=1000); op("p greetdone"); shot("greeter-6-done")
    print("\n".join(out))
    sys.exit()
DIR = sys.argv[0].rsplit('/', 1)[0]
def finish():
    op("w 200"); op(f"x sh {W}/kalive.sh"); op("w 200")
    print("\n".join(out))
    sys.exit()

if sys.argv[2:] == ["land1"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); t("0.5", "0.2", 900); keys("land"); finish()

if sys.argv[2:] == ["land2"]:
    # turned: the key places come from the dump of the first run
    rows = {l.split()[0]: l.split() for l in open(f"{W}/keys-land.txt")}
    OW, OH = 2400 / 2.75, 1080 / 2.75
    h = int(rows["size"][4])
    def ltap(n, wait=400):
        x, y = norm(float(rows[n][3]), float(rows[n][4]), h)
        op("d 0", x, y); op("f"); op("u 0"); op("f"); op("w", wait)
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); t("0.5", "0.2", 900)
    ltap("mods"); keys("land-mods"); shot("kbd-land-mods"); ltap("mods")
    ltap("emoji", 800); keys("land-emoji"); shot("kbd-land-emoji"); finish()

if sys.argv[2:] == ["mods"]:
    # the modifier row from the normal layout, in a real terminal
    op("w 1500"); op(f"x foot sh {W}/term.sh"); op("w 2000")
    typ("ab"); tap("enter"); op("w 300")
    tap("mods", wait=400); layout(modrow=True); keys("row")
    tap("r-ctrl"); shot("kbd-m1-latched"); tap("c", wait=400); op(f"x cp {W}/int.txt {W}/s31.txt"); op("w 100")
    tap("r-ctrl"); tap("r-ctrl", wait=200); tap("c", wait=300); tap("c", wait=300); op(f"x cp {W}/int.txt {W}/s32.txt"); op("w 100")
    tap("r-ctrl", wait=200); tap("c"); tap("enter"); op("w 300"); op(f"x cp {W}/int.txt {W}/s33.txt"); op("w 100")
    # locked, then the row is hidden: the next key is plain
    op("w 500"); tap("r-ctrl"); tap("r-ctrl", wait=200); tap("mods", wait=400); layout(); keys("hidden")
    tap("d"); tap("enter"); op("w 300"); op(f"x cp {W}/int.txt {W}/s34.txt"); op("w 100")
    # locked, then the keyboard goes away and comes back
    tap("mods", wait=400); layout(modrow=True); tap("r-ctrl"); tap("r-ctrl", wait=200); tap("r-alt", wait=100); shot("kbd-modifiers")
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op("p dismissed"); op("x phonegluewc-msg workspace 1"); op("w 1200"); layout(); keys("back")
    tap("e"); tap("enter"); op("w 300"); op(f"x cp {W}/int.txt {W}/s35.txt"); op("w 100")
    # a compositor binding on Super, and it types nothing into the terminal
    tap("mods", wait=400); layout(modrow=True); tap("r-super"); tap("g", wait=500); tap("mods", wait=400); layout()
    tap("f"); tap("enter"); op("w 300")
    # a raw terminal shows the exact bytes
    op(f"x foot sh {W}/term2.sh"); op("w 2000")
    tap("mods", wait=400); layout(modrow=True)
    tap("r-ctrl"); tap("r-right", wait=200)
    tap("r-esc"); tap("r-tab")
    tap("r-fn", wait=300); shot("kbd-m2-fn"); tap("F5", wait=300)
    op("w 500"); tap("r-fn"); tap("r-fn", wait=300); tap("F12", wait=300); tap("F1", wait=300); tap("r-left", wait=300); tap("r-fn", wait=300)
    tap("r-alt"); tap("a", wait=200)
    op("w 500"); tap("r-ctrl"); tap("r-fn", wait=300); tap("F2", wait=300)
    tap("r-left", wait=200)
    drag("space", -1.2 * U); drag("bksp", -1 * U)
    op("w 300"); op(f"x cp {W}/raw.bin {W}/s36.bin"); op("w 200")
    finish()

if sys.argv[2:] == ["emoji"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); op(f"x sh {W}/rss.sh before"); op("w 200")
    keys("start"); tap("page", wait=300); keys("sym"); tap("page", wait=300)
    tap("emoji", wait=900); op(f"x sh {W}/rss.sh open"); keys("open"); shot("kbd-emoji")
    tile(0); text(41)
    tab(1); a, b = ppos(0.5 * TILE, 44 + 0.5 * TILE); op("d 0", a, b); op("f"); op("w 600"); shot("kbd-emoji-tones")
    # the popup starts at the left margin: third cell is the second tone
    op("m 0", f"{(4 + 2.5 * 48) / OW:.5f}", b); op("f"); op("u 0"); op("f"); op("w 250"); text(42)
    tab(-1); keys("recent"); shot("kbd-emoji-recent"); tile(0); text(43)
    tab(0)
    # scrolling is not a tap
    a, b = ppos(OW / 2, 150); op("d 0", a, b); op("f")
    for i in range(1, 8):
        op("m 0", a, f"{float(b) - 0.01 * i:.5f}"); op("f"); op("w 16")
    op("u 0"); op("f"); op("w 250"); text(44)
    ptap(2.25 * U, SH - 24, 500); layout(); SH = 40 + 52 + 208; TOP = 92; keys("search")
    typ("rocket"); op("w 300"); shot("kbd-emoji-search"); ptap(0.5 * TILE, 40 + 26); text(45)
    ptap(9.25 * U, 20, 500); SH = 256; TOP = 48; keys("searchdone")
    ptap(0.75 * U, SH - 24, 1500); keys("closed"); op(f"x sh {W}/rss.sh closed"); op("w 200")
    tap("x"); text(46)
    finish()

if sys.argv[2:] == ["emoji-missing"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500")
    tap("emoji", wait=700); keys("nofont"); shot("kbd-emoji-nofont")
    ptap(0.75 * U, SH - 24, 500); tap("x"); text(47)
    finish()

if sys.argv[2:] == ["emoji-mono"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500")
    tap("emoji", wait=700); keys("mono"); shot("kbd-emoji-mono"); tile(0); text(48)
    finish()

if sys.argv[2:] == ["privacy"]:
    NORMAL, SECRET = ("0.5", "0.12"), ("0.5", "0.36")
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500")
    t(*NORMAL, 600)
    op(f"x sh {W}/copy.sh neutral-clip-one"); op("w 900")
    tap("clip", wait=500); keys("clip1"); shot("kbd-clip")
    ptap(OW / 2, 44 + 22, 300); text(61)
    ptap(1.25 * U, SH - 24, 500)
    t(*SECRET, 900); keys("secret"); shot("kbd-secret")
    typ("hunter teh "); typ("hunter "); op("w 300")
    # the key press itself must not show: compare with the idle frame
    op(f"x {DIR}/wshot {W}/secret-idle.ppm"); op("w 150")
    x, y = pos("q"); op("d 0", x, y); op("f"); op("w 40"); op(f"x {DIR}/wshot {W}/secret-down.ppm"); op("w 60"); op("u 0"); op("f"); op("w 200")
    op(f"x {DIR}/wshot {W}/secret-idle2.ppm"); op("w 150")
    x, y = pos("w"); op("d 0", x, y); op("f"); op("w 700"); op(f"x {DIR}/wshot {W}/secret-hold.ppm"); op("w 60"); op("u 0"); op("f"); op("w 200")
    op(f"x sh {W}/copy.sh neutral-clip-two"); op("w 900")
    t(*NORMAL, 900); keys("back")
    tap("clip", wait=500); keys("clip2")
    ptap(1.25 * U, SH - 24, 500)
    typ("xqzvk "); op("w 300")
    tap("clip", wait=500); ptap(8.75 * U, SH - 24, 300); keys("cleared"); ptap(1.25 * U, SH - 24, 500)
    op("x phonegluewc-msg workspace 2"); op("w 1000")
    op(f"x cp -r {W}/state5/phonekbd {W}/before-clear"); op("w 200")
    op("x phonekbd --clear-learned"); op("w 500"); op("x phonegluewc-msg workspace 1"); op("w 1000"); op("x phonegluewc-msg workspace 2"); op("w 1000")
    finish()

if sys.argv[2:] == ["history"]:
    NORMAL, SECRET = ("0.5", "0.12"), ("0.5", "0.36")
    def hs(name): op(f"x sh {W}/hs.sh {name}"); op("w 200")
    def setcfg(*lines): op("x sh " + f"{W}/setcfg.sh " + " ".join(lines)); op("w 200")
    def show(): op("x phonegluewc-msg workspace 2"); op("w 1000"); op("x phonegluewc-msg workspace 1"); op("w 1200"); t(*NORMAL, 900)
    def abc(): ptap(0.75 * U, SH - 24, 700)
    def copy(v): op(f"x sh {W}/copy.sh {v}"); op("w 900")
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); t(*NORMAL, 600)
    tap("emoji", wait=700); tile(0); abc(); hs("on")
    copy("neutral-clip-one"); tap("clip", wait=500); keys("h-on"); abc()
    # a password field never records, whichever switch is on
    tap("emoji", wait=700); t(*SECRET, 900); keys("h-secret"); hs("secret")
    copy("neutral-clip-two"); t(*NORMAL, 900); tap("clip", wait=500); keys("h-secret-clip"); abc()
    # emoji off: its file goes on the next show, the clipboard list stays
    setcfg("emoji_history=off"); show(); hs("eoff")
    tap("clip", wait=500); keys("h-eoff-clip"); abc()
    tap("emoji", wait=700); keys("h-eoff"); tile(0); text(101); abc(); hs("eoff2")
    # clipboard off: the list goes, the emoji file records again
    setcfg("emoji_history=true", "clipboard_history=false"); show()
    copy("neutral-clip-three"); tap("clip", wait=500); keys("h-coff"); shot("kbd-clip-off")
    ptap(3.5 * OW / 6, 22, 600); text(102); abc()
    tap("emoji", wait=700); tile(0); abc(); hs("coff")
    # both clear actions, with the switches on
    setcfg("emoji_history=on", "clipboard_history=on"); show(); copy("neutral-clip-four")
    tap("clip", wait=500); keys("h-on2"); abc()
    op("x phonekbd --clear-emoji-history"); op("w 300"); hs("cleared")
    # with the keyboard up, then hidden
    op("x phonekbd --clear-clipboard-history"); op("w 300")
    tap("clip", wait=500); keys("h-cleared-up"); abc()
    copy("neutral-clip-five"); tap("clip", wait=500); keys("h-on3"); abc()
    op("x phonegluewc-msg workspace 2"); op("w 1000")
    op("x phonekbd --clear-clipboard-history"); op("w 300"); op("x phonegluewc-msg workspace 1"); op("w 1200"); t(*NORMAL, 900)
    tap("clip", wait=500); keys("h-cleared"); abc()
    # the settings page writes the layout file while the keyboard is hidden
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op(f"x sh {W}/setlayout.sh laptop"); op("w 200")
    op("x phonegluewc-msg workspace 1"); op("w 1200"); t(*NORMAL, 900); keys("h-laptop")
    finish()

if sys.argv[2:] == ["histoff"]:
    op("w 1500"); op(f"x sh {W}/hs.sh start"); op("w 200"); op(f"x sh {W}/field.sh"); op("w 2500"); op(f"x sh {W}/hs.sh shown"); op("w 200")
    tap("emoji", wait=700); keys("hoff"); tile(0); text(103); ptap(0.75 * U, SH - 24, 700); op(f"x sh {W}/hs.sh after"); op("w 200")
    op(f"x sh {W}/copy.sh neutral-clip-five"); op("w 900"); tap("clip", wait=500); keys("hoff-clip"); finish()

if sys.argv[2:] == ["features"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); shot("kbd-predict-start")
    typ("hi"); text(71)                       # capital at the start of the field
    tap("space"); tap("space"); typ("t"); text(72)  # double space, then a capital
    typ("he "); op("w 200"); shot("kbd-predict"); tap("sug0", wait=200); text(73)
    tap("enter"); typ("abc"); drag("space", -1.2 * U); typ("x"); text(74)
    drag("space", 1.2 * U); tap("enter", wait=300); typ("one two"); op("w 200"); drag("bksp", -1 * U); text(75)
    tap("enter", wait=300); hold("q"); hold("m"); text(76)
    finish()

if sys.argv[2:] == ["features2"]:
    # number row, taller keys
    layout(row_h=52 * 1.2, numrow=True)
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); keys("numrow"); shot("kbd-numrow")
    tap("1"); tap("7"); tap("space"); text(81)
    typ("teh "); text(82)  # Romanian only: not an English typo
    finish()

if sys.argv[2:] == ["features3"]:
    # one handed on the right, red theme, feedback on
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); keys("onehand"); shot("kbd-onehand")
    V = 0.084 * OW
    ptap(0.16 * OW + 6 * V, 48 + 78); ptap(0.16 * OW + 7.5 * V, 48 + 26); text(91)
    ptap(0.08 * OW, 100, 400); keys("swapped")
    ptap(6 * V, 48 + 78); text(92)
    ptap(0.92 * OW, 204, 500); keys("full")
    tap("space"); typ("mananc "); text(93)
    finish()

if sys.argv[2:] == ["english"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); keys("english")
    hold("a"); hold("s"); text(131); finish()

if sys.argv[2:] == ["plang-ro"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500")
    typ("because mananc "); text(201); finish()

if sys.argv[2:] == ["plang-en"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500")
    typ("mananc teh "); text(202); finish()

if sys.argv[2:] == ["plang-empty"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); keys("plang-empty")
    typ("teh "); keys("plang-empty2"); text(203); hold("a"); text(206); finish()

if sys.argv[2:] == ["plang-live"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500")
    typ("mananc "); text(204)
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op(f"x sh {W}/setcfg.sh predict_languages=en"); op("w 200")
    op("x phonegluewc-msg workspace 1"); op("w 1000"); t("0.5", "0.2", 900)
    typ("mananc "); text(205); finish()

if sys.argv[2:] == ["memlang"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500")
    typ("the people mananc hello "); op(f"x sh {W}/rss.sh mem-shown"); op("w 200")
    op("x phonegluewc-msg workspace 2"); op("w 2500"); op(f"x sh {W}/rss.sh mem-hidden"); op("w 200"); finish()

if sys.argv[2:] == ["strip"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); shot("kbd-strip-empty")
    typ("internationaliz"); shot("kbd-strip-long"); keys("strip-long"); tap("space")
    typ("the "); shot("kbd-strip-next"); keys("strip-next"); typ("mana"); shot("kbd-strip-ro"); finish()

if sys.argv[2:] == ["chevron"]:
    def g(l): op("w 500"); op(f"g {l}")
    def strip(x, y=5, wait=300): ptap(x, SH + y, wait)
    CHEV = OW / 2 + 66
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); shot("kbd-chevron"); keys("chev"); g("cstart")
    # the last line of the bottom row still types
    a, b = norm(5 * U, SH - 1, SH); op("d 0", a, b); op("f"); op("u 0"); op("f"); op("w 200"); typ("a"); text(210)
    # beside the hide area, and over a key: nothing types, nothing hides
    strip(CHEV - 6, 24); strip(CHEV + 56 + 8, 24); strip(2 * U, 24); text(211); g("cbeside")
    # a drag that starts on it is not a tap
    a, b = norm(CHEV + 20, SH + 5, SH); op("d 0", a, b); op("f"); op("m 0", f"{(CHEV + 50) / OW:.5f}", b); op("f"); op("u 0"); op("f"); op("w 300"); g("cdrag")
    strip(CHEV + 20, 24, wait=500); g("chidden"); op("w 1000"); g("cstay")
    # Qt sends its state only when a field is enabled, so a tap in the same field says nothing
    t("0.5", "0.2", 900); g("cretap")
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op("x phonegluewc-msg workspace 1"); op("w 1000"); t("0.5", "0.2", 900); g("cback")
    typ("b"); text(212); op(f"x sh {W}/rss.sh chevron-shown"); op("w 100")
    tap("gear", wait=800); g("cgear"); op(f"x cp {W}/settings.txt {W}/settings-1.txt"); op("w 100"); text(213)
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op("x phonegluewc-msg workspace 1"); op("w 1000"); t("0.5", "0.2", 900); g("cgearback")
    # the hide key in the top strip, dark then light
    def back(): op("x phonegluewc-msg workspace 2"); op("w 1000"); op("x phonegluewc-msg workspace 1"); op("w 1000"); t("0.5", "0.2", 900)
    shot("kbd-hide-dark"); tap("hide", wait=800); g("khide"); text(214); back(); g("khideback"); typ("c"); text(215)
    op(f"x cp {W}/cfg-light {W}/cfg/phonekbd/config"); op("w 100"); tap("hide", wait=800); back(); shot("kbd-hide-light"); g("klight")
    tap("hide", wait=800); g("klighthide"); back(); g("klightback")
    finish()

if sys.argv[2:] == ["chevron-secret"]:
    def g(l): op("w 500"); op(f"g {l}")
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); t("0.5", "0.36", 900); keys("chev-secret"); shot("kbd-chevron-secret")
    ptap(OW / 2 + 86, SH + 5, 500); g("csecret")
    # where the gear would be, on the top strip
    # where the gear would be is the hide key here
    typ("ab"); tap("gear", wait=800); g("csecretgear"); op(f"x cp {W}/secret.txt {W}/s216.txt"); op("w 100")
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op("x phonegluewc-msg workspace 1"); op("w 1000"); t("0.5", "0.36", 900); g("csecretback")
    finish()

if sys.argv[2:] == ["options"]:
    def again(*lines):
        op("x phonegluewc-msg workspace 2"); op("w 1000"); op(f"x sh {W}/setcfg.sh " + " ".join(lines)); op("w 200")
        op("x phonegluewc-msg workspace 1"); op("w 1000"); t("0.5", "0.2", 900)
    def press(name, ms):
        a, b = pos(name); op("d 0", a, b); op("f"); op("w", ms); op("u 0"); op("f"); op("w 250")
    def down(name, n):
        a, b = pos(name); op("d 0", a, b); op("f"); op("w 40"); op(f"x {sys.argv[0].rsplit('/', 1)[0]}/wshot {W}/{n}.ppm"); op("w 100"); op("u 0"); op("f"); op("w 200")
    S85, S115 = 44.2, 59.8
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); shot("kbd-opt-default"); keys("opt-default")
    again("height=small", "number_row=on"); layout(row_h=S85, numrow=True); shot("kbd-opt-small-numrow"); keys("opt-small")
    typ("qam1"); text(220)
    again("height=large"); layout(row_h=S115); shot("kbd-opt-large"); keys("opt-large"); typ("qm"); text(221)
    again("height=85%"); layout(row_h=S85); keys("opt-pct"); typ("z"); text(222)
    # every value bad: the same keyboard as with no file
    again("height=banana", "number_row=maybe", "theme=banana", "accent=pink", "key_borders=2", "corner_hints=x", "key_preview=x", "long_press=x", "vibrate=x", "sound=x")
    layout(); shot("kbd-opt-bad"); keys("opt-bad"); typ("p"); text(223)
    for th in ("light", "contrast", "red", "dark"):
        again(f"theme={th}"); typ("h"); shot(f"kbd-opt-theme-{th}"); op(f"x sh {W}/rss.sh theme-{th}-shown"); op("w 100")
        op("x phonegluewc-msg workspace 2"); op("w 1000"); op(f"x sh {W}/rss.sh theme-{th}-hidden"); op("w 100"); op("x phonegluewc-msg workspace 1"); op("w 800")
    # a capture takes longer than a normal hold: the long delay keeps it a press
    again("long_press=long"); down("g", "kbd-opt-bubble")
    again("theme=light", "long_press=long"); down("g", "kbd-opt-light-press")
    op(f"x sh {W}/scheme.sh 'prefer-dark'"); again("theme=system"); shot("kbd-opt-system-dark")
    op(f"x sh {W}/scheme.sh 'default'"); again("theme=system"); shot("kbd-opt-system-light")
    op(f"x sh {W}/scheme.sh none"); again("theme=system"); shot("kbd-opt-system-none")
    again("accent=blue"); tap("shift", wait=200); shot("kbd-opt-accent-blue"); tap("shift", wait=200); tap("shift", wait=200)
    again("key_borders=off"); shot("kbd-opt-flat")
    again("corner_hints=off"); shot("kbd-opt-nohints")
    again("key_preview=off", "long_press=long"); down("g", "kbd-opt-nobubble")
    typ(" ")
    again("long_press=short"); press("s", 280); text(224)
    again("long_press=normal"); press("s", 280); text(225)
    again("long_press=normal"); press("s", 450); text(226)
    again("long_press=long"); press("s", 450); text(227)
    def ringer(v): op(f"x sh {W}/ringer.sh {v}"); op("w 100")
    def clicks(n): op(f"x cp {W}/sound.txt {W}/sound-{n}.txt"); op("w 100")
    ringer("normal"); again("sound=on"); clicks("normal0"); typ("a"); op("w 400"); clicks("normal")
    for v in ("silent", "vibrate"):
        ringer(v); again("sound=on"); clicks(v + "0"); typ("a"); op("w 400"); clicks(v)
    finish()

if sys.argv[2:] == ["predoff"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); shot("kbd-strip-predict-off"); keys("predoff"); op(f"x sh {W}/maps.sh predoff"); op("w 100")
    typ("teh "); keys("predoff2"); text(111); tap("bksp", wait=150); text(112); finish()

if sys.argv[2:] == ["coroff"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); keys("coroff")
    typ("teh "); text(113); finish()

if sys.argv[2:] == ["bothoff"]:
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); op(f"x sh {W}/maps.sh bothon"); op("w 100"); op(f"x sh {W}/rss.sh both-on"); op("w 100")
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op(f"x sh {W}/setcfg.sh predict=off autocorrect=off"); op("w 200")
    op("x phonegluewc-msg workspace 1"); op("w 1000"); t("0.5", "0.2", 900)
    keys("bothoff"); op(f"x sh {W}/maps.sh bothoff"); op("w 100"); op(f"x sh {W}/rss.sh both-off"); op("w 100")
    typ("teh "); text(114)
    op("x phonegluewc-msg workspace 2"); op("w 1000"); op("x phonegluewc-msg workspace 1"); op("w 1000")
    finish()

if sys.argv[2:] == ["translate"]:
    KEYSLAYOUT = (TOP, SH)
    def trlayout():
        global TOP, SH
        TOP, SH = 136, 344
    def keyslayout():
        global TOP, SH
        TOP, SH = KEYSLAYOUT
    def langlayout():
        global SH
        SH = 44 + 44 * 7 + 48
    def kids(n): op(f"x sh {W}/kids.sh {n}"); op("w 100")
    def inbar(x): ptap(x * U, 22, 500)
    def langs(n): keys(n)
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); keys("tr-closed"); op(f"x sh {W}/rss.sh tr-before"); op("w 100"); kids("closed")
    tap("translate", wait=600); trlayout(); keys("tr-none"); shot("kbd-translate-none"); op(f"x cp {W}/reqs {W}/reqs-opened"); op("w 100")
    # the list is read only once it is asked for
    inbar(8.05); langlayout(); op("w 900"); keys("lang-list"); shot("kbd-languages")
    ptap(5 * U, 44 + 44 * 1.5, 400); keys("lang-sel"); op(f"x cp {W}/reqs {W}/reqs-listed"); op("w 100")
    ptap(6 * U, SH - 24, 2500); keys("lang-done"); shot("kbd-languages-done"); op(f"x cp {W}/data/phonekbd/words.tsv {W}/merged-ui.tsv"); op("w 100")
    ptap(1 * U, SH - 24, 500); trlayout(); keys("tr-ready")
    typ("hi"); op("w 400"); kids("waiting"); op("w 1000"); keys("tr-result"); shot("kbd-translate-result"); kids("after")
    ptap(5 * U, 84 + 26, 500); keyslayout(); text(141); keys("tr-inserted")
    # the other way round, then a translator that never ends must go when the text changes and the panel closes
    tap("translate", wait=600); trlayout(); keys("tr-reopen"); inbar(3.7); keys("tr-swapped"); op(f"x cp {W}/cfg/phonekbd/config {W}/config-swapped"); op("w 100")
    typ("zz"); op("w 1000"); kids("slow"); op(f"x cp {W}/stubpid {W}/stubpid-slow"); op("w 100"); tap("bksp"); op("w 150"); op(f"x sh {W}/grp.sh edit"); op("w 100")
    tap("z"); op("w 1000"); op(f"x cp {W}/stubpid {W}/stubpid-slow"); op("w 100"); inbar(9.35); keyslayout(); op("w 300"); op(f"x sh {W}/grp.sh closed"); op("w 100"); kids("closed2")
    op("w 200"); op(f"x sh {W}/rss.sh tr-after"); op("w 100"); shot("kbd-after-translate")
    # delete it again from the same list
    tap("translate", wait=600); trlayout(); inbar(8.05); langlayout(); op("w 900"); keys("lang-list2")
    ptap(5 * U, 44 + 44 * 1.5, 400); ptap(6 * U, SH - 24, 1200); keys("lang-removed"); op(f"x cp {W}/reqs {W}/reqs-removed"); op("w 100")
    ptap(1 * U, SH - 24, 500); trlayout(); keys("tr-gone"); inbar(9.35); keys("tr-end")
    finish()

if sys.argv[2:] == ["force"]:
    def sig(n, label): op(f"x sh {W}/sig.sh {n}"); op("w 150"); op(f"x sh {W}/sig.sh {n}"); op("w 900"); op(f"g {label}")
    op("w 2500"); sig("USR1", "fup"); keys("force")
    tap("q", wait=200); sig("USR2", "fdown")
    op("x sh " + f"{W}/field.sh"); op("w 2500"); t("0.5", "0.36", 900); op("g fsecret"); keys("force-secret")
    sig("USR1", "fover"); sig("USR2", "fhidden"); op("x true"); op("w 1000"); op("g fstill")
    finish()

if sys.argv[2:] in (["pw"], ["pw-removed"], ["pw-en"]):
    SECRET = ("0.5", "0.36")
    mode = sys.argv[2]
    op("w 1500"); op(f"x sh {W}/field.sh"); op("w 2500"); t(*SECRET, 900); keys(mode)
    if mode == "pw":
        shot("kbd-pw-corners")
        op(f"x {DIR}/wshot {W}/pw-idle.ppm"); op("w 150")
        x, y = pos("s"); op("d 0", x, y); op("f"); op("w 40"); op(f"x {DIR}/wshot {W}/pw-down.ppm"); op("w 700"); op(f"x {DIR}/wshot {W}/kbd-pw-popup.ppm"); op("w 400")
        op("u 0"); op("f"); op("w 200")
        tap("shift", wait=200); hold("s"); hold("t", 1)
        op(f"x cp {W}/secret.txt {W}/s121.txt"); op("w 100")
    if mode == "pw-removed":
        hold("s"); op(f"x cp {W}/secret.txt {W}/s122.txt"); op("w 100")
    if mode == "pw-en":
        hold("s"); op(f"x cp {W}/secret.txt {W}/s123.txt"); op("w 100")
    finish()

if len(sys.argv) > 2:
    # the real shell: the menu's search field, then the app it finds
    op("w 4000")
    t("0.887", "0.92", 2500); t("0.35", "0.947", 1200); op("p search"); shot("kbd-11-menu-empty")
    typ("cam"); op("w 800"); op("p results"); shot("kbd-12-menu-search")
    # the last of many results can be scrolled clear of the keyboard
    op("d 0 0.5 0.55"); op("f")
    for i in range(10):
        op("m 0 0.5", f"{0.55 - 0.04 * (i + 1):.3f}"); op("f"); op("w 40")
    op("u 0"); op("f"); op("w 300")
    op("d 0 0.5 0.55"); op("f")
    for i in range(10):
        op("m 0 0.5", f"{0.55 - 0.04 * (i + 1):.3f}"); op("f"); op("w 40")
    op("u 0"); op("f"); op("w 900"); shot("kbd-15-menu-scrolled")
    for j in range(2):
        op("d 0 0.5 0.15"); op("f")
        for i in range(10):
            op("m 0 0.5", f"{0.15 + 0.04 * (i + 1):.3f}"); op("f"); op("w 40")
        op("u 0"); op("f"); op("w 500")
    t("0.148", "0.178", 1200); op("p searched"); op("w 300")
    finish()
op("w 1500")
op(f"x sh {W}/field.sh"); op("w 2500"); op("p shown"); op(f"x sh {W}/rss.sh shown"); op("w 300")
shot("kbd-1-empty")
typ("hi"); snap(1)
typ(" hell"); shot("kbd-2-suggestions")
tap("sug0"); snap(2)
typ("teh"); shot("kbd-3-autocorrect"); tap("space"); snap(3)
shot("kbd-4-undo")
tap("bksp", wait=150); snap(4)
tap("space"); typ("teh "); snap(5)
hold("a"); hold("s"); hold("t"); snap(6)
x, y = pos("a"); op("d 0", x, y); op("f"); op("w 500"); shot("kbd-5-diacritics"); op("u 0"); op("f"); op("w 120")
tap("bksp", wait=120)
typ(" mananc "); snap(7)
tap("shift"); tap("a"); snap(8)
tap("space"); swipe("salut"); shot("kbd-6-swipe"); snap(9)
# the lowest pixels of the bottom row belong to the keyboard, not to the bar
def edge(frac):
    x, y = norm(OW * frac, 48 + 52 * 4 - 2, 48 + 52 * 4); op("d 0", x, y); op("f"); op("u 0"); op("f"); op("w 100")
edge(0.298); snap(20); edge(0.55); snap(21); edge(0.797); snap(22)
tap("page", wait=300); shot("kbd-13-symbols"); tap("page", wait=300)
tap("clip", wait=500); ptap(3 * U, SH - 24, 500); keys("laptop"); shot("kbd-7-laptop")
x, y = norm(OW / 7 * 6.5, 24, 48 * 7); op("d 0", x, y); op("f"); op("u 0"); op("f"); op("w 300"); shot("kbd-14-fn"); op("d 0", x, y); op("f"); op("u 0"); op("f"); op("w 300")
op("x phonegluewc-msg workspace 2"); op("w 800"); op("p hidden"); op("w 1500"); op(f"x sh {W}/rss.sh hidden"); op("w 300")
op(f"x foot sh {W}/term.sh"); op("w 2000")
typ("ab", True); tap("shift", True); tap("c", True); tap("enter", True); op("w 300")
shot("kbd-8-laptop-foot")
# one tap: latches for one key
tap("ctrl", True); shot("kbd-9-ctrl-latched"); tap("c", True, 400); op(f"x cp {W}/int.txt {W}/s11.txt"); op("w 100")
# double tap: stays, then a third tap frees it
tap("ctrl", True); tap("ctrl", True, 200); shot("kbd-10-ctrl-locked")
tap("c", True, 300); tap("c", True, 300); op(f"x cp {W}/int.txt {W}/s12.txt"); op("w 100"); tap("ctrl", True, 200)
tap("z", True); tap("enter", True); op("w 400")
# the bar under the keyboard still takes the swipe
op("d 0 0.5 0.985"); op("f"); op("w 60"); op("m 0 0.5 0.85"); op("f"); op("w 60"); op("p kbdbar"); op("m 0 0.5 0.985"); op("f"); op("u 0"); op("f"); op("w 400")
finish()
