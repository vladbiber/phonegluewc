#!/bin/sh
# What a hardware button does outside the shell. Prints one line: flash=1 only after a saved shot, then message=
set -u

say() {
	printf 'message=%s\n' "$*"
	exit 0
}

case ${1:-} in
screenshot)
	dir=${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots
	path=$dir/Screenshot-$(date +%Y%m%d-%H%M%S)
	n=
	while [ -e "$path$n.png" ]; do n=$((${n:-0} + 1)); done
	# a partly written picture never carries the real name
	if mkdir -p "$dir" 2>/dev/null && grim -t png "$path$n.tmp" 2>/dev/null && mv "$path$n.tmp" "$path$n.png"; then
		echo flash=1
		say "Screenshot saved"
	fi
	rm -f "$path$n.tmp"
	say "Screenshot could not be saved"
	;;
flashlight)
	leds=${PHONE_LED_DIR:-/sys/class/leds}
	for led in "$leds"/*[Tt]orch* "$leds"/*[Ff]lash*; do
		[ -f "$led/brightness" ] || continue
		if [ "$(cat "$led/brightness" 2>/dev/null || echo 0)" -gt 0 ]; then
			value=0
			word=off
		else
			value=$(cat "$led/max_brightness" 2>/dev/null || echo 1)
			word=on
		fi
		{ echo "$value" >"$led/brightness"; } 2>/dev/null || say "The flashlight cannot be switched here"
		say "Flashlight $word"
	done
	say "No flashlight here"
	;;
esac
say "Unknown button action"
