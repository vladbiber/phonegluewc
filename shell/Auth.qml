pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// who a password opens, and whether it is right; the screen knows nothing else
Singleton {
    id: root

    // the password itself when set: a fake authenticator, no PAM or greetd is touched
    readonly property string mock: Quickshell.env("PHONE_AUTH_MOCK") || ""
    readonly property bool greeter: !!Quickshell.env("PHONEGLUEWC_GREETER")
    readonly property string configFile: Phone.configDir + "/login.conf"

    property var config: {
        const out = { user: "", left: "camera", right: "torch", wallpaper: "" };
        for (const line of file.text().split("\n")) {
            const at = line.indexOf("=");
            if (at > 0)
                out[line.slice(0, at).trim()] = line.slice(at + 1).trim();
        }
        return out;
    }
    FileView {
        id: file
        path: root.configFile
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }

    // Replace this one to let the password choose the account.
    function accountFor(password) {
        // the lock of a running session belongs to whoever is logged in; only the greeter needs login.conf
        return config.user || (greeter ? "" : (Quickshell.env("USER") || ""));
    }

    property bool busy: false
    signal answered(bool ok)

    function submit(password) {
        if (busy)
            return;
        busy = true;
        const account = accountFor(password);
        if (mock !== "") {
            pendingOk = password === mock && account !== "";
            mockDelay.restart();
        } else if (!account) {
            finish(false);
        } else {
            backend.active = true;
            backend.item.submit(account, password);
        }
    }
    function finish(ok) {
        busy = false;
        answered(ok);
    }

    property bool pendingOk: false
    Timer { id: mockDelay; interval: 300; onTriggered: root.finish(root.pendingOk) }

    Loader {
        id: backend
        active: false
        source: root.greeter ? "AuthGreetd.qml" : "AuthPam.qml"
    }

    // what the picker offers: the sessions installed on the system
    property var sessions: []
    Process {
        running: root.greeter
        command: ["sh", "-c", 'IFS=:; for d in ${XDG_DATA_DIRS:-/usr/share}; do for f in "$d"/wayland-sessions/*.desktop; do '
            + '[ -e "$f" ] && awk -F= \'/^Name=/{n=$2} /^Exec=/{e=$2} END{print n "\\t" e}\' "$f"; done; done']
        stdout: StdioCollector {
            onStreamFinished: root.sessions = text.split("\n").filter(l => l).map(l => {
                const p = l.split("\t");
                return { name: p[0], exec: p[1] };
            })
        }
    }
    property int sessionIndex: 0
    readonly property var session: sessions[sessionIndex] || null

    function launchSession() {
        if (mock !== "") {
            launchLog.command = ["sh", "-c", 'echo "$1" >>"$PHONE_AUTH_LOG"', "sh", session ? session.exec : "none"];
            if (Quickshell.env("PHONE_AUTH_LOG"))
                launchLog.running = true;
        }
    }
    Process { id: launchLog }

    readonly property string sessionCommand: session ? session.exec : ""
}
