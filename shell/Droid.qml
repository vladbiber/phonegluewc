pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Android's notifications and incoming calls, from the listener in the phonekbd bridge app
Singleton {
    id: root
    readonly property string data: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/waydroid/data"
    // while connected, Waydroid's own D-Bus copies of the same notifications are dropped
    readonly property bool live: sock.item ? sock.item.connected : false
    // the ringing call: { key, pkg, app, who, icon }
    property var call: null

    function iconOf(pkg) { return root.data + "/icons/" + pkg + ".png"; }
    function send(cmd, key) {
        if (!live)
            return;
        sock.item.write(cmd + "\t" + key + "\n");
        sock.item.flush();
    }
    function answer() {
        if (!call)
            return;
        send("a", call.key);
        woke = false;
        raise.pkg = call.pkg;
        raise.at = Date.now();
        call = null;
        // the app's call screen opens in its window: up now, or once the PIN is in
        if (!Phone.lockOpen)
            raise.restart();
    }
    Connections {
        target: Phone
        function onLockOpenChanged() {
            if (!Phone.lockOpen && raise.pkg !== "" && Date.now() - raise.at < 120000)
                raise.restart();
        }
    }
    function decline() {
        if (!call)
            return;
        send("d", call.key);
        call = null;
    }
    Timer {
        id: raise
        property string pkg: ""
        property real at: 0
        interval: 1500
        onTriggered: {
            Quickshell.execDetached(["phonegluewc-msg", "do", "raise", "waydroid." + pkg]);
            pkg = "";
        }
    }

    function received(l) {
        const f = l.split("\t");
        if ((f[0] === "n" || f[0] === "u") && f.length >= 6) {
            const n = { key: f[1], app: f[3], icon: iconOf(f[2]), summary: f[4], body: f[5], time: Qt.formatTime(new Date(), "HH:mm") };
            Status.notifs = [n].concat(Status.notifs.filter(o => o.key !== n.key)).slice(0, 30);
            if (f[0] === "n")
                Status.alert();
        } else if (f[0] === "i" && f.length >= 5) {
            if (!call || call.key !== f[1])
                callStarted();
            call = { key: f[1], pkg: f[2], app: f[3], who: f[4] || f[3], icon: iconOf(f[2]) };
        } else if (f[0] === "c" && f.length >= 2) {
            if (call && call.key === f[1])
                call = null;
            Status.notifs = Status.notifs.filter(o => o.key !== f[1]);
        }
    }
    // a call lights a dark screen; the lock screen then shows it, and it goes dark again unless answered or used
    property bool woke: false
    function callStarted() {
        woke = woke || Phone.screenOff;
        if (Phone.screenOff)
            Quickshell.execDetached(["phonegluewc-msg", "power", "on"]);
    }
    onCallChanged: {
        if (call || !woke)
            return;
        woke = false;
        if (Phone.lockOpen && !Phone.lockTyped && !Phone.screenOff)
            Quickshell.execDetached(["phonegluewc-msg", "power", "off"]);
    }

    // a Socket that failed once never connects again, so each try is a new one
    Loader {
        id: sock
        sourceComponent: Socket {
            path: root.data + "/data/org.phonegluewc.ime/n/s"
            connected: true
            parser: SplitParser { onRead: l => root.received(l) }
            onConnectedChanged: if (!connected) root.call = null
        }
    }
    // Android starts and stops with Waydroid: keep trying while it is not there
    Timer {
        running: !root.live
        interval: 5000
        repeat: true
        onTriggered: {
            sock.active = false;
            sock.active = true;
        }
    }

    // ringtone and vibration until the call is answered, declined or gone; the ringer and do not disturb decide
    readonly property bool sound: call !== null && !Status.dnd && Status.ringer === "normal"
    readonly property bool buzz: call !== null && !Status.dnd && Status.ringer !== "silent"
    Process {
        running: root.sound
        command: ["sh", "-c", 'f=$1; [ -r "$f" ] || f=/usr/share/sounds/freedesktop/stereo/phone-incoming-call.oga
            trap \'kill $p 2>/dev/null; exit 0\' TERM INT
            while :; do paplay --client-name=phonegluewc-ringtone "$f" & p=$!; wait $p || sleep 1; done', "ring", Phone.conf.ringtone || ""]
    }
    Process {
        running: root.buzz
        command: ["sh", "-c", 'command -v fbcli >/dev/null || exit 0; trap "exit 0" TERM INT; while :; do fbcli -E message-new-instant >/dev/null 2>&1; sleep 1.5 & wait $!; done']
    }
}
