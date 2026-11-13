#!/bin/sh
# phonegluewc in a phone shaped window on your desktop, with its own config and state.
# Usage: ./run-on-laptop.sh [--lock | --login] [window height, default 1000]
# The password screens use a fake password (test) here: no PAM, greetd or real password is involved.
set -eu
cd "$(dirname "$0")"
H=1000
SCREEN=
for a in "$@"; do
	case "$a" in
	--lock) SCREEN=PHONEGLUEWC_RELOCK=1 ;;
	--login) SCREEN=PHONEGLUEWC_GREETER=1 ;;
	*) H=$a ;;
	esac
done
W=$((H * 9 / 20))
SCALE=$(awk "BEGIN { printf \"%.2f\", $W / 392.7 }")
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo "run this from a Wayland session"; exit 1; }
make -s phonegluewc phonegluewc-msg phonecamera
make -s -C keyboard phonekbd phonekbd-lang
make -s -C screentext phonetext
if ! tesseract --list-langs 2>/dev/null | grep -qx ron || ! tesseract --list-langs 2>/dev/null | grep -qx eng; then
	echo "Screen text cannot read anything here: tesseract with Romanian and English is missing."
	echo "Everything else works. To add it on this Gentoo machine, run these yourself:"
	echo "  echo 'app-text/tessdata_fast l10n_ro' | sudo tee /etc/portage/package.use/tessdata"
	echo "  sudo emerge --ask app-text/tesseract"
fi

BASE=${PHONE_LAPTOP_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/phonegluewc-laptop}
# apps started in the window keep their files here too: a browser never touches your real profile
mkdir -p "$BASE/config/phonegluewc" "$BASE/state" "$BASE/data" "$BASE/cache" "$BASE/home"
# the flashlight here is a pretend one
mkdir -p "$BASE/leds/white:torch"
[ -e "$BASE/leds/white:torch/brightness" ] || echo 0 >"$BASE/leds/white:torch/brightness"
echo 1 >"$BASE/leds/white:torch/max_brightness"
# every tool that could change this computer is a fake that only moves files in $BASE
# a fresh window is a fresh boot: the first unlock takes the password
rm -rf "$BASE/run"; mkdir -p "$BASE/run"
mkdir -p "$BASE/fakebin" "$BASE/fake" "$BASE/sys/power_supply/BAT0" "$BASE/sys/backlight/laptop-fake"
for t in nmcli bluetoothctl rfkill wpctl pactl brightnessctl powerprofilesctl mmcli upower gsettings dconf gammastep wlsunset fbcli wf-recorder fuser \
	fprintd-list fprintd-verify fprintd-enroll fprintd-delete \
	systemctl loginctl reboot poweroff shutdown halt suspend rtcwake sudo doas pkexec; do
	ln -sf "$PWD/laptop/fake-tool" "$BASE/fakebin/$t"
done
: >"$BASE/fake/calls.log"
echo Battery >"$BASE/sys/power_supply/BAT0/type"
[ -e "$BASE/sys/power_supply/BAT0/capacity" ] || echo 62 >"$BASE/sys/power_supply/BAT0/capacity"
[ -e "$BASE/sys/power_supply/BAT0/status" ] || echo Discharging >"$BASE/sys/power_supply/BAT0/status"
echo 100 >"$BASE/sys/backlight/laptop-fake/max_brightness"
[ -e "$BASE/sys/backlight/laptop-fake/brightness" ] || echo 60 >"$BASE/sys/backlight/laptop-fake/brightness"
ln -sfn "$BASE/leds" "$BASE/sys/leds"
printf 'remember_layout = false\noutput = * mode=%sx%s scale=%s\n' "$W" "$H" "$SCALE" \
	> "$BASE/config/phonegluewc/config.conf"

[ -e "$BASE/config/phonegluewc/login.conf" ] || echo user=laptop > "$BASE/config/phonegluewc/login.conf"

# a private bus with nothing to activate: no portal or at-spi started for the window
cat > "$BASE/bus.conf" <<BUS
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$BASE/bus</listen>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
BUS

cat <<MSG
phonegluewc: ${W}x${H} window, scale $SCALE. Config and state are in $BASE.
  Fake tools   Wi-Fi, Bluetooth, mobile data, volume, brightness, battery, airplane and the like are pretend here: tiles only change $BASE/fake, never this computer; what they called is in $BASE/fake/calls.log
  Mouse        is one finger: a quick flick up from the bottom edge goes to the free workspace; drag up and pause for the overview
  Hold F4      while dragging for four fingers
  Bottom bar   is hidden: click the very bottom edge, or rest the pointer there, and it slides over the window without moving anything; a swipe never shows it
  Hold still   on the bottom edge for half a second for screen text (needs tesseract and wl-clipboard)
  Password     on the --lock and --login screens is: test
  PIN          Settings > Security sets one; the lock asks for the password once per window, then the PIN. Fingerprint here is pretend: put no-match in $BASE/fake/fpnext to fail it
Things to try in the overview, none of this motion can be judged in a test:
  Flick up from an app at several speeds, then drag up and pause: the flick must reach the free workspace, only the pause the overview
  Drag up slowly from the bottom edge and stop halfway: the cards and the tray follow your finger
  Open an app from the tray: it grows out of the icon; from a terminal in the window it grows from the middle; close it: it shrinks and fades
  Flick up from an app: it shrinks under your finger, then goes on at your speed into a small card that fades upward while the wallpaper settles; drag a little and let go slowly: it comes back the same way. Touch again during any of these: the new gesture takes over
  Put animations = off in $BASE/config/phonegluewc/phone.conf: everything is instant, at once, no restart
  Let go there, then again with a quick flick: both should settle without a jump or a bounce
  Swipe a card sideways: slowly it settles on the nearest card, a gentle flick moves one, a hard one carries two or three; it never runs past the first card or the free one, and gives a little there. Touch while the cards move: they stop where they are and nothing opens
  Flick a card up: the app closes. Hold still first and it picks up the window for tiling instead
  Hold an icon in the tray or the menu to pin or unpin it; a short click opens the app, or goes to its window if it is already open
  New window in that popup starts a second one on its own workspace: try it with a terminal, and with an app that has only one window
  Close a window in the middle of the row: the gap closes and the only empty card stays on the right
  Under the cards: Tray apps lists what runs, Close all closes everything; an app with unsaved work may still ask
  With the keyboard open, the strip under it keeps the bottom swipe; a tap on its down arrow, right of the line, hides the keyboard
  In the overview hold a tray icon and move: it comes off under the finger. Drop it on a card to split, on the free card to start alone, on nothing to cancel; rest at a screen edge to change card
  Hold a tile on a card and drop it on the half of another: left, right, top, bottom; its centre swaps the two, the free card gives it its own workspace
  Uninstall in that same hold popup is simulated here: nothing is removed from this computer
  Pull from the right edge, in the part between the bars, slowly: a small arrow follows your height and changes when letting go would go back; pull back and let go to cancel
  Open a browser here (its files stay in $BASE/home, not in your profile): a window wider than the screen shows whole, smaller; click its far right edge
  Pull from the left edge the same way: the keyboard opens with nothing to type in, and the same pull closes it
  F7 turns the pretend phone a quarter each press: an app turns with it, home and the lock screen stay upright. With the Rotation lock tile on, a round button shows for a few seconds instead; tap it to turn once
  F6 is the power button: once locks at once, twice shows the camera message, three times switches a pretend flashlight
  F5 is volume down: hold it with F6 for a screenshot and a white flash, saved in $BASE/home/Pictures/Screenshots; alone it does nothing here
  Open the overview on the empty home screen: the clock fades out and is on no card
  Pull down slowly from the left of the top bar, then the right: the sheet stays under your finger; a short flick also opens it, and a slow short pull falls back
  With it open, swipe sideways slowly and with a flick: notifications and quick settings trade places with your finger, nothing jumps
  The keyboard starts in English only. To add Romanian: the Translate button in the bar above the keys, Add, then Romanian
  Translating needs the translator once: PHONETEXT_MODELS=$BASE/data/phonegluewc/translate sh screentext/setup-translation.sh --binary-only
  Pull down from the right of the bar, then pull again: the tiles open under your finger; drag a slider slowly; hold a tile for its settings page; the pencil edits and reorders
  The clock is in the corner here and the bar is shorter; on the phone the clock starts after the camera and the bar covers it. PHONE_CAMERA=left shows that
  Dynamic camera: no real hole here, a drawn one stands in, in the middle; PHONE_CAMERA=left, center or right before this script moves it. From another terminal, ./phonecamera-demo lists what it can start: music, call, timer, charging and the rest; none of it touches this computer
  Close the window, or Ctrl+C here, to stop.
If your desktop tiles the window, make it float: the picture keeps its phone shape anyway.
MSG

env -u DISPLAY -u XDG_PICTURES_DIR -u GDK_SCALE -u GDK_DPI_SCALE -u QT_SCALE_FACTOR -u QT_AUTO_SCREEN_SCALE_FACTOR -u QT_SCREEN_SCALE_FACTORS -u QT_FONT_DPI -u XCURSOR_SIZE XDG_CONFIG_HOME="$BASE/config" XDG_STATE_HOME="$BASE/state" XDG_DATA_HOME="$BASE/data" XDG_CACHE_HOME="$BASE/cache" \
	HOME="$BASE/home" XDG_DATA_DIRS="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
	WLR_BACKENDS=wayland WLR_WL_OUTPUTS=1 PHONEGLUEWC_MOUSE_FINGER=1 PHONE_NO_HOLE=1 PHONE_CAMERA="${PHONE_CAMERA:-center}" PHONECAMERA_SOCK="$BASE/camera.sock" \
	PHONE_AUTH_MOCK=test PHONE_UNINSTALL_MOCK=1 PHONE_RUNTIME_DIR="$BASE/run" PHONE_BG_DAEMONS=phonetest-bgd PHONE_LED_DIR="$BASE/leds" PHONE_SYS_DIR="$BASE/sys" FAKE_STATE="$BASE/fake" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$BASE/no-system-bus" $SCREEN \
	PHONEGLUEWC_SHELL="$PWD/shell" PHONEKBD_DATA="$PWD/keyboard/data" PHONEKBD_PACKS="file://$PWD/keyboard/packs" PATH="$BASE/fakebin:$PWD:$PWD/keyboard:$PWD/screentext:$PWD/settings:$PATH" \
	dbus-run-session --config-file="$BASE/bus.conf" -- ./phonegluewc
