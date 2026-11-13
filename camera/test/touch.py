"""touch.py FIFO: a virtual touchscreen (uinput, root). Reads lines from FIFO:
tap X Y | drag X1 Y1 X2 Y2 [MS] | pinch CX CY D1 D2 | quit      coordinates in logical px (432x960)"""
import fcntl, os, struct, sys, time
W, H, SC = 1080, 2400, 2.5
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, SLOT, MTX, MTY, TID, AX, AY = 0x14a, 0x2f, 0x35, 0x36, 0x39, 0, 1
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for bit in (EV_KEY, EV_ABS, EV_SYN):
    fcntl.ioctl(fd, 0x40045564, bit)
fcntl.ioctl(fd, 0x40045565, BTN_TOUCH)
for a in (AX, AY, SLOT, MTX, MTY, TID):
    fcntl.ioctl(fd, 0x40045567, a)
fcntl.ioctl(fd, 0x4004556e, 1)  # INPUT_PROP_DIRECT
absmax, absmin = [0] * 64, [0] * 64
absmax[AX] = absmax[MTX] = W - 1; absmax[AY] = absmax[MTY] = H - 1; absmax[SLOT] = 4; absmax[TID] = 65535
os.write(fd, struct.pack("80sHHHHI", b"camtest-touch", 0x18, 1, 1, 1, 0) + struct.pack("64i", *absmax) + struct.pack("64i", *absmin) + bytes(4 * 128))
fcntl.ioctl(fd, 0x5501)
time.sleep(1.2)
def ev(t, c, v): os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))
def syn(): ev(EV_SYN, 0, 0)
tid = 1
def down(slot, x, y):
    global tid
    ev(EV_ABS, SLOT, slot); ev(EV_ABS, TID, tid); tid += 1; move(slot, x, y, False)
def move(slot, x, y, sl=True):
    if sl: ev(EV_ABS, SLOT, slot)
    ev(EV_ABS, MTX, int(x * SC)); ev(EV_ABS, MTY, int(y * SC))
    if slot == 0: ev(EV_ABS, AX, int(x * SC)); ev(EV_ABS, AY, int(y * SC))
def up(slot): ev(EV_ABS, SLOT, slot); ev(EV_ABS, TID, -1)
while True:
    with open(sys.argv[1]) as f:
        for line in f:
            a = line.split()
            if not a: continue
            if a[0] == "quit":
                fcntl.ioctl(fd, 0x5502); sys.exit(0)
            n = [float(v) for v in a[1:]]
            if a[0] == "tap":
                down(0, n[0], n[1]); ev(EV_KEY, BTN_TOUCH, 1); syn(); time.sleep(.07); up(0); ev(EV_KEY, BTN_TOUCH, 0); syn()
            elif a[0] == "drag":
                ms = n[4] if len(n) > 4 else 400
                down(0, n[0], n[1]); ev(EV_KEY, BTN_TOUCH, 1); syn()
                for i in range(1, 21):
                    time.sleep(ms / 20000); move(0, n[0] + (n[2] - n[0]) * i / 20, n[1] + (n[3] - n[1]) * i / 20); syn()
                time.sleep(.05); up(0); ev(EV_KEY, BTN_TOUCH, 0); syn()
            elif a[0] == "pinch":
                cx, cy, d1, d2 = n
                down(0, cx - d1, cy); down(1, cx + d1, cy); ev(EV_KEY, BTN_TOUCH, 1); syn()
                for i in range(1, 21):
                    d = d1 + (d2 - d1) * i / 20; time.sleep(.02); move(0, cx - d, cy); move(1, cx + d, cy); syn()
                time.sleep(.05); up(0); up(1); ev(EV_KEY, BTN_TOUCH, 0); syn()
            time.sleep(.15)
