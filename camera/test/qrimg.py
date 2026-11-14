#!/usr/bin/python3
"""qrimg.py OUTDIR: writes test pictures of QR codes (a code on grey, 2048x1536) and checks they decode.
python3 qrimg.py --selfcheck: the same in a temporary folder, plus the pill text each one must give"""
import os, sys, tempfile
import cv2
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import phonecamlib as lib

CODES = {
    "url": "https://example.com/menu?table=4",
    "wifi": "WIFI:T:WPA;S:CafeGuest;P:s3cret-pass;;",
    "text": "Hello from a QR code. Line two.",
    "long": "https://this-is-a-very-long-host-name-for-a-test.example.org/path",
    "contact": "BEGIN:VCARD\nVERSION:3.0\nFN:Ana Pop\nTEL:+40123456789\nEND:VCARD",
}


def picture(text, size=620, w=2048, h=1536):
    qr = cv2.QRCodeEncoder.create().encode(text)
    qr = cv2.resize(qr, (size, size), interpolation=cv2.INTER_NEAREST)
    img = np.full((h, w, 3), 118, np.uint8)
    y, x = (h - size) // 2, (w - size) // 2
    img[y:y + size, x:x + size] = cv2.cvtColor(qr, cv2.COLOR_GRAY2BGR)
    return img


def decode(img):
    small = cv2.resize(img, (800, 800 * img.shape[0] // img.shape[1]), interpolation=cv2.INTER_AREA)
    return cv2.QRCodeDetector().detectAndDecode(cv2.cvtColor(small, cv2.COLOR_BGR2GRAY))[0]


def write(out):
    os.makedirs(out, exist_ok=True)
    for name, text in CODES.items():
        cv2.imwrite(os.path.join(out, name + ".png"), picture(text))


if __name__ == "__main__":
    if sys.argv[1:] == ["--selfcheck"]:
        with tempfile.TemporaryDirectory() as d:
            write(d)
            for name, text in CODES.items():
                got = decode(cv2.imread(os.path.join(d, name + ".png")))
                assert got == text, (name, got)
        assert lib.qr_describe(CODES["wifi"])["label"] == "Wi-Fi: CafeGuest"
        print("ok")
    else:
        write(sys.argv[1])
