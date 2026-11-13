import Quickshell
import Quickshell.Io
import QtQuick

Page {
    id: root
    readonly property bool on: S.phone.dynamic_camera !== "off"
    readonly property var saved: {
        const p = (S.phone.camera_hole || "").split(",").map(Number);
        return p.length === 3 && p.every(n => !isNaN(n)) ? { x: p[0], y: p[1], d: p[2] } : null;
    }
    // the same lookup as the shell's: this is a program of its own
    FileView { id: holes; path: Quickshell.shellPath("../shell/camera-holes"); blockLoading: true; printErrors: false }
    FileView { id: compat; path: "/proc/device-tree/compatible"; blockLoading: true; printErrors: false }
    readonly property var known: {
        if (Quickshell.env("PHONE_NO_HOLE") === "1") {
            const place = Quickshell.env("PHONE_CAMERA");
            return { x: place === "center" ? 513.81 : place === "right" ? 938.32 : 89.3, y: 42.31, d: 52.38 };
        }
        const names = (Quickshell.env("PHONE_COMPATIBLE") || compat.text()).split("\0");
        for (const line of holes.text().split("\n")) {
            const p = line.trim().split(/\s+/);
            if (p.length === 4 && names.includes(p[0]))
                return { x: +p[1], y: +p[2], d: +p[3] };
        }
        return null;
    }
    property bool placing: false

    RowItem {
        label: "Dynamic camera"
        sub: "Activities grow out of the camera"
        onTapped: S.save(["set", "phone", "dynamic_camera", root.on ? "off" : "on"])
        Toggle { on: root.on }
    }
    Note {
        visible: !root.saved && !root.known
        text: "This phone's camera position is not known, so activities use a centred pill at the top. Set it below to wrap them around the camera."
    }
    RowItem {
        label: "Camera position"
        sub: root.saved ? "Set by you" : root.known ? "Automatic" : "Not known"
        chevron: true
        onTapped: root.placing = true
    }
    Section { text: "Show in it" }
    Repeater {
        model: [
            ["music", "Music"], ["calls", "Calls"], ["notifications", "Notifications"], ["charging", "Charging and low battery"],
            ["recording", "Screen recording"], ["timers", "Timer and stopwatch"], ["nav", "Navigation"], ["transfer", "File transfers"],
            ["flashlight", "Flashlight"], ["ringer", "Ringer and Do not disturb"], ["levels", "Volume and brightness"], ["network", "Hotspot and VPN"],
            ["devices", "Connected devices"], ["privacy", "Camera and microphone in use"], ["unlock", "Unlocking"], ["screenshot", "Screenshots"], ["apps", "Activities from other apps"]
        ]
        delegate: RowItem {
            required property var modelData
            readonly property string key: "dyn_" + modelData[0]
            readonly property bool shown: S.phone[key] !== "off"
            label: modelData[1]
            tappable: root.on
            opacity: root.on ? 1 : 0.4
            onTapped: S.save(["set", "phone", key, shown ? "off" : "on"])
            Toggle { on: parent.parent.shown; enabled_: root.on }
        }
    }

    LazyLoader {
        active: root.placing
        CameraPlace {
            start: root.saved || root.known || { x: 513.81, y: 42.31, d: 52.38 }
            known: root.known
            onFinished: root.placing = false
        }
    }
}
