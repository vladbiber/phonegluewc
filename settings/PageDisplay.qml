import Quickshell.Io
import QtQuick

Page {
    id: root
    property bool hasBrightness: false
    property bool checked: false
    property real level: 0.5
    property var output: null    // from phonegluewc-msg outputs
    property bool asked: false
    readonly property var sizes: [
        { value: 450, label: "Small" }, { value: 393, label: "Default" },
        { value: 340, label: "Large" }, { value: 300, label: "Larger" }
    ]
    readonly property int shortSide: output ? Math.min(output.pw, output.ph) : 0
    readonly property int logical: {
        if (!output)
            return 0;
        let best = sizes[0].value;
        for (const s of sizes)
            if (Math.abs(shortSide / output.scale - s.value) < Math.abs(shortSide / output.scale - best))
                best = s.value;
        return best;
    }
    function scaleFor(lw) { return (Math.round(shortSide / lw * 20) / 20).toFixed(2); }

    Component.onCompleted: {
        if (S.toolsReady)
            start();
    }
    Connections {
        target: S
        function onToolsReadyChanged() { root.start(); }
    }
    function start() {
        if (S.has("brightnessctl"))
            read.run(["brightnessctl", "-m"]);
        else
            checked = true;
        if (S.has("phonegluewc-msg"))
            outputs.run(["phonegluewc-msg", "outputs"]);
        else
            asked = true;
    }
    Cmd {
        id: read
        onDone: code => {
            const f = S.firstLine(out, "").split(",");
            root.hasBrightness = code === 0 && f.length >= 5;
            if (root.hasBrightness)
                root.level = Math.max(0.01, Math.min(1, parseInt(f[3]) / 100));
            root.checked = true;
        }
    }
    Cmd { id: write; onDone: code => { if (code !== 0) S.saveError = "Could not change the brightness."; } }
    Cmd {
        id: outputs
        onDone: {
            for (const l of S.lines(out)) {
                const o = {};
                for (const kv of l.split("\t")) {
                    const at = kv.indexOf("=");
                    o[kv.slice(0, at)] = kv.slice(at + 1);
                }
                if (o.enabled !== "1" || !(parseInt(o.pw) > 0) || !(parseFloat(o.scale) > 0))
                    continue;
                root.output = { name: o.name, pw: parseInt(o.pw), ph: parseInt(o.ph), scale: parseFloat(o.scale), transform: o.transform };
                root.asked = true;
                return;
            }
            root.output = null;
            root.asked = true;
        }
    }
    // the compositor picks up the file in about 0.1 s, then this reads what really applied
    Timer { id: reread; interval: 500; onTriggered: root.start() }
    function setOutput(key, value) {
        S.save(["output", output.name, key, String(value)]);
        reread.restart();
    }

    Section { text: "Brightness" }
    Slider {
        visible: root.hasBrightness
        low: 0.01
        value: root.level
        // the floor of 1% keeps the screen from going fully black with no way back
        onMoved: v => write.run(["brightnessctl", "-q", "set", Math.max(1, Math.round(v * 100)) + "%"])
    }
    Note {
        visible: root.checked && !root.hasBrightness
        problem: true
        text: S.has("brightnessctl") ? "This screen has no brightness control." : "Brightness needs the brightnessctl tool, and it is not installed."
    }

    Section { text: "Text and UI size" }
    Chips {
        visible: root.output !== null
        options: root.sizes
        current: root.logical
        onPicked: v => root.setOutput("scale", root.scaleFor(v))
    }
    Section { text: "Orientation" }
    Chips {
        visible: root.output !== null
        options: [{ value: "normal", label: "Portrait" }, { value: "90", label: "Landscape" },
                  { value: "180", label: "Upside down" }, { value: "270", label: "Landscape, other way" }]
        current: root.output ? root.output.transform : ""
        onPicked: v => root.setOutput("transform", v)
    }
    Note {
        visible: root.asked && root.output === null
        problem: true
        text: "The size and orientation can only be read from the running phone desktop, and it did not answer."
    }
    // the same flag as the Rotation lock tile, inverted; the compositor writes orientation once it can turn
    property bool canRotate: false
    property bool rotLocked: false
    FileView { path: S.stateDir + "/phonegluewc/orientation"; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: root.canRotate = true; onLoadFailed: root.canRotate = false }
    // temp file and rename, as pset does; only 0 or 1 is ever written
    FileView { id: lockFile; path: S.stateDir + "/phonegluewc/rotation-lock"; atomicWrites: true; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: root.rotLocked = text().trim() === "1"; onLoadFailed: root.rotLocked = false; onSaveFailed: S.saveError = "Could not change auto-rotate." }
    RowItem {
        label: "Auto-rotate"
        sub: root.canRotate ? "Turns the screen when the phone turns" : "This phone desktop cannot turn the screen"
        tappable: root.canRotate
        onTapped: { root.rotLocked = !root.rotLocked; lockFile.setText(root.rotLocked ? "1" : "0"); }
        Toggle { on: root.canRotate && !root.rotLocked; enabled_: root.canRotate }
    }
    RowItem {
        label: "Animations"
        sub: "Off makes windows and cards move instantly"
        onTapped: S.save(["set", "phone", "animations", S.phone.animations === "off" ? "on" : "off"])
        Toggle { on: S.phone.animations !== "off" }
    }
    Section { text: "Screen timeout" }
    // the shell reads sleep_after from phone.conf; unset means 2 minutes
    readonly property int sleepAfter: S.phone.sleep_after === undefined ? 2 : Math.max(0, parseInt(S.phone.sleep_after) || 0)
    readonly property var sleepSteps: [0, 1, 2, 3, 5, 10]
    property bool custom: false
    function setSleep(m) { S.save(["set", "phone", "sleep_after", String(Math.max(0, Math.min(240, m)))]); }
    Chips {
        options: [{ value: 0, label: "Never" }, { value: 1, label: "1 min" }, { value: 2, label: "2 min" }, { value: 3, label: "3 min" },
                  { value: 5, label: "5 min" }, { value: 10, label: "10 min" }, { value: -1, label: "Custom" }]
        current: root.custom || !root.sleepSteps.includes(root.sleepAfter) ? -1 : root.sleepAfter
        onPicked: v => { root.custom = v === -1; if (v >= 0) root.setSleep(v); }
    }
    Row {
        visible: root.custom || !root.sleepSteps.includes(root.sleepAfter)
        x: S.margin
        spacing: 16
        Btn { text: "−"; onTapped: root.setSleep(root.sleepAfter - 1) }
        T { anchors.verticalCenter: parent.verticalCenter; text: root.sleepAfter + " min"; font.pixelSize: 17; width: 80; horizontalAlignment: Text.AlignHCenter }
        Btn { text: "+"; onTapped: root.setSleep(root.sleepAfter + 1) }
    }
    Note { text: "The screen stays on while music or a video plays." }
}
