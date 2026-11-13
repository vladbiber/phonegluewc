#!/bin/sh
# The Active apps list's only way to the system: a pid is reported or signalled only after these checks.
#   scan QS_PID WINDOWS_FILE [bg PID:START...]  what is running, as tab separated lines (see below)
#   stamp PID...                 PID:START of each, to know the same process later
#   alive PID:START...           those still the same running process
#   signal TERM|KILL PID:START...
me=$(id -u)
tab=$(printf '\t')

# the kernel's start tick tells a process from a later one that got the same pid; a zombie has no process left
start_of() {
	[ -r "/proc/$1/stat" ] || return
	sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '$1 != "Z" { print $20 }'
}
# never the session's own parts, never another user's, never a proxy standing in for the real app
ours() {
	case "$1" in '' | *[!0-9]*) return 1 ;; esac
	[ "$1" -gt 1 ] || return 1
	[ "$(awk '/^Uid:/ { print $2; exit }' "/proc/$1/status" 2>/dev/null)" = "$me" ] || return 1
	case "$(cat "/proc/$1/comm" 2>/dev/null)" in
	'' | phonegluewc | phonekbd | phonetext | qs | quickshell | dbus-* | xdg-dbus-proxy | bwrap | Xwayland | pipewire* | wireplumber | \
		xdg-desktop-* | xdg-document-* | xdg-permission* | at-spi* | gvfs*) return 1 ;;
	esac
}
helper() {
	[ "$1" = "$qs" ] && return 0
	case "$(cat "/proc/$1/comm" 2>/dev/null)" in phonegluewc | phonekbd | phonetext) return 0 ;; esac
	return 1
}
# report KIND ID PID: "w|t ID PID START" when verified, "w|t ID" when not, "hide ID" for a system part
report() {
	if helper "$3"; then
		printf 'hide\t%s\n' "$2"
	elif ours "$3" && s=$(start_of "$3") && [ -n "$s" ]; then
		printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$s"
	else
		printf '%s\t%s\n' "$1" "$2"
	fi
}
bus() { dbus-send --session --print-reply --reply-timeout=800 "$@" 2>/dev/null; }

case "$1" in
scan)
	qs=$2
	[ -r "$3" ] && while IFS="$tab" read -r pid id; do
		[ -n "$pid" ] && report w "$id" "$pid"
	done <"$3"
	bus --dest=org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Properties.Get \
		string:org.kde.StatusNotifierWatcher string:RegisteredStatusNotifierItems |
		sed -n 's/.*string "\(.*\)"$/\1/p' | while read -r item; do
		svc=${item%%/*} path=/${item#*/}
		id=$(bus --dest="$svc" "$path" org.freedesktop.DBus.Properties.Get string:org.kde.StatusNotifierItem string:Id |
			sed -n 's/.*string "\(.*\)"$/\1/p')
		pid=$(bus --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID "string:$svc" |
			sed -n 's/.*uint32 //p')
		[ -n "$id" ] && report t "$id" "$pid"
	done
	[ "${4:-}" = bg ] || exit 0
	shift 4
	# "b PID START": a process that once had a window and is still the same one
	for a; do
		pid=${a%%:*}
		ours "$pid" && [ "$(start_of "$pid")" = "${a#*:}" ] && printf 'b\t%s\t%s\n' "$pid" "${a#*:}"
	done
	# "d NAME PID START": a known background program of this user
	for p in /proc/[0-9]*; do
		pid=${p#/proc/} c=$(cat "$p/comm" 2>/dev/null) || continue
		case " ${PHONE_BG_DAEMONS:-librespot spotifyd syncthing kdeconnectd openvpn wireguard-go boringtun} " in
		*" $c "*) ours "$pid" && s=$(start_of "$pid") && [ -n "$s" ] && printf 'd\t%s\t%s\t%s\n' "$c" "$pid" "$s" ;;
		esac
	done
	# "v NAME": an active VPN; nmcli escapes a colon in a name as \:
	nmcli -t -f NAME,TYPE connection show --active 2>/dev/null |
		sed -nE 's/^(.*):(vpn|wireguard)$/\1/p' | sed 's/\\:/:/g' | while IFS= read -r v; do printf 'v\t%s\n' "$v"; done
	;;
stamp)
	shift
	for pid; do
		ours "$pid" && s=$(start_of "$pid") && [ -n "$s" ] && echo "$pid:$s"
	done
	;;
alive)
	shift
	for a; do
		pid=${a%%:*}
		[ -n "$pid" ] && [ "$(start_of "$pid")" = "${a#*:}" ] && echo "$a"
	done
	;;
signal)
	sig=$2
	case "$sig" in TERM | KILL) ;; *) exit 2 ;; esac
	shift 2
	for a; do
		pid=${a%%:*}
		# shortcut: a few instructions pass between this check and kill, use a pidfd if a helper in C ever exists
		ours "$pid" && [ "$(start_of "$pid")" = "${a#*:}" ] && kill "-$sig" "$pid"
	done
	;;
*) exit 2 ;;
esac
exit 0
