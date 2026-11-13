# Quick settings: features and what can work

What iOS Control Center, Samsung One UI and Nothing OS offer, and what each one takes here.
A tile whose backend is missing stays hidden and appears by itself once detected. There are no fake buttons.

Status:

- **now**: works today on any Linux machine that has the named tool; shown only if it does
- **phone**: built and detected, needs hardware this laptop lacks, so only checked with fake tools
- **later**: possible, not built in this version, and no tile appears
- **never**: tied to that vendor's ecosystem or hardware

In the source columns, `y` means found in a source below and `?` means not confirmed. Vendors change the tile
lists by model and version, and no vendor publishes a complete list, so this is what could be checked.

## Connectivity

| Feature | iOS | One UI | Nothing | Our backend | Status |
|---|---|---|---|---|---|
| Wi-Fi | y | y | y | `nmcli radio wifi on/off` | now |
| Bluetooth | y | y | y | `bluetoothctl power on/off`, `rfkill unblock` | now |
| Mobile data | y | y | y | `nmcli con up/down` on the gsm profile, signal from `mmcli` | phone |
| Airplane mode | y | y | ? | `rfkill block/unblock all` | now |
| Hotspot | y | y | y | `nmcli device wifi hotspot`, only if the card reports AP support | now |
| NFC | ? | y | y | `rfkill block/unblock nfc`, only if an NFC radio is listed | phone |
| Location | ? | ? | ? | `rfkill block/unblock gps`, only if a GPS radio is listed | phone |
| Satellite | y | ? | ? | none | never |
| Data saver | ? | y | ? | no system wide switch on Linux | later |

## Sound and interruptions

| Feature | iOS | One UI | Nothing | Our backend | Status |
|---|---|---|---|---|---|
| Ringer: ring, vibrate, silent | y | y | y | `ringer` in `phone.conf`; notifications obey it; media volume stays separate | now |
| Vibrate on notifications | y | y | y | `fbcli`; the vibrate choice is hidden without it | phone |
| Do not disturb | y | y | y | `dnd` in `phone.conf`: no sound or vibration, notifications still collect | now |
| Named focus modes | y | y | ? | only do not disturb exists so far | later |
| Volume slider | y | y | y | `wpctl set-volume` | now |
| Output picker | y | y | ? | `wpctl status` and `wpctl set-default` | now |
| Media controls | y | y | y | MPRIS through Quickshell | now |
| Dolby Atmos | ? | y | ? | licensed | never |
| Background sounds, Recognize Music | y | ? | ? | none | never |

## Screen

| Feature | iOS | One UI | Nothing | Our backend | Status |
|---|---|---|---|---|---|
| Brightness slider | y | y | y | `brightnessctl` | now |
| Flashlight | y | y | y | `brightnessctl --class=leds` on a torch or flash LED | phone |
| Rotation lock | y | y | ? | flag file; the tile hides until the compositor rotates | phone |
| Dark mode | y | ? | y | `gsettings set org.gnome.desktop.interface color-scheme` for apps; the shell stays black | now |
| Night light | ? | ? | ? | `wlsunset`, else `gammastep`; the compositor has gamma control | now |
| Extra dim | ? | y | ? | needs a lower gamma curve than night light tools set | later |
| Screen recording | y | y | y | `wf-recorder` to `~/Videos`; the compositor has screen copy | now |
| Screenshot | ? | ? | y | `grim` to `~/Pictures/Screenshots` | now |
| Cast, mirroring | y | y | ? | launches a casting app if one is installed; no Miracast of our own | later |
| Glyph lights | no | no | y | `brightnessctl --class=leds` on an LED named glyph or aw20036; LED name not confirmed on real hardware | phone |

## Power

| Feature | iOS | One UI | Nothing | Our backend | Status |
|---|---|---|---|---|---|
| Battery saver | y | y | y | `powerprofilesctl set power-saver` | now |
| Keep screen awake | ? | ? | ? | needs a compositor switch | later |

## Shortcuts to apps

Each one opens an installed app found through its desktop entry. Without such an app the tile stays hidden.

| Feature | iOS | One UI | Nothing | Our backend | Status |
|---|---|---|---|---|---|
| Calculator | y | ? | ? | desktop entry with category Calculator | now |
| Timer, alarm, stopwatch | y | ? | ? | desktop entry with category Clock; no timer of our own | now |
| Camera | y | ? | ? | desktop entry with category Camera or id containing camera | phone |
| QR scanner | y | y | ? | desktop entry with id or name containing qr | phone |
| Notes, quick note | y | ? | ? | desktop entry with id or name containing note | now |
| Wireless sharing | y | y | y | an installed sharing app such as LocalSend; no AirDrop or Quick Share protocol | now |
| Voice memos, recorder | y | ? | ? | desktop entry with category Recorder | now |

## The panel itself

| Feature | iOS | One UI | Nothing | Ours | Status |
|---|---|---|---|---|---|
| Add, remove and reorder tiles | y | y | y | hold a tile and drag it; the pencil adds, removes and moves the sliders and big tiles; order in `phone.conf` (`quick_tiles`, `quick_blocks`) | now |
| Compact row, then full view | y | y | y | a second pull or the chevron expands | now |
| Several pages | y | y | y | pages of 6 tiles with dots; a sideways swipe turns them | now |
| Hold a tile for its settings | y | y | y | hold opens the `phonesettings` page | now |
| Resize tiles | y | y | y | one size per tile, Wi-Fi and Bluetooth larger | later |

## Never here

Apple Wallet and Tap to Cash, Apple TV Remote and Home, Apple Watch mirroring and Ping My Watch, Samsung Kids, Secure Folder,
SmartThings, Link to Windows, Essential Space, Live Listen and the hearing controls. They need the vendor's ecosystem,
apps or hardware. Accessibility controls (zoom, invert, reduce motion, text size) are possible, but they need compositor or
toolkit support that does not exist yet, so they count as later.

## Sources

- Apple, opening and customizing Control Center: https://support.apple.com/en-us/108330
- iOS control list, third party, the fullest one found: https://www.iphonelife.com/content/control-gallery-guide
- Samsung, customizing the Quick settings panel: https://www.samsung.com/ca/support/mobile-devices/customize-the-quick-settings-panel-on-your-samsung-galaxy/
- Samsung, Quick panel editing on recent models: https://www.samsung.com/uk/support/mobile-devices/how-to-customise-the-quick-panel-on-the-samsung-galaxy-s26-series/
- Samsung, One UI 7 features: https://www.samsung.com/latin_en/one-ui/features/
- Samsung, Dolby Atmos tile: https://www.samsung.com/us/support/answer/ANS10002953/
- One UI tiles, third party: https://www.makeuseof.com/samsung-galaxy-quick-settings/
- Nothing Phone (3) user guide, a copy hosted by a retailer: https://gzhls.at/blob/ldb/8/1/e/d/313f30e7f9944962e2bcf2d232339511d420.pdf
- Glyph tile, third party: https://beebom.com/how-turn-glyph-lights-on-off-nothing-phones
- Nothing OS 3 ringer and tile sizes, third party: https://beebom.com/nothing-os-3-0-hands-on-review/
