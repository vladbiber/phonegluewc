import Quickshell
import QtQuick

// the torch works locked; others stay a picture until the security phase decides what may run locked
Item {
    id: root

    property string kind: ""
    // starts from the last poll: Status stops polling behind the lock
    property bool lit: kind === "torch" && Status.torchOn
    implicitWidth: 56
    implicitHeight: 56

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.lit ? Phone.white : Phone.surface
        opacity: area.pressed ? 0.6 : 1
    }
    Canvas {
        id: icon
        anchors.centerIn: parent
        width: 24
        height: 24
        visible: root.kind === "camera" || root.kind === "torch"
        Connections { target: root; function onLitChanged() { icon.requestPaint(); } }
        onPaint: {
            const c = getContext("2d");
            c.strokeStyle = root.lit ? "#111111" : "#f5f5f5";
            c.lineWidth = 1.6;
            c.lineJoin = "round";
            c.beginPath();
            if (root.kind === "camera") {
                c.moveTo(3, 7); c.lineTo(8, 7); c.lineTo(10, 4); c.lineTo(14, 4); c.lineTo(16, 7); c.lineTo(21, 7);
                c.lineTo(21, 20); c.lineTo(3, 20); c.closePath();
                c.moveTo(16, 13); c.arc(12, 13, 4, 0, Math.PI * 2);
            } else {
                c.moveTo(7, 2); c.lineTo(17, 2); c.lineTo(17, 7); c.lineTo(14.5, 11); c.lineTo(14.5, 22); c.lineTo(9.5, 22);
                c.lineTo(9.5, 11); c.lineTo(7, 7); c.closePath();
                c.moveTo(7, 7); c.lineTo(17, 7);
            }
            c.stroke();
        }
    }
    Text {
        anchors.centerIn: parent
        visible: root.kind !== "camera" && root.kind !== "torch"
        text: root.kind.charAt(0).toUpperCase()
        color: Phone.white
        font.family: Phone.font
        font.pixelSize: 20
    }
    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: {
            if (root.kind !== "torch")
                return;
            root.lit = !root.lit;
            // Status never polls if the shell starts locked, so the LED is looked up here
            Quickshell.execDetached(["sh", "-c", 't=$(ls /sys/class/leds | grep -i torch | head -1); [ -n "$t" ] || t=$(ls /sys/class/leds | grep -i flash | head -1); '
                + '[ -n "$t" ] && brightnessctl -q --class=leds -d "$t" set "$1"', "torch", root.lit ? "100%" : "0"]);
        }
    }
}
