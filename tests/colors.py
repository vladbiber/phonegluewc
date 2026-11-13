#!/usr/bin/env python3
# for each hex colour: 1 if the PPM holds at least 200 pixels of exactly it
import sys
d = open(sys.argv[1], "rb").read()
parts = d.split(None, 4)
w, h = int(parts[1]), int(parts[2])
px = d[-w * h * 3:]
print(" ".join("1" if px.count(bytes.fromhex(c)) >= 200 else "0" for c in sys.argv[2:]))
