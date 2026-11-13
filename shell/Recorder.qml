pragma Singleton
import Quickshell
import QtQuick

// screen recording: the tile asks, a sheet picks sound, a countdown, then wf-recorder until stopped or locked
Singleton {
    id: root

    property string stage: ""          // "", "sheet", "count"
    property int count: 3
    readonly property bool sound: Phone.conf.record_sound === "on"
    readonly property string pidFile: Phone.stateDir + "/quick-record.pid"

    function ask() { stage = "sheet"; }
    function cancel() { stage = ""; tick.stop(); }
    function go() { count = 3; stage = "count"; tick.restart(); }
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            if (--root.count > 0)
                return;
            stop();
            root.stage = "";
            root.begin();
        }
    }
    function begin() {
        Status.recording = true;
        // the pid is wf-recorder's own, so the bar's check and stop() find it; the note comes once the file is closed
        // set -m: a job started by & otherwise ignores SIGINT
        Quickshell.execDetached(["sh", "-c", 'set -m; d="$HOME/Videos/Screen recordings"; mkdir -p "$d"; f="$d/Screen recording $(date "+%Y-%m-%d %H-%M-%S").mp4"; '
            + 'wf-recorder $2 -f "$f" & echo $! >"$1"; wait $!; rm -f "$1"; [ -s "$f" ] && command -v notify-send >/dev/null && notify-send -a "Screen recorder" "Recording saved" "$f"',
            "phonerecord", pidFile, sound ? "-a" : ""]);
    }
    function stop() {
        Status.recording = false;
        Quickshell.execDetached(["sh", "-c", 'p=$(cat "$1" 2>/dev/null); [ -n "$p" ] && [ -O "/proc/$p" ] && [ "$(cat "/proc/$p/comm")" = wf-recorder ] && kill -INT "$p"', "phonerecord", pidFile]);
    }
    Connections {
        target: Phone
        function onLockOpenChanged() {
            if (!Phone.lockOpen)
                return;
            root.cancel();
            if (Status.recording)
                root.stop();
        }
    }

    // by file name, so a shell without windows (the greeter's load check) never compiles the overlay
    LazyLoader {
        active: (root.stage !== "" || Status.recording) && !Phone.lockOpen && !Auth.greeter
        source: "RecordOverlay.qml"
    }
}
