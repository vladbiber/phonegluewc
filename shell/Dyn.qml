pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick

// The dynamic camera: what is active, in which order, and the one shape that shows it.
// Items are computed from their sources, so a source that ends takes its item with it.
Singleton {
    id: root

    readonly property bool on: !Auth.greeter && Phone.conf.dynamic_camera !== "off"
    function allowed(group) { return Phone.conf["dyn_" + group] !== "off"; }
    readonly property bool anim: Phone.conf.animations !== "off"

    // ---- the hole, in pixels of a 1080 wide panel ----
    // Linux has no API that says where it is, so: the user's setting, then camera-holes by device tree compatible
    readonly property bool noHole: Quickshell.env("PHONE_NO_HOLE") === "1"
    readonly property bool fake: noHole && on
    FileView { id: holesFile; path: Quickshell.shellPath("camera-holes"); blockLoading: true; printErrors: false }
    FileView { id: compatFile; path: "/proc/device-tree/compatible"; blockLoading: true; printErrors: false }
    readonly property var holeAuto: {
        if (noHole) {
            const place = Quickshell.env("PHONE_CAMERA");
            const d = 52.38;
            return on ? { x: place === "center" ? (1080 - d) / 2 : place === "right" ? 1080 - 89.3 - d : 89.3, y: 9.56, d: d } : null;
        }
        const names = (Quickshell.env("PHONE_COMPATIBLE") || compatFile.text()).split("\0");
        for (const line of holesFile.text().split("\n")) {
            const p = line.trim().split(/\s+/);
            if (p.length === 4 && names.includes(p[0]) && p[3] > 0)
                return { x: +p[1], y: +p[2], d: +p[3] };
        }
        return null;
    }
    readonly property var holeSet: {
        const p = (Phone.conf.camera_hole || "").split(",").map(Number);
        return p.length === 3 && p[0] >= 0 && p[1] >= 0 && p[2] > 0 && p[0] + p[2] <= 1080 ? { x: p[0], y: p[1], d: p[2] } : null;
    }
    readonly property var holeNow: noHole && !on ? null : holeSet || holeAuto
    // turned off the top edge the hole leaves the bar and the pill alone, as if there were none
    readonly property bool holeKnown: holeNow !== null && (turn === "normal" || hy + hd / 2 < sh / 2)
    // 0 by 0 when unknown: the bar then has its corners to itself
    readonly property rect hole: holeNow !== null ? Qt.rect(holeNow.x, holeNow.y, holeNow.d, holeNow.d) : Qt.rect(0, 0, 0, 0)

    readonly property var scr: Quickshell.screens.length ? Quickshell.screens[0] : null
    // shortcut: Qt truncates the logical width and gives no true scale here, a hole at the far right sits under 2 pixels off; read the output's size if a table entry shows it
    readonly property real sw: scr ? scr.width : 1
    readonly property real sh: scr ? scr.height : 1
    // the hole turns with the screen; wl_output 90 is counter-clockwise, so the panel's top edge lands on the right
    readonly property string turn: Status.orientation || "normal"
    readonly property bool sideways: turn === "90" || turn === "270"
    readonly property real k: (sideways ? sh : sw) / 1080
    readonly property real hd: hole.width * k
    readonly property real cx: (hole.x + hole.width / 2) * k
    readonly property real cy: (hole.y + hole.width / 2) * k
    readonly property real hx: (turn === "90" ? sw - cy : turn === "270" ? cy : turn === "180" ? sw - cx : cx) - hd / 2
    readonly property real hy: (turn === "90" ? cx : turn === "270" ? sh - cx : turn === "180" ? sh - cy : cy) - hd / 2
    readonly property string side: !holeKnown ? "center" : (hx + hd / 2) / sw < 0.4 ? "left" : (hx + hd / 2) / sw > 0.6 ? "right" : "center"

    // ---- what the bar needs: where the shape stands at its compact size, whatever it is doing now ----
    // a hole below the bar leaves the bar alone
    readonly property bool barActive: on && !Phone.lockOpen && (main !== null || moving) && (!holeKnown || hy < Status.barHeight)
    readonly property real pillStart: barActive ? barS : 0
    readonly property real pillEnd: barActive ? barE : 0

    // ---- sources ----
    property int tick: 0
    readonly property bool needTick: on && !Phone.screenOff && (shown || []).slice(0, 2).some(i => i.clock)
    Timer { interval: 1000; repeat: true; running: root.needTick; onTriggered: root.tick++ }
    function clock(ms) {
        const s = Math.max(0, Math.round(ms / 1000));
        const m = Math.floor(s / 60);
        const two = n => String(n).padStart(2, "0");
        return m >= 60 ? Math.floor(m / 60) + ":" + two(m % 60) + ":" + two(s % 60) : two(m) + ":" + two(s % 60);
    }

    // music: playing, or paused for a little while; gone with its owner
    readonly property var player: {
        if (!on || !allowed("music"))
            return null;
        const all = Mpris.players.values;
        return all.find(p => p.isPlaying) || (all.length ? all[0] : null);
    }
    readonly property bool playing: player !== null && player.isPlaying
    onPlayingChanged: if (!playing) pausedHold.restart(); else pausedHold.stop()
    Timer { id: pausedHold; interval: 30000 }

    // recording: the panel starts it, the pid file says whether it still runs
    property real recStart: 0
    Connections {
        target: Status
        function onRecordingChanged() {
            root.recStart = Date.now();
            root.tick++;
        }
        // later: Status's bindings on s update after this handler
        function onSChanged() { Qt.callLater(root.polled); }
        function onNotifsChanged() { root.notified(); }
        function onRingerChanged() {
            if (root.allowed("ringer"))
                root.event("ringer", "ringer", Status.ringerIcon, Status.ringer === "normal" ? "Ringer on" : Status.ringer === "vibrate" ? "Vibrate" : "Silent", "", 2500, { page: "sound" });
        }
        function onDndChanged() {
            if (root.allowed("ringer"))
                root.event("ringer", "dnd", "dnd", Status.dnd ? "Do not disturb" : "Do not disturb off", Status.dnd ? "DND on" : "DND off", 2500, { page: "sound" });
        }
    }
    Process {
        id: recCheck
        command: ["sh", "-c", 'p=$(cat "$1/quick-record.pid" 2>/dev/null); [ -n "$p" ] && [ "$(cat "/proc/$p/comm" 2>/dev/null)" = wf-recorder ]', "phonecamera", Phone.stateDir]
        onExited: code => {
            // the recorder starts half a second after the tile
            if (code !== 0 && Date.now() - root.recStart > 2500)
                Status.recording = false;
        }
    }
    Timer { interval: 3000; repeat: true; running: Status.recording; onTriggered: recCheck.running = true }

    // timer and stopwatch belong to this shell, the interface only starts them
    property real timerEnd: 0
    property real watchStart: 0
    Timer { id: timerDone; onTriggered: root.timerRang() }
    function timerRang() {
        timerEnd = 0;
        event("timers", "timerdone", "timer", "Timer finished", "Finished", 6000, {});
        Status.alert();
    }
    function startTimer(seconds) {
        timerEnd = Date.now() + seconds * 1000;
        timerDone.interval = seconds * 1000;
        timerDone.restart();
    }
    function cancelTimer() { timerDone.stop(); timerEnd = 0; }

    // what the polled state said last time, a change becomes a short activity
    property var lastS: null
    function polled() {
        const s = Status.s;
        const conns = s.conns || "";
        const now = { charging: Status.charging, bat: Status.battery, vol: s.vol, muted: s.muted, bl: s.bl, bt: s.btname || "",
            vpn: /:(vpn|wireguard)(,|$)/.test(conns) };
        const was = lastS;
        lastS = now;
        // the first reading is how things are, not a change
        if (!was)
            return;
        if (Status.hasBattery) {
            if (now.charging && !was.charging && allowed("charging"))
                event("charging", "charging", "bolt", "Charging", now.bat + "%", 3500, { tone: "green", page: "battery", progress: now.bat / 100 });
            else if (!now.charging && allowed("charging") && [15, 5].some(l => now.bat <= l && was.bat > l))
                event("charging", "lowbat", "battlow", "Low battery", now.bat + "%", 5000, { tone: "red", page: "battery", progress: now.bat / 100 });
        }
        if (allowed("levels") && !Status.panelLoaded) {
            if (was.vol !== undefined && (now.vol !== was.vol || now.muted !== was.muted))
                event("levels", "level", Status.volIcon, "Volume", "", 1800, { progress: Status.muted ? 0 : Status.volume, page: "sound" });
            else if (was.bl !== undefined && now.bl !== was.bl)
                event("levels", "level", "sun", "Brightness", "", 1800, { progress: Status.brightness, page: "display" });
        }
        if (allowed("devices") && now.bt !== "" && now.bt !== was.bt)
            event("devices", "device", "output", now.bt, "On", 3500, { page: "bluetooth" });
        if (allowed("network") && now.vpn !== was.vpn)
            event("network", "vpn", "vpn", now.vpn ? "VPN connected" : "VPN disconnected", now.vpn ? "VPN on" : "VPN off", 3000, { page: "wifi" });
    }

    // the screen unlocking, a screenshot
    Connections {
        target: Phone
        function onLockOpenChanged() {
            if (root.allowed("unlock") && !Phone.lockOpen)
                root.event("unlock", "unlock", "unlock", "", "", 1100, { noExpand: true });
            root.expandedId = "";
        }
        function onFlashOnChanged() {
            if (Phone.flashOn && root.allowed("screenshot"))
                root.event("screenshot", "shot", "shot", "Screenshot saved", "Saved", 2500, { noExpand: true });
        }
        function onOverviewChanged() { root.collapse(); }
        function onPillSeqChanged() { root.collapse(); }
        function onMenuOpenChanged() { root.collapse(); }
    }

    // notifications pop out of the camera; the panel keeps them
    property var lastNotif: null
    function notified() {
        const n = Status.notifs[0] || null;
        const fresh = n !== null && n !== lastNotif;
        lastNotif = n;
        if (!fresh || n.app === "Phone" || !on || !allowed("notifications") || Status.dnd)
            return;
        event("notifications", "notif", n.icon || "bell", n.summary || n.app, "", 4500, { prio: 1, notif: n, sub: n.body, head: n.app, pop: true });
    }
    function dismissPop() {
        const e = events.find(x => x.id === "notif");
        if (e) {
            lastNotif = Status.notifs[1] || null;
            Status.notifs = Status.notifs.filter(n => n !== e.notif);
            endEvent("notif");
        }
    }

    // ---- short activities: their time starts when they show; one that never gets a place is dropped ----
    property var events: []
    function event(group, id, icon, title, tail, ttl, more) {
        if (!on)
            return;
        const e = Object.assign({ group: group, id: id, kind: "event", prio: 9, icon: icon, title: title, tail: tail, ttl: ttl, born: Date.now(), shownAt: 0, buttons: [], lockText: group !== "notifications" }, more);
        events = events.filter(x => x.id !== id).concat([e]);
    }
    function endEvent(id) { events = events.filter(x => x.id !== id); }
    Timer { id: eventTimer; onTriggered: root.pump() }
    onEventsChanged: pump()
    onShownChanged: pump()
    onPostedChanged: pump()
    function pump() {
        const now = Date.now();
        // onEventsChanged can come before shown has been computed at start
        const up = (shown || []).slice(0, 2).map(i => i.id);
        let next = Infinity;
        const keep = [];
        for (const e of events) {
            if (!e.shownAt && up.includes(e.id))
                e.shownAt = now;
            const due = e.shownAt ? e.shownAt + e.ttl : e.born + 8000;
            if (due > now) {
                keep.push(e);
                next = Math.min(next, due);
            }
        }
        const alive = posted.filter(p => !p.expires || p.expires > now);
        for (const p of alive)
            if (p.expires)
                next = Math.min(next, p.expires);
        if (keep.length !== events.length)
            events = keep;
        if (alive.length !== posted.length)
            posted = alive;
        eventTimer.stop();
        if (next !== Infinity) {
            eventTimer.interval = Math.max(20, next - now);
            eventTimer.start();
        }
        if (Phone.lockOpen || !anyPop(up[0]))
            return;
        // an arriving call or notification opens by itself, unless a fullscreen app is on
        if (!fullscreen && autoShown !== popKey(up[0])) {
            autoShown = popKey(up[0]);
            expandedId = up[0];
        }
    }
    property string autoShown: ""
    function popItem(id) { return (items || []).find(i => i.id === id) || null; }
    function anyPop(id) { const i = popItem(id); return i !== null && (i.pop || i.kind === "call" && i.state === "incoming"); }
    function popKey(id) { const i = popItem(id); return id + (i.born || i.state); }
    readonly property bool fullscreen: ToplevelManager.activeToplevel !== null && ToplevelManager.activeToplevel.fullscreen
    onFullscreenChanged: if (fullscreen) collapse()
    // a fullscreen video or game: the pill steps aside, only a call still shows
    readonly property bool fullHidden: fullscreen && !Phone.overview && !Phone.lockOpen && !(main !== null && main.kind === "call")
    property real fullFade: fullHidden ? 0 : 1
    Behavior on fullFade { enabled: Phone.animationsConf !== "off"; NumberAnimation { duration: 200 } }

    // ---- the list, in priority order: call, then recording, timer, music, others ----
    readonly property var items: {
        if (!on)
            return [];
        const now = (tick, Date.now());
        const out = [];
        for (const p of posted)
            if (allowed(kinds[p.kind]))
                out.push(postedItem(p, now));
        for (const e of events)
            out.push(e);
        if (Status.recording && allowed("recording"))
            out.push({ id: "record", group: "recording", kind: "record", prio: 2, icon: "record", tone: "red", head: "Screen recording", title: clock(now - recStart), tail: clock(now - recStart), clock: true, lockText: true,
                buttons: [{ id: "stop", label: "Stop", icon: "stop", tone: "red" }] });
        if (timerEnd > 0)
            out.push({ id: "timer", group: "timers", kind: "timer", prio: 3, icon: "timer", head: "Timer", title: clock(timerEnd - now), tail: clock(timerEnd - now), clock: true, lockText: true,
                buttons: [{ id: "cancel", label: "Cancel", icon: "" }] });
        if (watchStart > 0)
            out.push({ id: "watch", group: "timers", kind: "watch", prio: 4, icon: "stopwatch", head: "Stopwatch", title: clock(now - watchStart), tail: clock(now - watchStart), clock: true, lockText: true,
                buttons: [{ id: "stop", label: "Stop", icon: "" }] });
        if (player && (playing || pausedHold.running || expandedId === "music") && (player.trackTitle || playing))
            out.push({ id: "music", group: "music", kind: "music", prio: 5, icon: "music", art: player.trackArtUrl || "", title: player.trackTitle || player.identity || "", sub: player.trackArtist || "", head: player.identity || "Music", bars: true, lockText: true, buttons: [] });
        const conns = Status.s.conns || "";
        if (/(^|,)Hotspot:/.test(conns) && allowed("network"))
            out.push({ id: "hotspot", group: "network", kind: "state", prio: 10, icon: "hotspot", head: "Hotspot", title: "Hotspot on", page: "wifi", lockText: true, buttons: [] });
        if (Status.s.micuse === "1" && allowed("privacy"))
            out.push({ id: "mic", group: "privacy", kind: "state", prio: 11, icon: "mic", tone: "red", head: "Privacy", title: "Microphone in use", lockText: true, buttons: [] });
        if (Status.s.camuse === "1" && allowed("privacy"))
            out.push({ id: "cam", group: "privacy", kind: "state", prio: 11, icon: "camera", tone: "red", head: "Privacy", title: "Camera in use", lockText: true, buttons: [] });
        if (Status.torchOn && Status.hasTorch && allowed("flashlight"))
            out.push({ id: "torch", group: "flashlight", kind: "torch", prio: 12, icon: "torch", head: "Flashlight", title: "Flashlight on", lockText: true,
                buttons: [{ id: "off", label: "Turn off", icon: "" }] });
        return out.sort((a, b) => a.prio - b.prio);
    }
    // on the lock screen: no words from notifications or from other programs
    function forLock(i) {
        return !Phone.lockOpen || i.lockText ? i : Object.assign({}, i, { title: "", sub: "", tail: "", head: "", buttons: [], art: "", noExpand: true, progress: undefined, icon: i.group === "notifications" ? "bell" : "dot" });
    }
    // the password screens come first
    readonly property bool hidden: Phone.removeEntry !== null || Phone.lockTyped
    property string swapId: ""
    readonly property var shown: {
        if (hidden)
            return [];
        const all = items.map(forLock);
        // a ringing call is never swapped away
        const first = all.length && all[0].kind === "call" && all[0].state === "incoming" ? null : all.find(i => i.id === swapId);
        return first ? [first].concat(all.filter(i => i !== first)) : all;
    }
    readonly property var main: shown.length ? shown[0] : null
    readonly property var bubble: shown.length > 1 ? shown[1] : null
    // content stays while the shape closes around it
    property var lastMain: null
    property var lastBubble: null
    onMainChanged: if (main) lastMain = main
    onBubbleChanged: if (bubble) lastBubble = bubble

    property string expandedId: ""
    readonly property bool open: main !== null && main.id === expandedId && !main.noExpand
    function expand() {
        if (!main || main.noExpand)
            return;
        expandedId = main.id;
        const e = events.find(x => x.id === main.id);
        if (e) {
            e.shownAt = Date.now();
            e.ttl = Math.max(e.ttl, 6000);
            pump();
        }
    }
    function collapse() { expandedId = ""; }
    function swap() {
        if (bubble) {
            collapse();
            swapId = bubble.id;
        }
    }

    function press(item, button) {
        if (item.kind === "record")
            Recorder.stop();
        else if (item.kind === "timer")
            cancelTimer();
        else if (item.kind === "watch")
            watchStart = 0;
        else if (item.kind === "torch")
            Status.toggleTorch();
        else
            tell(item.id, { event: "button", id: item.id, button: button });
    }
    // what a further tap or a hold opens; behind the lock nothing does
    function openApp() {
        const i = main;
        if (!i || Phone.lockOpen)
            return;
        collapse();
        const entry = name => name ? Phone.apps.find(e => e.id.toLowerCase() === name.toLowerCase() || e.name.toLowerCase() === name.toLowerCase()) : null;
        let e = null;
        if (i.kind === "music") {
            e = entry(player && player.desktopEntry) || entry(player && player.identity);
            if (!e && player && player.canRaise)
                player.raise();
        } else if (i.kind === "timer" || i.kind === "watch") {
            e = Phone.apps.find(a => (a.categories || []).includes("Clock")) || null;
        } else if (i.notif) {
            e = entry(i.notif.app);
            if (!e) {
                Status.side = 0;
                Status.settleTo(1);
            }
            endEvent("notif");
        } else if (i.app) {
            e = entry(i.app);
        }
        if (e)
            Phone.launch(e);
        else if (i.page)
            Status.settings(i.page);
        if (i.cid !== undefined)
            tell(i.id, { event: "open", id: i.id });
    }

    // ---- the local interface: one JSON object per line, from any local program, so never trusted ----
    readonly property string sockPath: Quickshell.env("PHONECAMERA_SOCK") || (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/phonegluewc-camera.sock"
    property var posted: []
    property var conns: ({})
    property real lastPollAsked: 0
    property int nextCid: 1
    readonly property var kinds: ({ live: "apps", call: "calls", nav: "nav", transfer: "transfer" })
    readonly property var limits: ({ title: 64, text: 140, tail: 12, head: 24 })
    SocketServer {
        active: root.on
        path: root.sockPath
        handler: Component {
            Socket {
                id: sock
                property int cid: 0
                property string buf: ""
                property int count: 0
                property real second: 0
                Component.onCompleted: {
                    cid = root.nextCid++;
                    root.conns[cid] = sock;
                }
                Component.onDestruction: root.connGone(cid)
                onConnectedChanged: if (!connected) root.connGone(cid)
                // an empty marker hands over each chunk: the size stays limited here, a line parser would buffer without end
                parser: SplitParser {
                    splitMarker: ""
                    onRead: data => {
                        sock.buf += data;
                        let at;
                        while ((at = sock.buf.indexOf("\n")) >= 0 && sock.connected) {
                            const line = sock.buf.slice(0, at);
                            sock.buf = sock.buf.slice(at + 1);
                            const t = Date.now();
                            if (t - sock.second > 1000) {
                                sock.second = t;
                                sock.count = 0;
                            }
                            if (line.length > 4096 || ++sock.count > 30)
                                return root.refuse(sock, "too much");
                            root.received(sock, line);
                        }
                        if (sock.buf.length > 4096)
                            root.refuse(sock, "too much");
                    }
                }
            }
        }
    }
    function connGone(cid) {
        if (conns[cid] === undefined)
            return;
        delete conns[cid];
        posted = posted.filter(p => p.cid !== cid);
    }
    function refuse(sock, why) {
        sock.write(JSON.stringify({ error: why }) + "\n");
        sock.flush();
        sock.connected = false;
    }
    function tell(id, msg) {
        const p = posted.find(x => x.id === id);
        const s = p && conns[p.cid];
        if (s) {
            s.write(JSON.stringify(msg) + "\n");
            s.flush();
        }
    }
    // no control or direction marks: they could dress one thing up as another
    function plain(v) { return v.replace(/[\u0000-\u001f\u007f‎‏‪-‮⁦-⁩]/g, " ").trim(); }
    function checked(m, old) {
        const out = Object.assign({}, old);
        for (const k in limits) {
            if (m[k] === undefined)
                continue;
            if (typeof m[k] !== "string" || m[k].length > limits[k])
                return "bad " + k;
            out[k] = plain(m[k]);
        }
        if (m.kind !== undefined && !Object.prototype.hasOwnProperty.call(kinds, m.kind))
            return "bad kind";
        if (m.kind !== undefined)
            out.kind = m.kind;
        // a name to look up, never a path
        if (m.icon !== undefined && !(typeof m.icon === "string" && /^[A-Za-z0-9_.+-]{1,64}$/.test(m.icon)))
            return "bad icon";
        if (m.icon !== undefined)
            out.icon = m.icon;
        if (m.app !== undefined && !(typeof m.app === "string" && /^[A-Za-z0-9_.+ -]{1,64}$/.test(m.app)))
            return "bad app";
        if (m.app !== undefined)
            out.app = m.app;
        if (m.progress !== undefined && !(typeof m.progress === "number" && m.progress >= 0 && m.progress <= 1))
            return "bad progress";
        if (m.progress !== undefined)
            out.progress = m.progress;
        if (m.ttl !== undefined && !(typeof m.ttl === "number" && m.ttl > 0 && m.ttl <= 86400))
            return "bad ttl";
        if (m.ttl !== undefined)
            out.expires = Date.now() + m.ttl * 1000;
        if (m.elapsed === true && !out.since)
            out.since = Date.now();
        if (m.state !== undefined && !["incoming", "active"].includes(m.state))
            return "bad state";
        if (m.state === "active" && out.state !== "active")
            out.since = Date.now();
        if (m.state !== undefined)
            out.state = m.state;
        out.muted = m.muted === undefined ? !!out.muted : m.muted === true;
        out.speaker = m.speaker === undefined ? !!out.speaker : m.speaker === true;
        if (m.buttons !== undefined) {
            if (!Array.isArray(m.buttons) || m.buttons.length > 3)
                return "bad buttons";
            const list = [];
            for (const b of m.buttons) {
                if (!b || typeof b.id !== "string" || !/^[A-Za-z0-9_-]{1,24}$/.test(b.id) || typeof b.label !== "string" || b.label.length > 16)
                    return "bad buttons";
                list.push({ id: b.id, label: plain(b.label), icon: "" });
            }
            out.buttons = list;
        }
        return out;
    }
    function received(sock, line) {
        let m = null;
        try {
            m = JSON.parse(line);
        } catch (e) {
        }
        if (m === null || typeof m !== "object")
            return refuse(sock, "not json");
        const why = act(sock, m);
        if (why)
            return refuse(sock, why);
        sock.write(JSON.stringify({ ok: m.op }) + "\n");
        sock.flush();
    }
    function act(sock, m) {
        if (m.op === "timer") {
            if (!(typeof m.seconds === "number" && m.seconds > 0 && m.seconds <= 86400))
                return "bad seconds";
            if (allowed("timers"))
                startTimer(m.seconds);
            return "";
        }
        if (m.op === "stopwatch") {
            if (allowed("timers"))
                watchStart = Date.now();
            return "";
        }
        if (m.op === "cancel") {
            if (m.what === "timer")
                cancelTimer();
            else
                watchStart = 0;
            return "";
        }
        // charging and the rest change without telling anyone: a program that knows may ask for a fresh look
        if (m.op === "poll") {
            if (Date.now() - lastPollAsked > 1000) {
                lastPollAsked = Date.now();
                Status.refresh();
            }
            return "";
        }
        if (typeof m.id !== "string" || !/^[A-Za-z0-9_.-]{1,32}$/.test(m.id))
            return "bad id";
        const old = posted.find(p => p.id === m.id);
        if (m.op === "end") {
            posted = posted.filter(p => p !== old);
            return "";
        }
        if (m.op !== "post" && !(m.op === "update" && old))
            return "bad op";
        if (!old && (posted.filter(p => p.cid === sock.cid).length >= 4 || posted.length >= 16))
            return "too many";
        const next = checked(m, old || { id: m.id, cid: sock.cid, kind: "live", icon: "", title: "", text: "", tail: "", head: "", buttons: [], state: "", born: Date.now() });
        if (typeof next === "string")
            return next;
        posted = posted.filter(p => p !== old).concat([next]);
        return "";
    }
    function postedItem(p, now) {
        const base = Object.assign({}, p, { group: kinds[p.kind], sub: p.text, clock: !!p.since, lockText: false });
        if (p.kind === "call") {
            const live = p.state === "active";
            return Object.assign(base, { prio: 0, icon: "phone", tone: "green", lockText: true, head: live ? "Call" : "Incoming call", tail: live ? clock(now - p.since) : "", title: p.title,
                clock: live, sub: "" });
        }
        return Object.assign(base, { prio: p.kind === "nav" ? 6 : p.kind === "transfer" ? 7 : 8,
            tail: p.since ? clock(now - p.since) : p.tail || (p.progress !== undefined ? Math.round(p.progress * 100) + "%" : "") });
    }

    // ---- the shape: every edge is a spring, so a new target always starts from where things are ----
    readonly property real margin: 4
    readonly property real pillH: holeKnown ? hd + 2 * margin : 28
    readonly property real pillT: holeKnown ? Math.max(0, hy - margin) : 6
    readonly property real holeL: holeKnown ? hx : sw / 2
    readonly property real holeR: holeKnown ? hx + hd : sw / 2
    readonly property real bubbleRoom: bubble && bubbleFits ? pillH + 6 : 0
    // a running time is never cut: beside the centre hole the bubble tucks into the pill first
    readonly property bool bubbleFits: !bubble || side !== "center" || hd / 2 + margin + padIn + Math.max(leadW, keepW) + padEnd + pillH + 6 <= iconsLeft - 6 - (holeL + holeR) / 2
    // what the compact content measures: filled in by DynCompact
    property real rowW: 0
    property real leadW: 0
    property real tailW: 0
    property real keepW: 0
    readonly property real padIn: 7
    readonly property real padEnd: 10
    readonly property real compactL: {
        if (side === "left")
            return holeL - margin;
        if (side === "right")
            return Math.max(sw * 0.44 + bubbleRoom, holeL - margin - padIn - rowW - padEnd);
        return (holeL + holeR) / 2 - centerHalf;
    }
    readonly property real compactR: {
        if (side === "left")
            return Math.min(sw * 0.62 - bubbleRoom, holeR + margin + padIn + rowW + padEnd);
        if (side === "right")
            return holeR + margin;
        return (holeL + holeR) / 2 + centerHalf;
    }
    // the bar reports where its icons start: the pill stops short of them, the lead always fits
    property real iconsLeft: sw * 0.75
    readonly property real centerHalf: {
        const beside = hd / 2 + margin + padIn;
        return Math.max(beside + Math.max(leadW, keepW) + padEnd, Math.min(beside + Math.max(leadW, tailW) + padEnd, iconsLeft - 6 - (holeL + holeR) / 2 - bubbleRoom));
    }
    // the expanded size: the strip beside the hole, then what DynExpanded measures
    property real bodyH: 120
    readonly property real openT: holeKnown ? Math.min(8, hy - margin) : 8
    readonly property real headH: holeKnown ? hy + hd + margin - openT : 36
    readonly property real openH: headH + bodyH
    property real dragUp: 0
    property real swipeX: 0
    property bool held: false
    readonly property real windowH: Math.ceil(Math.max(320, hy + hd + margin + 270))

    readonly property bool idle: main === null
    readonly property var targets: {
        const o = open;
        const l = idle ? holeL : o ? 8 : compactL;
        const r = idle ? holeR : o ? sw - 8 : compactR;
        const t = idle ? (holeKnown ? hy : pillT + pillH / 2) : o ? openT : pillT;
        const b = idle ? (holeKnown ? hy + hd : pillT + pillH / 2) : o ? Math.max(openT + pillH, openT + openH + dragUp) : pillT + pillH;
        const start = side === "right" ? compactL - bubbleRoom : compactL;
        const end = side === "right" ? compactR : compactR + bubbleRoom;
        const k = o ? swipeX : 0;
        return {
            L: l + k, R: r + k, T: t, B: b,
            // the bubble rests beside the pill, and inside it while there is none or the shape is open
            G: !bubble || o || !bubbleFits ? 0 : 1,
            S: idle ? (side === "left" ? 0 : holeL - 6 + 8) : start,
            E: idle ? (side === "right" ? sw : holeR + 6 - 8) : end
        };
    }
    readonly property var names: ["L", "R", "T", "B", "G", "S", "E"]
    property real pL: sw / 2
    property real pR: sw / 2
    property real pT: 0
    property real pB: 0
    property real pG: 0
    property real pS: 0
    property real pE: 0
    readonly property real barS: pS
    readonly property real barE: pE
    readonly property real shapeH: pB - pT
    // 0 at the pill, 1 fully open; the corners follow it
    readonly property real openness: Math.max(0, Math.min(1, (shapeH - pillH) / Math.max(1, openH - pillH)))
    readonly property real radius: Math.min(shapeH / 2, (pillH / 2) * (1 - openness) + 28 * openness)
    property var velocity: ({ L: 0, R: 0, T: 0, B: 0, G: 0, S: 0, E: 0 })
    property bool moving: false
    // later: this starts the window, whose measurements feed back into targets, and a binding must not change itself
    onTargetsChanged: Qt.callLater(retarget)
    function retarget() {
        if (!placed || !anim) {
            placed = true;
            for (const n of names)
                root["p" + n] = targets[n];
        } else {
            moving = true;
        }
    }
    property bool placed: false
    FrameAnimation {
        running: root.moving
        onTriggered: root.step(Math.min(frameTime, 1 / 30))
    }
    readonly property real stiffness: 380
    function step(dt) {
        // a little past the target when opening, never when closing
        const c = 2 * Math.sqrt(stiffness) * (open ? 0.78 : 1);
        let rest = true;
        const v = velocity;
        const n0 = Math.ceil(dt * 240);
        const h = dt / n0;
        for (const n of names) {
            const to = targets[n];
            const k = n === "G" ? stiffness * 0.4 : stiffness;
            const d = n === "G" ? 2 * Math.sqrt(k) * 0.8 : c;
            let x = root["p" + n];
            let u = v[n];
            for (let i = 0; i < n0; i++) {
                u += (k * (to - x) - d * u) * h;
                x += u * h;
            }
            if (Math.abs(to - x) < 0.05 && Math.abs(u) < 1) {
                x = to;
                u = 0;
            } else {
                rest = false;
            }
            v[n] = u;
            root["p" + n] = x;
        }
        if (rest)
            moving = false;
    }
    readonly property bool windowWanted: on && !Phone.lockOpen && (main !== null || moving || fake || held)
    // the bars only move when someone can see them
    readonly property bool barsRun: playing && !Phone.screenOff && Status.pull === 0
}
