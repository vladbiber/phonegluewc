pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// the lock PIN, checked by phonepin; the PIN goes to its stdin and is dropped at once
Singleton {
    id: root

    property bool isSet: false
    property bool passwordUsed: false
    property int wait: 0
    property bool busy: false
    // a set PIN always replaces the password at the lock; the boot login stays password only
    readonly property bool usable: isSet && !Auth.greeter
    signal answered(bool ok)

    function refresh() { status.running = true; }
    function submit(pin) {
        if (busy || wait > 0)
            return;
        busy = true;
        check.pending = pin;
        check.running = true;
    }
    // the password opened the lock: PINs work until the next boot
    function rememberPassword() { remember.running = true; }

    Component.onCompleted: refresh()

    Process {
        id: status
        command: ["phonepin", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = {};
                for (const kv of text.trim().split(" ")) {
                    const at = kv.indexOf("=");
                    if (at > 0)
                        v[kv.slice(0, at)] = kv.slice(at + 1);
                }
                root.isSet = v.pin === "1";
                root.passwordUsed = v.password === "1";
                root.wait = parseInt(v.wait) || 0;
            }
        }
    }
    Process {
        id: check
        property string pending: ""
        command: ["phonepin", "check"]
        stdinEnabled: true
        onRunningChanged: if (running) {
            write(pending + "\n");
            pending = "";
            stdinEnabled = false;
        }
        stdout: StdioCollector { id: checkOut }
        onExited: code => {
            check.stdinEnabled = true;
            const m = /wait=(\d+)/.exec(checkOut.text);
            root.wait = m ? parseInt(m[1]) : 0;
            root.busy = false;
            // 3: the password is needed again, 4: the PIN was removed meanwhile
            if (code === 3 || code === 4)
                root.refresh();
            root.answered(code === 0);
        }
    }
    Process {
        id: remember
        command: ["phonepin", "unlocked"]
        onExited: root.refresh()
    }
    Timer {
        running: root.wait > 0
        interval: 1000
        repeat: true
        onTriggered: root.wait = Math.max(0, root.wait - 1)
    }
}
