pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    readonly property color black: "#000000"
    readonly property color white: "#f5f5f5"
    readonly property color grey: "#8c8c8c"
    readonly property color surface: "#171717"
    // black..surface stay as they are for what sits over the wallpaper; sheets use these, which follow the theme
    readonly property bool light: conf.theme === "light"
    // 0 dark, 1 light; it slides so every mixed colour crossfades, or jumps with animations off
    property real lit: light ? 1 : 0
    Behavior on lit { enabled: root.animationsConf !== "off"; NumberAnimation { duration: 200 } }
    function mix(dark, lightColor) {
        const a = Qt.color(dark), b = Qt.color(lightColor), k = lit;
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k);
    }
    readonly property color bg: mix("#000000", "#f2f2f2")
    readonly property color fg: mix("#f5f5f5", "#000000")
    readonly property color dim: mix("#8c8c8c", "#666666")
    // secondary text over the frosted sheets: about 3:1 on any wallpaper
    readonly property color glassDim: wallpaper === "" ? dim : light ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(1, 1, 1, 0.75)
    readonly property color card: mix("#171717", "#ffffff")
    readonly property color line: mix("#262626", "#dddddd")
    // fills over the compositor's blur on the pull down sheet; solid with no wallpaper to blur
    readonly property color frost: wallpaper === "" ? mix("#262626", "#ffffff") : light ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.08)
    readonly property color frostLine: wallpaper === "" ? mix("#2a2a2a", "#e2e2e2") : light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08)
    // apps follow the same switch
    onLightChanged: Quickshell.execDetached(["sh", "-c", 'command -v gsettings >/dev/null && gsettings set org.gnome.desktop.interface color-scheme "$1"', "sh", light ? "prefer-light" : "prefer-dark"])
    function setTheme(on) { setConf("theme", on ? "light" : "dark"); }
    readonly property string accentSaved: /^#[0-9a-fA-F]{6}$/.test(conf.accent || "") ? conf.accent.toLowerCase() : "#d71921"
    // a white accent vanishes on a light sheet, it turns black there
    readonly property color accent: light && accentSaved === "#f5f5f5" ? "#111111" : accentSaved
    // not onAccent: Qt 6.10 reads that name as a signal handler and the binding never runs
    readonly property color inkOnAccent: 0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b > 0.55 ? "#000000" : "#ffffff"
    // unset means the shipped default; an empty value is the Black choice
    readonly property string wallpaper: conf.wallpaper ?? Quickshell.shellDir.replace(/\/[^/]*\/?$/, "") + "/wallpapers/06-ribbons-dark.jpg"
    readonly property string font: "Noto Sans"

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/phonegluewc"
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME")
        || Quickshell.env("HOME") + "/.config") + "/phonegluewc"

    // what the settings app wrote, it replaces the file in one rename
    readonly property var conf: {
        const out = {};
        for (const line of confFile.text().split("\n")) {
            const at = line.indexOf("=");
            if (at > 0)
                out[line.slice(0, at).trim()] = line.slice(at + 1).trim();
        }
        return out;
    }
    FileView {
        id: confFile
        path: root.configDir + "/phone.conf"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }

    // on|off; the compositor reads it at start, this is for a change while running
    readonly property string animationsConf: conf.animations || "on"
    onAnimationsConfChanged: Quickshell.execDetached(["phonegluewc-msg", "do", "animations", animationsConf])
    // off: home, its menu and its editor stay upright while apps still turn
    readonly property bool homeRotate: conf.home_rotate !== "off"
    onHomeRotateChanged: Quickshell.execDetached(["phonegluewc-msg", "do", "homerotate", homeRotate ? "on" : "off"])
    // carousel or grid: how the overview lays out the cards
    readonly property bool overviewGrid: conf.overview === "grid"
    onOverviewGridChanged: Quickshell.execDetached(["phonegluewc-msg", "do", "overviewmode", overviewGrid ? "grid" : "carousel"])

    property bool overview: false
    property int ws: 0
    property var counts: []
    property var wsApps: []
    function wsApp(i) {
        const id = (wsApps[i] || "").toLowerCase();
        if (!id)
            return null;
        return apps.find(e => e.id.toLowerCase() === id || (e.startupClass || "").toLowerCase() === id)
            || { id: id, name: wsApps[i].replace(/^.*\./, ""), icon: "" };
    }

    property bool lockOpen: !!Quickshell.env("PHONEGLUEWC_RELOCK")
    property bool menuOpen: false
    readonly property bool menuLoaded: menuOpen || menuClosing.running

    property var usage: ({})
    property var pinnedIds: []
    property var unpinnedIds: []
    // the tray's settings from the home editor: 3 to 6 apps, labels or not, a plate behind or not
    readonly property int dockSlots: Math.max(3, Math.min(6, parseInt(conf.tray_count) || 4))
    readonly property bool trayLabels: conf.tray_labels === "on"
    readonly property bool trayPlate: conf.tray_plate === "on"
    readonly property bool trayFull: pinnedIds.filter(id => apps.some(e => e.id === id)).length >= dockSlots
    // the app a hold asked about, the popup exists only while this is set
    property string pinId: ""
    property real pinX: 0
    property real pinBottom: 0
    property bool pinFailed: false
    property int pinWrites: 0
    property string pillSeq: ""

    // shortcut: looks in hicolor, Adwaita and pixmaps only, read the real theme once the OS is chosen
    property var icons: ({})
    // rerun when the app list changes, so an app installed later gets its icon
    Process {
        id: iconScan
        running: true
        command: ["sh", "-c", 'IFS=:; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do '
            + 'find "$d/icons/hicolor" "$d/icons/Adwaita" -path "*/apps/*" \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null; '
            + 'find "$d/pixmaps" -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                const rank = {};
                for (const path of text.split("\n")) {
                    const name = path.replace(/^.*\//, "").replace(/\.[^.]*$/, "");
                    const size = path.includes("/scalable/") ? 9999 : parseInt((path.match(/\/(\d+)x\d+\//) || [0, 1])[1]);
                    if (name && !(rank[name] >= size)) {
                        rank[name] = size;
                        found[name] = "file://" + path;
                    }
                }
                root.icons = found;
            }
        }
    }
    // icons measured too dark for a black screen, they get a light plate
    property var faintIcons: ({})
    function iconFor(entry) {
        if (!entry || !entry.icon)
            return "";
        if (entry.icon.startsWith("/"))
            return "file://" + entry.icon;
        return icons[entry.icon.replace(/\.(png|svg|xpm)$/, "")] || "";
    }

    // a rescan runs in many steps and swaps every object with no file changed: the dock and the menu
    // hold copies and only hear of a settled list that differs, or a rebuild loses the finger on them
    property var apps: []
    // Waydroid hides its system apps with NoDisplay on every sync and Quickshell leaves those out; only its keyboard and restore stub stay hidden
    property var androidHidden: []
    Process {
        id: androidScan
        command: ["sh", "-c", 'cd "${XDG_DATA_HOME:-$HOME/.local/share}/applications" 2>/dev/null && grep -l "^NoDisplay=true" waydroid.*.desktop']
        stdout: StdioCollector {
            onStreamFinished: {
                root.androidHidden = text.split("\n").map(l => l.replace(/\.desktop$/, "")).filter(id => id && !/inputmethod\.latin|apps\.restore/.test(id));
                root.appsSettle();
            }
        }
    }
    property string appsSig: ""
    function appsSettle() {
        const seen = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        const live = seen.concat(androidHidden.filter(id => !seen.some(e => e.id === id)).map(id => DesktopEntries.byId(id)).filter(e => e))
            .sort((a, b) => a.name.localeCompare(b.name))
            .map(e => ({
                id: e.id, name: e.name, icon: e.icon, genericName: e.genericName, startupClass: e.startupClass,
                keywords: Array.from(e.keywords), categories: Array.from(e.categories), command: Array.from(e.command),
                workingDirectory: e.workingDirectory, runInTerminal: e.runInTerminal
            }));
        const sig = JSON.stringify(live);
        if (sig === appsSig)
            return;
        appsSig = sig;
        live.forEach(e => e.execute = () => { const now = DesktopEntries.byId(e.id); if (now) now.execute(); });
        apps = live;
        iconScan.running = true;
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { Qt.callLater(root.appsSettle); androidScan.running = true; }
    }
    readonly property var mostUsed: apps
        .filter(e => (usage[e.id] || 0) > 0)
        .sort((a, b) => usage[b.id] - usage[a.id])
        .slice(0, 4)
    // pinned first, the rest fills up from use and the list, never with what the user unpinned
    readonly property var dock: {
        const out = [];
        const add = e => { if (e && out.length < dockSlots && !out.some(o => o.id === e.id)) out.push(e); };
        const fill = e => { if (!unpinnedIds.includes(e.id)) add(e); };
        pinnedIds.forEach(id => add(apps.find(e => e.id === id)));
        mostUsed.forEach(fill);
        apps.forEach(fill);
        return out;
    }

    property var dragEntry: null
    // a held tray icon that moves: the popup goes, the compositor carries it from here
    function startIconDrag(entry) {
        pinId = "";
        dragEntry = entry;
        Quickshell.execDetached(["phonegluewc-msg", "do", "icondrag",
            entry.command.join("\x1f"), entry.workingDirectory || ""]);
    }
    function askPin(entry, x, bottom) {
        pinX = x;
        pinBottom = bottom;
        pinFailed = false;
        pinId = entry.id;
    }
    // FileView cannot create the directory on a first run
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", configDir]);
        appsSettle();
        androidScan.running = true;
        applyVibration();
    }
    // the tray from the editor: exactly these apps in this order; what it showed before and loses stays out
    function setPinnedOrder(ids) {
        const gone = dock.map(e => e.id).filter(id => !ids.includes(id));
        const lines = list => list.length ? list.map(id => id + ".desktop").join("\n") + "\n" : "";
        const pinned = lines(ids);
        const unpinned = lines(unpinnedIds.filter(id => !ids.includes(id) && !gone.includes(id)).concat(gone));
        pinFailed = false;
        pinWrites = 0;
        if (pinned !== pinnedFile.text()) {
            pinWrites++;
            pinnedFile.setText(pinned);
        }
        if (unpinned !== unpinnedFile.text()) {
            pinWrites++;
            unpinnedFile.setText(unpinned);
        }
    }
    function setPinned(id, on) {
        pinFailed = false;
        pinWrites = 0;
        editIdList(pinnedFile, id, on);
        editIdList(unpinnedFile, id, !on);
        if (pinWrites === 0)
            pinId = "";
    }
    property var removeEntry: null
    function askRemove(id) {
        pinId = "";
        // a copy: a rescan of the desktop files replaces the entries
        const e = apps.find(a => a.id === id);
        removeEntry = { id: id, name: e ? e.name : id };
    }
    // the desktop file is gone by now, what the shell remembers about it goes too
    function forgetApp(id) {
        pinWrites = 0;
        editIdList(pinnedFile, id, false);
        editIdList(unpinnedFile, id, false);
        if (usage[id] !== undefined) {
            const next = Object.assign({}, usage);
            delete next[id];
            usage = next;
            usageFile.setText(JSON.stringify(next));
        }
    }
    function parseIds(text) {
        return text.split("\n").map(s => s.trim().replace(/\.desktop$/, "")).filter(s => s && s[0] !== "#");
    }
    // comments and the order stay, a new id goes last; FileView writes a temp file and renames it
    function editIdList(file, id, on) {
        const old = file.text();
        const lines = old.split("\n").filter(l => l.trim() !== "" && parseIds(l)[0] !== id);
        if (on)
            lines.push(id + ".desktop");
        const text = lines.length ? lines.join("\n") + "\n" : "";
        if (text === old)
            return;
        pinWrites++;
        file.setText(text);
    }
    function pinSaved() {
        if (--pinWrites === 0 && !pinFailed)
            pinId = "";
    }
    onOverviewChanged: pinId = ""
    onWsChanged: pinId = ""
    onPillSeqChanged: pinId = ""

    // an Android app goes through Waydroid whatever its desktop file says
    function run(entry) {
        if (/^waydroid\./.test(entry.id))
            Quickshell.execDetached(["waydroid", "app", "launch", entry.id.slice(9)]);
        else
            entry.execute();
    }
    function launch(entry) {
        const next = Object.assign({}, usage);
        next[entry.id] = (next[entry.id] || 0) + 1;
        usage = next;
        usageFile.setText(JSON.stringify(next));
        menuOpen = false;
        const open = openWindow(entry);
        if (open) {
            Quickshell.execDetached(["phonegluewc-msg", "do", "raise", open]);
        } else {
            Quickshell.execDetached(["phonegluewc-msg", "do", "openfrom"]);
            run(entry);
        }
    }
    function newWindow(entry) {
        menuOpen = false;
        pinId = "";
        run(entry);
    }
    // the app id of an open window of this entry; apps that declare a window class are matched by that alone
    function openWindow(entry) {
        const names = [entry.id.replace(/\.desktop$/, "")];
        if (entry.startupClass)
            names.push(entry.startupClass);
        else if (entry.command && entry.command[0])
            names.push(entry.command[0].replace(/^.*\//, ""));
        const wanted = names.map(n => n.toLowerCase());
        const t = ToplevelManager.toplevels.values.find(t => wanted.includes((t.appId || "").toLowerCase()));
        return t ? t.appId : "";
    }
    readonly property bool closeAllShown: overview && counts.some(n => n > 0)
    property int runningCount: 0
    property bool runningOpen: false

    // one key of phone.conf, the rest stays; FileView writes a temp file and renames it
    function setConf(k, v) {
        const lines = confFile.text().split("\n").filter(l => l.trim() !== "" && l.split("=")[0].trim() !== k);
        lines.push(k + " = " + v);
        confFile.setText(lines.join("\n") + "\n");
    }

    // ---- hardware buttons: the compositor counts the presses ----
    property string buttonSeq: ""
    property string toastText: ""
    property bool flashOn: false
    // characters show in a password field of the lock or the login
    property bool lockTyped: false
    function toast(text) {
        toastText = text;
        toastTimer.restart();
    }
    Timer { id: toastTimer; interval: 2200; onTriggered: root.toastText = "" }
    Timer { id: flashTimer; interval: 220; onTriggered: root.flashOn = false }
    function powerAction(key, fallback) {
        const v = conf[key];
        return ["camera", "flashlight", "screenshot", "none"].includes(v) ? v : fallback;
    }
    function runButton(action) {
        console.info("button action " + action);
        if (action === "camera") {
            const cam = apps.find(e => (e.categories || []).includes("Camera")) || apps.find(e => /camera/i.test(e.id + " " + e.name));
            if (cam) launch(cam); else toast("No camera app yet");
        } else if (action === "screenshot" && (lockTyped || removeEntry !== null))
            toast("No screenshot while a password is being typed");
        else if (action !== "none" && !buttonRun.running) {
            buttonRun.command = ["sh", Quickshell.shellDir + "/button.sh", action];
            buttonRun.running = true;
        }
    }
    function onButton(event) {
        console.info("button " + event);
        if (event === "nofree") {
            toast("All 9 workspaces are in use");
        } else if (event === "tilefull") {
            toast("This workspace already has 4 windows");
        } else if (event === "single") {
            Quickshell.execDetached(["phonegluewc-msg", "power", screenOff ? "on" : "off"]);
        } else if (event === "volup" || event === "voldown") {
            // the camera in front takes these as shutter and zoom, and reads the same button file itself
            if (cameraKeys.text().trim() !== "1")
                Status.stepVolume(event === "volup" ? 0.05 : -0.05);
        } else if (event === "chord") {
            runButton("screenshot");
        } else if (event === "double" || event === "triple") {
            const a = event === "double" ? powerAction("power_double", "camera") : powerAction("power_triple", "flashlight");
            if (screenOff && a === "camera")
                Quickshell.execDetached(["phonegluewc-msg", "power", "on"]);
            runButton(a);
        }
    }
    Process {
        id: buttonRun
        stdout: StdioCollector {
            onStreamFinished: {
                console.info("button result " + text.trim().replace(/\n/g, " "));
                for (const line of text.split("\n")) {
                    if (line === "flash=1") {
                        root.flashOn = true;
                        flashTimer.restart();
                        if (!Quickshell.env("PHONEGLUEWC_GREETER"))
                            Status.addNotif("Screenshot", "Saved in Pictures/Screenshots");
                    } else if (line.startsWith("message=")) {
                        root.toast(line.slice(8));
                    }
                }
            }
        }
    }
    FileView {
        id: cameraKeys
        path: root.stateDir + "/camera-keys"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    FileView {
        path: root.stateDir + "/button"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const line = text().trim();
            if (root.buttonSeq !== "" && root.buttonSeq !== line)
                root.onButton(line.split(" ")[1]);
            root.buttonSeq = line;
        }
    }

    onMenuOpenChanged: if (!menuOpen) menuClosing.restart()
    Timer { id: menuClosing; interval: 260 }

    FileView {
        path: root.stateDir + "/overview"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.overview = text().trim() === "1"
    }
    property bool screenOff: false
    // the compositor locks as the screen goes dark, after its fade; this draws that lock
    onScreenOffChanged: if (screenOff && !Quickshell.env("PHONEGLUEWC_GREETER")) lockOpen = true
    FileView {
        path: root.stateDir + "/screen"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.screenOff = text().trim() === "0"
    }

    // minutes untouched before the screen goes off and the phone locks, 0 never; playing media or a fullscreen app keeps it on
    readonly property int sleepAfter: conf.sleep_after === undefined ? 2 : Math.max(0, parseInt(conf.sleep_after) || 0)
    readonly property var sleepSteps: [0, 1, 2, 3, 5, 10]
    function nextSleep() {
        const n = sleepSteps.find(m => m > sleepAfter);
        setConf("sleep_after", String(n === undefined ? 0 : n));
    }
    // the haptics driver forgets its strength at reboot: the saved one goes back at every start and change
    readonly property int vibrationMv: parseInt(conf.vibration_mv) || 0
    function applyVibration() {
        if (vibrationMv >= 1500 && vibrationMv <= 3600)
            Quickshell.execDetached(["sh", "-c", 'f=/sys/module/qcom_hv_haptics_lite/parameters/vmax_mv; [ -w "$f" ] && echo "$1" >"$f"', "sh", String(vibrationMv)]);
    }
    onVibrationMvChanged: applyVibration()
    IdleMonitor {
        enabled: root.sleepAfter > 0 && !root.screenOff && !Mpris.players.values.some(p => p.isPlaying)
        timeout: root.sleepAfter * 60
        onIsIdleChanged: {
            if (isIdle)
                Quickshell.execDetached(["phonegluewc-msg", "power", "off"]);
        }
    }
    FileView {
        path: root.stateDir + "/workspaces"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const line = text().split("\n")[0].split(" ");
            if (line.length < 4)
                return;
            root.ws = parseInt(line[2]);
            root.counts = line[3].split(",").map(Number);
            root.wsApps = line.length > 5 ? line[5].split(",") : [];
        }
    }
    // the pill was used while the menu held the keyboard
    FileView {
        path: root.stateDir + "/pill"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.pillSeq !== "" && root.pillSeq !== text())
                root.menuOpen = false;
            root.pillSeq = text();
        }
    }
    // a swipe up on bare home, seen by the compositor
    property string menuSeq: ""
    FileView {
        path: root.stateDir + "/menu"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // the compositor counts swipes on our own sheets too; those are not home
            if (root.menuSeq !== "" && root.menuSeq !== text() && !root.lockOpen && !Status.panelLoaded && root.pinId === ""
                    && root.removeEntry === null && !Screens.editing && Recorder.stage === "")
                root.menuOpen = true;
            root.menuSeq = text();
        }
    }
    FileView {
        id: usageFile
        path: root.stateDir + "/app-usage.json"
        preload: true
        printErrors: false
        onLoaded: {
            try { root.usage = JSON.parse(text()) || {}; } catch (e) { root.usage = {}; }
        }
    }
    FileView {
        id: pinnedFile
        path: root.configDir + "/pinned-apps"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.pinnedIds = root.parseIds(text())
        onSaved: { root.pinnedIds = root.parseIds(text()); root.pinSaved(); }
        onSaveFailed: { root.pinFailed = true; reload(); }
    }
    FileView {
        id: unpinnedFile
        path: root.configDir + "/unpinned-apps"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.unpinnedIds = root.parseIds(text())
        onSaved: { root.unpinnedIds = root.parseIds(text()); root.pinSaved(); }
        onSaveFailed: { root.pinFailed = true; reload(); }
    }
}
