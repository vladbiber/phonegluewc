import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray as Tray
import QtQuick

// What runs: windows from foreign toplevel, background apps from the tray. Lives with the panel.
Scope {
    id: root

    readonly property string ctl: Quickshell.shellDir + "/appctl.sh"
    readonly property var system: ["phonegluewc", "phonekbd", "phonetext", "quickshell", "qs"]
    readonly property int graceMs: 3000

    // true: what runs without a window (tray, apps whose windows closed, known daemons, VPNs) for the overview pill
    property bool background: false
    readonly property string title: background ? "Tray apps" : "Active apps"

    // verified pids: which app id or tray id has which, and what scan says to hide; b, d, v only in background
    property var scan: ({ w: {}, t: {}, hide: {}, b: [], d: [], v: [] })
    // each list keeps its own closing entries in the shared Status.closing
    function mine(key) { return key.startsWith("bg:") === background; }

    function isSystem(id) { return system.includes(id.toLowerCase()) || id !== "" && scan.hide[id] === true; }
    // an Android window's process is the whole container, and a pid several apps share is not one app's to kill
    function ownPids(id) {
        if (id.toLowerCase().startsWith("waydroid"))
            return [];
        const list = scan.w[id] || [];
        return list.filter(p => !Object.keys(scan.w).some(o => o !== id && scan.w[o].some(q => q.pid === p.pid)));
    }

    readonly property var rows: background ? backgroundRows() : windowRows()
    function backgroundRows() {
        const out = [];
        const add = (key, name, kind, pids) => {
            const r = { key: key, appId: "", name: name, icon: "", trayIcon: "", windows: [], tray: [], pids: pids, state: "idle", kind: kind };
            out.push(r);
            return r;
        };
        for (const item of Tray.SystemTray.items.values) {
            const id = item.id || "";
            if (isSystem(id))
                continue;
            const r = add("bg:t:" + id, item.title || id, "Tray", (scan.t[id] || []).slice());
            r.tray.push(item);
            r.trayIcon = item.icon;
        }
        const listed = p => out.some(o => o.pids.some(q => q.pid === p.pid));
        const windowed = p => Object.keys(scan.w).some(id => scan.w[id].some(q => q.pid === p.pid));
        for (const p of scan.b) {
            if (listed(p) || windowed(p))
                continue;
            const id = Status.launched[p.pid + ":" + p.start] || "";
            const e = id ? DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id) : null;
            Object.assign(add("bg:p:" + p.pid, e ? e.name : id, "Running in background", [p]), { appId: id, icon: e ? e.icon : "" });
        }
        for (const d of scan.d)
            if (!listed(d) && !windowed(d))
                add("bg:p:" + d.pid, d.name, "Running in background", [{ pid: d.pid, start: d.start }]);
        for (const v of scan.v)
            add("bg:v:" + v, v, "VPN", []).vpn = true;
        for (const key in Status.closing) {
            if (!mine(key))
                continue;
            const c = Status.closing[key];
            const r = out.find(o => o.key === key) || add(key, c.name, c.kind || "Running in background", c.pids);
            r.state = c.force ? "force" : "closing";
        }
        return out;
    }
    function windowRows() {
        const out = [];
        const add = (key, id) => {
            const r = { key: key, appId: id, name: "", icon: "", trayIcon: "", windows: [], tray: [], pids: [], state: "idle" };
            out.push(r);
            return r;
        };
        for (const t of ToplevelManager.toplevels.values) {
            const id = t.appId || "";
            if (isSystem(id))
                continue;
            const r = id && out.find(o => o.appId === id) || add(id ? "app:" + id : "window:" + out.length, id);
            r.windows.push(t);
            if (!r.name) {
                const e = id ? DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id) : null;
                r.name = e ? e.name : id || t.title || "Window";
                r.icon = e ? e.icon : "";
                r.pids = id ? ownPids(id) : [];
            }
        }
        for (const item of Tray.SystemTray.items.values) {
            const id = item.id || "";
            if (isSystem(id))
                continue;
            const known = scan.t[id] || [];
            // the same process, or else the same id; a title never decides
            const r = out.find(o => o.pids.some(p => known.some(k => k.pid === p.pid)))
                || out.find(o => id && o.appId.toLowerCase() === id.toLowerCase())
                || out.find(o => o.key === "tray:" + id)
                || add("tray:" + id, "");
            r.tray.push(item);
            r.trayIcon = item.icon;
            if (!r.name)
                r.name = item.title || id;
            if (!r.appId.toLowerCase().startsWith("waydroid"))
                for (const k of known)
                    if (!r.pids.some(p => p.pid === k.pid))
                        r.pids.push(k);
        }
        // closed but not gone yet: stays listed until it exits or is force stopped
        for (const key in Status.closing) {
            if (!mine(key))
                continue;
            const c = Status.closing[key];
            const r = out.find(o => o.key === key)
                || out.find(o => o.pids.some(p => c.pids.some(q => q.pid === p.pid)))
                || Object.assign(add(key, ""), { name: c.name, icon: c.icon });
            r.key = key;
            r.state = c.force ? "force" : "closing";
        }
        return out;
    }
    readonly property int count: rows.length

    function canClose(r) { return r.vpn || r.windows.length > 0 || r.tray.some(i => i.hasMenu) || r.pids.length > 0; }

    function activate(r) {
        if (r.windows.length === 0)
            return;
        r.windows[r.windows.length - 1].activate();
        Status.close();
    }
    function close(r) {
        if (r.vpn) {
            Quickshell.execDetached(["nmcli", "connection", "down", "id", r.name]);
            return;
        }
        const next = Object.assign({}, Status.closing);
        next[r.key] = { since: Date.now(), pids: r.pids.slice(), name: r.name, icon: r.icon, kind: r.kind, force: false };
        Status.closing = next;
        if (r.windows.length > 0) {
            for (const w of r.windows)
                w.close();
        } else if (r.tray.some(i => i.hasMenu) && !(background && r.pids.length > 0)) {
            Status.askToQuit(r.tray.find(i => i.hasMenu), r.pids.slice());
        } else {
            term(r.pids);
        }
    }
    function term(pids) { send("TERM", pids); }
    function force(r) {
        const c = Status.closing[r.key];
        if (c && c.force)
            send("KILL", c.pids);
    }
    function send(sig, pids) { Status.sendSignal(sig, pids); }

    // ---- verified pids, read again only when the lists change ----
    Process {
        id: scanner
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root.lastScan)
                    return;
                root.lastScan = text;
                const o = { w: {}, t: {}, hide: {}, b: [], d: [], v: [] };
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "hide") {
                        o.hide[f[1]] = true;
                    } else if (f[0] === "w" || f[0] === "t") {
                        const list = o[f[0]][f[1]] = o[f[0]][f[1]] || [];
                        if (f[2])
                            list.push({ pid: f[2], start: f[3] });
                    } else if (f[0] === "b") {
                        o.b.push({ pid: f[1], start: f[2] });
                    } else if (f[0] === "d") {
                        o.d.push({ name: f[1], pid: f[2], start: f[3] });
                    } else if (f[0] === "v") {
                        o.v.push(f[1]);
                    }
                }
                root.scan = o;
                // forget the processes asked about that are gone
                const gone = scanner.asked.filter(a => !o.b.some(p => p.pid + ":" + p.start === a));
                if (gone.length > 0) {
                    const next = Object.assign({}, Status.launched);
                    for (const a of gone)
                        delete next[a];
                    Status.launched = next;
                }
            }
        }
        property var asked: []
        onExited: if (root.again) rescan.restart()
    }
    property string lastScan: ""
    property bool again: false
    Timer {
        id: rescan
        interval: 60
        onTriggered: {
            root.again = scanner.running;
            if (scanner.running)
                return;
            scanner.asked = root.background ? Object.keys(Status.launched) : [];
            scanner.command = ["sh", root.ctl, "scan", String(Quickshell.processId), Phone.stateDir + "/windows"]
                .concat(root.background ? ["bg"].concat(scanner.asked) : []);
            scanner.running = true;
        }
    }
    // daemons and VPNs come and go without a window or tray event: look again while the list or the pill shows
    Timer {
        running: root.background
        repeat: true
        interval: 3000
        onTriggered: rescan.restart()
    }
    onBackgroundChanged: rescan.restart()
    FileView {
        path: Phone.stateDir + "/windows"
        watchChanges: true
        printErrors: false
        onFileChanged: rescan.restart()
    }
    readonly property int windowCount: ToplevelManager.toplevels.values.length
    onWindowCountChanged: rescan.restart()
    readonly property int trayCount: Tray.SystemTray.items.values.length
    onTrayCountChanged: rescan.restart()
    Component.onCompleted: rescan.restart()

    // ---- after a close: gone, or Force stop once the grace is over; only runs while something is closing ----
    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                const alive = text.split("\n");
                const next = {};
                const now = Date.now();
                const dead = [];
                for (const key in Status.closing) {
                    const c = Status.closing[key];
                    if (!root.mine(key)) {
                        next[key] = c;
                        continue;
                    }
                    const live = c.pids.filter(p => alive.includes(p.pid + ":" + p.start));
                    const over = now - c.since >= root.graceMs;
                    for (const p of c.pids)
                        if (!live.includes(p))
                            dead.push(p.pid);
                    if (live.length > 0)
                        next[key] = Object.assign({}, c, { pids: live, force: over });
                    else if (!over && root.rows.some(r => r.key === key && r.windows.length > 0))
                        next[key] = c;
                }
                // a stopped background process leaves now, not at the next scan, so the rows under the finger stay put
                if (root.background && dead.length > 0) {
                    const keep = p => !dead.includes(p.pid);
                    root.scan = Object.assign({}, root.scan, { b: root.scan.b.filter(keep), d: root.scan.d.filter(keep) });
                    rescan.restart();
                }
                // the list rebuilds on a new value: a tick that changes nothing must not eat a finger on Force stop
                if (JSON.stringify(next) !== JSON.stringify(Status.closing))
                    Status.closing = next;
            }
        }
    }
    Timer {
        running: Object.keys(Status.closing).length > 0
        repeat: true
        interval: 500
        onTriggered: {
            if (checker.running)
                return;
            let all = [];
            for (const key in Status.closing)
                all = all.concat(Status.closing[key].pids.map(p => p.pid + ":" + p.start));
            checker.command = ["sh", root.ctl, "alive"].concat(all);
            checker.running = true;
        }
    }
}
