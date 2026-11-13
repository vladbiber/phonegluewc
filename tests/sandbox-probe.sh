#!/bin/sh
# Runs inside the sandbox and reports what a test program could reach.
env | sort
echo "== activatable"
dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListActivatableNames | grep -o '"[^"]*"'
echo "== launchers"
for p in xdg-open gtk-launch gio librewolf firefox chromium foot systemctl loginctl sudo; do command -v "$p"; done
echo "== runtime"
ls "$XDG_RUNTIME_DIR"
