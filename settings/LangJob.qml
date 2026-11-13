pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// one download at a time; it lives here so that leaving the page does not stop it
Singleton {
    id: root
    property string code: ""
    property real done: 0
    property real total: 0
    property string error: ""
    property bool cancelled: false
    property bool finished: false
    property bool quitWhenDone: false
    readonly property bool busy: code !== ""
    signal installed()

    // the helper's own rule, plus no leading dash so that a code cannot read as an option
    function valid(c) { return /^[A-Za-z][A-Za-z-]{1,11}$/.test(c) && c !== "en"; }
    function install(c) {
        if (busy || !valid(c))
            return;
        code = c;
        done = total = 0;
        error = "";
        cancelled = finished = false;
        job.command = ["phonekbd-lang", "install", c];
        job.running = true;
    }
    // SIGTERM: the helper removes its scratch folder, or finishes if it is already moving files in place
    function cancel() { job.running = false; }

    Process {
        id: job
        environment: ({ LC_ALL: "C" })
        stdout: SplitParser {
            onRead: line => {
                const p = line.match(/^P (\d+) (\d+)$/);
                if (p) {
                    root.done = Number(p[1]);
                    root.total = Number(p[2]);
                } else if (line === "D") {
                    root.finished = true;
                } else if (line === "E Cancelled") {
                    root.cancelled = true;
                } else if (line.startsWith("E ")) {
                    root.error = line.slice(2, 200);
                }
            }
        }
        onExited: {
            if (root.quitWhenDone)
                Qt.quit();
            if (root.finished) {
                root.code = "";
                root.installed();
                return;
            }
            if (!root.cancelled && root.error === "")
                root.error = "The download failed. Nothing was installed.";
            root.code = "";
        }
    }
}
