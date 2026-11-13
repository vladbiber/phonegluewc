import Quickshell
import QtQuick

Page {
    id: root
    property var info: ({})
    function gb(kb) { return (kb / 1048576).toFixed(1) + " GB"; }
    Cmd {
        running: true
        command: [S.pset, "about"]
        onDone: {
            const o = {};
            for (const l of S.lines(out)) {
                const f = l.split("\t");
                o[f[0]] = f.slice(1);
            }
            root.info = o;
        }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    function one(k) { return info[k] && info[k][0] ? info[k][0] : "Unknown"; }

    RowItem { label: "Device"; sub: root.one("device"); tappable: false }
    RowItem { label: "System"; sub: root.one("os"); tappable: false }
    RowItem { label: "Kernel"; sub: root.one("kernel"); tappable: false }
    RowItem {
        label: "Storage"
        sub: root.info.disk ? root.gb(root.info.disk[1]) + " free of " + root.gb(root.info.disk[0]) : "Unknown"
        tappable: false
    }
    RowItem {
        label: "Memory"
        sub: root.info.ram ? root.gb(root.info.ram[1]) + " free of " + root.gb(root.info.ram[0]) : "Unknown"
        tappable: false
    }
    RowItem {
        label: "Date and time"
        sub: Qt.formatDateTime(clock.date, "d MMMM yyyy, HH:mm") + (root.info.zone ? " " + root.info.zone[0] : "")
        tappable: false
    }
}
