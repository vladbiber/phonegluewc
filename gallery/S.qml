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
    property string dir: Quickshell.env("PHONEGALLERY_DIR") || Quickshell.env("HOME") + "/Pictures/Camera"
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
            root.tryOpen();
            if (root.deleted >= 0) {
                root.current = count ? Math.min(root.deleted, count - 1) : -1;
                root.deleted = -1;
            }
        }
        onStatusChanged: root.tryOpen()
    }
    // same name as phonegallery-thumbs writes: the mtime in it makes an edited photo a new thumbnail
    function thumbOf(name, modified) { return cacheDir + "/" + name + "@" + Math.floor(modified.getTime() / 1000) + ".jpg"; }
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
    property string pendingOpen: Quickshell.env("PHONEGALLERY_OPEN")
    function open(path) {
        if (path !== "" && path[0] === "/" && path.slice(0, path.lastIndexOf("/")) !== dir)
            dir = path.slice(0, path.lastIndexOf("/"));
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

    property int deleted: -1
    function remove(i) {
        deleted = i;
        Quickshell.execDetached(["rm", "-f", "--", folder.get(i, "filePath"), thumbOf(folder.get(i, "fileName"), folder.get(i, "fileModified"))]);
    }
}
