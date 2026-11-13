#!/bin/sh
# ui.sh [VAR=VAL ...] -- ACTION...   (sudo password on stdin)
# actions: s NAME (screenshot) | t X Y (tap) | d X1 Y1 X2 Y2 (drag) | p CX CY D1 D2 (pinch) | w SECONDS | r normal|90|270 | k (keep app, print pid)
# Runs the test copy of the camera on the live session; call under flock /tmp/phone-screen.lock.
export XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0
while [ "$1" != "--" ]; do export "$1"; shift; done; shift
[ -n "$KEEPCONF" ] || rm -f ~/.config/phonecam.json
mkdir -p ~/camtest/shots; F=~/camtest/touch.fifo; rm -f $F; mkfifo $F
read -r PW; echo "$PW" | sudo -S python3 ~/camtest/touch.py $F 2>~/camtest/touch.log &
say() { timeout 3 sh -c "echo $* > $F" || echo "touch injector not listening"; }
# the camera is on screen and in front: shutter disc white or red, black ring gap around it, black panel under it
px() { set -- $(grim -t ppm -g "$1,$2 1x1" - | tail -c 3 | od -An -tu1); echo "${1:-0}"; }
ring() { [ "$(px 216 903)" -gt 150 ] && [ "$(px 180 903)" -gt 200 ] && [ "$(px 252 903)" -gt 200 ] && [ "$(px 216 871)" -lt 40 ]; }
sheet() { v=$(px 6 900); [ "$v" -gt 12 ] && [ "$v" -lt 22 ] && [ "$(px 216 928)" -gt 200 ]; }  # sheet grey, white DONE text is off-centre: checked loosely
seen() { [ -n "$LAND" ] || { wlrctl toplevel find app_id:org.phonegluewc.Camera state:active >/dev/null 2>&1 && [ "$(px 216 950)" -lt 40 ] && { ring || [ "$(px 6 900)" = 17 ]; }; }; }
[ -n "$UNLOCK" ] && { phonegluewc-msg power on; sleep 0.7; wtype "$UNLOCK"; sleep 0.5; wtype -k Return; sleep 1.5; }
[ -n "$NOAPP" ] || ~/camtest/app/phonecam >~/camtest/app.log 2>&1 &
i=0; while ! seen && [ $i -lt 16 ]; do sleep 0.5; i=$((i+1)); done
if ! seen && [ -z "$NOAPP" ]; then echo "ABORT: camera not visible (locked?)"; grim ~/camtest/shots/abort.png; set --; fi
APP=$(pgrep -f "python3 -I /home/user/camtest/app/phonecam" | tail -1)
sleep 1.5; KEEP=; echo $APP > ~/camtest/app.pid
while [ $# -gt 0 ]; do
  case $1 in
    s) grim ~/camtest/shots/$2.png; shift 2 ;;
    t|d|p) if ! seen; then echo "ABORT before $*: camera not in front"; grim ~/camtest/shots/abort.png; break; fi ;;
  esac
  case $1 in
    t) say tap $2 $3; sleep 0.5; shift 3 ;;
    d) say drag $2 $3 $4 $5; sleep 0.9; shift 5 ;;
    p) say pinch $2 $3 $4 $5; sleep 0.9; shift 5 ;;
    w) sleep $2; shift 2 ;;
    r) phonegluewc-msg rotate $2; [ "$2" = normal ] && LAND= || LAND=1; sleep 1; shift 2 ;;
    k) KEEP=1; echo "APP $APP"; shift ;;
  esac
done
say quit
[ -z "$KEEP" ] && [ -n "$APP" ] && [ -z "$NOAPP" ] && kill $APP && sleep 1 && pgrep -f "camtest/app/phonecam" >/dev/null && echo "STILL RUNNING"
grep -v -E "portal|presented|^$" ~/camtest/app.log | tail -6
