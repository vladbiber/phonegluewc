import QtQuick

Page {
    id: root
    readonly property var pressActions: [{ value: "camera", label: "Camera" }, { value: "flashlight", label: "Flashlight" }, { value: "screenshot", label: "Screenshot" }, { value: "none", label: "Nothing" }]
    function pressOf(key, fallback) { return pressActions.some(a => a.value === S.phone[key]) ? S.phone[key] : fallback; }
    readonly property bool tool: S.has("upower")
    property bool loaded: false
    property string path: ""
    property var info: ({})

    Timer {
        running: root.tool
        interval: 15000
        repeat: true
        triggeredOnStart: true
        onTriggered: devices.run(["upower", "-e"])
    }
    Cmd {
        id: devices
        onDone: code => {
            const b = code === 0 ? S.lines(out).find(l => /battery_/.test(l)) : null;
            root.path = b ? b.trim() : "";
            root.loaded = true;
            if (root.path)
                details.run(["upower", "-i", root.path]);
        }
    }
    Cmd {
        id: details
        onDone: {
            const o = {};
            for (const l of S.lines(out)) {
                const at = l.indexOf(":");
                if (at > 0)
                    o[l.slice(0, at).trim()] = l.slice(at + 1).trim();
            }
            root.info = o;
        }
    }
    readonly property string percent: info.percentage || ""
    readonly property string health: info.capacity ? Math.round(parseFloat(info.capacity)) + "%" : ""
    readonly property string state: {
        const s = info.state || "";
        return s === "fully-charged" ? "Fully charged" : s === "pending-charge" ? "Waiting to charge"
             : s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
    }
    readonly property string timeLeft: info["time to full"] ? info["time to full"] + " to full" : info["time to empty"] ? info["time to empty"] + " left" : ""

    Note {
        visible: S.toolsReady && !root.tool
        problem: true
        text: "Battery details need the upower tool, and it is not installed."
    }
    Note {
        visible: root.tool && root.loaded && root.path === ""
        text: "No battery was found on this device."
    }
    Item {
        visible: root.percent !== ""
        width: parent.width
        height: 90
        DotText { x: S.margin; y: 22; text: root.percent; px: 5; gap: 2 }
    }
    Column {
        visible: root.path !== ""
        width: parent.width
        RowItem { label: "State"; sub: root.state || "Unknown"; tappable: false }
        RowItem { visible: root.timeLeft !== ""; label: "Time"; sub: root.timeLeft; tappable: false }
        RowItem { label: "Health"; sub: root.health ? root.health + " of original capacity" : "Not reported by this battery"; tappable: false }
        RowItem { visible: !!root.info["charge-cycles"] && root.info["charge-cycles"] !== "N/A"; label: "Charge cycles"; sub: root.info["charge-cycles"] || ""; tappable: false }
    }

    // the shell reads these two keys and falls back the same way on an unknown value
    Section { text: "Power button, press twice" }
    Chips {
        options: root.pressActions
        current: root.pressOf("power_double", "camera")
        onPicked: v => S.save(["set", "phone", "power_double", v])
    }
    Section { text: "Power button, press three times" }
    Chips {
        options: root.pressActions
        current: root.pressOf("power_triple", "flashlight")
        onPicked: v => S.save(["set", "phone", "power_triple", v])
    }
    Note { text: "There is no camera app yet, so Camera only says so for now." }
}
