import Quickshell.Io
import QtQuick

// one program, one argument array, never a shell; a run asked for while busy replaces any queued one
Process {
    id: root
    property var pending: null
    readonly property string out: outC.text
    readonly property string err: errC.text
    signal done(int code)
    environment: ({ LC_ALL: "C" })
    function run(argv) {
        if (running) {
            pending = argv;
            return;
        }
        command = argv;
        running = true;
    }
    stdout: StdioCollector { id: outC }
    stderr: StdioCollector { id: errC }
    onExited: code => {
        done(code);
        if (pending) {
            const next = pending;
            pending = null;
            run(next);
        }
    }
}
