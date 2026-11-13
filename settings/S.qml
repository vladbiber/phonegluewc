pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// colours, the current page, what is installed and the save queue
Singleton {
    id: root

    // black is the page and white the text, whichever way round the theme puts them
    readonly property bool light: phone.theme === "light"
    // 0 dark, 1 light; it slides so the colours crossfade, or jumps with animations off
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
    readonly property color line: mix("#262626", "#dddddd")
    readonly property color press: mix("#2a2a2a", "#e2e2e2")
    readonly property color edge: mix("#3a3a3a", "#b5b5b5")
    readonly property string font: "Noto Sans"
    readonly property int margin: 20
    readonly property string pset: Quickshell.shellPath("pset")
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/phonegluewc"
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"

    readonly property var pages: [
        { id: "wifi", label: "Wi-Fi", sub: "Networks and passwords", icon: "wifi3", keys: "wifi wireless internet network password ssid" },
        { id: "bluetooth", label: "Bluetooth", sub: "Pair and connect devices", icon: "bt", keys: "bluetooth pair headset headphones speaker" },
        { id: "mobile", label: "Mobile network", sub: "SIM, mobile data, roaming", icon: "phone", keys: "mobile cellular sim data roaming modem carrier operator" },
        { id: "display", label: "Display", sub: "Brightness, size, orientation", icon: "bright", keys: "display screen brightness rotate rotation orientation text size scale sleep timeout" },
        { id: "sound", label: "Sound", sub: "Output, volume, ringer", icon: "vol2", keys: "sound audio volume mute speaker output headphones ringer ringtone vibrate silent disturb dnd" },
        { id: "battery", label: "Battery", sub: "Level, charging, power button", icon: "power", keys: "battery charge charging health power button double triple press shortcut flashlight camera screenshot" },
        { id: "look", head: "Wallpaper", label: "Wallpaper and look", sub: "Dark or light, accent, wallpaper", icon: "palette", keys: "wallpaper background accent colour color theme look lock home dark light mode night" },
        { id: "apps", label: "Apps", sub: "Default browser, tray apps", icon: "grid", keys: "apps default browser pinned tray dock" },
        { id: "keyboard", head: "Keyboard", label: "Language and keyboard", sub: "Layouts, suggestions", icon: "keyboard", keys: "language keyboard layout suggestions autocorrect autocomplete learn emoji clipboard history laptop xkb typing" },
        { id: "languages", parent: "keyboard", label: "Languages", sub: "Download typing and translation languages", icon: "keyboard", keys: "languages translate translation download dictionary" },
        { id: "camera", label: "Dynamic camera", sub: "Live activities around the camera", icon: "bright", keys: "dynamic camera hole notch cutout island pill activities live position" },
        { id: "security", label: "Security", sub: "Screen lock, PIN, fingerprint", icon: "lock", keys: "security password lock pin fingerprint" },
        { id: "about", label: "About", sub: "Device, OS, storage, memory", icon: "info", keys: "about device os kernel storage ram memory date time version" }
    ]
    function titleOf(id) {
        const p = pages.find(x => x.id === id);
        return p ? p.head || p.label : "Settings";
    }

    // "" is the main list; an unknown name lands there too
    property string page: pages.some(p => p.id === Quickshell.env("PHONESETTINGS_PAGE")) ? Quickshell.env("PHONESETTINGS_PAGE") : ""
    function open(id) {
        saveError = "";
        page = pages.some(p => p.id === id) ? id : "";
    }
    // a running download gets SIGTERM first; the helper then removes its scratch files and exits
    function quit() {
        if (LangJob.busy) {
            LangJob.quitWhenDone = true;
            LangJob.cancel();
        } else {
            Qt.quit();
        }
    }
    function back() {
        if (page === "")
            quit();
        else
            open(pages.find(p => p.id === page)?.parent || "");
    }

    // ---- what is installed ----
    property var tools: ({})
    property bool toolsReady: false
    function has(t) { return tools[t] === true; }
    Process {
        running: true
        command: ["sh", "-c", 'for t; do command -v -- "$t" >/dev/null 2>&1 && echo "$t"; done', "sh",
            "nmcli", "bluetoothctl", "timeout", "brightnessctl", "wpctl", "pactl", "mmcli", "upower", "phonegluewc-msg", "phonekbd", "phonekbd-lang", "fbcli"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = {};
                for (const n of text.split("\n"))
                    if (n)
                        t[n] = true;
                root.tools = t;
                root.toolsReady = true;
            }
        }
    }

    // nmcli -t: fields split on ":", with "\\:" and "\\\\" as escapes
    function terse(line) {
        const out = [""];
        for (let i = 0; i < line.length; i++) {
            if (line[i] === "\\" && i + 1 < line.length)
                out[out.length - 1] += line[++i];
            else if (line[i] === ":")
                out.push("");
            else
                out[out.length - 1] += line[i];
        }
        return out;
    }
    function lines(text) { return text.split("\n").filter(l => l !== ""); }
    // the first line of what a tool complained about, for a message
    function firstLine(text, fallback) { return lines(text)[0] || fallback; }

    // ---- config files: read here, written one at a time by pset ----
    function confOf(text) {
        const out = {};
        for (const line of text.split("\n")) {
            const s = line.trim();
            const at = s.indexOf("=");
            if (at > 0 && s[0] !== "#")
                out[s.slice(0, at).trim()] = s.slice(at + 1).trim();
        }
        return out;
    }
    property var phone: ({})
    property var config: ({})
    property var kbd: ({})
    property string kbdLayout: "normal"
    property string saveError: ""
    readonly property string accentSaved: /^#[0-9a-fA-F]{6}$/.test(phone.accent || "") ? phone.accent.toLowerCase() : "#d71921"
    // a white accent vanishes on a light page, it turns black there
    readonly property color accent: light && accentSaved === "#f5f5f5" ? "#111111" : accentSaved
    // text on the accent: dark on a light accent, else white
    // not onAccent: Qt 6.10 reads that name as a signal handler and the binding never runs
    readonly property color inkOnAccent: 0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b > 0.55 ? "#000000" : "#ffffff"

    // the quick tile writes the theme too, so this one is watched
    FileView { id: phoneFile; path: root.configDir + "/phone.conf"; preload: true; printErrors: false; watchChanges: true; onFileChanged: reload(); onLoaded: root.phone = root.confOf(text()); onLoadFailed: root.phone = ({}) }
    FileView { id: configFile; path: root.configDir + "/config.conf"; preload: true; printErrors: false; onLoaded: root.config = root.confOf(text()); onLoadFailed: root.config = ({}) }
    FileView { id: kbdConf; path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/phonekbd/config"; preload: true; printErrors: false; onLoaded: root.kbd = root.confOf(text()); onLoadFailed: root.kbd = ({}) }
    FileView { id: kbdFile; path: root.stateDir + "/phonekbd/layout"; preload: true; printErrors: false; onLoaded: root.kbdLayout = text().trim() === "laptop" ? "laptop" : "normal" }
    FileView { id: pinnedFile; path: root.configDir + "/pinned-apps"; preload: true; printErrors: false
        onLoaded: root.pinned = text().split("\n").map(s => s.trim().replace(/\.desktop$/, "")).filter(s => s && s[0] !== "#")
        onLoadFailed: root.pinned = []
    }
    FileView { id: mimeFile; path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/mimeapps.list"; preload: true; printErrors: false
        onLoaded: { const m = text().match(/^x-scheme-handler\/https=([^;\n]*)/m); root.browser = m ? m[1].replace(/\.desktop$/, "") : ""; }
    }
    property var pinned: []
    property string browser: ""

    property var queue: []
    function save(args) {
        saveError = "";
        queue.push(args);
        next();
    }
    function next() {
        if (saver.running || queue.length === 0)
            return;
        saver.command = [pset].concat(queue.shift());
        saver.running = true;
    }
    Process {
        id: saver
        stderr: StdioCollector { id: saverErr }
        onExited: code => {
            if (code !== 0)
                root.saveError = "Could not save: " + (saverErr.text.trim() || "unknown error");
            phoneFile.reload();
            configFile.reload();
            kbdFile.reload();
            kbdConf.reload();
            pinnedFile.reload();
            mimeFile.reload();
            root.next();
        }
    }
}
