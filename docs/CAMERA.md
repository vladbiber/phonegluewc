# Camera: QR codes

In Pro mode the camera app scans the viewfinder about three times a second for a QR code, on a copy of the
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

# Camera: Retro mode

The modes are PRO (the normal camera), VIDEO and RETRO. Retro turns the phone into an old camera: the picture is
shrunk to that camera's size first and the look is built on the small picture, so softness, colour smear and
compression blocks have the right scale. A colour filter on a 12 MP photo cannot do that.

Styles (STYLE tile, or the settings sheet), all in `camera/phonecamretro.py` as one table of numbers:

- DIGICAM: an early 2000s compact or phone. Loud colour, burnt highlights, bluish whites, oversharpened, JPEG blocks.
- VHS: camcorder tape. Colour at a twentieth of the width and drawn to the right, sharpening halo, white that
  stops short of white, line noise, the torn band at the bottom, time and date in the corner.
- DREAM: hazy, milky blacks, little colour, glow around lights, heavy compression.
- LIMINAL: yellowed and dim, dark corners, grain.
- NIGHT: the dark as a cheap camera saw it: blacks crushed, shadows blue. LIGHT decides about the LED, as in every style.

The same renderer runs on live frames (`retro_loop` in `phonecam`: camera frame in, 640 x 480 frame out, to the
screen and to the encoder) and on the developed raw photo (`phonecam-develop --retro STYLE`), so the viewfinder,
the clip and the photo agree. In the dark, live frames are averaged with the ones before and smoothed, and the
black level rises: sensor noise becomes soft trails instead of a pattern of pixels. CAPTURE switches the shutter
between photo and clip; PHOTO SIZE is VGA, 1 MP or 2 MP; clips are always VGA. DATE STAMP prints the time.

Frames are turned upright for the way the phone is held before the look goes on (the stamp and the tape lines
have a bottom), so a clip keeps the shape it started with and carries no rotation tag.

Tests, on the phone (they need OpenCV): `python3 camera/phonecamretro.py --selfcheck`;
`python3 camera/phonecamretro.py IN.jpg OUT.jpg VHS` tries a look on any picture;
`PHONECAM_DO="mode:retro 5 set:rstyle=dream 3 shutter 8 set:rcap=video 1 shutter 6 shutter 3 quit"` drives the app.

Day and night: each style has a `dark` set of numbers and moves toward it as the scene gets darker (dusk turns
blue on DIGICAM, violet on VHS, lamps glow, grain comes up). Bright parts bend over under white (`knee`) instead
of clipping, so a sky stays sky. The tiles under the screen (EXPO, COLOR, WARM, GRAIN, BLUR, GLOW) are the
photographer's own corrections on top of the style, for the live picture, clips and photos alike.

The ISO tile sets the sensor gain by hand, as in PRO.

The retro screen is the back of a compact camera: DISP puts the date in the picture or takes it out, MENU opens the settings, the round pad has STYLE in the
middle and ZOOM, LIGHT, TIMER, FILTER around it. SCREEN INFO in the settings clears the screen text and the tiles. Turned sideways the screen is on the left and the keys on the
right. Buttons buzz at the press (BUTTON FEEL).

Volume keys: with the camera in front, volume up takes the picture (or starts and stops a clip) and volume down
zooms, in every mode (VOLUME KEYS in the settings). The compositor keeps sending the keys as button events; the
camera reads `~/.local/state/phonegluewc/button` itself and writes `1` to `camera-keys` next to it while it is
the active window, which is when the shell leaves the volume alone.

FILTER says how much is done to a retro photo after the shutter:

- RAW: the photo is the frame that was on the screen, saved as it is (640 x 480, at once, the sensor keeps running).
- SEMI: the photo is developed from the sensor's raw frames (cleaner, stacked in the dark, any PHOTO SIZE), then
  moved to the brightness and colour of the viewfinder frame taken with it (`phonecamretro.match`), then the look.
- FULL: developed from the raw frames with the developer's own colour, then the look. Colours can differ from
  the viewfinder, which shows the camera driver's own processing.
