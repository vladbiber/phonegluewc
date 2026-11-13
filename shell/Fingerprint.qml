import Quickshell
import Quickshell.Io
import QtQuick

// the under-screen sensor's spot, only with a finger enrolled in fprintd; a press asks fprintd once
Item {
    id: root

    signal matched()
    property bool enrolled: false
    property bool scanning: false
    property bool cancelled: false
    // like the PIN: after a boot the password comes first
    readonly property bool shown: enrolled && Pin.passwordUsed && !Auth.greeter
    // shortcut: fp_y is a guess of the sensor's height until it is measured on the phone
    readonly property real spot: {
        const v = parseFloat(Phone.conf.fp_y);
        return v >= 0.3 && v <= 0.98 ? v : 0.82;
    }

    width: 80
    height: 80
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? parent.height * spot - height / 2 : 0
    visible: shown

    function refresh() { list.running = true; }
    Component.onCompleted: refresh()

    Process {
        id: list
        // no fprintd installed: no output, no icon, no warning
        command: ["sh", "-c", 'command -v fprintd-list >/dev/null && exec fprintd-list "$1"', "sh", Quickshell.env("USER") || ""]
        stdout: StdioCollector { onStreamFinished: root.enrolled = /^\s*- #\d+:/m.test(text) }
    }
    Process {
        id: verify
        command: ["fprintd-verify"]
        stdout: StdioCollector { id: verifyOut }
        onExited: {
            root.scanning = false;
            if (/Verify result: verify-match\b/.test(verifyOut.text))
                root.matched();
            else if (!root.cancelled)
                shake.restart();
        }
    }
    // a finger that never comes stops the sensor
    Timer {
        running: root.scanning
        interval: 15000
        onTriggered: { root.cancelled = true; verify.running = false; }
    }

    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: 80
        height: 80
        radius: 40
        color: "transparent"
        border.width: 2
        border.color: Phone.accent
        opacity: 0
        SequentialAnimation on scale {
            running: root.scanning
            loops: Animation.Infinite
            NumberAnimation { from: 0.7; to: 1.15; duration: 700; easing.type: Easing.OutCubic }
        }
        SequentialAnimation on opacity {
            running: root.scanning
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 0; duration: 700 }
            onRunningChanged: if (!running) ring.opacity = 0
        }
    }
    Rectangle {
        id: disc
        anchors.centerIn: parent
        width: 64
        height: 64
        radius: 32
        color: "#40000000"
        scale: area.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Icon {
            anchors.centerIn: parent
            name: "finger"
            size: 40
            color: root.scanning ? Phone.accent : Phone.white
        }
    }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: disc; property: "anchors.horizontalCenterOffset"; to: 12; duration: 50 }
        NumberAnimation { target: disc; property: "anchors.horizontalCenterOffset"; to: -10; duration: 70 }
        NumberAnimation { target: disc; property: "anchors.horizontalCenterOffset"; to: 8; duration: 60 }
        NumberAnimation { target: disc; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        onPressed: {
            if (root.scanning)
                return;
            root.cancelled = false;
            root.scanning = true;
            verify.running = true;
        }
    }
    Component.onDestruction: if (verify.running) { cancelled = true; verify.running = false; }
}
