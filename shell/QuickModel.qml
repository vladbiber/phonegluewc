import Quickshell
import Quickshell.Io
import QtQuick

// Every tile: what it needs, what it shows, what a tap runs. Lives with the panel, so nothing here costs anything closed.
Scope {
    id: root

    readonly property var known: ["data", "airplane", "ringer", "dnd", "torch", "hotspot", "rotation", "turn", "sleep", "dark", "night", "record", "screenshot",
        "saver", "nfc", "location", "glyph", "calc", "clock", "camera", "qr", "notes", "share", "recorder"]
    // what the open panel polls; a key not printed means the tile is not there
    property var q: ({})
    property var sinks: []

    // phone.conf is written whole by rename; unknown names are dropped, nothing readable means the default
    function parse(v) {
        if (v === undefined)
            return known;
        if (v === "-")
            return [];
        const seen = [];
        for (const raw of v.split(",")) {
            const id = raw.trim();
            if (known.includes(id) && !seen.includes(id))
                seen.push(id);
        }
        return seen.length ? seen : known;
    }
    readonly property var order: parse(Phone.conf.quick_tiles)
    // tiles hidden for lack of hardware keep their place
    function saveOrder(shown) {
        const next = shown.concat(order.filter(i => !shown.includes(i) && !tile(i).avail));
        Phone.setConf("quick_tiles", next.join(",") || "-");
    }
    // the blocks of the page, top down; any left out go last
    readonly property var allBlocks: ["big", "brightness", "volume", "grid"]
    readonly property var blocks: {
        const seen = (Phone.conf.quick_blocks || "").split(",").map(b => b.trim()).filter((b, i, a) => allBlocks.includes(b) && a.indexOf(b) === i);
        return seen.concat(allBlocks.filter(b => !seen.includes(b)));
    }
    function saveBlocks(list) { Phone.setConf("quick_blocks", list.join(",")); }
    readonly property string idsKey: order.filter(i => tile(i).avail).join(" ")
    readonly property var ids: idsKey === "" ? [] : idsKey.split(" ")
    readonly property string offKey: known.filter(i => tile(i).avail && !order.includes(i)).join(" ")
    readonly property var available: offKey === "" ? [] : offKey.split(" ")

    // qs swaps its whole app list now and then, one entry at a time within one event:
    // following each step would rebuild the grid and lose the tile under the finger
    property var appList: []
    function takeApps() { appList = Phone.apps; }
    Connections {
        target: Phone
        function onAppsChanged() { Qt.callLater(root.takeApps); }
        Component.onCompleted: root.takeApps()
    }
    function entry(pattern, category) {
        return root.appList.find(e => (category && (e.categories || []).includes(category)) || (pattern && pattern.test(e.id + " " + e.name)));
    }
    readonly property var shortcuts: ({
        calc: entry(null, "Calculator"),
        clock: entry(null, "Clock"),
        camera: entry(null, "Camera") || entry(/camera/i, ""),
        qr: entry(/\bqr|qr\b/i, ""),
        notes: entry(/notes?\b/i, ""),
        share: entry(/localsend|warpinator|kdeconnect/i, ""),
        recorder: entry(null, "Recorder")
    })
    function openApp(e) {
        Status.close();
        Phone.launch(e);
    }
    function app(id, label, icon) {
        const e = shortcuts[id];
        return { avail: !!e, on: false, label: label, icon: icon, page: "", sub: "", tap: () => root.openApp(e) };
    }
    function rfToggle(type, label, icon) {
        const on = q["rf_" + type] === "unblocked";
        return { avail: q["rf_" + type] !== undefined, on: on, label: label, icon: icon, page: "",
            tap: () => root.act(["rfkill", on ? "block" : "unblock", type]) };
    }
    // the pid file holds the tool itself: exec keeps the pid, so stopping cannot hit anything else
    function startPid(name, tool) { return 'echo $$ >"' + Phone.stateDir + "/" + name + '.pid"; exec ' + tool; }
    function stop(name, comm, sig) {
        act(["sh", "-c", 'f=$1/$2.pid; p=$(cat "$f" 2>/dev/null); [ -n "$p" ] && [ -O "/proc/$p" ] && [ "$(cat "/proc/$p/comm")" = "$3" ] && kill -"$4" "$p"; rm -f "$f"',
            "phonequick", Phone.stateDir, name, comm, sig]);
    }

    function nextRinger() {
        const r = Status.ringer;
        return r === "normal" ? (q.fbcli ? "vibrate" : "silent") : r === "vibrate" ? "silent" : "normal";
    }
    function tile(id) {
        switch (id) {
        case "data": return { avail: Status.hasData, on: Status.dataOn, label: "Mobile data", icon: "data", page: "mobile", tap: () => Status.toggleData() };
        case "airplane": return { avail: q.rfall !== undefined, on: q.rfall === "1", label: "Airplane", icon: "plane", page: "",
            tap: () => root.act(["rfkill", q.rfall === "1" ? "unblock" : "block", "all"]) };
        case "ringer": return { avail: Status.hasVolume, on: Status.ringer !== "normal", icon: Status.ringerIcon, page: "sound", sub: "",
            label: { normal: "Ring", vibrate: "Vibrate", silent: "Silent" }[Status.ringer], tap: () => Status.setRinger(nextRinger()) };
        case "dnd": return { avail: !!q.player || !!q.fbcli, on: Status.dnd, label: "Do not disturb", icon: "dnd", page: "sound", tap: () => Phone.setConf("dnd", Status.dnd ? "off" : "on") };
        case "torch": return { avail: Status.hasTorch, on: Status.torchOn, label: "Flashlight", icon: "torch", page: "", tap: () => Status.toggleTorch() };
        case "hotspot": return { avail: q.hotspot !== undefined, on: q.hotspot === "on", label: "Hotspot", icon: "hotspot", page: "wifi",
            tap: () => root.act(q.hotspot === "on" ? ["nmcli", "con", "down", "Hotspot"] : ["nmcli", "device", "wifi", "hotspot"]) };
        case "rotation": return { avail: Status.hasRotation, on: Status.rotationLocked, label: "Rotation lock", icon: "lock", page: "display", tap: () => Status.toggleRotation() };
        // a tap turns between upright and sideways, a hold picks any of four; either locks the sensor out
        case "turn": return { avail: Status.hasRotation, on: false, label: "Rotate", icon: "rotate", page: "", sub: Status.turnName(Status.orientation),
            tap: () => Status.turnTo(Status.orientation === "normal" || !Status.orientation ? "90" : "normal") };
        case "sleep": return { avail: true, on: Phone.sleepAfter > 0, label: "Screen timeout", icon: "timer", page: "display",
            sub: Phone.sleepAfter > 0 ? Phone.sleepAfter + " min" : "Never", tap: () => Phone.nextSleep() };
        case "dark": return { avail: true, on: !Phone.light, label: "Dark mode", icon: "dark", page: "look", tap: () => Phone.setTheme(!Phone.light) };
        case "night": return { avail: q.night !== undefined, on: q.nighton === "1", label: "Night light", icon: "night", page: "display",
            tap: () => { if (q.nighton === "1") root.stop("quick-night", q.night, "TERM"); else root.act(["sh", "-c", root.startPid("quick-night", q.night === "gammastep" ? "gammastep -O 3500"
                // shortcut: wlsunset has no fixed mode, this is warm except for the minute after midnight; use its SIGUSR1 modes if that shows
                : "wlsunset -S 00:00 -s 00:01 -d 1 -t 3500")]); } };
        case "record": return { avail: q.recorder !== undefined, on: q.recording === "1", label: q.recording === "1" ? "Recording" : "Screen record", icon: "record", page: "", sub: "",
            tap: () => {
                if (q.recording === "1") {
                    Recorder.stop();
                    soon.restart();
                } else {
                    Status.close();
                    Recorder.ask();
                }
            } };
        case "screenshot": return { avail: !!q.grim, on: false, label: "Screenshot", icon: "shot", page: "", sub: "",
            tap: () => {
                Status.close();
                // the panel is gone by then; the note is the only sign that it worked
                root.act(["sh", "-c", 'sleep 0.5; d="$HOME/Pictures/Screenshots"; mkdir -p "$d"; f="$d/screenshot-$(date +%Y%m%d-%H%M%S).png"; grim "$f" && command -v notify-send >/dev/null && notify-send -a Screenshot "Screenshot saved" "$f"']);
            } };
        case "saver": return { avail: q.profile !== undefined, on: q.profile === "power-saver", label: "Battery saver", icon: "saver", page: "battery",
            tap: () => root.act(["powerprofilesctl", "set", q.profile === "power-saver" ? "balanced" : "power-saver"]) };
        case "nfc": return rfToggle("nfc", "NFC", "nfc");
        case "location": return rfToggle("gps", "Location", "pin");
        case "glyph": return { avail: q.glyph !== undefined, on: parseInt(q.glyphval) > 0, label: "Glyph", icon: "glyph", page: "",
            tap: () => root.act(["phoneglyph", "toggle"]) };
        case "calc": return app("calc", "Calculator", "calc");
        case "clock": return app("clock", "Timer", "clock");
        case "camera": return app("camera", "Camera", "camera");
        case "qr": return app("qr", "QR scanner", "qr");
        case "notes": return app("notes", "Notes", "note");
        case "share": return app("share", "Share", "share");
        case "recorder": return app("recorder", "Recorder", "mic");
        }
        return { avail: false };
    }

    function act(cmd) {
        Status.run(cmd);
        soon.restart();
    }
    function setSink(id) {
        Status.run(["wpctl", "set-default", String(id)]);
        sinkPoll.running = true;
    }

    Timer { id: soon; interval: 700; onTriggered: root.refresh() }
    Timer { running: true; repeat: true; interval: 3000; onTriggered: root.refresh() }
    function refresh() {
        if (!poll.running)
            poll.running = true;
    }
    Process {
        id: poll
        running: true
        command: ["sh", "-c", root.script, "phonequick", Status.sysDir, Phone.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0)
                        o[line.slice(0, i)] = line.slice(i + 1);
                }
                root.q = o;
                Status.recording = o.recording === "1";
            }
        }
    }
    readonly property string script: `
alive() { p=$(cat "$2/$1.pid" 2>/dev/null); [ -n "$p" ] && [ -O "/proc/$p" ] && [ "$(cat "/proc/$p/comm" 2>/dev/null)" = "$3" ]; }
command -v rfkill >/dev/null && rfkill -rn -o TYPE,SOFT 2>/dev/null | awk '{ print "rf_" $1 "=" $2; n++; if ($2 == "blocked") b++ } END { if (n) print "rfall=" (n == b ? 1 : 0) }'
if command -v nmcli >/dev/null; then
	d=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2 == "wifi" { print $1; exit }')
	if [ -n "$d" ] && [ "$(nmcli -g WIFI-PROPERTIES.AP dev show "$d" 2>/dev/null)" = yes ]; then
		nmcli -t -f NAME con show --active 2>/dev/null | grep -qx Hotspot && echo hotspot=on || echo hotspot=off
	fi
fi
for t in wlsunset gammastep; do
	command -v $t >/dev/null || continue
	echo "night=$t"
	alive quick-night "$2" $t && echo nighton=1
	break
done
if command -v wf-recorder >/dev/null; then
	echo recorder=1
	alive quick-record "$2" wf-recorder && echo recording=1
fi
command -v grim >/dev/null && echo grim=1
command -v powerprofilesctl >/dev/null && v=$(powerprofilesctl get 2>/dev/null) && echo "profile=$v"
command -v fbcli >/dev/null && echo fbcli=1
command -v pw-play >/dev/null || command -v paplay >/dev/null && echo player=1
if command -v phoneglyph >/dev/null; then
	echo glyph=aw21018
	grep -q '"on": true' /run/phoneglyph/state.json 2>/dev/null && echo glyphval=1 || echo glyphval=0
fi
exit 0
`
    // same reading as the settings app: the sinks lie between the Sinks heading and the next heading of Audio
    Process {
        id: sinkPoll
        running: true
        command: ["sh", "-c", 'command -v wpctl >/dev/null && timeout 2 wpctl status 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                let audio = false, inSinks = false;
                for (const l of text.split("\n")) {
                    if (/^Audio/.test(l))
                        audio = true;
                    else if (/^\S/.test(l))
                        audio = false;
                    if (!audio)
                        continue;
                    if (/Sinks:/.test(l)) {
                        inSinks = true;
                        continue;
                    }
                    if (/[├└]─/.test(l))
                        inSinks = false;
                    const m = inSinks && l.match(/(\*?)\s*(\d+)\.\s+(.+?)(?:\s+\[vol:.*\])?\s*$/);
                    if (m)
                        found.push({ id: m[2], name: m[3], active: m[1] === "*" });
                }
                root.sinks = found;
            }
        }
    }
}
