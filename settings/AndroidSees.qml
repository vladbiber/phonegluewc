import Quickshell
import Quickshell.Io
import QtQuick

// what Android (Waydroid) may see of the gallery; the same gallery-android.conf the gallery's Android tab edits
Column {
    id: root
    width: parent.width
    readonly property string confPath: S.configDir + "/gallery-android.conf"
    property string mode: "send"
    property var albums: []
    property string strip: "1"
    property var folders: []
    readonly property var modes: [
        { value: "send", label: "Only what I send", note: "Photos and clips you send from the gallery are copied into one folder, Pictures/PhoneGallery. Nothing else is visible to Android." },
        { value: "album", label: "Selected albums only", note: "Only the albums you tick below are visible to Android, read only. Details are not stripped from them." },
        { value: "all", label: "The whole gallery", note: "Every Android app with photo access can read all your photos and clips. Read only, details are not stripped." }
    ]
    FileView {
        id: conf
        path: root.confPath; preload: true; printErrors: false; watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            for (const line of text().split("\n")) {
                const at = line.indexOf("=");
                if (at < 0) continue;
                const k = line.slice(0, at).trim(), v = line.slice(at + 1).trim();
                if (k === "mode" && ["send", "album", "all"].includes(v)) root.mode = v;
                if (k === "albums") root.albums = v === "" ? [] : v.split(",");
                if (k === "strip") root.strip = v;
            }
        }
    }
    property string error: ""
    property var pending: null
    // the choice is saved, and applied from the values at hand (not by reading the file back: it may not be written yet)
    function save() {
        conf.setText("mode=" + mode + "\nalbums=" + albums.join(",") + "\nstrip=" + strip + "\n");
        const args = mode === "all" ? ["expose-all"] : mode === "album" && albums.length ? ["expose-albums", ...albums] : ["expose-none"];
        if (applier.running) { pending = args; return; }
        run(args);
    }
    function run(args) {
        error = "";
        applier.command = ["sudo", "-n", "/usr/local/bin/phonegallery-android", ...args];
        applier.running = true;
    }
    Process {
        id: applier
        stderr: StdioCollector { onStreamFinished: root.errText = text }
        onExited: code => {
            if (code !== 0) root.error = "Could not change what Android sees: " + (root.errText.trim().split("\n")[0] || "exit " + code);
            if (root.pending) { const p = root.pending; root.pending = null; root.run(p); }
        }
    }
    property string errText: ""
    Process {
        id: lister
        command: [Quickshell.shellPath("../gallery/phonegallery-albums"), "folders"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.folders = text.trim() === "" ? [] : text.trim().split("\n").map(l => { const p = l.split("\t"); return { name: p[0], count: +p[1] }; }) }
    }

    Section { text: "What Android can see of the gallery" }
    Chips {
        options: root.modes
        current: root.mode
        onPicked: v => { root.mode = v; root.save(); }
    }
    Note { text: root.modes.find(m => m.value === root.mode).note }
    T { visible: root.error !== ""; width: parent.width; leftPadding: S.margin; rightPadding: S.margin; text: root.error; color: S.accent; font.pixelSize: 13 }
    Repeater {
        model: root.mode === "album" ? root.folders : []
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool on: root.albums.includes(modelData.name)
            x: S.margin; width: root.width - 2 * S.margin; height: 52
            Rectangle {
                id: box
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 24; height: 24; radius: 7
                color: row.on ? S.accent : "transparent"
                border { width: 2; color: row.on ? S.accent : S.grey }
                T { anchors.centerIn: parent; visible: row.on; text: "✓"; color: S.inkOnAccent; font.pixelSize: 15; wrapMode: Text.NoWrap }
            }
            T { anchors { left: box.right; leftMargin: 14; verticalCenter: parent.verticalCenter } text: row.modelData.name; wrapMode: Text.NoWrap }
            T { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: row.modelData.count; color: S.grey; wrapMode: Text.NoWrap }
            MouseArea {
                anchors.fill: parent
                onClicked: { root.albums = row.on ? root.albums.filter(n => n !== row.modelData.name) : [...root.albums, row.modelData.name]; root.save(); }
            }
        }
    }
}
