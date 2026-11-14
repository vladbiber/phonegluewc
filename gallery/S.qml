pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// colours, the photo list, its thumbnails and which photo is open
Singleton {
    id: root

    readonly property bool light: phone.theme === "light"
    property real lit: light ? 1 : 0
    Behavior on lit { enabled: root.phone.animations !== "off"; NumberAnimation { duration: 200 } }
    function mix(dark, lightColor) {
        const a = Qt.color(dark), b = Qt.color(lightColor), k = lit;
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1);
    }
    readonly property color black: mix("#000000", "#f2f2f2")
    readonly property color white: mix("#f5f5f5", "#000000")
    readonly property color grey: mix("#8c8c8c", "#666666")
    readonly property color surface: mix("#171717", "#ffffff")
    readonly property color press: mix("#2a2a2a", "#e2e2e2")
    readonly property string font: "Noto Sans"
    readonly property bool anim: phone.animations !== "off"
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/phonegluewc"
    property var phone: ({})
    readonly property string accentSaved: /^#[0-9a-fA-F]{6}$/.test(phone.accent || "") ? phone.accent.toLowerCase() : "#d71921"
    readonly property color accent: light && accentSaved === "#f5f5f5" ? "#111111" : accentSaved
    // not onAccent: Qt 6.10 reads that name as a signal handler and the binding never runs
    readonly property color inkOnAccent: 0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b > 0.55 ? "#000000" : "#ffffff"
    FileView {
        path: root.configDir + "/phone.conf"; preload: true; printErrors: false; watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const out = {};
            for (const line of text().split("\n")) {
                const at = line.indexOf("=");
                if (at > 0 && line.trim()[0] !== "#")
                    out[line.slice(0, at).trim()] = line.slice(at + 1).trim();
            }
            root.phone = out;
        }
    }

    // ---- photos, newest first ----
    // albums are plain folders under ~/Pictures; Camera is the default one (and the timeline)
    readonly property string rootDir: Quickshell.env("PHONEGALLERY_ROOT") || Quickshell.env("HOME") + "/Pictures"
    property string album: "Camera"
    property string dirOverride: Quickshell.env("PHONEGALLERY_DIR")
    readonly property string dir: dirOverride !== "" ? dirOverride : rootDir + "/" + album
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/phonegallery/" + dir.replace(/\//g, "_")
    readonly property alias photos: folder
    FolderListModel {
        id: folder
        folder: "file://" + root.dir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.mp4"]
        caseSensitive: false
        showDirs: false
        sortField: FolderListModel.Time
        onCountChanged: {
            rescan.restart();
            root.rebuild();
            root.tryOpen();
            if (root.deleted >= 0) {
                root.current = count ? Math.min(root.deleted, count - 1) : -1;
                root.deleted = -1;
            }
        }
        onStatusChanged: { root.tryOpen(); if (status === FolderListModel.Ready) root.rebuild(); }
    }
    // same name as phonegallery-thumbs writes: the mtime in it makes an edited photo a new thumbnail
    function thumbOf(name, modified) { return cacheDir + "/" + name + "@" + (modified ? Math.floor(modified.getTime() / 1000) : 0) + "-2.jpg"; }
    // a clip's full-screen first frame, written next to its grid tile
    function posterOf(name, modified) { return thumbOf(name, modified).replace(/\.jpg$/, "-p.jpg"); }
    function isClip(name) { return /\.mp4$/i.test(name); }
    // where the tapped tile sits in the window: the viewer grows out of it and shrinks back into it
    property rect origin: Qt.rect(0, 0, 0, 0)
    property var ready: ({})
    property int thumbRev: 0
    function hasThumb(path) { return thumbRev >= 0 && ready[path] === true; }

    Timer { id: rescan; interval: 250; onTriggered: thumbs.running ? thumbs.again = true : thumbs.running = true }
    Process {
        id: thumbs
        property bool again: false
        command: ["nice", "-n", "10", Quickshell.shellPath("phonegallery-thumbs"), root.dir, root.cacheDir]
        stdout: SplitParser {
            onRead: line => { root.ready[line] = true; root.thumbRev++; }
        }
        onExited: if (again) { again = false; running = true; }
    }

    // ---- the open photo: -1 is the grid ----
    property int current: -1
    property bool bars: true
    property string pendingOpen: Quickshell.env("PHONEGALLERY_OPEN")
    function open(path) {
        if (path !== "" && path[0] === "/" && path.slice(0, path.lastIndexOf("/")) !== dir) {
            const d = path.slice(0, path.lastIndexOf("/"));
            if (dirOverride === "" && d.slice(0, d.lastIndexOf("/")) === rootDir)
                album = d.slice(d.lastIndexOf("/") + 1);
            else
                dirOverride = d;
        }
        pendingOpen = path;
        if (path === "")
            current = -1;
        tryOpen();
    }
    function tryOpen() {
        if (pendingOpen === "" || folder.status !== FolderListModel.Ready)
            return;
        const i = folder.indexOf("file://" + pendingOpen);
        if (i >= 0) {
            current = i;
            pendingOpen = "";
        }
    }
    function back() {
        if (current >= 0)
            current = -1;
        else
            Qt.quit();
    }

    // ---- the grid's rows: a date header, then up to three photos of that day (a, b, c are folder indexes or -1)
    readonly property alias days: dayRows
    ListModel { id: dayRows }
    function dayCount(from) {
        let n = 0;
        for (let r = from + 1; r < dayRows.count && dayRows.get(r).label === ""; r++) {
            const x = dayRows.get(r);
            n += (x.a >= 0) + (x.b >= 0) + (x.c >= 0);
        }
        return n;
    }
    function dayLabel(d) {
        const t = new Date(), y = new Date(t.getTime() - 864e5), k = x => Qt.formatDate(x, "yyyyMMdd");
        return k(d) === k(t) ? "Today" : k(d) === k(y) ? "Yesterday" : Qt.formatDate(d, "d MMM yyyy");
    }
    function rebuild() {
        dayRows.clear();
        let day = "", col = 3;
        for (let i = 0; i < folder.count; i++) {
            const d = folder.get(i, "fileModified"), k = Qt.formatDate(d, "yyyyMMdd");
            if (k !== day) {
                day = k;
                col = 3;
                dayRows.append({ label: dayLabel(d), a: -1, b: -1, c: -1 });
            }
            if (col === 3) {
                dayRows.append({ label: "", a: i, b: -1, c: -1 });
                col = 0;
            } else {
                dayRows.setProperty(dayRows.count - 1, col === 1 ? "b" : "c", i);
            }
            col++;
        }
    }
    function rowOf(i) {
        for (let r = 0; r < dayRows.count; r++) {
            const x = dayRows.get(r);
            if (x.a === i || x.b === i || x.c === i)
                return r;
        }
        return 0;
    }

    // ---- details of the open item, shown or hidden as the user chose (remembered in a file)
    property bool showInfo: false
    property var details: []
    FileView {
        id: infoFile
        path: root.configDir + "/gallery-info"; preload: true; printErrors: false; blockLoading: true; atomicWrites: true
        onLoaded: root.showInfo = text().trim() === "1"
    }
    function setInfo(on) { showInfo = on; infoFile.setText(on ? "1\n" : "0\n"); }
    function loadInfo(path) {
        details = [];
        infoProc.running = false;
        infoProc.command = [Quickshell.shellPath("phonegallery-info"), path];
        infoProc.running = true;
    }
    Process {
        id: infoProc
        stdout: StdioCollector { onStreamFinished: root.details = text.trim().split("\n").map(l => l.split("\t")) }
    }

    property int deleted: -1
    // from the timeline a delete removes every link of the file; inside another album it only drops that album's link
    // (a last link asks first: the result code 3 comes back as `lastLink`)
    property bool lastLink: false
    function remove(i, force) {
        deleted = i;
        const path = folder.get(i, "filePath");
        const thumb = thumbOf(folder.get(i, "fileName"), folder.get(i, "fileModified"));
        if (album === "Camera" || dirOverride !== "")
            albums(["trash", path], () => Quickshell.execDetached(["rm", "-f", "--", thumb]));
        else
            albums(force ? ["remove", album, path, "--force"] : ["remove", album, path], code => {
                lastLink = code === 3;
                if (code === 3) deleted = -1;
                else Quickshell.execDetached(["rm", "-f", "--", thumb]);
            });
    }

    // ---- albums: one helper does the file work, results come back through run()
    property var albumList: []
    property var onDone: null
    function albums(args, cb) {
        runner.args = args;
        onDone = cb || null;
        runner.command = [Quickshell.shellPath("phonegallery-albums"), ...args];
        runner.running = true;
    }
    property var folderList: []
    function refreshFolders() {
        albums(["folders"], () => {
            folderList = runner.out.trim() === "" ? [] : runner.out.trim().split("\n").map(l => { const p = l.split("\t"); return { name: p[0], count: +p[1] }; });
        });
    }
    function refreshAlbums() {
        albums(["list"], () => {
            albumList = runner.out.trim() === "" ? [] : runner.out.trim().split("\n").map(l => { const p = l.split("\t"); return { name: p[0], count: +p[1], cover: p[2] }; });
        });
    }
    Process {
        id: runner
        property var args: []
        property string out: ""
        environment: ({ PHONEGALLERY_ROOT: root.rootDir })
        stdout: StdioCollector { onStreamFinished: runner.out = text }
        onExited: code => { const f = root.onDone; root.onDone = null; if (f) f(code); }
    }
    Component.onCompleted: refreshAlbums()
    // what the viewer shows: "timeline" (the open album's photos) or "albums" (the album tiles)
    property string view: "timeline"
    function openAlbum(name) { album = name; view = "timeline"; current = -1; clearSel(); }

    // ---- Android (Waydroid): what it may see. Its own small file, apart from the Waydroid mode in phone.conf:
    // mode = send (only what is sent) | album (one album) | all (the whole gallery), album = NAME, strip = 1 | 0
    property string androidMode: "send"
    property var androidAlbums: []
    property bool androidStrip: true
    property string toast: ""
    FileView {
        id: androidConf
        path: root.configDir + "/gallery-android.conf"; preload: true; printErrors: false; blockLoading: true; atomicWrites: true; watchChanges: true
        onFileChanged: reload()  // the Settings page edits the same file
        onLoaded: {
            for (const line of text().split("\n")) {
                const at = line.indexOf("=");
                if (at < 0) continue;
                const k = line.slice(0, at).trim(), v = line.slice(at + 1).trim();
                if (k === "mode" && ["send", "album", "all"].includes(v)) root.androidMode = v;
                if (k === "albums") root.androidAlbums = v === "" ? [] : v.split(",");
                if (k === "strip") root.androidStrip = v !== "0";
            }
            root.reconcileAndroid();
        }
    }
    function saveAndroid() { androidConf.setText("mode=" + androidMode + "\nalbums=" + androidAlbums.join(",") + "\nstrip=" + (androidStrip ? 1 : 0) + "\n"); }
    // the exposure is a mount, so it is put back whenever the gallery starts (a reboot drops it)
    function applyAndroid() {
        if (Quickshell.env("PHONEGALLERY_ROOT")) return;  // a test run must not touch the real mounts
        if (androidMode === "album" && androidAlbums.length) android(["expose-albums", ...androidAlbums]);
        else if (androidMode === "all") android(["expose-all"]);
        else android(["expose-none"]);
    }
    // at start the helper only makes the mounts match the saved choice; it never takes a newer choice back
    function reconcileAndroid() {
        if (!Quickshell.env("PHONEGALLERY_ROOT")) android(["refresh"], null, true);
    }
    function setAndroid(mode) { androidMode = mode; saveAndroid(); applyAndroid(); }
    // tick or untick one album of the chosen ones
    function tickAlbum(name) {
        const a = androidAlbums.includes(name) ? androidAlbums.filter(n => n !== name) : [...androidAlbums, name];
        androidAlbums = a;
        saveAndroid();
        applyAndroid();
    }
    function say(text) { toast = text; toastTimer.restart(); }
    Timer { id: toastTimer; interval: 2200; onTriggered: root.toast = "" }
    // helper calls run one after the other (a second one asked for while one runs waits its turn)
    property var jobs: []
    function android(args, cb, quiet) {
        jobs.push({ args: args, cb: cb || null, quiet: quiet === true });
        nextJob();
    }
    function nextJob() {
        if (sender.running || jobs.length === 0) return;
        sender.job = jobs.shift();
        sender.errText = "";
        sender.command = ["sudo", "-n", "/usr/local/bin/phonegallery-android", ...sender.job.args];
        sender.running = true;
    }
    function sendFiles(paths) {
        android(["send", ...(androidStrip ? ["--strip"] : []), ...paths], code => say(code === 0 ? "Sent to Android" : "Could not send"));
    }
    function clearAndroid() { android(["clear"], code => say(code === 0 ? "Android folder emptied" : "Could not empty it")); }
    Process {
        id: sender
        property var job: ({ args: [], cb: null, quiet: true })
        property string errText: ""
        stderr: StdioCollector { onStreamFinished: sender.errText = text }
        onExited: code => {
            const j = job;
            if (code !== 0 && !j.quiet)
                root.say("Android access failed: " + (sender.errText.trim().split("\n")[0] || "exit " + code));
            if (j.cb) j.cb(code);
            root.nextJob();
        }
    }

    // ---- multi-select in the grid
    property var selected: ({})
    property int selCount: 0
    readonly property bool selecting: selCount > 0
    function toggleSel(path) {
        const s = Object.assign({}, selected);
        if (s[path]) delete s[path]; else s[path] = true;
        selected = s;
        selCount = Object.keys(s).length;
    }
    function clearSel() { selected = ({}); selCount = 0; }
    function selPaths() { return Object.keys(selected); }
    // after an album action the grid and the album tiles are read again
    function afterAction() { clearSel(); refreshAlbums(); }
}
