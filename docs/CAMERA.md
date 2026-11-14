# Camera: QR codes

In Photo mode the camera app scans the viewfinder about three times a second for a QR code, on a copy of the
frame shrunk to 800 px, in a thread of its own at low priority. It skips frames while a photo is taken, a
countdown runs, the screen is off or the app is paused, and when QR CODES is off in the settings sheet (on by
default, remembered in `~/.config/phonecam.json`). The decoder is OpenCV's `QRCodeDetector`, already installed for
the camera itself (`py3-opencv`), so there is no new package. A code covering under about a tenth of the frame width
is not read.

A pill near the bottom names what was found: the host of a link, `Wi-Fi: NAME`, `Contact` or `Text`. It goes
1.5 s after the code leaves the frame. Nothing happens until the pill is tapped:

- link (http or https): opens in the default browser through `xdg-open`. A host over 28 characters, a `user@`
  part or a punycode host shows the whole address first, with OPEN, COPY and CLOSE.
- Wi-Fi: a card with the name and password; JOIN runs `nmcli --ask dev wifi connect NAME` (the same call the
  Settings app uses), COPY PASSWORD uses `wl-copy`.
- anything else, including `mailto:` and `tel:`: the full text with COPY.

Tests: `python3 camera/phonecamlib.py --selfcheck` (the parsing), `python3 camera/test/qrimg.py --selfcheck` (needs
OpenCV, so on the phone). `qrimg.py DIR` writes PNGs of test codes. Headless, `PHONECAM_TESTSRC=1
PHONECAM_QRIMG=code.png PHONECAM_QR_DRY=log.txt` feeds the picture as the camera and writes the actions to
`log.txt` instead of running them; `PHONECAM_DO="3 qrpill 4 qrbtn:OPEN"` taps the pill and a card button.
