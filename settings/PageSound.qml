import QtQuick

Page {
    id: root
    // wpctl where PipeWire has it, pactl otherwise
    readonly property bool noVibration: S.toolsReady && !S.has("fbcli")
    readonly property string backend: S.has("wpctl") ? "wpctl" : S.has("pactl") ? "pactl" : ""
    property real volume: 0
    property bool muted: false
    property bool failed: false
    property var sinks: []       // { id, name, active }

    function refresh() {
        if (backend === "wpctl") {
            vol.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]);
            list.run(["wpctl", "status"]);
        } else if (backend === "pactl") {
            vol.run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"]);
            mute.run(["pactl", "get-sink-mute", "@DEFAULT_SINK@"]);
            def.run(["pactl", "get-default-sink"]);
        }
    }
    function setVolume(v) {
        const pct = Math.round(v * 100);
        if (backend === "wpctl")
            write.run(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", pct + "%"]);
        else
            write.run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", pct + "%"]);
    }
    function toggleMute() {
        muted = !muted;
        if (backend === "wpctl")
            write.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        else
            write.run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]);
    }
    function pick(sink) {
        if (backend === "wpctl")
            write.run(["wpctl", "set-default", sink.id]);
        else
            write.run(["pactl", "set-default-sink", sink.id]);
        sinks = sinks.map(s => Object.assign({}, s, { active: s.id === sink.id }));
        reread.restart();
    }

    onBackendChanged: refresh()
    Component.onCompleted: refresh()
    Timer { id: reread; interval: 400; onTriggered: root.refresh() }
    Cmd {
        id: vol
        onDone: code => {
            root.failed = code !== 0;
            if (code !== 0)
                return;
            if (root.backend === "wpctl") {
                const m = out.match(/Volume:\s*([0-9.]+)/);
                root.volume = m ? Math.min(1, parseFloat(m[1])) : 0;
                root.muted = /MUTED/.test(out);
            } else {
                const m = out.match(/(\d+)%/);
                root.volume = m ? Math.min(1, parseInt(m[1]) / 100) : 0;
            }
        }
    }
    Cmd { id: mute; onDone: root.muted = /yes/.test(out) }
    Cmd {
        id: def
        onDone: {
            sinkNames.defaultName = out.trim();
            sinkNames.run(["pactl", "list", "short", "sinks"]);
        }
    }
    Cmd {
        id: sinkNames
        property string defaultName: ""
        onDone: root.sinks = S.lines(out).map(l => l.split("\t")).filter(f => f.length > 1)
            .map(f => ({ id: f[1], name: f[1], active: f[1] === defaultName }))
    }
    Cmd {
        id: list
        // wpctl status is a drawn tree: the sinks lie between the Sinks heading and the next heading of Audio
        onDone: {
            const found = [];
            let audio = false, inSinks = false;
            for (const l of out.split("\n")) {
                if (/^Audio/.test(l))
                    audio = true;
                else if (/^\S/.test(l))
                    audio = false;
                if (!audio)
                    continue;
                if (/Sinks:/.test(l)) {
                    inSinks = true;
                    continue;
                }
                if (/[├└]─/.test(l))
                    inSinks = false;
                const m = inSinks && l.match(/(\*?)\s*(\d+)\.\s+(.+?)(?:\s+\[vol:.*\])?\s*$/);
                if (m)
                    found.push({ id: m[2], name: m[3], active: m[1] === "*" });
            }
            root.sinks = found;
        }
    }
    Cmd { id: write; onDone: code => { if (code !== 0) S.saveError = "The sound system refused that change."; } }

    Note {
        visible: S.toolsReady && root.backend === ""
        problem: true
        text: "Sound settings need wpctl or pactl, and neither is installed."
    }
    Note {
        visible: root.backend !== "" && root.failed
        problem: true
        text: "The sound service did not answer. It may not be running."
    }
    Section { visible: root.backend !== "" && !root.failed; text: "Volume " + Math.round(root.volume * 100) + "%" }
    Slider {
        visible: root.backend !== "" && !root.failed
        value: root.volume
        onMoved: v => { root.volume = v; root.setVolume(v); }
    }
    RowItem {
        visible: root.backend !== "" && !root.failed
        label: "Mute"
        onTapped: root.toggleMute()
        Toggle { on: root.muted }
    }
    Section { visible: root.sinks.length > 0; text: "Output" }
    Repeater {
        model: root.sinks
        delegate: RowItem {
            required property var modelData
            label: modelData.name
            icon: "speaker"
            active: modelData.active
            onTapped: root.pick(modelData)
        }
    }
    // the shell owns what these do; here they are only the two keys it reads
    Section { text: "Ringer" }
    Note {
        visible: root.noVibration
        problem: true
        text: "Vibration is not available on this phone: it needs fbcli, which is not installed."
    }
    Chips {
        options: [{ value: "normal", label: "Normal" }].concat(root.noVibration ? [] : [{ value: "vibrate", label: "Vibrate" }], [{ value: "silent", label: "Silent" }])
        // without a motor, vibrate alerts make no sound and no movement, which is silent
        current: S.phone.ringer === "vibrate" && root.noVibration ? "silent" : ["vibrate", "silent"].indexOf(S.phone.ringer) >= 0 ? S.phone.ringer : "normal"
        onPicked: v => S.save(["set", "phone", "ringer", v])
    }
    Note { text: "For calls and notifications only. Music and videos keep playing." }
    RowItem {
        label: "Do not disturb"
        sub: "Silences alerts. Notifications still appear"
        onTapped: S.save(["set", "phone", "dnd", S.phone.dnd === "on" ? "off" : "on"])
        Toggle { on: S.phone.dnd === "on" }
    }
    // the motor's drive voltage, 1500 to 3600 mV; the shell writes it to the driver
    Section { visible: !root.noVibration; text: "Vibration strength" }
    Slider {
        visible: !root.noVibration
        value: ((parseInt(S.phone.vibration_mv) || 2400) - 1500) / 2100
        onReleased: v => S.save(["set", "phone", "vibration_mv", String(1500 + Math.round(v * 21) * 100)])
    }
}
