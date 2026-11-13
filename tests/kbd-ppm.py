# pixel checks on a P6 capture of the 2.75 scale test output, coordinates in logical px
import sys
SC = 2.75
def load(p):
    b = open(p, "rb").read()
    parts, i = [], 0
    while len(parts) < 4:
        j = i
        while b[j] not in b" \n": j += 1
        parts.append(b[i:j]); i = j + 1
    return int(parts[1]), int(parts[2]), b[i:]
def rect(a): return [int(float(v) * SC) for v in a]
cmd = sys.argv[1]
if cmd == "at":
    w, h, d = load(sys.argv[2]); x, y = rect(sys.argv[3:5])
    print(d[(y * w + x) * 3:(y * w + x) * 3 + 3].hex())
elif cmd == "has":
    w, h, d = load(sys.argv[2]); c = bytes.fromhex(sys.argv[3]); x0, y0, x1, y1 = rect(sys.argv[4:8])
    print(int(any(d[(y * w + x) * 3:(y * w + x) * 3 + 3] == c for y in range(y0, min(y1, h)) for x in range(x0, min(x1, w)))))
elif cmd == "ink":
    w, h, d = load(sys.argv[2]); x0, y0, x1, y1 = rect(sys.argv[3:7]); c = d[(y0 * w + x0) * 3:(y0 * w + x0) * 3 + 3]
    print(int(any(d[(y * w + x) * 3:(y * w + x) * 3 + 3] != c for y in range(y0, min(y1, h)) for x in range(x0, min(x1, w)))))
else:
    w, h, a = load(sys.argv[2]); _, _, b = load(sys.argv[3]); x0, y0, x1, y1 = rect(sys.argv[4:8])
    n = sum(a[(y * w + x0) * 3:(y * w + x1) * 3] != b[(y * w + x0) * 3:(y * w + x1) * 3] for y in range(y0, min(y1, h)))
    print(int(n > 0) if cmd == "diffq" else n)
