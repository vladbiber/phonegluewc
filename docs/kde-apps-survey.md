# Phone apps survey: KDE/Kirigami vs lighter alternatives

Date: 2026-11-08. Nothing here is adopted; the user decides per app.

## Method

- Packages: real `APKINDEX` of Alpine edge main/community/testing and postmarketOS (Nura) master, aarch64, fetched 2026-11-07. All apps in the table exist in Alpine edge aarch64 (community, iotas in testing). None needed the pmOS repo.
- Size: aarch64 installed size from the index, dependency closure resolved by apk 3.0.7 itself (`--arch aarch64 add --simulate`), minus a baseline of `alpine-base qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qtsvg qt6-qtshadertools mesa-dri-gallium mesa-gbm pipewire wireplumber dbus` (413.5 MiB). "+MiB" is what the app adds on top.
- Memory: x86_64 Alpine edge rootfs, rootless (user/mount/pid/net namespaces, no network), each app alone in a fresh headless phonegluewc at `mode=1080x2222 scale=2.75` = 392x808 logical, fresh HOME, session + system D-Bus. Snapshot 15 s after start (browsers 30 s, local static page), then SIGTERM to the app and 8 s later list what still runs. x86_64 RSS is a proxy for aarch64, not the same number.
- Rendering was software (`QT_QUICK_BACKEND=software`, `GSK_RENDERER=cairo`, WebEngine/WebKit GPU off), so numbers exclude GPU driver memory and differ from a real phone.
- Apps ran as namespace root with browser sandboxes off (QtWebEngine/WebKit/Firefox), so process counts of browsers may be lower than on a real system.
- PSS: each app ran alone, so PSS is close to RSS; on the phone, Qt libs shared with Quickshell would lower a Qt app's PSS. USS (private) is the floor.
- Empty library everywhere (no photos, music, contacts).

## Table

PSS/USS = whole app tree in MiB while open. "Stays" = processes alive 8 s after the app was killed. Fit = screenshot at 392x808.

| Role | App | Kind | Licence | +MiB aarch64 | Main RSS | Tree PSS / USS | Fit 392x808 | Depends on / stays after close |
|---|---|---|---|---|---|---|---|---|
| Dialer | Plasma Dialer 6.8.2 | KDE | GPL-2.0+ | 209.6 | 156 | 142 / 129 | good (dialpad, tabs) | ModemManager + KF6 ModemManagerQt, kpeople, KIO; **autostart daemons `modem-daemon`, `kde-telephony-daemon` (not measured: showed "Telephony daemons are not responding")** |
| Dialer | GNOME Calls 51.1 | GNOME | GPL-3.0+ | 450.3 | 108 | 145 / 62 | good | starts ModemManager, callaudiod, feedbackd, evolution-data-server, goa-daemon, polkitd, at-spi; **all 10 stay** |
| SMS | Spacebar 6.8.2 | KDE | GPL-2.0+ | 190.5 | 165 | 156 / 147 | good | ModemManagerQt, kpeople, KIO; **autostart `spacebar-daemon` (not measured: "Unable to connect to messaging daemon")** |
| SMS | Chatty 0.8.9 | GNOME | GPL-3.0+ | 358.2 | 115 | 137 / 62 | good | libpurple, EDS, webkit; **8 stay** (EDS, goa, ModemManager, polkitd, at-spi) |
| Browser | Angelfish 26.08.2 | KDE | GPL-3.0+ | 570.7 | 312 | 391 / 233 | good (mobile UI, adblock prompt) | QtWebEngine (256 MiB), KIO, kwallet; nothing stays |
| Browser | Epiphany 50.6 | GNOME | GPL-3.0+ | 328.6 | 233 | 431 / 270 | good | WebKitGTK 6; at-spi stays |
| Browser | Firefox ESR 140 + mobile-config-firefox | Mozilla | MPL-2.0 etc. | 298.4 | n/a (12 procs) | 513 / 387 | good with mobile-config | at-spi stays |
| Gallery | Koko 26.08.2 | KDE | LGPL | 615.2 (50.5 if Angelfish already in) | 179 | 165 / 152 | good | pulls QtWebEngine, KIO, kwallet, purpose; nothing stays |
| Gallery | Loupe 51.1 | GNOME | GPL-3.0+ | 174.7 | 102 | 99 / 88 | good (viewer, no grid) | glycin loader; at-spi stays |
| Gallery | swayimg 5.7 | other | MIT | 5.8 | 30 | 25 / 20 | viewer only, no touch UI | nothing stays |
| Camera | Plasma Camera 26.08.2 | KDE | GPL-3.0+ | 273.0 | 175 | 161 / 147 | good | libcamera 0.8, GStreamer, QtMultimedia; nothing stays |
| Camera | Snapshot 51.0 | GNOME | GPL-3.0+ | 195.2 | 163 | 158 / 147 | good | libcamera, GStreamer; at-spi stays |
| Camera | Megapixels 2.1.0 | other | GPL-3.0 | 239.3 | 204 | 200 / 191 | good | PinePhone-oriented libmegapixels config; feedbackd + at-spi stay |
| Music | Elisa 26.08.2 | KDE | LGPL-3.0+ | 399.7 | **1420** | 1415 / 1410 | ok ("Now playing") | VLC, KIO, samba-libs; nothing stays. **1.4 GB looks like a software-rendering artifact; retest on GPU before judging** |
| Music | G4Music 4.6 | GTK4 | GPL-3.0 | 165.3 | 96 | 91 / 80 | good | GStreamer; at-spi stays |
| Music | Amberol 2026.1 | GNOME | GPL-3.0+ | 228.5 | 95 | 90 / 79 | good | GStreamer, ffmpeg; at-spi stays |
| Files | Dolphin 26.08.2 | KDE | GPL-2.0 | 314.5 | 158 | 174 / 86 | poor (desktop sidebar, cramped) | KIO workers; **upowerd, udisksd, polkitd stay** |
| Files | Index (Maui) | KDE/Maui | | **not packaged** in Alpine or pmOS | | | | upstream last human commit 2026-07-13 |
| Files | Portfolio 1.0.3 | GTK | GPL-3.0+ | 205.4 | 112 | 110 / 98 | good (built for phones) | Python 3; udisksd, polkitd, at-spi stay |
| Files | PCManFM-Qt 2.4.0 | LXQt | LGPL-2.0+ | 3.6 | 114 | 100 / 87 | poor (desktop menus) | nothing stays |
| Calculator | Kalk 26.08.2 | KDE | GPL-3.0+ | 96.6 (82 of it breeze-icons) | 145 | 140 / 135 | very good | libqalculate; nothing stays |
| Calculator | GNOME Calculator 51.1 | GNOME | GPL-3.0+ | 173.5 | 97 | 92 / 81 | good | at-spi stays |
| Calendar | Merkuro Calendar 26.08.2 | KDE | GPL-3.0+ | 703.1 | 247 | 323 / 226 | good | **Akonadi: 10 processes (akonadiserver + agents) stay** |
| Calendar | Calindori 26.08.2 | KDE | GPL-3.0+ | 129.4 | 149 | 145 / 84 | good (month grid) | **`calindac` alarm daemon stays** (needed for reminders) |
| Calendar | GNOME Calendar 51.0 | GNOME | GPL-3.0+ | 345.6 | not measured | | | crashed at start in the rootfs (date assertion, likely missing tzdata); EDS + goa stayed |
| Contacts | Plasma Phonebook 24.02.0 | KDE | KDE-Accepted-GPL | 140.4 | 134 | 124 / 115 | good | kpeople, kcontacts; nothing stays. Alpine ships 24.02.0 though upstream is active |
| Contacts | Merkuro Contact 26.08.2 | KDE | GPL-3.0+ | (in merkuro, 703.1) | n/a | 241 / 143 | good | Akonadi + keyboxd, 11 stay |
| Contacts | GNOME Contacts 51.0 | GNOME | GPL-2.0+ | 349.7 | 107 | 126 / 55 | good | EDS, goa, at-spi: 6 stay |
| Notes | Marknote 1.6.0 | KDE | GPL-3.0+ | 135.4 | 153 | 139 / 125 | good | nothing stays |
| Notes | Iotas 2026.10 | GNOME | GPL-3.0+ | 587.0 | 142 | 136 / 125 | good | WebKitGTK, Python; at-spi stays |
| Not measured | Nautilus 51.1 | GNOME | GPL-2.0+ | 238.8 | refuses to run as root | | | localsearch/tinysparql, upower |

Supporting daemons (alone, x86_64): ModemManager 9 MiB RSS (+ polkitd); feedbackd 5; kded6 76 (+ starts upowerd, udisksd, polkitd that stay). None of the KDE apps above started kded6 or baloo in this test.

Shared costs (aarch64): the first Kirigami app adds about 106 MiB, of which **breeze-icons is 82 MiB** (a hard dependency); the first GTK4+libadwaita app adds about 165 MiB; QtWebEngine 256 MiB; WebKitGTK 6 about 295 MiB. The recommended set below totals **865.8 MiB** over the baseline (dialer, SMS, calculator, calendar, contacts, notes alone: 233.4; plus Angelfish 624.5; plus Koko and Plasma Camera 772.6; plus G4Music and Portfolio 847.2; plus ModemManager 865.8).

Maintenance (last commit by a person, not a bot, as of 2026-11-07): Plasma Dialer and Spacebar 2026-10-27 (on the Plasma release cycle since 6.2), Plasma Camera 2026-11-03, Angelfish/Koko/Kalk/Merkuro/Elisa/Marknote/Dolphin within the last two weeks, Calindori 2026-08-12, Plasma Phonebook 2026-07-17, Index 2026-07-13, GNOME Calls 2026-11-03, Megapixels 2026-07-27, G4Music 2026-09-03 (translation).

## Recommended pick per role

- **Dialer: Plasma Dialer.** Same Qt/Kirigami stack as the shell, nothing left over after closing. GNOME Calls costs twice the disk and leaves 10 daemons. Caveat: it relies on two autostart daemons that I did not measure. Our session should start them; they will be resident anyway for incoming calls.
- **SMS: Spacebar.** Same reasoning. `spacebar-daemon` must run all the time to receive SMS (true of any SMS app). Its memory is not measured.
- **Browser: Angelfish** for lowest PSS (391 vs 431 Epiphany vs 513 Firefox) and shared Qt. Firefox ESR + mobile-config remains the fallback for site compatibility and is smaller on disk.
- **Gallery: Koko if Angelfish is taken** (then only +50 MiB, since it shares QtWebEngine). Otherwise Loupe: half the RAM, no WebEngine.
- **Camera: Plasma Camera**, nothing stays after closing. Whether the Nothing Phone (1) camera works under libcamera on mainline is unverified, and that matters more than the app choice.
- **Music: G4Music** (91 MiB PSS, 165 MiB disk incl. GTK4). Elisa's 1.4 GB in software mode needs a retest on a GPU before it can be considered.
- **Files: Portfolio** (made for phones). Dolphin is cramped at 392 px and leaves udisks/upower/polkit running. Index is not packaged.
- **Calculator: Kalk.** Best fit; only 14 MiB beyond Kirigami.
- **Calendar: Calindori.** Avoid Merkuro: Akonadi keeps 10 processes alive.
- **Contacts: Plasma Phonebook.** Light, nothing stays; Merkuro Contact and GNOME Contacts both keep a PIM daemon stack running.
- **Notes: Marknote.**

Cheapest disk win to consider: breeze-icons (82 MiB) is a hard dependency of Kirigami. Only a custom package could drop it.

## Ideas from Plasma Mobile's look (descriptions only, nothing taken)

- Two-stage pull-down drawer: the first swipe shows a row of quick toggles plus notifications, and a second swipe expands to the full grid. A swipe from a corner opens the full panel in one stroke, and the grid is paged when there are many toggles. ([2021 update](https://plasma-mobile.org/2021/04/27/plasma-mobile-update-march-april/), [Gear 22.06](https://plasma-mobile.org/2022/06/28/plasma-mobile-gear-22-06/))
- Quick toggles hide themselves when they don't apply (mobile data without a modem). The column count is configurable. The drawer hides while brightness is being dragged. ([dev log 2025-06](https://plasma-mobile.org/2025/06/18/dev-log/), [6.5](https://plasma-mobile.org/2025/11/10/plasma-6-5/))
- Media tile in the drawer expands on tap into a seek bar. ([dev log](https://plasma-mobile.org/2025/06/18/dev-log/))
- Status bar: adjustable height, optional battery percentage, optional date next to the time, and a swipe down that reveals it over fullscreen apps. ([dev log](https://plasma-mobile.org/2025/06/18/dev-log/))
- Task switcher: swipe up and hold to open it, a quick swipe up goes home, and horizontal swipes along the bottom edge scrub between apps. Double-tapping the switcher button toggles the last two apps, and haptics fire at the point where releasing will open the switcher. ([dev log](https://plasma-mobile.org/2025/06/18/dev-log/), [Gear 22.06](https://plasma-mobile.org/2022/06/28/plasma-mobile-gear-22-06/))
- Homescreen (Folio): swipe up for the app drawer with a search field on top, swipe down for search, double tap to lock, and the layout can be locked and exported. ([Plasma 6 post](https://plasma-mobile.org/2024/03/01/plasma-6/), [6.5](https://plasma-mobile.org/2025/11/10/plasma-6-5/))
- Lockscreen reuses the running status bar and drawer instead of loading its own, which makes it faster and keeps notifications in sync. ([6.5](https://plasma-mobile.org/2025/11/10/plasma-6-5/))
- Floating rotation button when auto-rotate is off. ([dev log](https://plasma-mobile.org/2025/06/18/dev-log/))

## Not verified

- Memory of plasma-dialer's `modem-daemon` and `kde-telephony-daemon` and of `spacebar-daemon`. They didn't start in the test.
- Anything on aarch64 hardware: RSS, GPU-path memory, and camera support on the Nothing Phone (1).
- GNOME Calendar and Nautilus memory (crash and refusal to run as root in the rootfs).
- Elisa's real memory (the software-rendering result looks abnormal).
- Behaviour with a real library (photos, music, contacts) and with a modem present.
- **Quickshell is not packaged in Alpine edge or postmarketOS at all** (checked all four indexes): the shell will need its own package on Nura.
