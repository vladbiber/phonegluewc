pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray
import QtQuick

// What the bar and the panel show. Everything comes from one polled script: a key it does
// not print stays undefined and its icon or tile stays hidden, so nothing is ever guessed.
Singleton {
    id: root

    // The camera hole in panel pixels of the 1080 wide screen: x, y, width, height; 0 by 0 when unknown.
    readonly property rect cameraHole: Dyn.hole
    readonly property real holeMargin: 6
    // the least that still covers the hole's bottom edge (94.7 px is 34.4 at scale 2.75); same tree: rounded_corner_content_padding 63px
    // no real hole to cover, as in the laptop window: only as tall as the row, with small equal margins
    readonly property bool rowOnHole: Dyn.holeKnown && Dyn.turn === "normal"
    readonly property int barHeight: Dyn.sideways ? 24 : Dyn.noHole ? 26 : rowOnHole ? Math.max(36, Math.ceil(Dyn.hy + Dyn.hd + 4)) : 36
    readonly property real cornerPad: 23

    // where the hole is now, turned with the screen
    function holeLeft(w) { return Dyn.hx * w / Dyn.sw - holeMargin; }
    function holeRight(w) { return (Dyn.hx + Dyn.hd) * w / Dyn.sw + holeMargin; }
    // left edge for something wide: in the corner if it fits before the hole, else after it
    function startFor(wide, w) { return !Dyn.holeKnown || cornerPad + wide <= holeLeft(w) ? cornerPad : holeRight(w); }
    // portrait: the row lines up with the camera hole; otherwise the middle of the bar
    function barCenter(w) { return rowOnHole ? Dyn.hy + Dyn.hd / 2 : barHeight / 2; }

    // ---- pull down: pull 0 closed, 1 open; side 0 notifications, 1 quick settings; the finger or settle moves them ----
    property real pull: 0
    property real side: 0
    property bool dragging: false
    // loading starts with the touch: by the first pixel of a pull the sheet is on its way
    property bool barHeld: false
    readonly property bool panelLoaded: pull > 0 || dragging || barHeld
    NumberAnimation {
        id: settle
        target: root
        property: "pull"
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: settleSideAnim
        target: root
        property: "side"
        easing.type: Easing.OutCubic
    }
    function settleTo(v, ms) {
        settle.stop();
        dragging = false;
        settle.duration = ms || 220;
        settle.to = v;
        settle.start();
    }
    function close() { if (panelLoaded) settleTo(0); }
    // the press starts the trail: under load a short flick reaches us as a single move
    function grab(pressedAt) {
        if (!dragging)
            trail = pressedAt ? [[pressedAt, 0]] : [];
        settle.stop();
        settleSideAnim.stop();
        dragging = true;
    }

    // finger positions of the last 100 ms, in logical pixels
    property var trail: []
    function track(pos) {
        const now = Date.now();
        trail.push([now, pos]);
        while (now - trail[0][0] > 100)
            trail.shift();
    }
    // px/s now; a finger that rested before lifting has none, and neither has the tremble of a tap
    function speed() {
        if (trail.length < 2 || Date.now() - trail[trail.length - 1][0] > 80)
            return 0;
        const a = trail[0], b = trail[trail.length - 1];
        return Math.abs(b[1] - a[1]) < 12 ? 0 : (b[1] - a[1]) * 1000 / Math.max(8, b[0] - a[0]);
    }
    readonly property real flick: 500
    // the curve starts at 3x its average speed, so this duration carries on at the finger's speed
    function msFor(px, v) { return Math.abs(v) < 50 ? 220 : Math.max(120, Math.min(320, 3000 * px / Math.abs(v))); }
    // a flick decides by direction, otherwise position against limit
    function releasePull(h, limit) {
        const v = speed();
        const to = Math.abs(v) >= flick ? (v > 0 ? 1 : 0) : pull > limit ? 1 : 0;
        settleTo(to, msFor(Math.abs(to - pull) * h, v));
    }
    function releaseSide(w) {
        const v = speed();
        const to = Math.abs(v) >= flick ? (v < 0 ? 1 : 0) : Math.round(side);
        dragging = false;
        settleSideAnim.stop();
        settleSideAnim.duration = msFor(Math.abs(to - side) * w, v);
        settleSideAnim.to = to;
        settleSideAnim.start();
    }

    Connections {
        target: Phone
        function onPillSeqChanged() { root.close(); }
        function onOverviewChanged() { root.close(); }
        function onLockOpenChanged() { root.close(); }
        function onMenuOpenChanged() { root.close(); }
    }
    // opening is the moment the panel's detail must be fresh
    onPanelLoadedChanged: if (panelLoaded) refresh()

    // ---- polled state ----
    readonly property string sysDir: Quickshell.env("PHONE_SYS_DIR") || "/sys/class"
    property var s: ({})

    readonly property bool hasBattery: s.bat !== undefined && s.bat !== ""
    readonly property int battery: parseInt(s.bat)
    readonly property bool charging: s.batstate === "Charging"
    readonly property bool hasWifi: s.wifistate !== undefined
    readonly property bool wifiOn: s.wifiradio === "enabled"
    readonly property bool wifiConnected: (s.wifistate || "").startsWith("connected")
    readonly property int wifiLevel: !wifiConnected || s.wifisig === undefined ? 0
        : s.wifisig > 66 ? 3 : s.wifisig > 33 ? 2 : 1
    readonly property bool hasCell: s.cellsig !== undefined
    readonly property int cellLevel: Math.min(4, Math.ceil(parseInt(s.cellsig) / 25))
    // ModemManager lists from slowest to fastest and the last line wins, so a 5G link with LTE anchor reads 5G
    readonly property string cellType: ({ "5gnr": "5G", lte: "LTE", "hspa-plus": "H+", hspa: "H", hsdpa: "H", hsupa: "H", umts: "3G", edge: "E", gprs: "G", gsm: "2G" })[s.celltech] || ""
    readonly property bool hasData: hasCell && s.gsmprofile !== undefined
    readonly property bool dataOn: (s.gsmstate || "").startsWith("connected")
    readonly property bool hasBt: s.btpower !== undefined
    readonly property bool btOn: s.btpower === "yes"
    readonly property int btConnected: parseInt(s.btn) || 0
    readonly property bool hasVolume: s.vol !== undefined
    readonly property real volume: parseFloat(s.vol)
    readonly property bool muted: s.muted === "1"
    readonly property string volIcon: muted ? "volx" : volume > 0.5 ? "vol2" : volume > 0 ? "vol1" : "vol0"
    readonly property bool hasBrightness: s.blname !== undefined && parseInt(s.blmax) > 0 && s.setlight === "1"
    readonly property real brightness: parseInt(s.bl) / parseInt(s.blmax)
    readonly property bool hasTorch: s.torch !== undefined && s.setlight === "1"
    readonly property bool torchOn: parseInt(s.torchval) > 0
    // the compositor writes normal, 90, 180 or 270 once it can rotate; no file, no tile
    readonly property bool hasRotation: orientation !== ""
    readonly property bool rotationLocked: s.rotlock === "1"
    property string orientation: ""
    FileView {
        path: Phone.stateDir + "/orientation"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.orientation = ["normal", "90", "180", "270"].includes(text().trim()) ? text().trim() : ""
        onLoadFailed: root.orientation = ""
    }
    // "<counter> <transform>": a new counter while locked offers that turn for a few seconds
    property string rotateOffer: ""
    property string offerCount: ""
    property bool offerPrimed: false
    FileView {
        path: Phone.stateDir + "/rotate-offer"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const p = text().trim().split(/\s+/);
            const fresh = root.offerPrimed && p[0] !== root.offerCount;
            root.offerCount = p[0];
            root.offerPrimed = true;
            if (fresh && ["normal", "90", "180", "270"].includes(p[1]) && p[1] !== root.orientation) {
                root.rotateOffer = p[1];
                offerTimer.restart();
            }
        }
        onLoadFailed: root.offerPrimed = true
    }
    Timer { id: offerTimer; interval: 4000; onTriggered: root.rotateOffer = "" }
    function rotateTo(t) {
        rotateOffer = "";
        Quickshell.execDetached(["phonegluewc-msg", "rotate", t]);
    }

    // Linux has no ringer: phone.conf holds it, either side may change it; media volume is never touched
    readonly property string ringer: ["vibrate", "silent"].includes(Phone.conf.ringer) ? Phone.conf.ringer : "normal"
    readonly property string ringerIcon: ringer === "normal" ? "bell" : ringer
    readonly property bool dnd: Phone.conf.dnd === "on"
    function setRinger(m) { Phone.setConf("ringer", m); }
    property real lastAlert: 0
    function alert() {
        if (dnd || ringer === "silent" || Date.now() - lastAlert < 800)
            return;
        lastAlert = Date.now();
        if (ringer === "vibrate")
            Quickshell.execDetached(["sh", "-c", 'command -v fbcli >/dev/null && exec fbcli -E message-new-instant']);
        else
            Quickshell.execDetached(["sh", "-c", 'if command -v pw-play >/dev/null; then exec pw-play "$1"; elif command -v paplay >/dev/null; then exec paplay "$1"; fi',
                "phonestatus", Quickshell.shellDir + "/notify.wav"]);
    }
    // shortcut: set by the panel, a recorder that dies by itself keeps the dot until the panel next opens
    property bool recording: false

    readonly property string rotationFile: Phone.stateDir + "/rotation-lock"

    Process {
        id: poll
        property real startedAt: 0
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root.lastPoll)
                    return;
                root.lastPoll = text;
                const o = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0)
                        o[line.slice(0, i)] = line.slice(i + 1).replace(/\\(.)/g, "$1");
                }
                // a value set here after this poll began, or still on its way out, beats what the poll read
                for (const k in root.setAt)
                    if (root.setAt[k] > poll.startedAt - 400 && root.s[k] !== undefined)
                        o[k] = root.s[k];
                root.s = o;
            }
        }
    }
    property string lastPoll: ""
    function refresh() {
        if (poll.running) {
            soon.restart();
            return;
        }
        poll.command = ["sh", "-c", script, "phonestatus", sysDir, panelLoaded ? "open" : "", rotationFile];
        poll.startedAt = Date.now();
        poll.running = true;
    }
    // a shell that starts locked still learns the volume and the torch once
    Component.onCompleted: if (Phone.lockOpen) refresh()
    // nothing to see behind the lock, and fresh the moment it opens
    Timer {
        running: !Phone.lockOpen
        repeat: true
        triggeredOnStart: true
        interval: root.panelLoaded ? 3000 : 15000
        onTriggered: root.refresh()
    }
    Timer { id: soon; interval: 500; onTriggered: root.refresh() }

    readonly property string script: `
B=$1
for d in "$B"/power_supply/*; do
	[ "$(cat "$d/type" 2>/dev/null)" = Battery ] || continue
	[ "$(cat "$d/scope" 2>/dev/null)" = Device ] && continue
	echo "bat=$(cat "$d/capacity" 2>/dev/null)"
	echo "batstate=$(cat "$d/status" 2>/dev/null)"
	echo "batdir=$d"
	break
done
if command -v nmcli >/dev/null; then
	dev=$(nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null)
	if [ -n "$dev" ]; then
		echo "$dev" | awk -F: '$1=="wifi" && !w++ { print "wifistate=" $2; n=$0; sub(/^[^:]*:[^:]*:/,"",n); print "wifiname=" n }
			$1=="gsm" && !g++ { print "gsmstate=" $2 }'
		echo "wifiradio=$(nmcli -t -f WIFI radio 2>/dev/null)"
		case "$dev" in *wifi:connected*) nmcli -t -f ACTIVE,SIGNAL dev wifi list --rescan no 2>/dev/null | awk -F: '$1=="yes" { print "wifisig=" $2; exit }' ;; esac
		[ "$2" = open ] && nmcli -t -f NAME,TYPE con show 2>/dev/null | sed -n 's/:gsm$//p' | head -1 | sed 's/^/gsmprofile=/'
	fi
fi
if command -v mmcli >/dev/null; then
	timeout 3 mmcli -m any -K 2>/dev/null | awk -F' *: *' '/signal-quality.value/ { print "cellsig=" $2 } /3gpp.operator-name/ && $2 != "--" { print "operator=" $2 } /access-technologies.value/ { print "celltech=" $2 }'
fi
if command -v bluetoothctl >/dev/null; then
	p=$(timeout 2 bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }')
	if [ -n "$p" ]; then
		echo "btpower=$p"
		[ "$p" = yes ] && echo "btn=$(timeout 2 bluetoothctl devices Connected 2>/dev/null | grep -c ^Device)"
	fi
fi
if command -v wpctl >/dev/null; then
	timeout 2 wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '/^Volume:/ { print "vol=" $2; if (/MUTED/) print "muted=1" }'
fi
command -v nmcli >/dev/null && echo "conns=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | awk '{ printf "%s%s", (NR > 1 ? "," : ""), $0 }')"
[ "$p" = yes ] && timeout 2 bluetoothctl devices Connected 2>/dev/null | awk 'NR==1 { sub(/^Device [^ ]+ /,""); print "btname=" $0 }'
if command -v wpctl >/dev/null; then
	wpctl status 2>/dev/null | awk '/Streams:/ { s=1; next } /^[^ │]|^$/ { s=0 } s && / < / { print "micuse=1"; exit }'
fi
for v in /dev/video* "$1/fake-video"; do
	[ -e "$v" ] && command -v fuser >/dev/null && fuser "$v" >/dev/null 2>&1 && { echo camuse=1; break; }
done
command -v brightnessctl >/dev/null && echo setlight=1
for d in "$B"/backlight/*; do
	[ -e "$d/max_brightness" ] || continue
	echo "blname=\${d##*/}"
	echo "blmax=$(cat "$d/max_brightness")"
	echo "bl=$(cat "$d/actual_brightness" 2>/dev/null || cat "$d/brightness")"
	break
done
t=$(ls "$B/leds" 2>/dev/null | grep -i torch | head -1)
[ -n "$t" ] || t=$(ls "$B/leds" 2>/dev/null | grep -i flash | head -1)
if [ -n "$t" ]; then
	echo "torch=$t"
	echo "torchval=$(cat "$B/leds/$t/brightness" 2>/dev/null)"
fi
[ "$2" = open ] || exit 0
[ -e "$3" ] && echo "rotlock=$(cat "$3")"
exit 0
`

    // ---- charger in or out: read each second without a process, so it shows at once, also locked or dark ----
    readonly property string batDir: s.batdir || ""
    property string plugState: ""
    // reload answers later, in onLoaded
    Timer {
        interval: 1000
        repeat: true
        running: root.batDir !== ""
        onTriggered: { batLevel.reload(); batStatus.reload(); }
    }
    FileView { id: batLevel; path: root.batDir ? root.batDir + "/capacity" : ""; printErrors: false }
    FileView {
        id: batStatus
        path: root.batDir ? root.batDir + "/status" : ""
        printErrors: false
        onLoaded: {
            const t = text().trim();
            const was = root.plugState;
            root.plugState = t;
            const on = v => ["Charging", "Full", "Not charging"].includes(v);
            if (was === "" || t === "" || on(t) === on(was))
                return;
            const level = parseInt(batLevel.text()) || root.battery;
            // the level is left to the poll: this read of it can be a second old
            root.s = Object.assign({}, root.s, { batstate: t });
            // the same switch as the dynamic camera's charging alerts
            if (Phone.conf.dyn_charging !== "off")
                root.charged(on(t), level);
        }
    }
    // the animation's state; a dark screen lights for it and goes dark again unless someone started using it
    property int chargeSeq: 0
    property bool chargePlugged: false
    property int chargeLevel: 0
    property bool chargeShowing: false
    property bool chargeWoke: false
    function charged(plugged, level) {
        chargePlugged = plugged;
        chargeLevel = Math.max(0, Math.min(100, level));
        chargeWoke = chargeWoke || Phone.screenOff;
        if (Phone.screenOff)
            Quickshell.execDetached(["phonegluewc-msg", "power", "on"]);
        // hidden a moment so a second plug while showing starts the animation over
        chargeShowing = false;
        chargeHold.stop();
        chargeLit.interval = Phone.screenOff ? 300 : 60;
        chargeLit.restart();
    }
    // a dark screen fades in for 200 ms first
    Timer {
        id: chargeLit
        onTriggered: {
            root.chargeShowing = true;
            root.chargeSeq++;
            chargeHold.restart();
        }
    }
    Timer {
        id: chargeHold
        interval: 3000
        onTriggered: {
            root.chargeShowing = false;
            if (root.chargeWoke && Phone.lockOpen && !Phone.lockTyped && !Phone.screenOff)
                Quickshell.execDetached(["phonegluewc-msg", "power", "off"]);
            root.chargeWoke = false;
        }
    }

    // ---- actions ----
    function run(cmd) {
        Quickshell.execDetached(cmd);
        soon.restart();
    }
    // a slider fires faster than the tools run: only the newest value of each goes out
    property var pending: ({})
    Timer {
        id: flush
        interval: 120
        onTriggered: {
            for (const k in root.pending)
                root.run(root.pending[k]);
            root.pending = {};
        }
    }
    // when each field was last set here
    property var setAt: ({})
    function later(key, cmd, patch) {
        pending[key] = cmd;
        for (const k in patch)
            setAt[k] = Date.now();
        s = Object.assign({}, s, patch);
        flush.start();
    }

    function toggleWifi() { run(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"]); }
    function toggleBt() {
        run(["sh", "-c", 'command -v rfkill >/dev/null && [ "$1" = on ] && rfkill unblock bluetooth; bluetoothctl power "$1"',
            "phonestatus", btOn ? "off" : "on"]);
    }
    function toggleData() { run(["nmcli", "con", dataOn ? "down" : "up", "id", s.gsmprofile]); }
    function toggleTorch() { run(["brightnessctl", "-q", "--class=leds", "-d", s.torch, "set", torchOn ? "0" : "100%"]); }
    // a manual turn: the lock goes on first so the sensor cannot undo it, the lock tile gives it back
    function turnTo(t) {
        run(["sh", "-c", 'printf 1 > "$1" && exec phonegluewc-msg rotate "$2"', "phonestatus", rotationFile, t]);
    }
    function turnName(t) {
        return { normal: "Portrait", "90": "Landscape", "270": "Landscape, flipped", "180": "Portrait, flipped" }[t] || "";
    }
    function toggleRotation() {
        run(["sh", "-c", 'printf %s "$1" > "$2"', "phonestatus", rotationLocked ? "0" : "1", rotationFile]);
    }
    function toggleMute() { run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]); }
    // a hardware key: the new level shows at once, wpctl follows
    // the bar shows on every press, also one that hits either end
    signal volumeStepped()
    function stepVolume(d) {
        if (hasVolume)
            setVolume(Math.max(0, Math.min(1, Math.round((volume + d) * 20) / 20)));
        else
            run(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "5%" + (d > 0 ? "+" : "-")]);
        volumeStepped();
    }
    function setVolume(v) {
        const p = Math.round(v * 100);
        later("volume", ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", p + "%"], { vol: String(p / 100) });
    }
    // never all the way down: at 0 the panel can go dark with the slider out of sight
    function setBrightness(v) {
        const p = Math.max(3, Math.round(v * 100));
        later("brightness", ["brightnessctl", "-q", "-d", s.blname, "set", p + "%"], { bl: String(Math.round(p / 100 * parseInt(s.blmax))) });
    }
    // shortcut: loginctl only, as logind or elogind provide it; add others if a phone image lacks both
    function power(verb) {
        close();
        run(["loginctl", verb]);
    }
    function settings(page) {
        Quickshell.execDetached(page ? ["phonesettings", page] : ["phonesettings"]);
        close();
    }

    // ---- active apps ----
    // tray apps register once, at their start: the watcher must exist from now on, not from the first panel
    readonly property var trayWatcher: SystemTray.items
    // apps asked to close, kept here so that closing the panel forgets nothing
    property var closing: ({})
    readonly property string appCtl: Quickshell.shellDir + "/appctl.sh"
    // "pid:start" -> app id of every process that had a window; alive with none left, it runs in the background
    property var launched: ({})
    FileView {
        id: windowsFile
        path: Phone.stateDir + "/windows"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.stampWindows()
    }
    function stampWindows() {
        if (stamper.running) {
            stamper.again = true;
            return;
        }
        const ids = {};
        for (const l of windowsFile.text().split("\n")) {
            const f = l.split("\t");
            // an Android window's pid is the whole container
            if (f[0] && f[1] && !/^waydroid/i.test(f[1]) && !Object.keys(launched).some(k => k.startsWith(f[0] + ":")))
                ids[f[0]] = f[1];
        }
        if (Object.keys(ids).length === 0)
            return;
        stamper.ids = ids;
        stamper.command = ["sh", appCtl, "stamp"].concat(Object.keys(ids));
        stamper.running = true;
    }
    Process {
        id: stamper
        property var ids: ({})
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                const next = Object.assign({}, root.launched);
                for (const a of text.split("\n"))
                    if (a)
                        next[a] = stamper.ids[a.split(":")[0]];
                root.launched = next;
            }
        }
        onExited: if (again) { again = false; root.stampWindows(); }
    }
    function sendSignal(sig, pids) {
        if (pids.length > 0)
            Quickshell.execDetached(["sh", appCtl, "signal", sig].concat(pids.map(p => p.pid + ":" + p.start)));
    }
    // here and not with the panel: closing the panel must not drop the fallback signal
    function askToQuit(item, pids) { quitter.createObject(root, { item: item, pids: pids }); }
    // the item's own Quit when its menu has one, otherwise a TERM
    Component {
        id: quitter
        QtObject {
            id: q
            property var item
            property var pids: []
            function look() {
                const kids = opener.children ? opener.children.values : [];
                // labels may mark a shortcut, as in _Quit or &Quit
                const e = kids.find(m => /^(quit|exit|ieși|ieșire)( |$)/i.test((m.text || "").replace(/[_&]/g, "")));
                if (e) {
                    e.triggered();
                    q.destroy();
                }
            }
            property QsMenuOpener opener: QsMenuOpener { menu: q.item ? q.item.menu : null }
            // the menu loads over the bus and its labels arrive later than the entries
            property Timer poke: Timer {
                running: true
                repeat: true
                interval: 100
                onTriggered: q.look()
            }
            property Timer giveUp: Timer {
                running: true
                interval: 1500
                onTriggered: {
                    root.sendSignal("TERM", q.pids);
                    q.destroy();
                }
            }
        }
    }

    // ---- notifications: this shell is the daemon, ported from glueqs Notifs ----
    property var notifs: []
    NotificationServer {
        bodySupported: true
        imageSupported: false
        actionsSupported: false
        onNotification: n => {
            // Waydroid reposts every update and summary over D-Bus; Droid has the real ones
            if ((Droid.live && /^waydroid\./.test(n.desktopEntry || "")) || (!n.summary && !n.body)) {
                n.dismiss();
                return;
            }
            root.notifs = [{
                app: n.appName || "",
                icon: (n.appIcon || "").replace(/^file:\/\//, ""),
                summary: n.summary || "",
                body: n.body || "",
                time: Qt.formatTime(new Date(), "HH:mm")
            }].concat(root.notifs).slice(0, 30);
            n.dismiss();
            root.alert();
        }
    }
    // one per app, the newest first
    readonly property var notifApps: {
        const out = [];
        for (const n of notifs)
            if (!out.some(o => o.app === n.app))
                out.push(n);
        return out;
    }
    // the panel's cards: one per app, the newest first
    readonly property var notifGroups: notifApps.map(a => ({ app: a.app, icon: a.icon, items: notifs.filter(n => n.app === a.app) }))
    // from this shell itself: goes in the panel without a sound
    function addNotif(summary, body) {
        notifs = [{ app: "Phone", icon: "", summary: summary, body: body, time: Qt.formatTime(new Date(), "HH:mm") }].concat(notifs).slice(0, 30);
    }
    function clearNotifs() { notifs = []; }
}
