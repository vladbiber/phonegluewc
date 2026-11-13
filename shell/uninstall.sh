#!/bin/sh
# Finds what owns an app and removes it. Names only ever travel as single arguments.
#   inspect DESKTOP_ID           owner=, name=, essential=, needpw= and data= when it can be deleted
#   remove DESKTOP_ID [data]     result=ok|simulated or error=; a password, if needed, comes on stdin
set -u
set -f

# only the phone image ships this file, so any other machine refuses real removal
MARKER=/etc/phonegluewc/phone-session
MOCK=${PHONE_UNINSTALL_MOCK:-}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}

fail() {
	printf 'error=%s\n' "$*"
	exit 1
}

valid() { # REGEX VALUE, whole value on one line
	[ "$(printf '%s\n' "$2" | wc -l)" = 1 ] && printf '%s\n' "$2" | grep -Eqx "$1"
}

key() {
	sed -n '/^\[Desktop Entry\]/,/^\[/p' "$file" | sed -n "s/^$1=//p" | head -n 1
}

locate() {
	valid '[A-Za-z0-9][A-Za-z0-9._+-]*' "$1" || fail "Not a valid app id"
	file=
	dirs=$DATA:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
	old=$IFS
	IFS=:
	for d in $dirs; do
		if [ -f "$d/applications/$1.desktop" ]; then
			file=$d/applications/$1.desktop
			break
		fi
	done
	IFS=$old
	[ -n "$file" ] || fail "This app has no desktop file"
}

essential_name() {
	case "$1" in
	phonegluewc*|phonesettings*|phonekbd*|phonetext*|quickshell*|greetd*) return 0 ;;
	calls|gnome-calls|org.gnome.Calls|sm.puri.Calls|modemmanager|ofono|callaudiod) return 0 ;;
	esac
	return 1
}

# does anything essential need this package, however indirectly
needed_by_essential() {
	todo=$1
	seen=
	n=0
	while [ -n "$todo" ] && [ "$n" -lt 200 ]; do
		next=
		for p in $todo; do
			case " $seen " in *" $p "*) continue ;; esac
			seen="$seen $p"
			n=$((n + 1))
			essential_name "$p" && return 0
			next="$next $(apk info -r "$p" 2>/dev/null | sed -e '/is required by/d' -e 's/-[0-9][^-]*-r[0-9]*$//')"
		done
		todo=$next
	done
	return 1
}

# sets owner, name, essential, needpw, datadir
find_owner() {
	owner=none
	name=
	essential=0
	needpw=0
	datadir=
	exec_line=$(key Exec)
	flat=$(key X-Flatpak)
	if [ -n "$flat" ]; then
		valid '[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+' "$flat" || fail "Not a valid Flatpak id"
		owner=flatpak
		name=$flat
		[ -d "$DATA/flatpak/app/$flat" ] || needpw=1
		[ ! -d "$HOME/.var/app/$flat" ] || datadir=$HOME/.var/app/$flat
	else
		case "$exec_line" in
		waydroid\ app\ launch\ *|*/waydroid\ app\ launch\ *)
			name=${exec_line##* }
			valid '[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+' "$name" || fail "Not a valid Android package"
			owner=waydroid
			;;
		*)
			case "$file" in
			"$DATA"/*|"$HOME"/*) ;;
			*)
				if [ -n "$MOCK" ]; then
					# nothing is asked of the real tools here
					owner=system
					name=$1
				elif command -v apk >/dev/null 2>&1; then
					name=$(apk info --who-owns "$file" 2>/dev/null | sed -n 's/.* is owned by //p' | sed 's/-[0-9][^-]*-r[0-9]*$//' | head -n 1)
					if [ -n "$name" ]; then
						valid '[a-z0-9][a-z0-9._+-]*' "$name" || fail "Not a valid package name"
						owner=system
						needpw=1
					fi
				fi
				;;
			esac
			;;
		esac
	fi
	if essential_name "$1" || { [ -n "$name" ] && essential_name "$name"; }; then
		essential=1
	elif [ "$owner" = system ] && [ -z "$MOCK" ] && needed_by_essential "$name"; then
		essential=1
	fi
	[ -z "$MOCK" ] || needpw=0
}

# the last line says why; a password never reaches an argument
run() {
	if ! out=$("$@" 2>&1); then
		out=$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d' | tail -n 1)
		fail "${out:-The removal failed}"
	fi
}

priv() {
	command -v sudo >/dev/null 2>&1 || fail "A password tool (sudo) is missing"
	run sudo -S -k -p '' -- "$@"
}

remove_app() {
	if [ -n "$MOCK" ]; then
		echo result=simulated
		return
	fi
	[ -f "$MARKER" ] || fail "This is not a phone session, nothing was removed"
	case "$owner" in
	flatpak)
		command -v flatpak >/dev/null 2>&1 || fail "flatpak is missing"
		if [ "$needpw" = 1 ]; then
			priv flatpak uninstall -y --noninteractive --system "$name"
		else
			run flatpak uninstall -y --noninteractive --user "$name"
		fi
		[ "$2" != data ] || [ -z "$datadir" ] || rm -rf -- "$datadir"
		;;
	waydroid)
		command -v waydroid >/dev/null 2>&1 || fail "waydroid is missing"
		run waydroid app remove "$name"
		;;
	system)
		priv apk del "$name"
		# apk only drops it from the wanted list while something else needs it
		! apk info -e "$name" >/dev/null 2>&1 || fail "$name is still needed by another package"
		;;
	*)
		fail "Nothing here says what installed this app"
		;;
	esac
	echo result=ok
}

cmd=${1:-}
id=${2:-}
locate "$id"
find_owner "$id"
case "$cmd" in
inspect)
	printf 'owner=%s\nname=%s\nessential=%s\nneedpw=%s\ndata=%s\n' "$owner" "$name" "$essential" "$needpw" "$datadir"
	;;
remove)
	remove_app "$id" "${3:-}"
	;;
*)
	fail "Usage: uninstall.sh inspect|remove DESKTOP_ID [data]"
	;;
esac
