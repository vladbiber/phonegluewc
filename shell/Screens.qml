pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// the saved home and lock screens; a screen's wallpaper here counts only while it is not active,
// the active one's lives in phone.conf and login.conf where the settings app writes it
Singleton {
    id: root

    readonly property int cols: 4
    readonly property int rowH: 44
    readonly property int pad: 28
    // a type's sizes in cells, first is what a new one gets
    readonly property var sizes: ({
        clock: [[4, 2], [3, 2], [2, 1], [2, 2], [2, 4]],
        date: [[4, 1], [2, 1], [2, 4], [1, 2]],
        battery: [[2, 1], [1, 1], [1, 2], [2, 2]],
        music: [[4, 2], [2, 4], [2, 2]],
        note: [[2, 2], [4, 2], [4, 4]],
        app: [[1, 2]],
        analog: [[2, 4], [1, 2]],
        world: [[2, 4], [2, 2]],
        storage: [[2, 2], [1, 2]],
        wifi: [[2, 2], [1, 2]],
        bluetooth: [[2, 2], [1, 2]],
        torch: [[2, 2], [1, 2]],
        airplane: [[2, 2], [1, 2]],
        rotate: [[2, 2], [1, 2]],
        dark: [[2, 2], [1, 2]],
        timer: [[2, 2], [1, 2]],
        stopwatch: [[2, 2], [1, 2]],
        weather: [[2, 4], [4, 2], [2, 2], [1, 2]],
        photo: [[2, 4], [4, 4], [1, 2]]
    })
    // nothing personal behind the lock, whatever the file says; the lock clock already shows time and date,
    // and toggles that cut the radios stay off it so a found phone keeps its network
    readonly property var lockTypes: ["analog", "world", "battery", "weather", "timer", "stopwatch", "torch"]
    readonly property int noteMax: 200

    // widget looks: each widget may name one, the rest follow the default kept in phone.conf
    readonly property var styles: ["nothing-dark", "nothing-light", "apple"]
    readonly property string widgetStyle: styles.includes(Phone.conf.widget_style) ? Phone.conf.widget_style : "nothing-dark"
    function setWidgetStyle(v) { if (styles.includes(v)) Phone.setConf("widget_style", v); }
    function styleOf(w) { return w && styles.includes(w.style) ? w.style : widgetStyle; }
    // the bare dot clock and date line of the old layouts draw on the wallpaper, every other size on a tile
    function bare(w) { return (w.type === "clock" && !(w.w === 2 && w.h >= 2)) || (w.type === "date" && w.h === 1); }
    // the per-type settings a widget may carry
    function cleanExtra(w, out) {
        if (styles.includes(w.style))
            out.style = w.style;
        if (w.type === "weather" && typeof w.city === "string")
            out.city = w.city.replace(/[\x00-\x1f]/g, "").slice(0, 60);
        if (w.type === "world")
            out.offset = Math.max(-720, Math.min(840, Math.round((Number(w.offset) || 0) / 15) * 15));
        if (w.type === "timer")
            out.minutes = Math.max(1, Math.min(600, Number(w.minutes) | 0 || 5));
        if (w.type === "photo" && typeof w.file === "string" && /^\/[^\x00-\x1f]*$/.test(w.file))
            out.file = w.file;
        return out;
    }

    property bool editing: false
    property int noteRequest: -1
    // an open while it is still closing turns it back
    signal reopened()
    function openEditor() { if (editing) reopened(); editing = true; }

    function top(kind) { return kind === "lock" ? 72 : 92; }
    function rows(kind, height) { return Math.max(3, Math.floor((height - top(kind) - (kind === "lock" ? 180 : 96)) / rowH)); }

    readonly property string path: Phone.configDir + "/screens.json"
    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
    }
    FileView {
        id: login
        path: Phone.configDir + "/login.conf"
        blockLoading: true
        printErrors: false
    }

    function newScreen() {
        return { wallpaper: "", widgets: [{ type: "clock", col: 0, row: 0, w: 4, h: 2 }, { type: "date", col: 0, row: 2, w: 4, h: 1 }] };
    }
    function cleanWidget(kind, w) {
        if (!w || typeof w !== "object" || !sizes.hasOwnProperty(w.type) || (kind === "lock" && !lockTypes.includes(w.type)))
            return null;
        const size = sizes[w.type].find(s => s[0] === w.w && s[1] === w.h) || sizes[w.type][0];
        const out = { type: w.type, col: Math.max(0, Math.min(cols - size[0], w.col | 0)), row: Math.max(0, w.row | 0), w: size[0], h: size[1] };
        if (w.type === "note")
            out.text = String(w.text || "").slice(0, noteMax);
        if (w.type === "app") {
            if (typeof w.app !== "string" || !w.app)
                return null;
            out.app = w.app;
        }
        return cleanExtra(w, out);
    }
    // the screens form a grid: x is the page a swipe on home reaches, y a variant of that page picked in the editor;
    // the list stays flat and sorted by x then y, so an index still names one screen; a file without x and y migrates as x = index
    function cleanKind(kind, k) {
        const raw = k && Array.isArray(k.screens) ? k.screens.filter(s => s && typeof s === "object") : [];
        if (raw.length === 0)
            return { active: 0, picks: [0], screens: [Object.assign(newScreen(), { x: 0, y: 0 })] };
        const at = Math.max(0, Math.min(raw.length - 1, (k.active | 0)));
        const ok = v => Number.isInteger(v) && v >= 0;
        const cells = raw.map((s, i) => ({ i: i, x: ok(s.x) ? s.x : i, y: ok(s.y) ? s.y : 0, s: s }));
        cells.sort((a, b) => a.x - b.x || a.y - b.y || a.i - b.i);
        let col = -1, last = -1, row = 0;
        for (const c of cells) {
            if (c.x !== last) { col++; last = c.x; row = 0; }
            c.x = col;
            c.y = row++;
        }
        const old = k && Array.isArray(k.picks) ? k.picks : [];
        const picks = [];
        for (const c of cells)
            picks[c.x] = Math.min(c.y, Math.max(0, old[c.x] | 0));
        const active = cells.findIndex(c => c.i === at);
        picks[cells[active].x] = cells[active].y;
        return {
            active: active,
            picks: picks,
            screens: cells.map(c => ({
                x: c.x,
                y: c.y,
                // these end up in the conf files, one line each
                wallpaper: typeof c.s.wallpaper === "string" && /^\/[^\x00-\x1f]*$/.test(c.s.wallpaper) ? c.s.wallpaper : "",
                widgets: Array.isArray(c.s.widgets) ? c.s.widgets.map(w => cleanWidget(kind, w)).filter(w => w) : []
            }))
        };
    }
    readonly property var all: {
        let raw = null;
        try {
            raw = JSON.parse(file.text());
        } catch (e) {
            // missing or corrupt: the defaults, and the file stays as it is until something is changed
        }
        return { home: cleanKind("home", raw && raw.home), lock: cleanKind("lock", raw && raw.lock) };
    }
    function copy() { return JSON.parse(JSON.stringify(all)); }
    function write(next) { file.setText(JSON.stringify(Object.assign({ version: 1 }, next)) + "\n"); }

    function list(kind) { return all[kind].screens; }
    function active(kind) { return all[kind].active; }
    function screenOf(kind, i) {
        const k = all[kind];
        return k.screens[i < 0 ? k.active : i] || newScreen();
    }

    function confWallpaper(kind) { return kind === "lock" ? Auth.config.wallpaper || "" : Phone.wallpaper; }
    function setConfWallpaper(kind, v) {
        if (kind !== "lock") {
            Phone.setConf("wallpaper", v);
            return;
        }
        const lines = login.text().split("\n").filter(l => l.trim() !== "" && l.split("=")[0].trim() !== "wallpaper");
        lines.push("wallpaper=" + v);
        login.setText(lines.join("\n") + "\n");
    }
    function wallpaperOf(kind, i) { return i === active(kind) ? confWallpaper(kind) : (list(kind)[i] || {}).wallpaper || ""; }
    function setWallpaper(kind, i, v) {
        const next = copy();
        next[kind].screens[i].wallpaper = v;
        write(next);
        if (i === active(kind))
            setConfWallpaper(kind, v);
    }

    function columns(kind) { return all[kind].picks.length; }
    function variants(kind, x) { return list(kind).filter(s => s.x === x).length; }
    function indexAt(kind, x, y) { return list(kind).findIndex(s => s.x === x && s.y === y); }
    function picked(kind, x) { return indexAt(kind, x, all[kind].picks[x] | 0); }
    // a swipe on home: the next page as its variant was last picked, nothing past either end
    function step(kind, dx) {
        const x = screenOf(kind, -1).x + dx;
        if (x < 0 || x >= columns(kind))
            return false;
        activate(kind, picked(kind, x));
        return true;
    }

    // the screen being left keeps the wallpaper it has now
    function activate(kind, i) {
        const next = copy();
        const k = next[kind];
        if (i === k.active || !k.screens[i])
            return;
        k.screens[k.active].wallpaper = confWallpaper(kind);
        k.active = i;
        k.picks[k.screens[i].x] = k.screens[i].y;
        const v = k.screens[i].wallpaper;
        write(next);
        setConfWallpaper(kind, v);
    }
    // a new page after the last one, or a new variant at the bottom of page x; its index once written
    function add(kind, x) {
        const next = copy();
        const k = next[kind];
        const col = x === undefined ? k.picks.length : x;
        const at = k.screens.filter(s => s.x <= col).length;
        k.screens.splice(at, 0, Object.assign(newScreen(), { x: col, y: k.screens.filter(s => s.x === col).length }));
        if (at <= k.active)
            k.active++;
        write(next);
        return at;
    }
    function remove(kind, i) {
        const next = copy();
        const k = next[kind];
        const gone = k.screens[i];
        if (k.screens.length < 2 || !gone)
            return;
        const wasActive = i === k.active;
        k.screens.splice(i, 1);
        if (i < k.active)
            k.active--;
        const alone = !k.screens.some(s => s.x === gone.x);
        if (alone)
            k.picks.splice(gone.x, 1);
        k.screens.forEach(s => {
            if (alone && s.x > gone.x)
                s.x--;
            else if (!alone && s.x === gone.x && s.y > gone.y)
                s.y--;
        });
        // the active one gone: the same page's variant above it, or the page before
        if (wasActive) {
            const x = alone ? Math.max(0, gone.x - 1) : gone.x;
            const y = alone ? Math.min(k.picks[x] | 0, k.screens.filter(s => s.x === x).length - 1) : Math.max(0, gone.y - 1);
            k.active = k.screens.findIndex(s => s.x === x && s.y === y);
            k.picks[x] = y;
        }
        write(next);
        if (wasActive)
            setConfWallpaper(kind, k.screens[k.active].wallpaper);
    }
    function setWidgets(kind, i, widgets) {
        const next = copy();
        next[kind].screens[i].widgets = widgets;
        write(next);
    }

    // an app's icon on the home screen in view: the menu's and the tray's hold popup adds and removes it
    function hasApp(id) { return screenOf("home", -1).widgets.some(w => w.type === "app" && w.app === id); }
    function setApp(id, on) {
        const i = active("home");
        const list = JSON.parse(JSON.stringify(screenOf("home", i).widgets)).filter(w => !(w.type === "app" && w.app === id));
        if (on) {
            const scr = Quickshell.screens[0];
            const size = sizes.app[0];
            const spot = freeSpot(list, size[0], size[1], rows("home", scr ? Math.max(scr.width, scr.height) : 873));
            if (!spot)
                return false;
            list.push({ type: "app", app: id, col: spot.col, row: spot.row, w: size[0], h: size[1] });
        }
        setWidgets("home", i, list);
        return true;
    }

    function overlaps(widgets, skip, c, r, w, h) {
        return widgets.some((o, n) => n !== skip && c < o.col + o.w && o.col < c + w && r < o.row + o.h && o.row < r + h);
    }
    function freeSpot(widgets, w, h, maxRows) {
        for (let r = 0; r + h <= maxRows; r++)
            for (let c = 0; c + w <= cols; c++)
                if (!overlaps(widgets, -1, c, r, w, h))
                    return { col: c, row: r };
        return null;
    }
    function lowest(kind) {
        return screenOf(kind, -1).widgets.reduce((n, w) => Math.max(n, w.row + w.h), 0);
    }
}
