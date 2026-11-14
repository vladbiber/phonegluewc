import QtQuick

Page {
    id: root
    readonly property var modes: [
        { value: "on_demand", label: "Only when I use it", note: "Android starts when you open an Android app and stops a few minutes after the last one closes. Uses the least battery and frees about 2 GB of memory, but Android apps get no messages or calls while it is stopped." },
        { value: "always", label: "Always on", note: "Android starts with the phone and keeps running with the screen off, so every Android app gets its messages and calls. It holds about 2 GB of memory all the time and drains the battery noticeably faster." },
        { value: "hybrid", label: "Hybrid", note: "Android keeps running while WhatsApp or Discord is installed, so their messages and calls arrive with the screen off. Without them it works like Only when I use it. It holds about 2 GB of memory while it runs and uses more battery than Only when I use it." }
    ]
    // the same fallback as phone-waydroid-idle: anything unknown is on demand
    readonly property string current: modes.some(m => m.value === S.phone.waydroid) ? S.phone.waydroid : "on_demand"

    Section { text: "Keep Android running" }
    Chips {
        options: root.modes
        current: root.current
        onPicked: v => S.save(["set", "phone", "waydroid", v])
    }
    Note { text: root.modes.find(m => m.value === root.current).note }
    // what Android sees of the gallery: its own block, in AndroidSees.qml
    AndroidSees { }
}
