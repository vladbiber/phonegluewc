# Camera UI research

Scope: what cinema cameras, premium stills cameras and pro phone apps expose, and how they lay it out.
Anything tagged "unverified" was not confirmed in a source read for this document.
Source tags in brackets refer to the Sources list at the end.

## Controls that matter

| Control | Who has it | How it is presented |
|---|---|---|
| Frame rate (FPS) | ARRI, RED, Sony BIG6, Blackmagic (BM), BM app, Kino | First item of the status row. ARRI: label turns orange when sensor fps differs from project fps [A35]. BM: tap opens a bottom menu with arrows + slider; separate "off speed frame rate" switch at bottom right [BMPCC]. Sony: Fixed/Variable switch on the same tile [SONY-HOME]. |
| Shutter | All video UIs | Angle or time, user selectable unit. ARRI: 1.0 to 356.0 degrees or 1 s to 1/8000 s, chosen from a preset list plus custom values [A35]. BM app: 1.1 to 360 degrees, or 1/24 to 1/8000 [BMAPP]. BM: small "A" next to the value when auto exposure drives it [BMPCC]. |
| ISO / EI | All | ARRI: EI 160 to 6400, a gain remap that does not change dynamic range [A35]. BM: preset buttons with a 1/3 stop slider under them; dual native ISO 400 / 3200 [BMPCC]. Sony: ISO tile becomes "EI of the base ISO" in Cine EI [SONY-HOME]. |
| Iris | BM, RED, Sony BIG6, Leica, Hasselblad | Status row value. Sony lets the iris tile be swapped for ND (lower left tile) [SONY-HOME]. A fixed-aperture phone module can drop it or reuse the slot. |
| ND | ARRI, Sony Venice/FX6 | ARRI: own home button, FSND 0.6 / 1.2 / 1.8 + clear [A35]. Not applicable without hardware ND. |
| White balance + tint | All | ARRI: Kelvin with CC shown as a superscript exponent, 2000 to 11000 K in 10 K steps, CC -16 to +16 [A35]. BM: WB and TINT as two adjacent top row items; menu has 5 presets, Kelvin slider left, tint right (-50 to +50), 50 K per tap, AWB button with a centre target square [BMPCC]. BM app: Locked / Auto / Manual, 2500 to 10000 K [BMAPP]. |
| Look / LUT | ARRI (look + Textures), Sony (LUT tile), BM, BM app, Kino | BM: LUT icon top left; blue means the LUT is baked into the clip [BMOS]. Kino: one tap "Instant Grade", previewed live, baked into the file, or off to keep the log original; imports .cube [KINO]. |
| Histogram | BM, RED, Halide, Leica, Hasselblad, Moment | BM: RGB histogram bottom left with per channel clip lights on its right side [BMPCC]. RED: RGB histogram flanked by "goal posts" and "traffic lights" [RED-HIST]. Halide: beside the notch, small or enlarged, luma or colour [HALIDE2]. Hasselblad: movable by long press + drag [X2D]. |
| Waveform | ARRI (unverified for on-camera monitor), Halide, Kino, Moment, Filmic | Halide: horizontal scan showing which channels clip [HALIDE2]. Kino: RGB waveform [KINO]. |
| Zebra | BM, BM app, RED, Halide, Moment, Filmic, ARRI (EXP button cycles false colour / zebra) | BM: on/off switch bottom left of its tab, level by slider or arrows, 8 presets [BMPCC]. Halide: colour zebras per clipped channel, also an underexposure/noise zebra [HALIDE2]. |
| False colour | ARRI, RED, BM, BM app, Filmic | Full frame greyscale with signal bands in colour; BM shows the legend on the left edge of the screen [BMPCC]. ARRI toggles it with one dedicated EXP button [A35]. |
| Focus peaking | All | ARRI: modes Color / Aperture (edge only), level 1 to 20, 7 colours [A35]. BM: "peaking" or "colored lines", level slider [BMPCC]. Halide: peaking + loupe that appears only while the focus dial is dragged [HALIDE2]. |
| Magnify | BM, ARRI, Halide, Hasselblad | BM: double tap zooms at the tapped point, pinch up to x8, drag to pan, double tap returns [BMPCC]. |
| Frame guides | ARRI, BM, BM app, RED | BM: slider/arrows through ratios, tap the ratio to type a custom one, opacity setting [BMPCC]. ARRI: frame line files, colour + opacity, centre mark, 2 user rectangles [A35]. |
| Grid / level | BM, Halide, Kino, Hasselblad, Leica | BM: thirds, horizon meter, crosshair, centre dot; horizon lines turn blue when level [BMPCC]. Hasselblad: spirit level as one of the display pages [X2D]. |
| Exposure compensation | Leica, Hasselblad, Halide, BM app | Hasselblad: one exposure scale that shows EV comp in A/S/P and the meter reading in M [X2D]. Leica M11: +/-3 EV in 1/3 steps on the thumbwheel [LEICA-M11]. BM app: +/-3 stops [BMAPP]. Halide: swipe up/down on the viewfinder [HALIDE]. |
| Audio meters | BM, BM app, Kino, Sony BIG6 centre | BM: 2 channel peak meters in dBFS with peak hold; tap opens gain controls [BMPCC]. |
| Timecode / duration | ARRI, BM, BM app, RED | BM: centre of the top row; tap toggles duration / timecode; red while recording [BMPCC]. |
| Storage remaining | ARRI, BM, Kino, Sony, Leica, Hasselblad | BM: minutes remaining per card at the bottom; text turns red at about 5 min, blinks at 2 min, shows "full" [BMPCC]. Stills cameras show remaining frames [X2D, LEICA-M11]. |
| Codec / resolution | ARRI, RED, BM, Sony, Kino | ARRI: in the status section [A35]. BM: can replace the histogram [BMPCC]. Kino: format picker in the upper right with HDR / SDR / Log presets [KINO]. |
| User buttons | ARRI (9 on body + 2 on viewfinder), BM (3), BM app (F1 to F3) | Each has one function and a state LED [A35]. BM app: None / Preset / Toggle [BMAPP]. |

## Layout patterns

### Status row: the same six values everywhere
- ARRI HOME is a 3 over 3 grid of screen buttons around a central status section: top FPS, TC, SHUTTER; bottom EI, ND, WB. The status section shows state (STBY / PREREC / REC / PLAY / ERROR), codec, sensor mode, resolution, power and media [A35]. There is no look button on the Alexa 35 HOME screen in this manual; look and Textures live in the menu.
- Sony BIG6 uses six tiles: FPS, ISO or EI/base ISO, shutter (speed or angle), aperture (swappable for ND), picture profile or LUT, white balance. The centre holds read only status: codec, remaining time, battery, audio meters [SONY-HOME, SONY-BIG6].
- Blackmagic keeps a single text row on top of the live image, left to right: monitor options icon, FPS, shutter, iris, duration/timecode (centre), ISO, WB, tint, power (top right). Bottom row: histogram (bottom left), round record button next to it, storage indicators, audio meters [BMPCC]. Exact left to right order is taken from the manual's section order and figures; treat the precise order as "unverified".
- RED puts the equivalent values in a "Lower Status Row" under the image, with the histogram block as one section of that row; tapping the histogram opens the tools menu [RED-HIST]. The exact item order of the RED row (FPS, ISO, aperture, shutter, WB, resolution, REDCODE) is unverified.
- Common rule: values sit on the image edge as label + number, never as icons only, and every value is itself the button that edits it.

### How a value is adjusted
- Blackmagic pattern (best fit for touch): tap a status value, a panel slides in along the bottom edge. Panel layout: current value at far left with left/right arrows (tap = one step, hold = fast repeat), a slider in the middle, preset chips above, and the Auto switch at the far right. The top row stays visible, so the edited value is still read in place [BMPCC].
- ARRI pattern: each parameter opens a short list of presets; custom values can be added to the list; user buttons step through the list (Shutter / EI / ND / WB Increase and Decrease) [A35]. Lists of a few trusted values beat free sliders for shutter and WB.
- Hasselblad pattern: tap a value, an option list opens, swipe to scroll it [X2D].
- Halide pattern: direct gestures on the viewfinder, swipe up/down for exposure, left/right for focus, "modeled on turning camera dials" [HALIDE]. Kino deliberately has no tap to expose; a swipe down on the viewfinder reveals an exposure dial, to avoid accidental changes [KINO].
- Filmic Pro: two arc sliders on the left and right screen edges (focus / exposure) [FILMIC]. Details beyond the v6 release notes are unverified.

### Auto versus manual, per parameter
- Blackmagic: a small "A" appears next to the shutter or iris value when auto exposure controls it; auto modes are named by what they move (Shutter, Shutter + Iris, Iris + Shutter) [BMPCC]. WB that was hand tuned shows "CWB" instead of a preset name [BMPCC].
- Hasselblad: automatic values are drawn in grey, user controlled values in white. In A mode shutter is grey, in S mode aperture is grey, in P both [X2D].
- Kino: an "Auto" label that lights green when AutoMotion can hold cinematic settings and goes grey when it cannot (for example bright daylight) [KINO].
- Halide: tapping the "AF" button switches to manual focus and swaps in the manual focus tools [HALIDE2].
- BM app: WB and tint each have three states: Locked, Auto, Manual [BMAPP].
- ARRI warns by colour: a label turns orange when the setting conflicts with the project (FPS, TC) [A35].

### What sits near the thumb
- Halide: "All controls fall within easy thumb reach"; rarely needed toggles were moved out of the prime thumb zone; readouts use the screen corners and the notch area; last shot thumbnail bottom left [HALIDE2].
- Kino: controls that may need adjusting during a take sit near the record button; layout works in portrait and landscape; exposure values, audio meters and free disk space are readable at a glance; the viewfinder stays clear [KINO].
- Blackmagic: record button and storage at the bottom, everything editable opens at the bottom edge even though the readouts are at the top [BMPCC].

### Recording state
- Blackmagic: record button, storage bar and timecode all turn red; a flashing "!" over the record button means dropped frames [BMPCC].
- Kino: a large red ring around the screen edge; the record button shrinks and can be dragged sideways into a corner to lock, after which only a swipe stops recording; grade picker and review are disabled mid take [KINO].
- ARRI: state word in the status section (STBY, REC, PREREC) [A35].

### Monitoring overlays are a separate layer from exposure values
- Blackmagic groups zebra, focus assist, frame guides, grids, safe area and false colour behind one "monitor" icon (top left); they open as tabs along the bottom, each with its own on/off switch at bottom left plus a level slider [BMPCC].
- Swipe up or down hides all status text and meters ("full screen mode"); record indicator, guides, grids, peaking and zebra stay [BMPCC]. Swipe left/right opens the slate [BMOS].
- Hasselblad cycles display pages with one button: info, info + histogram, info + grid, info + distance scale, info + spirit level, none [X2D].

### Stills minimalism (Leica, Hasselblad)
- Hasselblad live view shows only: WB, ISO, drive, focus mode, exposure mode, exposure scale, AE lock, aperture, shutter, remaining frames. Icons for default states are hidden (no icon for single drive, AF, stabilisation on) [X2D].
- Hasselblad Control Screen: reached by swiping down from the top; large tiles for mode, aperture, shutter, ISO, EV comp, WB, battery percent, remaining frames; swipe left for the main menu; sensor is off while it shows [X2D].
- Leica M11 status screen: opened with the MENU button; lists ISO, shutter, exposure compensation scale, light balance, battery, remaining frames; info display adds clipping, level gauge, grid, focus peaking [LEICA-M11]. Whether every item is tap editable is unverified.
- Leica SL3 / Q3 (firmware 4.0.0): a customisable Control Center of touch tiles replaces the favourites menu; SL3 uses red accents for photo and yellow for video and swipes between the two [LEICA-SL3, LEICA-Q].

### Phone apps
- Halide: Process Zero = single exposure RAW develop with no computational processing and no multi frame merging, noisier in low light; Image Lab re-develops exposure from the RAW later [HALIDE, HALIDE-P0]. Histogram/waveform/zebra switch to 14 bit sensor data while RAW streaming [HALIDE2].
- Kino: Instant Grade presets per format, .cube import, AutoMotion picks shutter for cinematic blur without computational tricks (the 180 degree target is implied, not stated: unverified), shutter shown as speed or angle, lockable auto WB and exposure, RGB waveform, peaking, long curved focus dial, grid with built in level [KINO].
- Moment Pro Camera: manual ISO, shutter, focus, WB; RGB histogram, waveform, zebra, peaking; flat/log profiles [MOMENT].
- Filmic Pro: arc sliders; live analytics = zebras, clipping, false colour, peaking; histogram and waveform [FILMIC].
- Blackmagic Camera app: same HUD idea as the cameras (lens, FPS, shutter, timecode, ISO, WB, tint, histogram, audio); swipe up/down hides HUD; swipe right dims the screen while recording; each indicator (histogram, audio, storage, battery) can be switched off; focus slider 0.00 to 1.00 with three recallable focus presets [BMAPP].

## Reference numbers

### Shutter
- exposure time = shutter angle / (360 x fps) (quoted in the ARRI manual [A35]).
- 180 degrees at 24 fps = 1/48 s; at 25 = 1/50; at 30 = 1/60; at 60 = 1/120.
- 180 is the default because it exposes for half the frame interval, matching the half disc rotary shutter of film cameras and the motion blur audiences expect. Common alternates: 90 (crisp action), 172.8 (24 fps under 50 Hz lighting), 270 / 360 (low light).
- Longest exposure is 1/fps (360 degrees) [A35].

### Frame rates
23.976, 24, 25, 29.97, 30, 48, 50, 59.94, 60; high speed 100, 120 [BMAPP]. Cinema 24; PAL regions 25/50; NTSC regions 29.97/59.94 [BMPCC].

### ISO
- Full stops: 100, 200, 400, 800, 1600, 3200, 6400, 12800, 25600.
- Third stops: 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200.
- Dual native examples: Blackmagic Pocket 400 / 3200 (crossover at 1250) [BMPCC]; Sony Venice 500 / 2500 and FX6/FX3 S-Log3 800 / 12800 (known values, not re-fetched: unverified).
- ARRI Alexa 35: EI 160 to 6400, LogC4 mid grey at 28 percent code value (about 40 percent in Rec.709) [A35].

### White balance
- Ranges: ARRI 2000 to 11000 K, CC -16 to +16 [A35]; BM app 2500 to 10000 K, tint -50 to +50 [BMAPP].
- Presets on Blackmagic cameras: bright sunlight 5600 K, incandescent 3200 K, fluorescent 4000 K, mixed light 4500 K, cloud 6500 K [BMPCC].
- Shade is commonly 7000 to 7500 K (unverified, no source read).
- Tint axis is green to magenta; fluorescent light typically needs magenta added [BMPCC, A35].

### Zebra
- Blackmagic: 8 presets = middle grey, middle grey + 1 stop, then 75, 80, 85, 90, 95, 100 percent [BMPCC].
- RED: classic single zebra at 70 IRE; up to two zebras with user IRE ranges (example: above 85 and below 10) [RED-EXP].
- Convention: about 70 percent for light skin, 95 to 100 percent for clipping.

### False colour
- Blackmagic legend, top to bottom: white clipping (95%WC), near white clipping (80%WC), one stop over middle grey (MG+1), middle grey (18%MG), near black detail loss, black detail loss. Pink = light skin, green = middle grey / darker skin, yellow then red = overexposed [BMPCC].
- ARRI (classic LogC3 table, recalled from ALEXA Classic/Mini manuals, not re-fetched: unverified): red 99 to 100 percent white clipping; yellow 97 to 99 just below clipping; pink 52 to 56 one stop over grey (light skin); green 38 to 42 18 percent grey; blue 2.5 to 4 just above black clip; purple 0 to 2.5 black clipping. Everything else greyscale. On Alexa 35 the tool switches the output to LogC4 and green marks 18 percent grey [A35].
- RED "Exposure" mode: only two colours on a raw based check, purple = underexposed/noise (left goal post), red = clipping (right goal post). RED "Video" mode: green = 18 percent grey, pink = light skin, straw/yellow/orange = highlights, teal = deep shadow, blue = near textureless black [RED-EXP].
- RED histogram extras: goal posts = bars left and right of the histogram, each scaled to a quarter of all pixels, left = noise risk, right = clipped; traffic lights = three R/G/B dots that light when that channel clips in raw [RED-HIST].

### Aspect ratios and frame guides
- IMAX 1.43:1: full height IMAX frame of 15 perf 70 mm film, shown only on the tallest (film and dual laser GT) screens. 1.90:1: the digital IMAX ratio used by most IMAX screens and for "expanded aspect ratio" scenes in "Filmed for IMAX" titles. Against 2.39:1 at equal width, 1.90:1 is 26 percent taller and 1.43:1 is 67 percent taller (arithmetic). Which screens show which is taken from secondary sources: unverified [IMAX].
- "Filmed for IMAX" certified digital cameras at the 2020 launch: ARRI Alexa LF, Mini LF, Alexa 65 IMAX, Panavision DXL2, RED Ranger Monstro, Sony Venice (secondary source: unverified) [IMAX2].
- Cinema: 2.39:1 (scope), 2.35:1, 2.40:1, 2.00:1, 1.85:1 (flat), 2.76:1.
- Video and social: 16:9 (1.78), 4:3, 14:9, 1:1, 4:5, 9:16.
- Blackmagic app list: 9:16, 4:5, 1:1, 4:3, 14:9, 1.85:1, 2:1, 2.35:1, 2.39:1, 2.4:1, 2.76:1 [BMAPP]. No surveyed UI ships 1.43:1 or 1.90:1 as a stock guide; Blackmagic covers them through custom ratio entry [BMPCC].
- Safe area: adjustable percentage, 85 percent shown as the example [BMPCC]; BM app 5 to 100 percent [BMAPP].

### Other
- Audio meters: dBFS, never reach 0; BM app reference level -18 or -20 dBFS, VU or PPM [BMPCC, BMAPP].
- Peaking: ARRI level 1 to 20, colours red, green, blue, cyan, magenta, yellow, white [A35].
- Guide opacity steps: 25, 50, 75, 100 percent [BMAPP].

## Sources

- [A35] https://www.arri.com/resource/blob/401824/823cd1114755dc134ff9ee3c98be6e15/alexa-35-sup-5-2-0-user-manual-en-data.pdf : ARRI Alexa 35 manual, SUP 5.2.0
- [BMPCC] https://documents.blackmagicdesign.com/UserManuals/BlackmagicPocketCinemaCameraManual.pdf : Blackmagic Pocket manual, touchscreen chapter
- [BMOS] https://www.blackmagicdesign.com/products/blackmagiccinemacamera/blackmagicos : Blackmagic OS HUD and gestures
- [BMAPP] https://www.blackmagicdesign.com/products/blackmagiccamera/techspecs/W-APP-01 : Blackmagic Camera app tech specs
- [RED-HIST] https://docs.red.com/955-0192_v7.2/REDRANGER/Content/4_Basic_Menus/Lower_Status/Histogram.htm : RED goal posts, traffic lights
- [RED-EXP] https://www.reddigitalcinema.com/red-101/exposure-false-color-zebra-tools : RED false colour and zebra modes
- [SONY-HOME] https://helpguide.sony.net/ilc/2510/v1/en/contents/251h_home_screen.html : Sony help guide, home screen
- [SONY-BIG6] https://www.videomaker.com/news/sony-fx3-gets-big6-home-menu-and-braw-recording-with-firmware-update/ : FX3 BIG6 firmware summary
- [X2D] https://www.lensrentals.com/product-assets/70ecfc2c-7442-4d55-9ff0-498145e5312b/X2D_100C_User_Manual_V1.6_EN.pdf : Hasselblad X2D 100C manual v1.6
- [LEICA-M11] https://www.manualslib.com/manual/2555769/Leica-M11.html : Leica M11 manual index (search excerpt)
- [LEICA-Q] https://leica-camera.com/sites/default/files/EN_-4.0.0--Q-Family-Release-Notes.pdf : Leica Q firmware 4.0.0 notes (search excerpt)
- [LEICA-SL3] https://leica-camera.com/en-GB/press/new-leica-sl3 : Leica SL3 press release (search excerpt)
- [HALIDE] https://halide.cam/ : Halide product page, gestures
- [HALIDE2] https://www.lux.camera/pro-camera-action-introducing-halide-mark-ii/ : Halide Mark II design post
- [HALIDE-P0] https://techcrunch.com/2024/08/14/camera-app-halides-latest-update-adds-an-option-for-zero-ai-image-processing : Process Zero launch coverage
- [KINO] https://lux.camera/introducing-kino-pro-video-camera : Kino launch post by Lux
- [MOMENT] https://www.shopmoment.com/gb/articles/getting-started-with-the-moment-pro-camera-app : Moment Pro Camera getting started
- [FILMIC] https://9to5mac.com/2017/03/16/filmic-pro-v6-new-interface-focus-peaking-gamma-log/ : Filmic Pro v6 interface report
- [IMAX] https://www.imax.com/md/filmed-for-imax : IMAX program page (blocked, search excerpt)
- [IMAX2] https://celluloidjunkie.com/?p=65514 : Filmed in IMAX launch camera list

## What phonecam took from this

- The row of values is the control surface (ARRI home screen, Sony BIG6, Blackmagic HUD): Pro shows SHUTTER, ISO, EV, WB, TINT, FOCUS; Video shows FPS, ANGLE, ISO, WB, TINT, FOCUS. Each tile is label over value and is itself the button; the tile row sits right above the shutter, in thumb reach, and the editor opens over the foot of the picture so the picture does not move (Blackmagic: edit at the bottom edge).
- A value is edited on a ruler of third stops with an AUTO pill at its left (Blackmagic slider plus Auto switch, ARRI preset lists). Automatic values are grey, manual ones white (Hasselblad).
- Video uses shutter angle, 180 degrees shown when automatic exposure lands there; exposure time = angle / (360 x fps) (ARRI). Photo Pro uses shutter time.
- Exposure tools are a separate layer chosen in the settings sheet, not buttons on the picture (Blackmagic monitor menu, Hasselblad display pages): histogram with clip lights (Blackmagic, RED traffic lights), zebra at 70 or 95 percent, false colour on the ARRI scale with its legend under the picture, focus peaking in the accent red. Photo mode shows none of them.
- Frame guides include the two IMAX ratios, 1.43:1 and 1.90:1, which no surveyed UI ships as stock. Photos are cropped to the frame; video records the full 16:9 frame and shows lines only, as cinema cameras do.
- Recording state is loud and redundant (Blackmagic, Kino): the status line turns red and carries the clock, minutes of storage left, a missing microphone and dropped frames; the shutter becomes a red square.
- Stills stay minimal (Leica, Hasselblad): Photo mode has the shutter, zoom, mode switch, last shot and camera flip, nothing else.
- Left out because this hardware cannot do it honestly: iris and ND (fixed aperture, no filter), waveform, log or raw video (the software ISP outputs 8-bit sRGB; FLAT is lower contrast and saturation from the ISP, not a log curve), LUT preview, audio gain (no microphone on this OS yet; the meter appears when a source exists), timecode.
